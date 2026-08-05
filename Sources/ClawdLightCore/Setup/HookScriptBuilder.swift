import Foundation

/// Generates the shell script the Claude Code hooks run.
///
/// The script is deliberately dumb: it reads the JSON on stdin, forwards it to
/// the traffic light and **always exits 0**. A failing hook can interrupt a
/// Claude Code turn, and nobody wants their work to stop because a decorative
/// widget wasn't running.
public enum HookScriptBuilder {

    public static func script(port: UInt16 = AppConfig.listenPort) -> String {
        """
        #!/bin/bash
        # clawd-light — forwards Claude Code events to the floating traffic light.
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
             --data-binary "$BODY" \\
             'http://\(AppConfig.listenHost):\(port)\(AppConfig.signalPath)' \\
             2>/dev/null || true

        exit 0

        """
    }
}
