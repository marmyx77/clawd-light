import Foundation

/// Finds, among the VS Code window titles, the one belonging to a workspace.
///
/// VS Code exposes no AppleScript dictionary, so the only handle for bringing
/// *that* window to the front is its title. The observed format is:
///
///     <context> — <folder> — <profile>
///     tsconfig.base.json — os-platform — Claude Minimal
///
/// The recognition logic lives here rather than inside an AppleScript script,
/// precisely so it can be verified without opening any windows.
public enum WindowTitleMatcher {

    /// Separators VS Code uses between title segments.
    /// The em dash is the default; the others cover custom `window.title` settings.
    private static let separators: [String] = ["—", "–", "-", "|", "·", "•"]

    /// Index of the title that best matches `workspaceName`, or `nil`.
    ///
    /// - Parameters:
    ///   - titles: titles in the order System Events returns them.
    public static func bestMatch(workspaceName: String, titles: [String]) -> Int? {
        let target = workspaceName.trimmed
        guard !target.isEmpty else { return nil }

        let scored = titles.enumerated().compactMap { index, title -> (Int, Int)? in
            guard let score = score(title: title, workspaceName: target) else { return nil }
            return (index, score)
        }

        // On a tie the first window wins: System Events lists them in depth order,
        // so the first one is the most recently used.
        return scored.max { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0 > rhs.0 : lhs.1 < rhs.1
        }?.0
    }

    /// Match score, `nil` when the title has nothing to do with the workspace.
    /// Higher = more reliable.
    static func score(title: String, workspaceName: String) -> Int? {
        let segments = split(title)

        // Exact match on a segment: the normal case and the most solid one.
        if segments.contains(where: { $0.caseInsensitiveCompare(workspaceName) == .orderedSame }) {
            return 100
        }

        // The window of a folder with spaces or suffixes ("clawd-light (Workspace)").
        if segments.contains(where: { segment in
            segment.hasPrefix(workspaceName + " ") || segment.hasSuffix(" " + workspaceName)
        }) {
            return 50
        }

        // Last resort: the name appears somewhere as a whole word.
        // Stops "clawd-light" from capturing the window of "clawd-light-old".
        if containsAsWord(title, workspaceName) {
            return 10
        }

        return nil
    }

    // MARK: - Helpers

    private static func split(_ title: String) -> [String] {
        var parts = [title]
        for separator in separators {
            parts = parts.flatMap { $0.components(separatedBy: " \(separator) ") }
        }
        return parts.map { $0.trimmed }.filter { !$0.isEmpty }
    }

    /// `true` when `needle` appears in `haystack` delimited by non-alphanumeric characters.
    private static func containsAsWord(_ haystack: String, _ needle: String) -> Bool {
        guard let range = haystack.range(of: needle, options: .caseInsensitive) else {
            return false
        }
        let isBoundary: (Character?) -> Bool = { character in
            guard let character else { return true }
            return !(character.isLetter || character.isNumber || character == "-" || character == "_")
        }
        let before = range.lowerBound > haystack.startIndex
            ? haystack[haystack.index(before: range.lowerBound)]
            : nil
        let after = range.upperBound < haystack.endIndex
            ? haystack[range.upperBound]
            : nil
        return isBoundary(before) && isBoundary(after)
    }
}
