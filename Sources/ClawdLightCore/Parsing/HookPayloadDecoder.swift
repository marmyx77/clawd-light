import Foundation

/// Decoding errors for a hook payload.
public enum HookPayloadError: Error, Equatable, CustomStringConvertible {
    case bodyTooLarge(Int)
    case invalidJSON
    case notAnObject
    case missingField(String)
    case emptyField(String)
    case relativePath(field: String, value: String)
    /// The event is syntactically valid but moves no traffic light.
    /// Not a fault: callers treat it as a no-op.
    case ignoredEvent(String)

    public var description: String {
        switch self {
        case .bodyTooLarge(let size):
            return "body of \(size) bytes exceeds the limit of \(AppConfig.maxRequestBodyBytes)"
        case .invalidJSON:
            return "body is not valid JSON"
        case .notAnObject:
            return "top-level JSON is not an object"
        case .missingField(let name):
            return "required field missing: \(name)"
        case .emptyField(let name):
            return "required field empty: \(name)"
        case .relativePath(let field, let value):
            return "field \(field) must be an absolute path, received: \(value)"
        case .ignoredEvent(let name):
            return "irrelevant event: \(name)"
        }
    }

    /// `true` when the error should be logged as an anomaly. `ignoredEvent` is business as usual.
    public var isFailure: Bool {
        if case .ignoredEvent = self { return false }
        return true
    }
}

/// Decodes and validates the JSON Claude Code hands to the hooks.
///
/// This is the only point where external data enters the domain, so it validates
/// strictly: no required field is ever inferred or filled in with a default.
public enum HookPayloadDecoder {
    /// - Parameters:
    ///   - data: request body.
    ///   - entrypoint: value of `CLAUDE_CODE_ENTRYPOINT` read by the hook script
    ///     and carried in a header; it is not present in Claude Code's JSON.
    public static func decode(_ data: Data, entrypoint: String? = nil) throws -> HookSignal {
        guard data.count <= AppConfig.maxRequestBodyBytes else {
            throw HookPayloadError.bodyTooLarge(data.count)
        }

        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw HookPayloadError.invalidJSON
        }

        guard let object = parsed as? [String: Any] else {
            throw HookPayloadError.notAnObject
        }

        let sessionId = try requiredString(object, key: "session_id")
        let eventName = try requiredString(object, key: "hook_event_name")
        let cwd = try requiredString(object, key: "cwd")

        guard cwd.hasPrefix("/") else {
            throw HookPayloadError.relativePath(field: "cwd", value: cwd)
        }

        guard let event = HookEventKind(rawValue: eventName) else {
            throw HookPayloadError.ignoredEvent(eventName)
        }

        return HookSignal(
            sessionId: sessionId,
            event: event,
            cwd: PathNormalizer.normalize(cwd),
            notificationKind: (object["notification_type"] as? String)
                .flatMap(NotificationKind.init(rawValue:)),
            agentId: optionalString(object, key: "agent_id"),
            entrypoint: entrypoint?.trimmed.nilIfEmpty,
            lastAssistantMessage: optionalString(object, key: "last_assistant_message"),
            sessionSource: optionalString(object, key: "source"),
            failureReason: failureReason(in: object, event: event),
            runningBackgroundTasks: runningBackgroundTasks(in: object),
            transcriptPath: absolutePath(object, key: "transcript_path")
        )
    }

    /// Cause of the interruption for `StopFailure`.
    ///
    /// Two field names are tried because the documentation uses both in different
    /// sections. If neither is present the cause stays `unknown`: what must never
    /// happen is for a missing field to make the turn look successful.
    private static func failureReason(
        in object: [String: Any],
        event: HookEventKind
    ) -> StopFailureReason? {
        guard event == .stopFailure else { return nil }
        let raw = optionalString(object, key: "error_type")
            ?? optionalString(object, key: "error")
        return StopFailureReason.from(rawValue: raw)
    }

    /// Counts the background shells still running at the end of the turn.
    ///
    /// Only `running` counts. A finished task is in the list too, and treating it
    /// as live would leave the row yellow for ever — the same stuck-counter failure
    /// the subagent design has a safety net for.
    private static func runningBackgroundTasks(in object: [String: Any]) -> Int {
        guard let tasks = object["background_tasks"] as? [[String: Any]] else { return 0 }
        return tasks.filter { ($0["status"] as? String) == "running" }.count
    }

    // MARK: - Helpers

    private static func requiredString(_ object: [String: Any], key: String) throws -> String {
        guard let raw = object[key] else {
            throw HookPayloadError.missingField(key)
        }
        guard let value = raw as? String else {
            throw HookPayloadError.missingField(key)
        }
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else {
            throw HookPayloadError.emptyField(key)
        }
        return trimmed
    }

    private static func optionalString(_ object: [String: Any], key: String) -> String? {
        (object[key] as? String)?.trimmed.nilIfEmpty
    }

    /// An optional field that is only usable as an absolute path.
    ///
    /// A relative one is dropped rather than kept: this value ends up being opened
    /// for reading, and resolving it against whatever the app's working directory
    /// happens to be would read a file nobody asked for.
    private static func absolutePath(_ object: [String: Any], key: String) -> String? {
        guard let value = optionalString(object, key: key), value.hasPrefix("/") else {
            return nil
        }
        return value
    }
}
