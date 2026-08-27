import Foundation

/// Reads the conversation title out of the head of a transcript.
///
/// The rule is the one the chat window already uses — `TranscriptTail` keeps the
/// last `ai-title` record it sees — applied to the first `headLimit` bytes rather
/// than to a stream. One rule, two readers: a column and a window that named the
/// same file under two rules would disagree the first time the title changed.
///
/// Measured on four hundred transcripts: the first `ai-title` sits within 119 KB
/// of the start, and the record repeats identically afterwards. Half a megabyte
/// is a wide margin, and it bounds what a title costs on a transcript that has
/// grown to tens of megabytes.
public enum TranscriptTitleScanner {
    public static let headLimit = 512 * 1024

    public static func title(in data: Data) -> String? {
        let head = data.prefix(headLimit)
        var tail = TranscriptTail()
        _ = tail.consume(String(decoding: head, as: UTF8.self))
        return tail.title
    }
}
