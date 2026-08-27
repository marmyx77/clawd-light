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
    /// The name given to a folder, if any.
    public static func name(of path: String, in names: [String: String]) -> String? {
        names[PathNormalizer.normalize(path)]?.trimmed.nilIfEmpty
    }

    /// The table with one folder renamed; a blank name removes the entry, which
    /// is how "rename" doubles as "back to the original".
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
