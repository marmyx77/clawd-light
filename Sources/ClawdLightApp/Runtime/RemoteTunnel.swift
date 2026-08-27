import ClawdLightCore
import Foundation

/// The ssh tunnel that lets another machine's hooks reach this one.
///
/// `ssh -N -R 127.0.0.1:9877:127.0.0.1:<port> host`: on the node, `127.0.0.1:9877`
/// becomes this app's server, so the hook script installed there posts exactly
/// like the local one and needs no knowledge of where the Mac is. The bind
/// address is spelled out — loopback on the node, never a network interface.
///
/// It is kept alive, not merely started: ssh exits when the node sleeps, the VPN
/// drops or the Mac wakes, and each exit schedules a restart with a doubling
/// delay, reset to the minimum after a run that lasted. `ExitOnForwardFailure`
/// makes "port 9877 is taken over there" an exit with a reason instead of a
/// tunnel that looks up and carries nothing.
@MainActor
final class RemoteTunnel {

    enum State: Equatable {
        case starting
        /// ssh is running with the forward in place.
        case up(since: Date)
        /// ssh exited; the reason, and when the next attempt is.
        case down(reason: String, retryIn: TimeInterval)
        case stopped

        var label: String {
            switch self {
            case .starting: return "connecting…"
            case .up: return "connected"
            case .down(let reason, let retry): return "down — \(reason); retrying in \(Int(retry)) s"
            case .stopped: return "off"
            }
        }
    }

    let host: String
    private let localPort: UInt16
    private let onChange: @MainActor (State) -> Void

    private(set) var state: State = .stopped {
        didSet {
            guard state != oldValue else { return }
            Diagnostics.log("tunnel \(host): \(state.label)")
            onChange(state)
        }
    }

    private var process: Process?
    private var retryTimer: Timer?
    private var delay: TimeInterval = AppConfig.remoteTunnelRetryMin
    private var startedAt: Date?
    private var wantsToRun = false

    init(host: String, localPort: UInt16, onChange: @escaping @MainActor (State) -> Void) {
        self.host = host
        self.localPort = localPort
        self.onChange = onChange
    }

    func start() {
        wantsToRun = true
        launch()
    }

    func stop() {
        wantsToRun = false
        retryTimer?.invalidate()
        retryTimer = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        state = .stopped
    }

    // MARK: - Internal

    private func launch() {
        guard wantsToRun, process == nil else { return }
        state = .starting

        let ssh = Process()
        ssh.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        ssh.arguments = [
            "-N",
            "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
            "-o", "ConnectTimeout=\(Int(AppConfig.remoteProbeTimeout))",
            "-o", "StrictHostKeyChecking=accept-new",
            "-R", "127.0.0.1:\(AppConfig.listenPort):127.0.0.1:\(localPort)",
            host,
        ]
        let errors = Pipe()
        ssh.standardOutput = FileHandle.nullDevice
        ssh.standardError = errors
        ssh.standardInput = FileHandle.nullDevice

        ssh.terminationHandler = { [weak self] finished in
            let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.exited(status: finished.terminationStatus, stderr: text)
            }
        }

        do {
            try ssh.run()
        } catch {
            exited(status: -1, stderr: error.localizedDescription)
            return
        }
        process = ssh
        startedAt = Date()

        // ssh says nothing on success. If it is still running after the connect
        // timeout, the forward is in place: with ExitOnForwardFailure a refused
        // port would already have ended it.
        let launched = ssh
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConfig.remoteProbeTimeout) { [weak self] in
            guard let self, self.process === launched, launched.isRunning else { return }
            self.state = .up(since: self.startedAt ?? Date())
        }
    }

    private func exited(status: Int32, stderr: String) {
        process = nil
        guard wantsToRun else { return }

        let lasted = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        // A tunnel that held for a minute earned a fresh start; one that died at
        // once keeps backing off.
        delay = lasted > 60 ? AppConfig.remoteTunnelRetryMin : min(delay * 2, AppConfig.remoteTunnelRetryMax)

        state = .down(reason: Self.reason(status: status, stderr: stderr), retryIn: delay)

        retryTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.launch() }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    private static func reason(status: Int32, stderr: String) -> String {
        let text = stderr
            .split(separator: "\n")
            .filter { !$0.hasPrefix("Warning: Permanently added") }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.localizedCaseInsensitiveContains("remote port forwarding failed") {
            return "port \(AppConfig.listenPort) is taken on the node"
        }
        if text.localizedCaseInsensitiveContains("permission denied") {
            return "ssh refused the key"
        }
        if text.isEmpty { return "ssh exited (\(status))" }
        return String(text.prefix(100))
    }
}
