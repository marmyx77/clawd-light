import Foundation

/// Generates the shell script a coding agent's hooks run.
///
/// The script is deliberately dumb: it reads the JSON on stdin, forwards it to
/// the traffic light and **always exits 0**. A failing hook can interrupt a
/// turn, and nobody wants their work to stop because a decorative widget wasn't
/// running. Codex is stricter still — it holds a turn for up to three seconds
/// waiting for its hooks — so the timeouts below are a promise to both.
public enum HookScriptBuilder {

    /// - Parameters:
    ///   - port: where to post. Locally the app's port; on another machine the
    ///     per-user loopback port the tunnel binds there (`AppConfig.remotePort`).
    ///   - host: when given, the script runs on another machine and says which in
    ///     an `X-LampBoard-Host` header, so that a signal arriving through the tunnel is
    ///     told apart from a local one. The value is embedded in single quotes; it
    ///     has passed `RemoteHostList.isUsable`, whose allow-list has no quote,
    ///     space or backslash in it, so nothing here can escape.
    ///   - harness: which agent this copy serves. One script is installed per
    ///     harness and each declares itself in a header, because the sender is
    ///     the only party that knows for certain — see `AppConfig.harnessHeader`.
    public static func script(
        port: UInt16 = AppConfig.listenPort,
        host: String? = nil,
        harness: Harness = .claudeCode
    ) -> String {
        let origin = host.map { "     --header '\(AppConfig.remoteHostHeader): \($0)' \\\n" } ?? ""
        let target = "http://\(AppConfig.listenHost):\(port)\(AppConfig.signalPath)"
        let where_ = host.map {
            " It runs on \($0) and posts through the ssh tunnel lampboard keeps open."
        } ?? ""

        // Claude Code names the surface a session was started from in this
        // variable; Codex has no equivalent, and inventing one would put a lie in
        // a field the workspace resolver trusts. Codex says where it came from in
        // the rollout's `originator` instead, which is read where it belongs.
        let entrypoint = harness == .claudeCode
            ? "     --header \"X-Claude-Entrypoint: ${CLAUDE_CODE_ENTRYPOINT:-}\" \\\n"
            : ""

        // Codex answers its hooks synchronously and gives them one second before
        // it starts waiting, three before it gives up. Claude Code is patient. The
        // tighter pair costs nothing to the patient one and keeps a turn from ever
        // noticing this script.
        let connect = harness == .codex ? "0.5" : "1"
        let total = harness == .codex ? "1.5" : "2"

        return """
        #!/bin/bash
        # LampBoard: forwards \(harness.displayName) events to the floating traffic light.\(where_)
        #
        # Generated automatically: hand edits are overwritten on the next
        # installation. Always exits 0, so the absence of the traffic light can
        # never block a turn.

        set -u

        BODY=$(cat)

        curl --silent --show-error --output /dev/null \\
             --connect-timeout \(connect) --max-time \(total) \\
             --request POST \\
             --header 'Content-Type: application/json' \\
             --header '\(AppConfig.harnessHeader): \(harness.rawValue)' \\
        \(entrypoint)\(origin)     --data-binary "$BODY" \\
             '\(target)' \\
             2>/dev/null || true

        exit 0

        """
    }
}
