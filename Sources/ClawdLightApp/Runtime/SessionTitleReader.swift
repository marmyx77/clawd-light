import ClawdLightCore
import Foundation

/// Reads a conversation's title out of its transcript on disk.
///
/// The file handling only; the rule lives in `TranscriptTitleScanner`, in Core,
/// where it is under test. Reads at most `TranscriptTitleScanner.headLimit`
/// bytes: a transcript can be tens of megabytes, and the title sits in its head.
enum SessionTitleReader {
    static func title(atPath path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: TranscriptTitleScanner.headLimit) else { return nil }
        return TranscriptTitleScanner.title(in: head)
    }
}
