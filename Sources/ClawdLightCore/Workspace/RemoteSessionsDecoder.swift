import Foundation

/// Turns what a remote machine reports into `LiveSession` values.
///
/// The node runs the two checks that only make sense where the processes are —
/// `kill(pid, 0)` and the transcript's modification time — and emits one JSON
/// array. This is the boundary where that crosses into the domain, so it
/// validates the way `HookPayloadDecoder` does: nothing required is ever inferred
/// or defaulted.
///
/// **One bad record does not lose the others.** The output comes from a machine
/// whose Claude Code version we do not control; a single unparsable entry is not
/// a reason to blank the column for the whole host.
public enum RemoteSessionsDecoder {

    /// - Parameters:
    ///   - data: the node's JSON array.
    ///   - host: the name it answers to over ssh, carried into each session's
    ///     workspace so a row can say where it is.
    public static func decode(_ data: Data, host: String) throws -> [LiveSession] {
        guard data.count <= AppConfig.maxRequestBodyBytes else {
            throw HookPayloadError.bodyTooLarge(data.count)
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
              let records = parsed as? [[String: Any]]
        else {
            return []
        }
        return records.compactMap { session(from: $0, host: host) }
    }

    /// `nil` for a record we cannot use, which is skipped rather than thrown.
    private static func session(from record: [String: Any], host: String) -> LiveSession? {
        guard let sessionId = string(record, "sessionId"),
              let cwd = string(record, "cwd"),
              cwd.hasPrefix("/")
        else {
            // A relative path would mean guessing which root it hangs off, on a
            // filesystem that is not ours to guess about.
            return nil
        }

        let pid = (record["pid"] as? NSNumber)?.intValue ?? 0
        guard pid > 0 else { return nil }

        // The node's clock, not this machine's: the whole point of asking it.
        let epoch = (record["activityEpoch"] as? NSNumber)?.doubleValue ?? 0

        // The same scanner the Mac runs on its own transcripts, over the
        // miniature the probe sent. One rule, one implementation, one set of
        // tests — the alternative was a copy of it in Python on a machine we do
        // not update, which is how two implementations of one rule start
        // disagreeing without anybody noticing.
        let context = (record["contextTail"] as? String)
            .flatMap { $0.isEmpty ? nil : ContextScanner.read(tail: $0) }

        return LiveSession(
            pid: pid,
            sessionId: sessionId,
            cwd: cwd,
            entrypoint: string(record, "entrypoint"),
            name: string(record, "name"),
            kind: string(record, "kind"),
            modifiedAt: Date(timeIntervalSince1970: epoch),
            host: host,
            context: context
        )
    }

    private static func string(_ record: [String: Any], _ key: String) -> String? {
        (record[key] as? String)?.trimmed.nilIfEmpty
    }
}
