import LampBoardCore
import SwiftUI

/// Draws an answer the way it was written.
///
/// Blocks come from `MarkdownParser` in Core; this only decides how each one
/// looks. Inline markup — bold, italic, `code`, links — is handed to
/// `AttributedString`, because the platform already has a markdown parser for
/// exactly that and it would be silly to write a second one.
///
/// No dependency was added for this. The project has none, and a rendering
/// library would have brought a build story, a version to track and a surface to
/// keep up with, in exchange for constructs Claude does not write.
struct MarkdownView: View {

    let text: String

    /// Base size. Code steps down one point: monospaced glyphs read larger at the
    /// same nominal size, and a code block that shouts is a code block that takes
    /// over the bubble.
    var size: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(MarkdownParser.blocks(from: text)) { identified in
                block(identified.block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func block(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let value):
            inline(value)
                .font(.system(size: headingSize(level), weight: .semibold))
                .padding(.top, level <= 2 ? 4 : 1)

        case .paragraph(let value):
            inline(value).font(.system(size: size))

        case .list(let items, let start):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker(at: index, start: start))
                            .font(.system(size: size, design: start == nil ? .default : .monospaced))
                            .foregroundStyle(StatusPalette.timeColor)
                        inline(item).font(.system(size: size))
                    }
                }
            }

        case .code(let language, let value):
            codeBlock(language: language, text: value)

        case .quote(let value):
            HStack(spacing: 8) {
                Rectangle()
                    .fill(StatusPalette.pinMarker)
                    .frame(width: 2)
                inline(value)
                    .font(.system(size: size))
                    .foregroundStyle(Color.primary.opacity(0.82))
            }

        case .rule:
            Divider().padding(.vertical, 2)

        case .table(let header, let rows):
            table(header: header, rows: rows)
        }
    }

    // MARK: - Pieces

    /// A code block scrolls **sideways on its own** rather than wrapping.
    ///
    /// A wrapped command line is a command line you cannot copy and paste, and
    /// copying things out of here is most of why this window stays open. It also
    /// keeps a long line from widening the whole conversation.
    private func codeBlock(language: String?, text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language {
                Text(language)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(StatusPalette.timeColor)
                    .padding(.horizontal, 8)
                    .padding(.top, 5)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: size - 1, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.07))
        )
    }

    private func table(header: [String], rows: [[String]]) -> some View {
        // Also horizontal, and for the same reason: a table squeezed into the
        // bubble's width becomes one word per column.
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(header, isHeader: true)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    tableRow(row, isHeader: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                inline(cell)
                    .font(.system(size: size - 1, weight: isHeader ? .semibold : .regular))
                    .frame(minWidth: 40, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
    }

    /// Inline markup, via the platform's own parser.
    ///
    /// `inlineOnlyPreservingWhitespace` matters: the full syntax would try to
    /// handle the block constructs we have already split out, and would collapse
    /// the whitespace inside what is left.
    private func inline(_ value: String) -> Text {
        let attributed = (try? AttributedString(
            markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(value)
        return Text(attributed)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return size + 4
        case 2: return size + 2
        case 3: return size + 1
        default: return size
        }
    }

    private func marker(at index: Int, start: Int?) -> String {
        guard let start else { return "•" }
        return "\(start + index)."
    }
}
