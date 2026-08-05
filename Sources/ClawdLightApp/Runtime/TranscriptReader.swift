import ClawdLightCore
import Foundation

/// Reads a session transcript incrementally.
///
/// A transcript is an append-only JSONL file that reaches tens of thousands of
/// lines — this conversation's was 8,739 when the reader was written. Re-reading
/// it on every tick would make an open chat window cost more than the rest of the
/// app put together, so the reader keeps a byte offset and only ever looks at
/// what arrived since last time.
///
/// What is left here is the file handling; the part that decides where one record
/// ends and the next begins lives in `TranscriptTail`, in Core, where it is under
/// test. The two facts this file exists to get right:
///
/// - **The file can shrink.** A transcript can be replaced — `/clear`, a fork, a
///   session id reused after a crash. An offset past the end then reads garbage
///   or nothing forever, so a file smaller than the offset resets the reader
///   instead of trusting it.
/// - **Nothing changed is the common case.** One `stat` and an early return, so
///   an open window costs nothing between messages.
final class TranscriptReader {

    /// Absolute path of the file being followed.
    let path: String

    /// How far into the file we have already parsed.
    private var offset: UInt64 = 0

    /// Holds the half-written final line between reads.
    private var tail = TranscriptTail()

    /// The title Claude gave the conversation, once it has given one.
    var title: String? { tail.title }

    init(path: String) {
        self.path = path
    }

    /// Everything appended since the last call.
    ///
    /// Returns an empty array when nothing changed, which is the common case and
    /// deliberately cheap: one `stat`, no read, no parse.
    func readNewEntries() -> [TranscriptEntry] {
        guard let size = fileSize() else { return [] }

        if size < offset {
            // The file was replaced or truncated. Starting over is the only honest
            // option: we cannot know which of the entries we already showed are
            // still in there.
            offset = 0
            tail.reset()
        }

        guard size > offset else { return [] }

        guard let handle = try? FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }

        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(),
              !data.isEmpty
        else { return [] }

        offset = size

        // A transcript can hold text that is not valid UTF-8 — pasted binary,
        // a truncated multi-byte sequence at the read boundary. Replacing is
        // right: one mangled character beats losing the whole read.
        return tail.consume(String(decoding: data, as: UTF8.self))
    }

    /// Reads the file from the beginning, for a window opening on a conversation
    /// that was already long.
    func readAll() -> [TranscriptEntry] {
        offset = 0
        tail.reset()
        return readNewEntries()
    }

    // MARK: - Internals

    private func fileSize() -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber
        else { return nil }
        return size.uint64Value
    }
}
