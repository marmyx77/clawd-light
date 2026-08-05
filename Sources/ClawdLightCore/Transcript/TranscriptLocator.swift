import Foundation

/// Works out where a session's transcript *would* be.
///
/// The hooks carry `transcript_path` and that is always the better answer. This
/// exists for the sessions that arrive the other way: adopted from
/// `~/.claude/sessions/`, which knows a session exists but not where it writes.
/// After a restart of clawd-light that is **every** session, so without this the
/// chat window would be empty until the next time somebody pressed enter.
///
/// The rule was measured, not guessed: across the 7066 transcripts on the machine
/// where it was written, `~/.claude/projects/<cwd with every non-alphanumeric
/// character replaced by "-">/<session-id>.jsonl` matched 7065 times.
///
/// The one exception is the reason `candidateURL` is named the way it is. A
/// session running in a git worktree reports the **main** repository as its `cwd`
/// while Claude Code files the transcript under the worktree, so the derived path
/// points at a file that does not exist. A caller that trusts this without
/// checking opens nothing and shows an empty conversation; one that checks falls
/// back to saying it has no transcript, which is true.
public enum TranscriptLocator {

    /// The directory name Claude Code derives from a working directory.
    ///
    /// **ASCII** letters and digits, deliberately: `Character.isLetter` is
    /// Unicode-aware and would preserve the `à` in `/Users/me/Città`, where the
    /// measured rule replaces it. Being clever here produces a path that is wrong
    /// only for people with accents in their folder names — the worst kind of bug
    /// to own.
    public static func directoryName(forWorkspace path: String) -> String {
        String(path.map { character in
            character.isASCII && (character.isLetter || character.isNumber)
                ? character
                : "-"
        })
    }

    /// Where the transcript would be. **Verify it exists before reading it.**
    public static func candidateURL(
        sessionId: String,
        cwd: String,
        home: URL? = nil
    ) -> URL {
        (home ?? AppConfig.homeDirectory)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(directoryName(forWorkspace: cwd), isDirectory: true)
            .appendingPathComponent("\(sessionId).jsonl")
    }
}
