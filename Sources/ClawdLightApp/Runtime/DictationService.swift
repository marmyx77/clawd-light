import AVFoundation
import ClawdLightCore
import Foundation
import Speech

/// Dictation, inside the window.
///
/// macOS ships dictation that works in any text field, and it needs no code and no
/// microphone permission from us — the system captures and inserts the text. It is
/// the right answer for anybody it works for. This exists because it is driven by a
/// system shortcut rather than a button, and because it cannot do the thing that
/// makes dictation worth having in a chat: **stop talking and have the message go**.
///
/// Everything here is on-device. `SpeechTranscriber` is the macOS 26 API; nothing
/// is sent anywhere, and the language model is a local asset.
///
/// The whole type is gated on macOS 26. On anything older the button is not drawn
/// — see `DictationAvailability.isOffered` — because a control that cannot work is
/// worse than no control: it invites a click and answers with silence.
@available(macOS 26.0, *)
@MainActor
final class DictationService: ObservableObject {

    /// What has been heard so far, updated as you speak.
    @Published private(set) var transcript = ""

    /// `true` while the microphone is open.
    @Published private(set) var isListening = false

    @Published private(set) var availability: DictationAvailability = .ready(identifier: "")

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var converter: AVAudioConverter?

    /// Text finalised so far. Volatile results are appended to this for display
    /// but replaced as the recogniser changes its mind, which it does constantly
    /// mid-sentence.
    private var settled = ""

    // MARK: - Availability

    /// Works out whether dictation can run, without opening the microphone.
    ///
    /// Called when the window appears, so the button's state is honest before it
    /// is ever pressed.
    func refreshAvailability() async {
        guard let locale = DictationLocale.choose(
            preferred: Locale.preferredLanguages,
            supported: await SpeechTranscriber.supportedLocales
        ) else {
            availability = .noLanguage
            return
        }

        let identifier = locale.identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales
        let isInstalled = installed.contains {
            $0.identifier(.bcp47) == identifier
        }
        availability = isInstalled
            ? .ready(identifier: identifier)
            : .needsDownload(identifier: identifier)
    }

    // MARK: - Listening

    func toggle() async {
        if isListening {
            await stop()
        } else {
            await start()
        }
    }

    func start() async {
        guard !isListening else { return }

        guard await requestMicrophone() else {
            availability = .denied
            return
        }

        guard let locale = DictationLocale.choose(
            preferred: Locale.preferredLanguages,
            supported: await SpeechTranscriber.supportedLocales
        ) else {
            availability = .noLanguage
            return
        }

        do {
            let transcriber = SpeechTranscriber(
                locale: locale,
                // Volatile results are what makes the box fill in as you speak
                // instead of after you stop. Without them dictation feels broken
                // even when it is working.
                preset: .progressiveTranscription
            )
            try await installModelIfNeeded(for: transcriber, locale: locale)

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

            self.transcriber = transcriber
            self.analyzer = analyzer
            self.inputBuilder = continuation

            settled = ""
            transcript = ""
            listenForResults(from: transcriber)

            let target = await transcriber.availableCompatibleAudioFormats.first
            Diagnostics.log("dictation: format \(target?.description ?? "<native>")")

            try startCapture(feeding: continuation, format: target)

            // The state goes up BEFORE the analyser is started, and the analyser is
            // started in a task rather than awaited.
            //
            // `SpeechAnalyzer.start(inputSequence:)` does not return until the
            // sequence ends — it is the pump, not the ignition. Awaiting it here
            // meant the next line never ran: `isListening` stayed false, so the
            // button looked idle, pressing it again started a second capture, and
            // `stop()` refused to do anything because it believed nothing was
            // running. The microphone stayed open with no way back short of
            // quitting the app. That is what this ordering exists to prevent.
            isListening = true
            availability = .ready(identifier: locale.identifier(.bcp47))
            Diagnostics.log("dictation: listening in \(locale.identifier(.bcp47))")

            analysisTask = Task { [weak self] in
                do {
                    try await analyzer.start(inputSequence: stream)
                    Diagnostics.log("dictation: analyser finished")
                } catch {
                    Diagnostics.log("dictation: analyser failed — \(error)")
                    await self?.failed(error)
                }
            }
        } catch {
            await teardown()
            availability = .failed(error.localizedDescription)
            Diagnostics.log("dictation: failed to start — \(error)")
        }
    }

    /// Stops listening and returns everything that was heard.
    @discardableResult
    func stop() async -> String {
        // The microphone is released **first and unconditionally**, before any
        // check on our own state. A bug anywhere else in this file must never be
        // able to leave the input device open: that is the one failure the user
        // cannot undo from inside the app.
        releaseMicrophone()

        guard isListening else { return transcript }
        isListening = false
        inputBuilder?.finish()

        // Finalising is what turns the last volatile guess into a real word. Cutting
        // the analyser off instead loses the end of the sentence, which is the part
        // people notice.
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()

        let heard = transcript
        await teardown()
        Diagnostics.log("dictation: stopped with \(heard.count) chars")
        return heard
    }

    // MARK: - Internals

    /// Something failed while listening: shut down and say so.
    private func failed(_ error: Error) async {
        isListening = false
        releaseMicrophone()
        await teardown()
        availability = .failed(error.localizedDescription)
    }

    /// Closes the input device. Safe to call when nothing is open.
    private func releaseMicrophone() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
    }

    private func teardown() async {
        // Belt and braces: `teardown` is reached from the failure path too, and a
        // teardown that left the engine running is exactly how the microphone got
        // stuck the first time.
        releaseMicrophone()
        analysisTask?.cancel()
        analysisTask = nil
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        inputBuilder = nil
        converter = nil
    }

    private func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    /// Fetches the language model the first time it is needed.
    ///
    /// It is a real download, of real size, and it happens on the first press. The
    /// progress goes into `availability` so the button can say what it is doing
    /// rather than appear stuck.
    private func installModelIfNeeded(
        for transcriber: SpeechTranscriber, locale: Locale
    ) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) else { return }

        availability = .downloading(fraction: 0)
        let progress = request.progress
        let observer = Task { [weak self] in
            while !Task.isCancelled, !progress.isFinished {
                await MainActor.run {
                    self?.availability = .downloading(fraction: progress.fractionCompleted)
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        defer { observer.cancel() }

        try await request.downloadAndInstall()
        availability = .ready(identifier: locale.identifier(.bcp47))
    }

    private func listenForResults(from transcriber: SpeechTranscriber) {
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    await MainActor.run {
                        guard let self else { return }
                        // A result is either final — keep it — or the recogniser's
                        // current guess, which it will replace. Appending both
                        // would repeat every word as it firms up.
                        if result.isFinal {
                            self.settled += self.settled.isEmpty ? text : " " + text
                            self.transcript = self.settled
                        } else {
                            self.transcript = self.settled.isEmpty
                                ? text
                                : self.settled + " " + text
                        }
                    }
                }
            } catch {
                await MainActor.run { self?.availability = .failed(error.localizedDescription) }
            }
        }
    }

    /// Opens the microphone and pushes buffers at the analyser.
    ///
    /// The input device's format is whatever the hardware feels like — 48 kHz
    /// stereo, usually — and the recogniser wants its own. An `AVAudioConverter`
    /// sits between them, because handing the analyser the wrong format does not
    /// error: it transcribes noise.
    private func startCapture(
        feeding continuation: AsyncStream<AnalyzerInput>.Continuation,
        format target: AVAudioFormat?
    ) throws {
        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0 else {
            throw DictationError.noInputDevice
        }

        if let target, target != source {
            converter = AVAudioConverter(from: source, to: target)
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: source) { [weak self] buffer, _ in
            guard let self else { return }
            guard let converter = self.converter, let target else {
                continuation.yield(AnalyzerInput(buffer: buffer))
                return
            }
            guard let converted = Self.convert(buffer, with: converter, to: target) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }

        engine.prepare()
        try engine.start()
    }

    private nonisolated static func convert(
        _ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to target: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}

enum DictationError: LocalizedError {
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "no microphone is available"
        }
    }
}
