import Foundation

/// Which transcript paths the app is willing to open.
///
/// `transcript_path` arrives in the hook payload, and `POST /signal` is the one
/// route with no token — deliberately, because a hook that fails authentication
/// would block a Claude Code turn for the sake of a widget. The consequence had
/// not been followed through: whatever absolute path the payload named was
/// stored and later **read and rendered** in the extended window. Measured on
/// the running app: a forged signal naming `/etc/passwd` produced a row holding
/// that path in about a second.
///
/// Nobody could read the result from outside — the content is shown to the
/// user, not returned to the sender — and the only sender that can reach
/// loopback without already owning the account is a browser, which this build
/// of Chromium blocks under Private Network Access. But "the browser refuses on
/// our behalf" is not a boundary we control, and an app that will open any file
/// it is told to is one bad afternoon away from being a way to read files.
///
/// So the rule is where the answer actually lives: Claude Code writes
/// transcripts under `~/.claude`, and nothing outside it is a transcript.
public enum TranscriptPathPolicy {

    /// The path, if it is one the app may open; `nil` otherwise.
    ///
    /// - Parameter root: the directory transcripts must live under, normally
    ///   `~/.claude`. Injected rather than read here so the rule can be tested
    ///   without a home directory, and so the fake home the end-to-end run uses
    ///   is honoured for free.
    public static func accepted(_ raw: String?, under root: URL) -> String? {
        guard let raw = raw?.trimmed, raw.hasPrefix("/") else { return nil }

        // `standardizingPath` resolves `..` and `.`, which is what turns
        // `~/.claude/../../etc/passwd` from a path under the root into what it
        // really is. It does not resolve symlinks — a link planted inside the
        // Claude directory would still point out of it — but planting one there
        // already requires writing to the user's home, and at that point the
        // transcript itself can simply be replaced.
        let path = (raw as NSString).standardizingPath
        let base = (root.path as NSString).standardizingPath

        // The trailing separator matters: without it `/x/.claude-evil` passes as
        // a child of `/x/.claude`.
        let prefix = base.hasSuffix("/") ? base : base + "/"
        guard path.hasPrefix(prefix) else { return nil }

        return path
    }
}
