import ClawdLightCore
import Foundation

/// Verifies the hook → server → workspace resolution chain end to end, without
/// opening the interface.
///
/// It exists to answer the question you ask yourself when a traffic light doesn't
/// come on: is transport failing, or decoding, or window recognition? Trying to
/// guess that from an unlit dot doesn't work.
enum SelfTest {

    /// - Parameter cwd: folder to use in the probe signal.
    static func run(port: UInt16, cwd: String = FileManager.default.currentDirectoryPath) -> Int32 {
        var failures = 0

        print("clawd-light — self-diagnosis\n")

        // 1. Can the server open the port?
        let received = Box<HookSignal?>(nil)
        let semaphore = DispatchSemaphore(value: 0)

        let server = SignalServer(
            port: port,
            onSignal: { signal in
                received.value = signal
                semaphore.signal()
            },
            onError: { message in
                print("  server: \(message)")
            }
        )

        do {
            try server.start()
            print("✓ server listening on \(AppConfig.listenHost):\(port)")
        } catch {
            print("✗ the server won't start: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
            print("\n  If the panel is already running the port is taken: that's normal.")
            return 1
        }
        defer { server.stop() }

        // 2. Does a signal cross HTTP and get decoded?
        let payload = probePayload(cwd: cwd)
        switch post(payload, port: port) {
        case .failed(let reason):
            print("✗ the probe POST failed: \(reason)")
            failures += 1
        case .status(204):
            print("✓ the server accepts signals (HTTP 204)")
        case .status(let code):
            print("✗ unexpected response from the server: HTTP \(code)")
            failures += 1
        }

        if semaphore.wait(timeout: .now() + 3) == .success, let signal = received.value {
            print("✓ signal decoded: \(signal.event.rawValue) from \(signal.cwd)")
        } else {
            print("✗ the signal never reached the handler")
            failures += 1
        }

        // 3. Does the current folder match a VS Code window?
        let windows = IDEWindowReader().readWindows()
        let fresh = windows.filter { $0.isSupported }
        print("\nVS Code windows with Claude Code active: \(fresh.count)")

        if let workspace = WorkspaceResolver.resolve(cwd: cwd, in: windows, at: Date()) {
            print("✓ \(cwd)\n  → workspace «\(workspace.name)»")
        } else {
            print("✗ no VS Code window contains \(cwd)")
            print("  (normal if you are running the command from an external terminal)")
            failures += 1
        }

        // 4. Are the permissions to activate windows in place? There are two, distinct.
        if VSCodeFocuser.hasAccessibilityPermission {
            print("✓ Accessibility permission granted")
        } else {
            print("✗ Accessibility permission missing")
            print("  System Settings › Privacy & Security › Accessibility")
            failures += 1
        }

        if let error = VSCodeFocuser.checkAutomationPermission() {
            print("✗ Automation permission: \(error.shortDescription)")
            print("  System Settings › Privacy & Security › Automation")
            print("  → clawd-light → System Events")
            failures += 1
        } else {
            print("✓ Automation permission (System Events) granted")
        }

        if !VSCodeFocuser.hasAccessibilityPermission
            || VSCodeFocuser.checkAutomationPermission() != nil {
            print("  Without either of the two the click falls back to `open`: VS Code")
            print("  still comes to the front, but it may open a new window.")
        }

        // 5. Are the hooks registered?
        let installer = HookInstaller()
        let events = installer.installedEvents()
        if events.isEmpty {
            print("✗ no hooks registered — run `clawd-light install-hooks`")
            failures += 1
        } else {
            print("✓ hooks registered for: \(events.joined(separator: ", "))")
        }

        print("\n" + String(repeating: "─", count: 56))
        switch failures {
        case 0: print("All good.")
        case 1: print("1 problem found.")
        default: print("\(failures) problems found.")
        }
        return failures == 0 ? 0 : 1
    }

    // MARK: - Helpers

    private static func probePayload(cwd: String) -> Data {
        let object: [String: Any] = [
            "session_id": "self-diagnosis",
            "hook_event_name": "SessionStart",
            "cwd": cwd,
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    /// Outcome of the probe POST.
    private enum ProbeResult {
        case status(Int)
        case failed(String)
    }

    private static func post(_ body: Data, port: UInt16) -> ProbeResult {
        guard let url = URL(
            string: "http://\(AppConfig.listenHost):\(port)\(AppConfig.signalPath)"
        ) else {
            return .failed("invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-vscode", forHTTPHeaderField: "X-Claude-Entrypoint")
        request.timeoutInterval = 3

        let result = Box<ProbeResult>(.failed("no response within the timeout"))
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                result.value = .failed(error.localizedDescription)
            } else if let http = response as? HTTPURLResponse {
                result.value = .status(http.statusCode)
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 5)
        return result.value
    }
}

/// Reference container used to get a value out of a callback.
/// It serves the synchronous diagnostics only: the rest of the code mutates nothing.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
