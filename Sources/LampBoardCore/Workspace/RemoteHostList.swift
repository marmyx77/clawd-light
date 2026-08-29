import Foundation

/// The machines to read sessions from.
///
/// One name per line in `~/.lampboard/remotes`, `#` starts a comment. A name is
/// whatever `ssh` already understands — an entry in `~/.ssh/config`, a hostname, a
/// `user@host`. Nothing is invented here: if ssh cannot reach it, neither can we.
///
/// **Absent or empty means off**, and that is the default. Reading another machine
/// is an outbound connection this app would otherwise never make, and the project
/// does not start those unless somebody asked.
public enum RemoteHostList {

    /// Hosts, in file order, without duplicates.
    public static func parse(_ contents: String) -> [String] {
        var seen = Set<String>()
        return contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                // A trailing comment is stripped, so `node # the always-on box` works.
                let withoutComment = line.split(separator: "#", maxSplits: 1).first ?? ""
                return String(withoutComment).trimmed
            }
            .filter { !$0.isEmpty }
            .filter { isUsable($0) }
            .filter { seen.insert($0).inserted }
    }

    /// `true` when the name is safe to hand to `ssh` as an argument.
    ///
    /// An allow-list, and for the same reason as `Mailbox.isValidSessionId`: this
    /// value becomes an argument to a process. It never reaches a shell — the
    /// reader spawns ssh directly, with no interpretation — but a name carrying a
    /// space or a leading dash would still be read by ssh as *options*, and that
    /// is a door worth keeping shut.
    public static func isUsable(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, !host.hasPrefix("-") else { return false }
        return host.allSatisfy { character in
            character.isASCII
                && (character.isLetter || character.isNumber
                    || character == "." || character == "-" || character == "_"
                    || character == "@" || character == ":")
        }
    }
}
