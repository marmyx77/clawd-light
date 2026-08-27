import ClawdLightCore
import Foundation

/// What another machine reported about itself.
struct RemoteInspection {
    let home: String
    /// Claude Code's settings there; `nil` when the file exists and cannot be parsed.
    let settings: [String: Any]?
    let pythonVersion: String
    let hasCurl: Bool
    let error: String?

    var scriptPath: String { home + "/" + AppConfig.remoteHookScriptRelativePath }

    /// `true` when the clawd-light hook is registered there.
    var hooksInstalled: Bool {
        guard let settings else { return false }
        return HookConfigMerger.isInstalled(in: settings, scriptPath: scriptPath)
    }
}

/// Installs and removes the clawd-light hooks on another machine.
///
/// The same merge as the local installer — `HookConfigMerger`, verified by the
/// same tests — applied to a file read from the node and written back to it. The
/// hook script it writes there posts to `127.0.0.1:9877`, which on that machine is
/// the far end of the tunnel this app keeps open (`RemoteTunnel`), and names the
/// host in a header so the signal is attributed when it arrives.
///
/// Two round trips, both blocking: inspect, then apply. Message delivery (the
/// second `Stop` hook) is not installed remotely — the mailbox is local.
enum RemoteHookInstaller {

    static func inspect(_ host: String) -> Result<RemoteInspection, RemoteCommandError> {
        RemoteCommand.runPythonForObject(on: host, script: RemoteInstallScripts.inspect).flatMap { object in
            guard let home = object["home"] as? String, home.hasPrefix("/") else {
                return .failure(.badAnswer("no home directory in the answer"))
            }
            return .success(RemoteInspection(
                home: home,
                settings: object["settings"] as? [String: Any],
                pythonVersion: (object["python"] as? String) ?? "?",
                hasCurl: (object["curl"] as? Bool) ?? false,
                error: object["error"] as? String
            ))
        }
    }

    /// Registers the hooks there. Returns a one-line description of what was done.
    static func install(on host: String, port: UInt16 = AppConfig.listenPort) -> Result<String, RemoteCommandError> {
        inspect(host).flatMap { inspection in
            guard let settings = inspection.settings else {
                return .failure(.remoteFailure(
                    "settings.json there cannot be parsed (\(inspection.error ?? "unknown error")); nothing was changed"
                ))
            }
            guard inspection.hasCurl else {
                return .failure(.remoteFailure("curl is missing there, and the hook script needs it"))
            }
            let merged = HookConfigMerger.install(
                into: settings,
                scriptPath: inspection.scriptPath,
                rewakeScriptPath: nil,
                registerMessageDelivery: false
            )
            return apply(on: host, payload: [
                "scriptRelativePath": AppConfig.remoteHookScriptRelativePath,
                "settingsRelativePath": AppConfig.remoteClaudeSettingsRelativePath,
                "settings": merged,
                "hookScript": HookScriptBuilder.script(port: port, host: host),
            ]).map { result in
                let backup = (result["backup"] as? String).map { " (backup: \($0))" } ?? ""
                return "hooks installed on \(host)\(backup)"
            }
        }
    }

    /// Removes the hooks and the script there.
    static func uninstall(on host: String) -> Result<String, RemoteCommandError> {
        inspect(host).flatMap { inspection in
            guard let settings = inspection.settings else {
                return .failure(.remoteFailure(
                    "settings.json there cannot be parsed (\(inspection.error ?? "unknown error")); nothing was changed"
                ))
            }
            let cleaned = HookConfigMerger.uninstall(from: settings, scriptPath: inspection.scriptPath)
            return apply(on: host, payload: [
                "scriptRelativePath": AppConfig.remoteHookScriptRelativePath,
                "settingsRelativePath": AppConfig.remoteClaudeSettingsRelativePath,
                "settings": cleaned,
                "removeScript": true,
            ]).map { _ in "hooks removed from \(host)" }
        }
    }

    /// Asks the node whether the tunnel reaches this app: an HTTP answer of any
    /// kind from `127.0.0.1:9877` *there* is the proof.
    static func tunnelReaches(_ host: String) -> Result<Bool, RemoteCommandError> {
        RemoteCommand.runPython(on: host, script: RemoteInstallScripts.checkTunnel).map { data in
            let answer = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(answer) != nil
        }
    }

    private static func apply(
        on host: String, payload: [String: Any]
    ) -> Result<[String: Any], RemoteCommandError> {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return .failure(.badAnswer("the payload could not be encoded"))
        }
        return RemoteCommand.runPythonForObject(
            on: host,
            script: RemoteInstallScripts.apply(payloadBase64: data.base64EncodedString()),
            timeout: AppConfig.remoteProbeTimeout * 2
        ).flatMap { result in
            guard (result["ok"] as? Bool) == true else {
                return .failure(.badAnswer("the machine did not confirm the write"))
            }
            return .success(result)
        }
    }
}
