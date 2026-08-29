import LampBoardCore
import Foundation

/// The one-line preview under each name in the conversation list.
///
/// The obvious source is `last_assistant_message`, which the hooks already carry
/// and which costs nothing — but it is the wrong thing twice over: it is only ever
/// Claude's side, so a list of projects you just wrote to shows yesterday's
/// answers, and on an interrupted turn it holds the **error text** rather than
/// anything that was said.
///
/// So it reads the transcript. The cost is kept where it belongs by three things:
///
/// 1. **Only the tail is read.** 32 KB from the end, not the eight thousand lines
///    in front of it.
/// 2. **It widens rather than gives up.** The tail of a working session is a wall
///    of tool calls; when nothing conversational is in the slice it tries a bigger
///    one, twice, and then leaves the preview alone rather than reading the lot.
/// 3. **It is cached on the file's size.** A transcript only ever grows, so an
///    unchanged size means an unchanged answer, and a redraw of the list costs
///    one `stat` per row.
final class TranscriptPreviewReader {

    /// First slice. Comfortably more than one exchange, comfortably less than a
    /// file — an assistant turn with a long answer runs to a few kilobytes.
    private static let firstSlice = 32 * 1024

    /// How far it will widen before giving up: 32 KB, then 256 KB, then 2 MB.
    private static let widenings = 3

    private struct Cached {
        let size: UInt64
        let preview: String?
    }

    private var cache: [String: Cached] = [:]

    /// The last thing said in a conversation, as one plain line.
    ///
    /// - Parameter path: the transcript. An empty path yields `nil`.
    func preview(ofTranscriptAt path: String, for sessionId: String) -> String? {
        guard !path.isEmpty, let size = fileSize(of: path) else { return nil }

        if let cached = cache[sessionId], cached.size == size {
            return cached.preview
        }

        let preview = read(path: path, size: size).map {
            MarkdownParser.plainSummary(of: $0.text)
        }
        cache[sessionId] = Cached(size: size, preview: preview)
        return preview
    }

    /// Drops what is remembered about a session, for one that ended.
    func forget(sessionId: String) {
        cache.removeValue(forKey: sessionId)
    }

    // MARK: - Internals

    private func read(path: String, size: UInt64) -> TranscriptEntry? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        var slice = UInt64(Self.firstSlice)
        for _ in 0..<Self.widenings {
            let wholeFile = slice >= size
            let offset = wholeFile ? 0 : size - slice

            guard (try? handle.seek(toOffset: offset)) != nil,
                  let data = try? handle.readToEnd(),
                  !data.isEmpty
            else { return nil }

            if let spoken = TranscriptTail.lastSpoken(
                inTailChunk: String(decoding: data, as: UTF8.self),
                isWholeFile: wholeFile
            ) {
                return spoken
            }
            // Nothing was said in that slice — a long run of tool calls. Reading
            // the whole file to find out has no upper bound, so it widens a fixed
            // number of times and then leaves the row without a preview, which is
            // a smaller lie than a stale one.
            if wholeFile { return nil }
            slice *= 8
        }
        return nil
    }

    private func fileSize(of path: String) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber
        else { return nil }
        return size.uint64Value
    }
}
