import Foundation
import LampBoardCore

/// Reads, from the rollout an event names, who will answer its permission request.
///
/// Lives in the shell because it touches a file: the reducer receives the answer,
/// never the path. See `CodexApproval` for what is read and why the row depends
/// on it.
enum CodexApprovalReader {

    /// How much of the tail is read.
    ///
    /// The `turn_context` records are written when the turn's settings are
    /// established, so the one in force is normally close to the end — ten of them
    /// in a rollout of two thousand records, measured. Reading the whole file on
    /// every request would make the cost grow with the length of a conversation,
    /// which is the wrong thing to make expensive. When the answer is not in the
    /// tail the reader says it does not know, and not knowing shows the request.
    private static let tailBytes = 512 * 1024

    /// The reviewer for this signal, or `nil` when it cannot be known.
    ///
    /// Only asked for a Codex permission request: no other event changes what the
    /// row says about waiting, and no other harness publishes this one.
    static func reviewer(for signal: HookSignal) -> ApprovalReviewer? {
        guard signal.harness == .codex, signal.event == .permissionRequest,
              let path = signal.transcriptPath, !path.isEmpty
        else { return nil }
        guard let text = tail(ofFileAt: path) else { return nil }
        return CodexApproval.reviewer(inRollout: text.components(separatedBy: "\n"))
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
