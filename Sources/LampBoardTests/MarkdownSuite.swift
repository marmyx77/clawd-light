import LampBoardCore
import Foundation
import TestKit

/// Splitting an answer into blocks.
enum MarkdownParserSuite {

    private static func blocks(_ markdown: String) -> [MarkdownBlock] {
        MarkdownParser.blocks(from: markdown).map(\.block)
    }

    static let suite = TestSuite("Markdown parsing", [

        TestCase("Headings carry their level, and a hashtag is not one") { t in
            t.expectEqual(blocks("# Title"), [.heading(level: 1, text: "Title")], "h1")
            t.expectEqual(blocks("### Deep"), [.heading(level: 3, text: "Deep")], "h3")
            // No space after the hashes: markdown says that is not a heading, and
            // treating it as one eats the word.
            t.expectEqual(blocks("#hashtag"), [.paragraph("#hashtag")], "hashtag")
            // Seven is past the limit.
            t.expectEqual(blocks("####### too deep"), [.paragraph("####### too deep")], "h7")
        },

        // The case that justifies parsing fences before everything else.
        TestCase("A comment inside code is not a heading") { t in
            let markdown = """
            ```bash
            # install the thing
            brew install thing
            ```
            """
            t.expectEqual(
                blocks(markdown),
                [.code(language: "bash", text: "# install the thing\nbrew install thing")],
                "the shell comment must survive as code"
            )
        },

        TestCase("An unterminated fence keeps its contents") { t in
            // Answers get cut off — by a token limit, by an interrupt. Losing the
            // code because the closing fence never arrived would be the worst
            // possible response to that.
            let markdown = "```swift\nlet x = 1\nlet y = 2"
            t.expectEqual(
                blocks(markdown),
                [.code(language: "swift", text: "let x = 1\nlet y = 2")],
                "contents"
            )
        },

        TestCase("A fence with no language is still code") { t in
            t.expectEqual(blocks("```\nplain\n```"), [.code(language: nil, text: "plain")])
        },

        TestCase("Bullets and numbers become lists") { t in
            t.expectEqual(
                blocks("- one\n- two"),
                [.list(items: ["one", "two"], start: nil)],
                "bullets"
            )
            t.expectEqual(
                blocks("3. three\n4. four"),
                [.list(items: ["three", "four"], start: 3)],
                "numbered lists keep where they started"
            )
        },

        TestCase("A paragraph stops where the next block starts") { t in
            let markdown = "Some prose\nstill prose\n\n- a list"
            t.expectEqual(
                blocks(markdown),
                [.paragraph("Some prose\nstill prose"), .list(items: ["a list"], start: nil)],
                "blocks"
            )
        },

        TestCase("A table is read, header and rows") { t in
            let markdown = """
            | who | what |
            |-----|------|
            | me  | this |
            | you | that |
            """
            t.expectEqual(
                blocks(markdown),
                [.table(header: ["who", "what"], rows: [["me", "this"], ["you", "that"]])],
                "table"
            )
        },

        // Without checking the divider line, every shell pipeline written in prose
        // would open a table.
        TestCase("A pipe in prose is not a table") { t in
            let markdown = "run ls | grep foo and see"
            t.expectEqual(blocks(markdown), [.paragraph("run ls | grep foo and see")], "prose")
        },

        TestCase("Rules are rules, of every flavour") { t in
            for line in ["---", "***", "___", "-----"] {
                t.expectEqual(blocks(line), [.rule], "rule: \(line)")
            }
        },

        TestCase("Quotes lose their marker and keep their text") { t in
            t.expectEqual(blocks("> quoted\n> lines"), [.quote("quoted\nlines")], "quote")
        },

        TestCase("Empty input produces nothing at all") { t in
            t.expect(blocks("").isEmpty, "empty")
            t.expect(blocks("\n\n   \n").isEmpty, "whitespace")
        },

        // The constructs are tested one at a time above. This is the one that
        // matters: all of them in the same answer, in the order Claude writes
        // them. Parsers pass on isolated cases and fall over on the seams.
        TestCase("A whole answer comes apart in the right order") { t in
            let answer = """
            Verdict first, then the proof.

            ## What is already there

            | surface | verdict |
            |---------|---------|
            | hooks   | works   |
            | webview | blocked |

            Three things follow:

            - the first
            - the second

            ```bash
            # not a heading
            ./Scripts/check-contract.sh --live
            ```

            > and a warning

            ---

            1. then a numbered point
            """

            let kinds = blocks(answer).map { block -> String in
                switch block {
                case .heading: return "heading"
                case .paragraph: return "paragraph"
                case .list(_, let start): return start == nil ? "bullets" : "numbers"
                case .code: return "code"
                case .quote: return "quote"
                case .rule: return "rule"
                case .table: return "table"
                }
            }
            t.expectEqual(
                kinds,
                ["paragraph", "heading", "table", "paragraph", "bullets",
                 "code", "quote", "rule", "numbers"],
                "the seams between constructs are where parsers fail"
            )

            // And nothing may leak: a fence or a divider surviving into a
            // paragraph means that block was drawn as its own source text.
            for block in blocks(answer) {
                if case .paragraph(let text) = block {
                    t.expect(!text.contains("```"), "a fence leaked into prose: \(text)")
                    t.expect(!text.contains("|---"), "a table divider leaked: \(text)")
                }
            }
        },

        TestCase("Blocks are given distinct identities") { t in
            let identified = MarkdownParser.blocks(from: "# a\n\n# b\n\n# c")
            t.expectEqual(Set(identified.map(\.id)).count, 3, "SwiftUI needs them to differ")
        },
    ])
}

/// The one-line summary that goes under a name in the conversation list.
enum MarkdownSummarySuite {

    static let suite = TestSuite("Markdown summary", [

        TestCase("Markup is stripped, not shown") { t in
            t.expectEqual(
                MarkdownParser.plainSummary(of: "**Done.** See `Mailbox.swift`."),
                "Done. See Mailbox.swift.",
                "summary"
            )
        },

        TestCase("It takes the first thing that says something") { t in
            let markdown = "---\n\n# Heading\n\nthe paragraph"
            t.expectEqual(MarkdownParser.plainSummary(of: markdown), "Heading", "summary")
        },

        // A code block's first line is a shebang or an import: no use to anybody
        // scanning a list.
        TestCase("A code block is named, not quoted") { t in
            t.expectEqual(
                MarkdownParser.plainSummary(of: "```swift\nimport Foundation\n```"),
                "<swift code>",
                "summary"
            )
        },

        // What the first, blunter version of the strip got wrong. It removed
        // every `_`, `#` and `>`, which quietly mangles ordinary prose — and ate
        // the closing bracket of our own placeholder.
        TestCase("Ordinary text keeps its punctuation") { t in
            t.expectEqual(
                MarkdownParser.plainSummary(of: "check that a > b and rename snake_case to #1"),
                "check that a > b and rename snake_case to #1",
                "nothing may be eaten"
            )
        },

        TestCase("Newlines collapse into one line") { t in
            t.expectEqual(
                MarkdownParser.plainSummary(of: "first\nsecond\n\nthird"),
                "first second",
                "one line"
            )
        },

        TestCase("Long summaries are cut with a mark") { t in
            let long = String(repeating: "word ", count: 60)
            let summary = MarkdownParser.plainSummary(of: long, limit: 40)
            t.expect(summary.count <= 41, "length: \(summary.count)")
            t.expect(summary.hasSuffix("…"), "no ellipsis: \(summary)")
        },
    ])
}

/// Finding the last thing said by reading only the end of a transcript.
enum TranscriptPreviewSuite {

    private static func record(_ text: String, human: Bool) -> String {
        var object: [String: Any] = [
            "type": human ? "user" : "assistant",
            "uuid": UUID().uuidString,
            "timestamp": "2026-08-01T10:00:00.000Z",
            "sessionId": "s1",
        ]
        if human {
            object["origin"] = ["kind": "human"]
            object["message"] = ["role": "user", "content": text]
        } else {
            object["message"] = [
                "role": "assistant", "content": [["type": "text", "text": text]],
            ]
        }
        return String(
            decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self
        )
    }

    private static func toolCall() -> String {
        let object: [String: Any] = [
            "type": "assistant",
            "uuid": UUID().uuidString,
            "timestamp": "2026-08-01T10:00:00.000Z",
            "sessionId": "s1",
            "message": [
                "role": "assistant",
                "content": [["type": "tool_use", "name": "Read", "id": "t", "input": [:]]],
            ],
        ]
        return String(
            decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self
        )
    }

    static let suite = TestSuite("Transcript preview", [

        // The defining property: a slice from the middle of a file starts on half
        // a record, and half a JSON object must be dropped rather than repaired.
        TestCase("The first, partial line of a slice is discarded") { t in
            let chunk = "id\":\"broken\",\"type\":\"user\"}\n" + record("real answer", human: false)
            let spoken = TranscriptTail.lastSpoken(inTailChunk: chunk)
            t.expectEqual(spoken?.text, "real answer", "text")
        },

        TestCase("Read from the start, nothing is discarded") { t in
            let chunk = record("the only line", human: false)
            let spoken = TranscriptTail.lastSpoken(inTailChunk: chunk, isWholeFile: true)
            t.expectEqual(spoken?.text, "the only line", "text")
        },

        TestCase("It finds the last thing said, not the last record") { t in
            let chunk = [
                "", record("older", human: false), record("newer", human: true),
                toolCall(), toolCall(),
            ].joined(separator: "\n")
            let spoken = TranscriptTail.lastSpoken(inTailChunk: chunk)
            t.expectEqual(spoken?.text, "newer", "tool calls are not speech")
            t.expectEqual(spoken?.kind, .human, "kind")
        },

        // The tail of a working session is a wall of tool calls. Saying so lets
        // the caller widen the slice instead of showing a fragment.
        TestCase("A slice with nothing said returns nothing") { t in
            let chunk = ["", toolCall(), toolCall()].joined(separator: "\n")
            t.expectNil(TranscriptTail.lastSpoken(inTailChunk: chunk), "must report emptiness")
        },

        TestCase("Rubbish in the slice is survivable") { t in
            let chunk = ["", "not json at all", "{\"half\": ", record("fine", human: false)]
                .joined(separator: "\n")
            t.expectEqual(TranscriptTail.lastSpoken(inTailChunk: chunk)?.text, "fine", "text")
        },
    ])
}
