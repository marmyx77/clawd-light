import Foundation

/// Turns a stream of bytes arriving in arbitrary chunks into whole entries.
///
/// This is the half of "follow a transcript" that can be wrong without anybody
/// noticing, so it lives here rather than next to the `FileHandle`: a transcript
/// is being written while it is read, which means a chunk almost always ends in
/// the middle of a JSON object. Parsing that fragment loses one record per read —
/// silently, and most often on the busiest session, where records arrive fastest
/// and the loss matters most.
///
/// The rule is one line: **only the part up to the last newline is ready.**
/// Everything after it is held back until the rest of it arrives.
public struct TranscriptTail: Sendable, Equatable {

    /// The fragment left over from the previous chunk.
    public private(set) var carry: String

    /// The title seen so far, if the stream has carried one.
    public private(set) var title: String?

    public init(carry: String = "", title: String? = nil) {
        self.carry = carry
        self.title = title
    }

    /// Feeds the next chunk and returns the entries that are now complete.
    public mutating func consume(_ chunk: String) -> [TranscriptEntry] {
        // `omittingEmptySubsequences: false` matters: it is what makes a chunk
        // ending exactly on a newline produce a final empty piece, which is how
        // "ended on a boundary" is told apart from "ended mid-line".
        var lines = (carry + chunk)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        carry = lines.popLast() ?? ""

        var entries: [TranscriptEntry] = []
        for line in lines where !line.isEmpty {
            if let found = TranscriptDecoder.title(fromLine: line) {
                title = found
                continue
            }
            entries.append(contentsOf: TranscriptDecoder.entries(fromLine: line))
        }
        return entries
    }

    /// Forgets everything, for a file that was replaced under us.
    public mutating func reset() {
        carry = ""
        title = nil
    }

    /// The last thing said inside a chunk read from the **end** of a transcript.
    ///
    /// This is how the conversation list gets a real preview without reading
    /// twenty-four whole files: seek near the end, read a slice, and look for the
    /// last thing a person or Claude actually said.
    ///
    /// The first line of such a slice is almost always half a record, because the
    /// read started at an arbitrary byte. It is **dropped**, not repaired: half a
    /// JSON object is not decodable, and pretending otherwise is how a preview
    /// ends up showing a fragment of a tool result.
    ///
    /// Returns `nil` when the slice holds nothing conversational — a long run of
    /// tool calls, which is exactly what the tail of a working session looks like.
    /// The caller then widens the slice or leaves the preview alone.
    public static func lastSpoken(inTailChunk chunk: String, isWholeFile: Bool = false) -> TranscriptEntry? {
        var lines = chunk.components(separatedBy: "\n")
        if !isWholeFile, !lines.isEmpty { lines.removeFirst() }

        for line in lines.reversed() where !line.isEmpty {
            let entries = TranscriptDecoder.entries(fromLine: line)
            if let spoken = entries.last(where: { $0.isConversation }) {
                return spoken
            }
        }
        return nil
    }
}
