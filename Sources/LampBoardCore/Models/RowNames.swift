import Foundation

/// The names the user gave to rows, keyed by the row's folder.
///
/// A name overrides what the panel **shows** — never what the session is: the
/// window title, the folder, the transcript keep their own names, and the row
/// is still found by them. Keyed by folder rather than by session, on purpose:
/// a session id is born and dies with a process, and a name that vanished with
/// every restart would be a name you gave twice a day. A folder is the row's
/// identity (D4, D23), so the name follows the row.
public enum RowNames {

    /// Where one row's own name lives: the folder and the agent together.
    ///
    /// A folder can hold a Claude row and a Codex row at once, and they need two
    /// names or they are told apart by a single letter inside a sixteen-point
    /// ring. The separator is a unit separator rather than a slash or a colon,
    /// because a folder path may contain either and this key must not be
    /// ambiguous for any path a filesystem allows.
    private static func key(_ path: String, _ harness: Harness) -> String {
        "\(PathNormalizer.normalize(path))\u{1F}\(harness.rawValue)"
    }

    /// Where one conversation's own name lives.
    ///
    /// Prefixed rather than bare, because a folder key is an absolute normalized
    /// path and a session id is a UUID: without the prefix an id that happened to
    /// look like a path would land in the folder's cell. The names stored here
    /// outlive the sessions they name, which costs a few bytes each and can never
    /// be shown again, since an id is never reused.
    private static func sessionKey(_ id: String) -> String { "session\u{1F}\(id)" }

    /// The name the user gave one conversation, if any.
    public static func name(ofSession id: String, in names: [String: String]) -> String? {
        names[sessionKey(id)]?.trimmed.nilIfEmpty
    }

    /// The table with **one conversation** renamed, and nothing else touched.
    ///
    /// This is the level that was missing, and its absence was a defect somebody
    /// met: with one row per session, renaming one renamed every other session in
    /// the folder, because the most specific key held the folder and the agent and
    /// never the conversation.
    public static func renaming(session id: String, to name: String?, in names: [String: String]) -> [String: String] {
        var next = names
        let key = sessionKey(id)
        if let name = name?.trimmed.nilIfEmpty {
            next[key] = String(name.prefix(maxLength))
        } else {
            next.removeValue(forKey: key)
        }
        return next
    }

    /// The name to show a row: its own if it has one, otherwise the folder's.
    ///
    /// Two lookups and not one, because every name given before rows could split
    /// is stored against the folder alone. Reading only the specific key would
    /// rename somebody's entire column back to its folder names on the release
    /// that introduced the split, which is the kind of upgrade nobody forgives.
    public static func name(of path: String, harness: Harness, in names: [String: String]) -> String? {
        names[key(path, harness)]?.trimmed.nilIfEmpty
            ?? names[PathNormalizer.normalize(path)]?.trimmed.nilIfEmpty
    }

    /// The name given to a folder, ignoring any agent. What the notifier and the
    /// command line use, because both speak about a project rather than a row.
    public static func name(of path: String, in names: [String: String]) -> String? {
        names[PathNormalizer.normalize(path)]?.trimmed.nilIfEmpty
    }

    /// The table with **one row** renamed.
    ///
    /// A blank name removes that row's own entry, which gives it the folder's
    /// name back rather than no name at all: "rename" doubles as "undo", and
    /// undoing a row's name should not also undo the project's.
    public static func renaming(
        _ path: String, harness: Harness, to name: String?, in names: [String: String]
    ) -> [String: String] {
        var next = names
        let specific = key(path, harness)
        if let name = name?.trimmed.nilIfEmpty {
            next[specific] = String(name.prefix(maxLength))
        } else {
            next.removeValue(forKey: specific)
        }
        return next
    }

    /// The table with a **folder** renamed, for every row that has no name of its
    /// own. This is what `lampboard rename` writes, and the split is deliberate:
    /// the menu renames the row you right-clicked, the command renames the project.
    public static func renaming(_ path: String, to name: String?, in names: [String: String]) -> [String: String] {
        var next = names
        let key = PathNormalizer.normalize(path)
        if let name = name?.trimmed.nilIfEmpty {
            next[key] = String(name.prefix(maxLength))
        } else {
            next.removeValue(forKey: key)
        }
        return next
    }

    /// Long enough for a sentence, short enough not to become the row.
    public static let maxLength = 60
}
