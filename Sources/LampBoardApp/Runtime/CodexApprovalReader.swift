import Foundation
import LampBoardCore

/// Reads, from the rollout an event names, who will answer its permission request.
///
/// Lives in the shell because it touches a file: the reducer receives the answer,
/// never the path. See `CodexApproval` for what is read and why the row depends
/// on it.
enum CodexApprovalReader {

    /// How much of the tail is read first.
    ///
    /// A `turn_context` is written when the settings of a turn are established, so
    /// a newly written one is always at the end and the tail answers cheaply. What
    /// the tail cannot answer is a long session whose settings never changed:
    /// measured on an audit of a whole codebase, rollouts of 1.8 MB and 3.5 MB
    /// whose only `turn_context` sat in the first records, far outside any tail.
    ///
    /// Reading only the tail was the first version of this file, and it put those
    /// sessions straight back to blinking amber — the defect it exists to fix,
    /// reported within minutes of shipping. So the tail is an optimisation, never
    /// the answer: when it says nothing, the whole file is read.
    private static let tailBytes = 512 * 1024

    /// What the whole file said, for a rollout whose tail does not carry it.
    ///
    /// Without this, a 3.5 MB rollout would be read from the start on **every**
    /// request, and those are exactly the sessions that make many. The entry stays
    /// valid however much the file grows: a `turn_context` written later lands in
    /// the tail, and the tail is consulted first, so a fresher answer always wins
    /// over this one.
    private static let remembered = Remembered()

    private final class Remembered: @unchecked Sendable {
        private let lock = NSLock()
        private var byPath: [String: ApprovalReviewer] = [:]

        func value(for path: String) -> ApprovalReviewer? {
            lock.lock(); defer { lock.unlock() }
            return byPath[path]
        }

        func remember(_ reviewer: ApprovalReviewer, for path: String) {
            lock.lock(); defer { lock.unlock() }
            byPath[path] = reviewer
        }
    }

    /// The reviewer for this signal, or `nil` when it cannot be known.
    ///
    /// Only asked for a Codex permission request: no other event changes what the
    /// row says about waiting, and no other harness publishes this one.
    static func reviewer(for signal: HookSignal) -> ApprovalReviewer? {
        guard signal.harness == .codex, signal.event == .permissionRequest,
              let path = signal.transcriptPath, !path.isEmpty
        else { return nil }
        // The tail first: it holds the newest `turn_context`, and the newest one is
        // the one in force.
        if let text = tail(ofFileAt: path),
           let fresh = CodexApproval.reviewer(inRollout: text.components(separatedBy: "\n")) {
            return fresh
        }
        // Nothing in the tail. Either this session never changed its settings, or
        // the rollout is long enough that the record sits outside it.
        if let known = remembered.value(for: path) { return known }
        guard let whole = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        guard let found = CodexApproval.reviewer(inRollout: whole.components(separatedBy: "\n"))
        else { return nil }
        remembered.remember(found, for: path)
        return found
    }

    /// The last `tailBytes` of a file, as text, or `nil` if it cannot be read.
    ///
    /// A partial first line is expected and harmless: the parser skips whatever
    /// does not decode, and a truncated record decodes as nothing rather than as
    /// something wrong.
    private static func tail(ofFileAt path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        do {
            let end = try handle.seekToEnd()
            let start = end > UInt64(tailBytes) ? end - UInt64(tailBytes) : 0
            try handle.seek(toOffset: start)
            guard let data = try handle.readToEnd() else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
