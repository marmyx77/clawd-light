import Foundation

/// A block of an answer, ready to be drawn.
///
/// Claude writes markdown, and a chat window that shows it raw shows half a
/// message: headings become `##`, tables become a hedge of pipes, and code —
/// which is most of what gets copied out of this window — loses the one bit of
/// formatting that makes it readable.
///
/// The **parsing** lives here, in Core, where it can be tested against awkward
/// input without drawing anything. The rendering is in the shell, where SwiftUI
/// belongs. That split is the reason this is a value type and not a view.
public enum MarkdownBlock: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// A list. `start` is `nil` when it is a bullet list.
    case list(items: [String], start: Int?)
    /// A fenced block. The text is **literal** — no inline markup is applied.
    case code(language: String?, text: String)
    case quote(String)
    case rule
    case table(header: [String], rows: [[String]])
}

/// A block with a stable identity, so SwiftUI can draw a list of them.
public struct IdentifiedBlock: Sendable, Equatable, Identifiable {
    public let id: Int
    public let block: MarkdownBlock

    public init(id: Int, block: MarkdownBlock) {
        self.id = id
        self.block = block
    }
}
