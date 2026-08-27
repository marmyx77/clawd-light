import Foundation

/// Where a window opening on a long transcript starts reading.
///
/// It shows the last `AppConfig.chatHistoryLimit` entries, so it does not need
/// the whole file — and the whole file can be half a gigabyte. Reading it all
/// into memory and parsing it on the main thread was ten to thirty seconds of
/// beachball on every ⌘+click; reading the last few megabytes is the same window
/// in a fraction of a second. The title lives in the file's head and is read
/// separately (`TranscriptTitleScanner`).
public enum TranscriptWindow {
    /// The offset to start from: the beginning for a file that fits, otherwise
    /// `window` bytes before the end.
    public static func initialOffset(fileSize: UInt64, window: UInt64 = UInt64(AppConfig.transcriptInitialWindow)) -> UInt64 {
        fileSize > window ? fileSize - window : 0
    }

    /// A read that started mid-file starts mid-record: the bytes up to and
    /// including the first newline belong to a line whose beginning we do not
    /// have. Dropped, so the first line handed to the parser is a whole one.
    public static func trimmedToLineStart(_ data: Data) -> Data {
        guard let newline = data.firstIndex(of: 0x0A) else { return Data() }
        return data.subdata(in: data.index(after: newline)..<data.endIndex)
    }
}
