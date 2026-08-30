import Foundation

/// Whether a conversation is in the middle of a turn, read from its transcript.
///
/// Every other surface is **told** what colour it is: a hook fires and says
/// `Stop`, or `UserPromptSubmit`, and the panel repeats what it was told. This
/// one cannot be. A Claude Desktop session runs with its own `CLAUDE_CONFIG_DIR`
/// inside the application's data, so the hooks registered on this machine are
/// not its hooks, and there is nowhere to put ours that exists before the
/// session does.
///
/// What it does leave is the transcript, and a transcript is not a rumour: it is
/// the record the session writes about itself, in the format this project
/// already reads for timestamps and for context. So the colour here is
/// **derived**, and the difference from a colour that was reported is real and
/// is declared rather than hidden — see `Harness.cannotReport`.
///
/// Two phases only, because two are all the file can carry honestly:
///
/// - the last record is the assistant asking for a tool, or the user answering
///   one, or a fresh prompt: **the turn is running**
/// - the last record is the assistant speaking in words: **the turn ended and
///   there is something to read**
///
/// What it cannot see is a session stopped waiting for a permission. That turn
/// has not ended and no record marks the pause, so it reads as running. It is
/// the state the panel exists for and this surface cannot give it: better to say
/// so than to guess it.
public enum TranscriptTurn {

    public enum Phase: Sendable, Equatable {
        /// A turn is in progress.
        case running
        /// The assistant finished speaking; there is an answer nobody has read.
        case answered
    }

    /// The phase of the last record that carries one.
    ///
    /// Records that say nothing about a turn — a summary, the bookkeeping rows
    /// written by tooling around the session — are stepped over rather than
    /// treated as an answer. That is the same rule `TranscriptActivity` follows
    /// for timestamps, and for the same reason: a row that has been appended to
    /// a file is not a thing a conversation said.
    ///
    /// - Parameter isWholeFile: `false` means the chunk was read from the end
    ///   and its first line is a fragment, which is dropped.
    public static func phase(inTailChunk chunk: String, isWholeFile: Bool = false) -> Phase? {
        var lines = chunk.split(separator: "\n", omittingEmptySubsequences: true)
        if !isWholeFile, !lines.isEmpty { lines.removeFirst() }

        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = record["type"] as? String
            else { continue }

            switch type {
            case "user":
                // Either a prompt just sent or a tool's result handed back. Both
                // mean the model has the floor.
                return .running
            case "assistant":
                guard let message = record["message"] as? [String: Any] else { continue }
                return speaks(message) ? .answered : .running
            default:
                continue
            }
        }
        return nil
    }

    /// `true` when the assistant's message is words rather than a tool call.
    ///
    /// A message can hold both — a sentence and then a tool call — and then the
    /// turn is **not** over: the tool call is the last thing it did. So the test
    /// is for the absence of a tool call, not for the presence of text.
    private static func speaks(_ message: [String: Any]) -> Bool {
        guard let content = message["content"] else { return false }
        if content is String { return true }
        guard let blocks = content as? [[String: Any]] else { return false }
        if blocks.contains(where: { ($0["type"] as? String) == "tool_use" }) { return false }
        return blocks.contains { ($0["type"] as? String) == "text" }
    }
}
