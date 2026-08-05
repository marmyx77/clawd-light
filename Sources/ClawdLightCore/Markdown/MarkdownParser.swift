import Foundation

/// Splits an answer into blocks.
///
/// Deliberately **not** a general markdown implementation. It handles what Claude
/// actually writes — headings, paragraphs, lists, fenced code, quotes, rules and
/// pipe tables — and treats anything it does not recognise as a paragraph. That is
/// the safe direction to be wrong in: an unhandled construct comes out as its own
/// source text, which is readable, rather than disappearing.
///
/// Inline markup (bold, italic, `code`, links) is **left in the text** for the
/// renderer to apply. Doing it here would mean inventing a second attributed
/// string type in Core, and the platform already has one.
public enum MarkdownParser {

    /// The line that opens or closes a fenced block.
    private static let fence = "```"

    public static func blocks(from markdown: String) -> [IdentifiedBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = markdown.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmed

            // Fences first, and greedily: everything inside is literal, so no other
            // rule may look at it. A `# comment` in a shell snippet is not a heading.
            if trimmed.hasPrefix(fence) {
                let language = String(trimmed.dropFirst(fence.count)).trimmed.nilIfEmpty
                var body: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmed.hasPrefix(fence) {
                    body.append(lines[index])
                    index += 1
                }
                // Past the closing fence, or past the end when the answer was cut
                // off mid-block — which happens, and must not lose the code.
                index += 1
                blocks.append(.code(language: language, text: body.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if isRule(trimmed) {
                blocks.append(.rule)
                index += 1
                continue
            }

            if let heading = heading(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            // A table is recognised by its **second** line: a row of dashes between
            // pipes. Without that check every line containing a pipe — a shell
            // pipeline in prose, most often — would start a table.
            if trimmed.contains("|"), index + 1 < lines.count,
               isTableDivider(lines[index + 1].trimmed) {
                let (table, next) = table(from: lines, startingAt: index)
                blocks.append(table)
                index = next
                continue
            }

            if let (block, next) = list(from: lines, startingAt: index) {
                blocks.append(block)
                index = next
                continue
            }

            if trimmed.hasPrefix(">") {
                var body: [String] = []
                while index < lines.count, lines[index].trimmed.hasPrefix(">") {
                    var piece = lines[index].trimmed
                    piece.removeFirst()
                    body.append(piece.trimmed)
                    index += 1
                }
                blocks.append(.quote(body.joined(separator: "\n")))
                continue
            }

            var paragraph: [String] = []
            while index < lines.count {
                let candidate = lines[index].trimmed
                if candidate.isEmpty || candidate.hasPrefix(fence) || candidate.hasPrefix(">")
                    || isRule(candidate) || heading(candidate) != nil
                    || bulletBody(candidate) != nil || orderedBody(candidate) != nil {
                    break
                }
                paragraph.append(candidate)
                index += 1
            }
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            }
        }

        return blocks.enumerated().map { IdentifiedBlock(id: $0.offset, block: $0.element) }
    }

    /// A one-line, markup-free rendering, for the conversation list.
    public static func plainSummary(of markdown: String, limit: Int = 160) -> String {
        for identified in blocks(from: markdown) {
            switch identified.block {
            case .heading(_, let value), .paragraph(let value), .quote(let value):
                if let summary = shorten(strippingMarkup(value), to: limit) { return summary }
            case .list(let items, _):
                if let first = items.first,
                   let summary = shorten(strippingMarkup(first), to: limit) {
                    return summary
                }
            case .code(let language, _):
                // The contents say nothing useful in one line — the first line of a
                // code block is a shebang or an import. Returned **without**
                // stripping: the placeholder is ours, not the author's markup.
                return language.map { "<\($0) code>" } ?? "<code>"
            case .table:
                return "<table>"
            case .rule:
                continue
            }
        }
        return ""
    }

    /// Removes the inline emphasis markers, and only those.
    ///
    /// `*` and a backtick, and nothing else. The wider sweep that seemed obvious —
    /// also dropping `_`, `#` and `>` — mangles ordinary text: `snake_case` names
    /// lose their underscores, `#1` loses its hash, and `a > b` turns into `a  b`.
    /// The block parser has already removed the `#` and `>` that were structural,
    /// so what is left of them is prose.
    private static func strippingMarkup(_ value: String) -> String {
        value
            .replacingOccurrences(of: "[*`]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }

    private static func shorten(_ value: String, to limit: Int) -> String? {
        guard !value.isEmpty else { return nil }
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "…"
    }

    // MARK: - Pieces

    private static func heading(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = String(line.dropFirst(hashes))
        // `#hashtag` is not a heading: markdown wants the space.
        guard rest.hasPrefix(" ") || rest.isEmpty else { return nil }
        return .heading(level: hashes, text: rest.trimmed)
    }

    private static func isRule(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        return ["-", "_", "*"].contains { symbol in
            line.allSatisfy { String($0) == symbol }
        }
    }

    private static func bulletBody(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmed
        }
        return nil
    }

    private static func orderedBody(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2)).trimmed
    }

    private static func list(
        from lines: [String], startingAt start: Int
    ) -> (MarkdownBlock, Int)? {
        let first = lines[start].trimmed
        let ordered = bulletBody(first) == nil && orderedBody(first) != nil
        guard bulletBody(first) != nil || ordered else { return nil }

        let startNumber = ordered
            ? Int(first.prefix { $0.isNumber }) ?? 1
            : nil

        var items: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index].trimmed
            guard let body = ordered ? orderedBody(line) : bulletBody(line) else { break }
            items.append(body)
            index += 1
        }
        return (.list(items: items, start: startNumber), index)
    }

    private static func isTableDivider(_ line: String) -> Bool {
        guard line.contains("-"), line.contains("|") else { return false }
        return line.allSatisfy { "|-: ".contains($0) }
    }

    private static func table(
        from lines: [String], startingAt start: Int
    ) -> (MarkdownBlock, Int) {
        let header = cells(in: lines[start])
        var rows: [[String]] = []
        var index = start + 2                       // past the header and the divider

        while index < lines.count {
            let line = lines[index].trimmed
            guard line.contains("|"), !line.isEmpty else { break }
            rows.append(cells(in: lines[index]))
            index += 1
        }
        return (.table(header: header, rows: rows), index)
    }

    /// Splits a table row, tolerating the leading and trailing pipes that are
    /// optional in markdown and that Claude always writes.
    private static func cells(in line: String) -> [String] {
        var trimmed = line.trimmed
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmed }
    }
}
