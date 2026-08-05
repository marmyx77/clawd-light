import Foundation

/// Three shortcuts used wherever data arriving from outside is read.
///
/// They live here rather than next to the decoder because the app shell uses
/// them too: a field read from a file or a header needs cleaning up just as much
/// as one read from a JSON payload.
extension String {
    /// The string without leading or trailing whitespace and newlines.
    public var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `nil` when the string is empty, the string otherwise.
    ///
    /// Used to collapse "field absent" and "field present but empty" at the point
    /// where the difference stops mattering: from there on both mean "not there".
    public var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    /// The string padded with spaces out to the given width.
    ///
    /// Needed to line up terminal output: `String(format:)` honors a width on C's
    /// numeric and textual placeholders but **ignores** it on `%@`, and the result
    /// is columns jammed together. Anyone meeting this for the first time loses a
    /// quarter of an hour hunting for a mistake in the format string.
    public func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
