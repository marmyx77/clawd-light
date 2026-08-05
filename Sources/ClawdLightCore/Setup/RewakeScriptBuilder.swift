import Foundation

/// Generates the listener that carries a message into a running session.
///
/// # What it is
///
/// A second `Stop` hook, registered alongside the traffic light one and marked
/// `asyncRewake`. Claude Code spawns it **detached** at the end of a turn, so it
/// outlives the turn that launched it. When it eventually exits with code **2**,
/// whatever it printed on stdout is enqueued as the session's next turn.
///
/// So the two halves of "send a message" are one act: **stdout is the message,
/// exit 2 is the send.**
///
/// # What it costs, and the three defences
///
/// This is a blocking process that survives the CLI, one per session being
/// chatted with. Left alone that is a leak, so:
///
/// 1. **It arms only when a chat window is open** — the `.open` marker. Sessions
///    you are not chatting with pay one `[ -f ]` and leave.
/// 2. **It gives up.** After `maxWaitSeconds` it exits 0 rather than waiting for
///    ever. The session then hears nothing until its next turn re-arms it, which
///    is the safe direction to fail in.
/// 3. **One at a time.** A second `Stop` while one is already waiting would give
///    two readers racing for the same message; the pid file stands them down.
///
/// # Why it polls instead of blocking on a pipe
///
/// A named pipe would let it sleep properly, but opening one for writing blocks
/// until a reader is there — so typing while Claude was working would hang the
/// panel, which is exactly when you most want to type. A one-second `[ -f ]` on a
/// sleeping process costs nothing measurable and makes "queue it while busy" fall
/// out for free: the message is simply already on disk when the listener arms.
///
/// The script never exits non-zero except the deliberate 2. A hook that fails can
/// interrupt a turn, and no chat feature is worth costing somebody their work.
public enum RewakeScriptBuilder {

    /// How long an armed listener waits before giving up, in seconds.
    ///
    /// Half an hour: long enough that a chat window left open stays useful across
    /// a coffee, short enough that a forgotten window does not hold a process all
    /// day. The window re-arms it on the session's next turn either way.
    public static let maxWaitSeconds = 1800

    /// The line the contract check greps for. If Claude Code renames `asyncRewake`
    /// this feature dies silently, so the name is asserted rather than assumed.
    public static let requiredHookOption = "asyncRewake"

    public static func script(inboxPath: String = Mailbox.directory.path) -> String {
        """
        #!/bin/bash
        # clawd-light — carries a message from the chat window into a running session.
        #
        # Generated automatically: hand edits are overwritten on the next
        # installation.
        #
        # Registered as a second `Stop` hook with "asyncRewake": true, which makes
        # Claude Code spawn it detached so it outlives the turn. Printing on stdout
        # and exiting 2 enqueues what was printed as the session's next turn.
        #
        # Every other path out of here is exit 0. A hook that fails can interrupt a
        # Claude Code turn, and no chat window is worth that.

        set -u

        INBOX='\(inboxPath)'
        MAX_WAIT=\(maxWaitSeconds)

        BODY=$(cat)

        # The session id, without assuming a JSON parser is installed. Claude Code
        # session ids are uuids, and the pattern is anchored to that shape so a
        # surprising payload yields nothing rather than something usable as a path.
        SESSION=$(printf '%s' "$BODY" \\
            | /usr/bin/sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\\([A-Za-z0-9-]\\{8,64\\}\\)".*/\\1/p' \\
            | head -n 1)
        [ -n "$SESSION" ] || exit 0

        OPEN="$INBOX/$SESSION.open"
        MSG="$INBOX/$SESSION.msg"
        PIDFILE="$INBOX/$SESSION.pid"

        # Arm only for a session whose chat window is open. This is what keeps the
        # cost proportional to what you are reading, not to how much is running.
        [ -f "$OPEN" ] || exit 0

        # One listener per session. Without this, two closely spaced turns leave two
        # processes racing for the same message and one of them loses it.
        if [ -f "$PIDFILE" ]; then
            OTHER=$(cat "$PIDFILE" 2>/dev/null)
            if [ -n "$OTHER" ] && kill -0 "$OTHER" 2>/dev/null; then
                exit 0
            fi
        fi
        printf '%s' "$$" > "$PIDFILE"
        trap 'rm -f "$PIDFILE"' EXIT

        WAITED=0
        while [ "$WAITED" -lt "$MAX_WAIT" ]; do
            # The window was closed: stand down rather than hold a process for a
            # conversation nobody is looking at.
            [ -f "$OPEN" ] || exit 0

            if [ -f "$MSG" ]; then
                TEXT=$(cat "$MSG" 2>/dev/null)
                # Claim it before delivering. If we are killed between the read and
                # the send, the message is lost — which is better than a message
                # that arrives twice, because the second copy looks like the user
                # repeating themselves.
                rm -f "$MSG"
                [ -n "$TEXT" ] || exit 0
                printf '%s' "$TEXT"
                exit 2
            fi

            sleep 1
            WAITED=$((WAITED + 1))
        done

        exit 0

        """
    }
}
