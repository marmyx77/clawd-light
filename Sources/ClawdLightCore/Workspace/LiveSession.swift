import Foundation

/// A Claude Code session declared alive by the filesystem.
///
/// Claude Code writes one file per process at `~/.claude/sessions/<pid>.json`.
/// It is the only source that says which sessions **exist right now**: the hooks
/// only report what happens, never what disappeared. Without this source, closing
/// a panel leaves behind a clickable row that leads nowhere.
public struct LiveSession: Sendable, Equatable {
    public let pid: Int
    public let sessionId: String

    /// Working directory, from which the VS Code workspace is derived.
    public let cwd: String

    /// `claude-vscode`, `cli`, … Used to exclude terminal sessions.
    public let entrypoint: String?

    /// Readable name Claude Code derives from the project (`event-tracker-64`).
    public let name: String?

    /// `interactive` for sessions with a user in front of them.
    public let kind: String?

    /// Modification date of the file, used to estimate last activity when a
    /// session is discovered without ever having received a hook.
    public let modifiedAt: Date

    /// Copy with a different activity timestamp.
    public func with(modifiedAt newValue: Date) -> LiveSession {
        LiveSession(
            pid: pid, sessionId: sessionId, cwd: cwd, entrypoint: entrypoint,
            name: name, kind: kind, modifiedAt: newValue
        )
    }

    public init(
        pid: Int,
        sessionId: String,
        cwd: String,
        entrypoint: String?,
        name: String?,
        kind: String? = nil,
        modifiedAt: Date
    ) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = PathNormalizer.normalize(cwd)
        self.entrypoint = entrypoint
        self.name = name
        self.kind = kind
        self.modifiedAt = modifiedAt
    }

    /// `true` when the session deserves a row in the column.
    ///
    /// As with hook signals, the criterion is *where* it runs — which the
    /// workspace resolver decides — and not which command started it. What remains
    /// here is only the exclusion of what isn't interactive.
    ///
    /// `kind` is the most reliable source because Claude Code writes it itself;
    /// when it is missing we fall back to the entrypoint. A file declaring neither
    /// is kept: the risk of one row too many is smaller than the risk of a session
    /// you can't see.
    public var deservesTrafficLight: Bool {
        if let kind, !kind.isEmpty {
            return kind == AppConfig.interactiveSessionKind
        }
        guard let entrypoint, !entrypoint.isEmpty else { return true }
        return !AppConfig.nonInteractiveEntrypoints.contains(entrypoint)
    }
}

public enum LiveSessionError: Error, Equatable {
    case invalidJSON
    case missingField(String)
}

/// Decodes a file from `~/.claude/sessions/`.
public enum LiveSessionParser {
    public static func parse(data: Data, modifiedAt: Date) throws -> LiveSession {
        guard
            let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
            let object = parsed as? [String: Any]
        else {
            throw LiveSessionError.invalidJSON
        }

        guard
            let sessionId = (object["sessionId"] as? String)?.trimmed, !sessionId.isEmpty
        else {
            throw LiveSessionError.missingField("sessionId")
        }

        guard
            let cwd = (object["cwd"] as? String)?.trimmed, cwd.hasPrefix("/")
        else {
            throw LiveSessionError.missingField("cwd")
        }

        return LiveSession(
            pid: (object["pid"] as? Int) ?? 0,
            sessionId: sessionId,
            cwd: cwd,
            entrypoint: (object["entrypoint"] as? String)?.trimmed.nilIfEmpty,
            name: (object["name"] as? String)?.trimmed.nilIfEmpty,
            kind: (object["kind"] as? String)?.trimmed.nilIfEmpty,
            modifiedAt: modifiedAt
        )
    }
}
