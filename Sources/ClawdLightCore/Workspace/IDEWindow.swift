import Foundation

/// An IDE window hosting a Claude Code connection, reconstructed from a lock file
/// in `~/.claude/ide/`.
public struct IDEWindow: Sendable, Equatable {
    /// Root folders open in the window.
    public let workspaceFolders: [String]

    /// IDE name declared in the lock (`Visual Studio Code`, `Cursor`, …).
    public let ideName: String

    /// PID of the IDE process. Careful: VS Code writes the same PID into every
    /// lock, one per window — so it does not identify the window, it only tells
    /// you whether the IDE is still alive.
    public let pid: Int

    /// Modification date of the lock, used to discard orphaned files.
    public let lockModifiedAt: Date

    public init(workspaceFolders: [String], ideName: String, pid: Int, lockModifiedAt: Date) {
        self.workspaceFolders = workspaceFolders.map(PathNormalizer.normalize)
        self.ideName = ideName
        self.pid = pid
        self.lockModifiedAt = lockModifiedAt
    }

    /// The editor that wrote this lock, if we know it.
    public var kind: IDEKind? {
        IDEKind.matching(declaredName: ideName)
    }

    /// `true` when we know how to bring this window to the front.
    ///
    /// The question used to be "is this Visual Studio Code?", and that answer
    /// discarded the forks that do have the Claude Code extension installed. Now
    /// it is "can we raise it?", which is what actually needs knowing.
    public var isSupported: Bool { kind != nil }

    /// `true` when the window belongs to Visual Studio Code.
    public var isVSCode: Bool { kind == .visualStudioCode }

    /// `true` when this lock still describes a window that exists.
    ///
    /// The question is **liveness, not age**. A lock file is written once, when the
    /// window connects, and never touched again — so its timestamp measures how
    /// long the window has been open, which is the opposite of what it was being
    /// used for. Windows left open for a week or two are normal, and every one of
    /// them silently disappeared from the column on its eighth day: five projects
    /// at once, on the machine where this was found.
    ///
    /// The lock carries the editor's `pid`, and it always did. If that process is
    /// running, the window is real however old the file is.
    ///
    /// Age remains the fallback for a lock with no usable pid — which is what the
    /// rule was always *for*, since locks are not always removed when a window
    /// closes.
    ///
    /// - Parameter alivePids: editor processes confirmed running.
    public func isUsable(
        at now: Date,
        alivePids: Set<Int>,
        maxAge: TimeInterval = AppConfig.ideLockMaxAge
    ) -> Bool {
        if pid > 0 { return alivePids.contains(pid) }
        return now.timeIntervalSince(lockModifiedAt) <= maxAge
    }
}

/// Errors reading a lock file.
public enum IDELockError: Error, Equatable {
    case invalidJSON
    case missingWorkspaceFolders
}

/// Decodes the JSON of a Claude Code lock file.
public enum IDELockParser {
    public static func parse(
        data: Data,
        modifiedAt: Date
    ) throws -> IDEWindow {
        guard
            let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
            let object = parsed as? [String: Any]
        else {
            throw IDELockError.invalidJSON
        }

        guard
            let folders = object["workspaceFolders"] as? [Any]
        else {
            throw IDELockError.missingWorkspaceFolders
        }

        let paths = folders.compactMap { $0 as? String }.filter { $0.hasPrefix("/") }
        guard !paths.isEmpty else {
            throw IDELockError.missingWorkspaceFolders
        }

        return IDEWindow(
            workspaceFolders: paths,
            ideName: (object["ideName"] as? String) ?? "",
            pid: (object["pid"] as? Int) ?? 0,
            lockModifiedAt: modifiedAt
        )
    }
}
