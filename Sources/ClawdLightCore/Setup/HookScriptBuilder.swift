import Foundation

/// Generates the shell script the Claude Code hooks run.
///
/// The script is deliberately dumb: it reads the JSON on stdin, forwards it to
/// the traffic light and **always exits 0**. A failing hook can interrupt a
/// Claude Code turn, and nobody wants their work to stop because a decorative
/// widget wasn't running.
public enum HookScriptBuilder {

    /// - Parameter host: when given, the script runs on another machine and says
    ///   so in an `X-Clawd-Host` header, so that a signal arriving through the
    ///   tunnel is told apart from a local one. The value is embedded in single
    ///   quotes; it has passed `RemoteHostList.isUsable`, whose allow-list has no
    ///   quote, space or backslash in it, so nothing here can escape.
    public static func script(port: UInt16 = AppConfig.listenPort, host: String? = nil) -> String {
        let origin = host.map { "     --header '\(AppConfig.remoteHostHeader): \($0)' \\\n" } ?? ""
        let where_ = host.map { " It runs on \($0) and posts through the ssh tunnel clawd-light keeps open." } ?? ""
        return """
        #!/bin/bash
        # clawd-light — forwards Claude Code events to the floating traffic light.\(where_)
        #
        # Generated automatically: hand edits are overwritten on the next
        # installation. Always exits 0, so the absence of the traffic light can
        # never block a Claude Code turn.

        set -u

        BODY=$(cat)

        curl --silent --show-error --output /dev/null \\
             --connect-timeout 1 --max-time 2 \\
             --request POST \\
             --header 'Content-Type: application/json' \\
             --header "X-Claude-Entrypoint: ${CLAUDE_CODE_ENTRYPOINT:-}" \\
        \(origin)     --data-binary "$BODY" \\
             'http://\(AppConfig.listenHost):\(port)\(AppConfig.signalPath)' \\
             2>/dev/null || true

        exit 0

        """
    }
}
