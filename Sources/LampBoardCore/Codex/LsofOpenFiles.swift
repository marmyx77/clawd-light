import Foundation

/// One regular file a process holds open.
public struct OpenFile: Sendable, Equatable {
    public let pid: Int32
    public let command: String
    public let path: String

    public init(pid: Int32, command: String, path: String) {
        self.pid = pid
        self.command = command
        self.path = path
    }
}

/// What `lsof -nP -F pcftn -p <pids>` says about the files a process holds open.
///
/// Field output rather than columns, and that is not a preference: a path may
/// contain spaces, and the column form has already cost this project an
/// afternoon somewhere else. In field mode every line is one letter and one
/// value, so a name is whatever follows `n` and nothing has to be guessed from
/// its shape.
///
/// The evidence this parses is the whole reason a Codex session can be seen at
/// all. A rollout file on disk proves a session **existed**; a live process
/// holding that file open proves it exists **now**, and the executable behind the
/// pid says which of the three Codex surfaces it is. Nothing else on this machine
/// offers all three at once.
public enum LsofOpenFiles {

    /// Parses field output. Only regular files come out: sockets, pipes and the
    /// working directory are not evidence of anything here.
    ///
    /// Nothing fails loudly. An empty result means "this call saw no open file",
    /// which the caller must not confuse with "the session is gone" — a probe
    /// that did not answer is absence of evidence, and the difference is the one
    /// that decides whether a row survives.
    public static func parse(_ output: String) -> [OpenFile] {
        var files: [OpenFile] = []
        var pid: Int32?
        var command = ""
        var type: String?

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value)
                command = ""
                type = nil
            case "c":
                command = value
            case "f":
                // A new descriptor: whatever the last one was, it is over.
                type = nil
            case "t":
                type = value
            case "n":
                guard let pid, type == "REG", value.hasPrefix("/") else { break }
                files.append(OpenFile(pid: pid, command: command, path: value))
            default:
                break
            }
        }
        return files
    }

    /// The open files that live under `root`, which is how a rollout is told from
    /// every other file a process happens to have open.
    ///
    /// Compares normalised paths and requires a real descendant, so a sibling
    /// directory whose name merely starts the same way cannot pass. `~/.codexes`
    /// is not `~/.codex`.
    public static func under(_ root: String, in files: [OpenFile]) -> [OpenFile] {
        under([root], in: files)
    }

    /// The same, against several spellings of the same place.
    ///
    /// `lsof` reports the **real** path and a root can be reached through a link:
    /// on every Mac `/var` is a link to `/private/var`, which is where a temporary
    /// Codex home lands. Comparing one spelling against the other matched nothing
    /// and said so quietly, as a scan that succeeded and found no sessions.
    ///
    /// Foundation is no help here on purpose: `resolvingSymlinksInPath` leaves
    /// `/var/folders` exactly as it found it, so the caller resolves with
    /// `realpath` and hands both spellings in.
    public static func under(_ roots: [String], in files: [OpenFile]) -> [OpenFile] {
        let prefixes = Set(roots.map { PathNormalizer.normalize($0) + "/" })
        return files.filter { file in
            let path = PathNormalizer.normalize(file.path)
            return prefixes.contains { path.hasPrefix($0) }
        }
    }
}
