import ClawdLightCore
import Combine
import SwiftUI

/// Holds the dictation service, or doesn't.
///
/// `DictationService` exists only on macOS 26, and a stored property cannot be of
/// a type newer than its container. This box is the seam: it stores the service
/// as an opaque reference, hands it back only behind an availability check, and
/// **forwards its changes** so the view redraws when dictation reports progress.
///
/// Without that forwarding the box would be an `ObservableObject` that never
/// announces anything, and the microphone would look dead while it downloaded a
/// language model.
@MainActor
final class DictationBox: ObservableObject {

    private let storage: AnyObject?
    private var forwarding: AnyCancellable?

    init() {
        if #available(macOS 26.0, *) {
            let service = DictationService()
            storage = service
            forwarding = service.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        } else {
            storage = nil
        }
    }

    @available(macOS 26.0, *)
    var service: DictationService? { storage as? DictationService }

    /// `true` when the button can be drawn at all. A control that cannot work is
    /// worse than no control: it invites a click and answers with silence.
    var isOffered: Bool { storage != nil }

    /// What to say under the composer, if anything.
    var explanation: String? {
        guard #available(macOS 26.0, *), let service else { return nil }
        return service.availability.explanation
    }
}

/// The microphone.
///
/// Press to start, press again to stop **and put what was heard into the
/// composer**. It deliberately does not send: a mis-heard sentence you can still
/// fix is a different thing from one already delivered, and dictation mis-hears.
@available(macOS 26.0, *)
struct DictationButton: View {

    @ObservedObject var service: DictationService

    /// Called with the finished text when listening stops.
    let onFinish: (String) -> Void

    @State private var pulsing = false

    var body: some View {
        Button(action: press) {
            Image(systemName: service.isListening ? "mic.fill" : "mic")
                .font(.system(size: 14))
                .foregroundStyle(service.isListening ? Color.red : Color.primary.opacity(0.7))
                .opacity(service.isListening && pulsing ? 0.45 : 1)
        }
        .buttonStyle(.borderless)
        .help(service.isListening ? "Stop dictating" : "Dictate the message")
        // The pulse is the only proof the microphone is open. Without it, a
        // dictation that silently failed to start looks exactly like one that is
        // listening to you patiently.
        .onChange(of: service.isListening) { _, listening in
            pulsing = false
            guard listening else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .task { await service.refreshAvailability() }
    }

    private func press() {
        Task {
            if service.isListening {
                let heard = await service.stop()
                let trimmed = heard.trimmed
                if !trimmed.isEmpty { onFinish(trimmed) }
            } else {
                await service.start()
            }
        }
    }
}
