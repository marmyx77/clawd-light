import ClawdLightCore
import Foundation
import TestKit

/// Reading a transcript: who spoke, and what counts as speaking.
///
/// The shapes here are copied from real records, not invented. The ratio they
/// encode is the reason the suite exists: in the transcript this project was
/// written in, 1683 of the 1802 `user` records were tool results.
enum TranscriptDecoderSuite {

    private static func line(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }

    private static func humanRecord(_ text: String, uuid: String = "u1") -> String {
        line([
            "type": "user",
            "uuid": uuid,
            "timestamp": "2026-07-31T10:00:00.000Z",
            "sessionId": "s1",
            "origin": ["kind": "human"],
            "message": ["role": "user", "content": [["type": "text", "text": text]]],
        ])
    }

    static let suite = TestSuite("Transcript decoding", [

        TestCase("A typed message becomes a human entry") { t in
            let entries = TranscriptDecoder.entries(fromLine: humanRecord("how do I start it?"))
            t.expectEqual(entries.count, 1, "one entry")
            t.expectEqual(entries.first?.kind, .human, "kind")
            t.expectEqual(entries.first?.text, "how do I start it?", "text")
        },

        // The load-bearing case. A tool result is a `user` record with a `user`
        // role, and rendering it as a bubble puts words in the user's mouth that
        // they never said — for the majority of the file.
        TestCase("A tool result is not a message, however much it looks like one") { t in
            let entries = TranscriptDecoder.entries(fromLine: line([
                "type": "user",
                "uuid": "u2",
                "timestamp": "2026-07-31T10:00:01.000Z",
                "sessionId": "s1",
                "toolUseResult": ["stdout": "ok"],
                "message": [
                    "role": "user",
                    "content": [["type": "tool_result", "content": "ok", "tool_use_id": "t1"]],
                ],
            ]))
            t.expect(entries.isEmpty, "produced \(entries.count) entries, expected none")
        },

        // Belt and braces: even a `user` record whose content is plain text is
        // discarded without the origin. Claude Code injects such records itself.
        TestCase("A user record without origin.kind is discarded") { t in
            let entries = TranscriptDecoder.entries(fromLine: line([
                "type": "user",
                "uuid": "u3",
                "timestamp": "2026-07-31T10:00:02.000Z",
                "sessionId": "s1",
                "message": ["role": "user", "content": [["type": "text", "text": "injected"]]],
            ]))
            t.expect(entries.isEmpty, "an unattributed record must not become a bubble")
        },

        // The case that measurement turned up, and the one the tool-result test
        // does NOT cover: injected context carries no `toolUseResult`, so the
        // tempting shortcut ("not a tool result, therefore a person") promotes it.
        // Across 60 recent transcripts that shortcut invents 579 user messages
        // against 209 real ones.
        TestCase("Injected context is not something the user said") { t in
            for flag in ["isMeta", "isVisibleInTranscriptOnly"] {
                let entries = TranscriptDecoder.entries(fromLine: line([
                    "type": "user",
                    "uuid": "u3-\(flag)",
                    "timestamp": "2026-07-31T10:00:02.000Z",
                    "sessionId": "s1",
                    flag: true,
                    "message": [
                        "role": "user",
                        "content": [["type": "text", "text": "<system-reminder>…</system-reminder>"]],
                    ],
                ]))
                t.expect(entries.isEmpty, "\(flag) reached the conversation")
            }
        },

        // A background agent reporting in is a fact, not a line of dialogue.
        TestCase("A task notification is a note, never a bubble") { t in
            let entries = TranscriptDecoder.entries(fromLine: line([
                "type": "user",
                "uuid": "u7",
                "timestamp": "2026-07-31T10:00:09.000Z",
                "sessionId": "s1",
                "origin": ["kind": "task-notification"],
                "message": ["role": "user", "content": [["type": "text", "text": "agent finished"]]],
            ]))
            t.expectEqual(entries.first?.kind, .note, "kind")
        },

        TestCase("An answer and its tool calls are two different lines") { t in
            let entries = TranscriptDecoder.entries(fromLine: line([
                "type": "assistant",
                "uuid": "a1",
                "timestamp": "2026-07-31T10:00:03.000Z",
                "sessionId": "s1",
                "message": [
                    "role": "assistant",
                    "content": [
                        ["type": "thinking", "thinking": "hidden"],
                        ["type": "text", "text": "Done."],
                        ["type": "tool_use", "name": "Read", "id": "t1", "input": [:]],
                        ["type": "tool_use", "name": "Read", "id": "t2", "input": [:]],
                        ["type": "tool_use", "name": "Edit", "id": "t3", "input": [:]],
                    ],
                ],
            ]))
            t.expectEqual(entries.count, 2, "answer plus activity")
            t.expectEqual(entries.first?.kind, .assistant, "first is the answer")
            t.expectEqual(entries.first?.text, "Done.", "the thinking stays out")
            t.expectEqual(entries.last?.kind, .activity, "second is the activity")
            t.expectEqual(entries.last?.text, "Read ×2 · Edit", "tools folded, order kept")
        },

        TestCase("Two entries from one record get distinct ids") { t in
            let entries = TranscriptDecoder.entries(fromLine: line([
                "type": "assistant",
                "uuid": "a2",
                "timestamp": "2026-07-31T10:00:04.000Z",
                "sessionId": "s1",
                "message": [
                    "role": "assistant",
                    "content": [
                        ["type": "text", "text": "ok"],
                        ["type": "tool_use", "name": "Bash", "id": "t1", "input": [:]],
                    ],
                ],
            ]))
            // Identical ids would make SwiftUI collapse them into one row.
            t.expectEqual(Set(entries.map(\.id)).count, 2, "ids must differ")
        },

        TestCase("An answer with no tools produces no activity line") { t in
            let entries = TranscriptDecoder.entries(fromLine: line([
                "type": "assistant",
                "uuid": "a3",
                "timestamp": "2026-07-31T10:00:05.000Z",
                "sessionId": "s1",
                "message": ["role": "assistant", "content": [["type": "text", "text": "yes"]]],
            ]))
            t.expectEqual(entries.count, 1, "just the answer")
            t.expectEqual(entries.first?.kind, .assistant, "kind")
        },

        TestCase("An attachment leaves a trace instead of vanishing") { t in
            let entries = TranscriptDecoder.entries(fromLine: line([
                "type": "user",
                "uuid": "u4",
                "timestamp": "2026-07-31T10:00:06.000Z",
                "sessionId": "s1",
                "origin": ["kind": "human"],
                "message": [
                    "role": "user",
                    "content": [
                        ["type": "image", "source": ["type": "base64"]],
                        ["type": "text", "text": "look at this"],
                    ],
                ],
            ]))
            t.expectEqual(entries.count, 1, "one entry")
            t.expect(
                entries.first?.text.contains("[image]") == true,
                "the image left no trace: \(entries.first?.text ?? "-")"
            )
        },

        TestCase("Content as a bare string is read too") { t in
            let entries = TranscriptDecoder.entries(fromLine: line([
                "type": "user",
                "uuid": "u5",
                "timestamp": "2026-07-31T10:00:07.000Z",
                "sessionId": "s1",
                "origin": ["kind": "human"],
                "message": ["role": "user", "content": "thanks"],
            ]))
            t.expectEqual(entries.first?.text, "thanks", "text")
        },

        TestCase("A compaction is a visible boundary") { t in
            let entries = TranscriptDecoder.entries(fromLine: line([
                "type": "user",
                "uuid": "u6",
                "timestamp": "2026-07-31T10:00:08.000Z",
                "sessionId": "s1",
                "isCompactSummary": true,
                "message": ["role": "user", "content": [["type": "text", "text": "summary…"]]],
            ]))
            t.expectEqual(entries.first?.kind, .note, "compaction is a note")
        },

        // Adding record types is what Claude Code does between releases. Treating
        // an unknown one as an error would break a window over a new feature.
        TestCase("An unknown record type is ignored, not an error") { t in
            for type in ["queue-operation", "file-history-snapshot", "mode", "last-prompt"] {
                let entries = TranscriptDecoder.entries(
                    fromLine: line(["type": type, "sessionId": "s1"])
                )
                t.expect(entries.isEmpty, "\(type) produced entries")
            }
        },

        TestCase("A line that isn't JSON produces nothing") { t in
            t.expect(TranscriptDecoder.entries(fromLine: "{half an obj").isEmpty, "partial")
            t.expect(TranscriptDecoder.entries(fromLine: "").isEmpty, "empty")
            t.expect(TranscriptDecoder.entries(fromLine: "[1,2,3]").isEmpty, "not an object")
        },

        TestCase("The title is read from its own record") { t in
            let title = TranscriptDecoder.title(fromLine: line([
                "type": "ai-title", "sessionId": "s1", "aiTitle": "Build the traffic light",
            ]))
            t.expectEqual(title, "Build the traffic light", "title")
            t.expectNil(
                TranscriptDecoder.title(fromLine: humanRecord("x")),
                "a message is not a title"
            )
        },

        TestCase("Timestamps survive both ISO shapes") { t in
            let withFraction = TranscriptDecoder.entries(fromLine: humanRecord("a")).first
            t.expect(
                withFraction?.timestamp != Date.distantPast,
                "fractional seconds not parsed"
            )
        },
    ])
}

/// Assembling a conversation, and what counts as unread.
enum ConversationSuite {

    private static func entry(
        _ kind: TranscriptEntry.Kind, _ id: String, _ minute: Int
    ) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            kind: kind,
            text: id,
            timestamp: Date(timeIntervalSince1970: TimeInterval(minute * 60))
        )
    }

    static let suite = TestSuite("Conversation", [

        TestCase("Unread counts answers, not your own messages") { t in
            let conversation = Conversation(sessionId: "s", entries: [
                entry(.human, "h1", 1),
                entry(.assistant, "a1", 2),
                entry(.activity, "t1", 3),
                entry(.assistant, "a2", 4),
            ])
            t.expectEqual(conversation.unreadCount(since: nil), 2, "never opened")
            t.expectEqual(
                conversation.unreadCount(since: Date(timeIntervalSince1970: 180)), 1,
                "since minute 3"
            )
            t.expectEqual(
                conversation.unreadCount(since: Date(timeIntervalSince1970: 600)), 0,
                "all read"
            )
        },

        // An activity line is not something you can be behind on: a badge that
        // went up because Claude ran a `Read` is a badge nobody can act on.
        TestCase("Activity and notes never make a conversation unread") { t in
            let conversation = Conversation(sessionId: "s", entries: [
                entry(.activity, "t1", 5),
                entry(.note, "n1", 6),
            ])
            t.expectEqual(conversation.unreadCount(since: nil), 0, "count")
        },

        TestCase("The last thing said skips the machinery") { t in
            let conversation = Conversation(sessionId: "s", entries: [
                entry(.assistant, "a1", 1),
                entry(.activity, "t1", 2),
            ])
            t.expectEqual(conversation.lastSpoken?.id, "a1", "activity is not speech")
        },

        TestCase("Appending keeps the title when none is offered") { t in
            let first = Conversation(sessionId: "s", title: "Named", entries: [])
            let second = first.appending([entry(.human, "h1", 1)])
            t.expectEqual(second.title, "Named", "title survives")
            t.expectEqual(second.appending([], title: "Renamed").title, "Renamed", "and updates")
        },

        TestCase("Trimming keeps the tail, which is the part anybody reads") { t in
            let conversation = Conversation(
                sessionId: "s",
                entries: (1...10).map { entry(.assistant, "a\($0)", $0) }
            )
            let trimmed = conversation.trimmed(to: 3)
            t.expectEqual(trimmed.entries.map(\.id), ["a8", "a9", "a10"], "tail")
            t.expectEqual(conversation.trimmed(to: 50).entries.count, 10, "shorter is untouched")
        },

        // A window that silently starts in the middle of a conversation is a
        // dropped message the reader cannot see. tmux never does this: a control
        // client that falls behind is told `%pause`, in band, or killed with
        // "too far behind" — the consumer always learns what it stopped getting.
        TestCase("Trimming says how much it dropped") { t in
            let conversation = Conversation(
                sessionId: "s",
                entries: (1...10).map { entry(.assistant, "a\($0)", $0) }
            )
            t.expectEqual(conversation.omittedEntries, 0, "nothing dropped yet")
            t.expectEqual(conversation.trimmed(to: 3).omittedEntries, 7, "dropped")
            t.expectEqual(conversation.trimmed(to: 50).omittedEntries, 0, "nothing to drop")
        },

        // Trimming happens on every poll, over an already trimmed conversation.
        // A count that reset each time would say "7 omitted" for ever while the
        // real number climbed into the hundreds.
        TestCase("Successive trims accumulate what was dropped") { t in
            let conversation = Conversation(
                sessionId: "s",
                entries: (1...10).map { entry(.assistant, "a\($0)", $0) }
            )
            let once = conversation.trimmed(to: 5)
            let twice = once
                .appending((11...14).map { entry(.assistant, "a\($0)", $0) })
                .trimmed(to: 5)
            t.expectEqual(once.omittedEntries, 5, "first pass")
            t.expectEqual(twice.omittedEntries, 9, "first pass plus second")
            t.expectEqual(twice.entries.map(\.id), ["a10", "a11", "a12", "a13", "a14"], "tail")
        },

        TestCase("Appending alone never invents an omission") { t in
            let conversation = Conversation(sessionId: "s", entries: [entry(.human, "h1", 1)])
                .appending([entry(.assistant, "a1", 2)])
            t.expectEqual(conversation.omittedEntries, 0, "count")
        },
    ])
}

/// Deriving a transcript path when no hook has told us one.
enum TranscriptLocatorSuite {

    static let suite = TestSuite("Transcript location", [

        TestCase("The directory name replaces every non-alphanumeric character") { t in
            t.expectEqual(
                TranscriptLocator.directoryName(
                    forWorkspace: "/Users/dev/Development/clawd-light"
                ),
                "-Users-dev-Development-clawd-light",
                "slashes"
            )
            // The case that made the naive rule wrong on 6988 of 7066 real
            // transcripts: dots are replaced too.
            t.expectEqual(
                TranscriptLocator.directoryName(forWorkspace: "/Users/dev/.claude-mem/x"),
                "-Users-dev--claude-mem-x",
                "dots"
            )
        },

        // `Character.isLetter` is Unicode-aware and would keep the accent, which
        // produces a path that is wrong only for people whose folders have them.
        TestCase("Accented letters are replaced, not preserved") { t in
            t.expectEqual(
                TranscriptLocator.directoryName(forWorkspace: "/Users/dev/Città"),
                "-Users-dev-Citt-",
                "à must not survive"
            )
        },

        TestCase("The candidate path is assembled under ~/.claude/projects") { t in
            let url = TranscriptLocator.candidateURL(
                sessionId: "abc-123",
                cwd: "/Users/dev/p",
                home: URL(fileURLWithPath: "/home", isDirectory: true)
            )
            t.expectEqual(
                url.path, "/home/.claude/projects/-Users-dev-p/abc-123.jsonl", "path"
            )
        },
    ])
}

/// Following a file that is being written while it is read.
///
/// This is where the silent defect lives: a chunk almost always ends mid-object,
/// and a reader that parses the fragment loses one record per read.
enum TranscriptTailSuite {

    private static let messageA = """
    {"type":"user","uuid":"a","timestamp":"2026-07-31T10:00:00.000Z","sessionId":"s",\
    "origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":"one"}]}}
    """

    private static let messageB = """
    {"type":"user","uuid":"b","timestamp":"2026-07-31T10:00:01.000Z","sessionId":"s",\
    "origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":"two"}]}}
    """

    static let suite = TestSuite("Transcript tail", [

        TestCase("A chunk ending on a newline yields everything") { t in
            var tail = TranscriptTail()
            let entries = tail.consume(messageA + "\n" + messageB + "\n")
            t.expectEqual(entries.map(\.text), ["one", "two"], "entries")
            t.expectEqual(tail.carry, "", "nothing held back")
        },

        // The defect this whole type exists for.
        TestCase("A half-written line is held back, then completed") { t in
            var tail = TranscriptTail()
            let split = messageB.index(messageB.startIndex, offsetBy: 30)

            let first = tail.consume(messageA + "\n" + String(messageB[..<split]))
            t.expectEqual(first.map(\.text), ["one"], "only the complete one")
            t.expect(!tail.carry.isEmpty, "the fragment must be held")

            let second = tail.consume(String(messageB[split...]) + "\n")
            t.expectEqual(second.map(\.text), ["two"], "completed on the next chunk")
        },

        TestCase("A record split across three chunks still arrives whole") { t in
            var tail = TranscriptTail()
            let thirds = stride(from: 0, to: messageA.count, by: messageA.count / 3 + 1)
                .map { offset -> String in
                    let start = messageA.index(messageA.startIndex, offsetBy: offset)
                    let end = messageA.index(
                        start,
                        offsetBy: min(messageA.count / 3 + 1, messageA.count - offset)
                    )
                    return String(messageA[start..<end])
                }
            var seen: [TranscriptEntry] = []
            for piece in thirds { seen += tail.consume(piece) }
            t.expect(seen.isEmpty, "nothing is complete until the newline")
            seen += tail.consume("\n")
            t.expectEqual(seen.map(\.text), ["one"], "arrives on the newline")
        },

        TestCase("The title is picked up out of the stream") { t in
            var tail = TranscriptTail()
            _ = tail.consume("{\"type\":\"ai-title\",\"sessionId\":\"s\",\"aiTitle\":\"Named\"}\n")
            t.expectEqual(tail.title, "Named", "title")
        },

        // The scanner names terminal rows out of the head of a file, under the
        // very rule the chat window follows — the column and the window must not
        // read one transcript two ways.
        TestCase("The scanner reads the title out of a file's head, last record winning") { t in
            func line(_ title: String) -> String {
                "{\"type\":\"ai-title\",\"sessionId\":\"s\",\"aiTitle\":\"\(title)\"}\n"
            }
            t.expectEqual(
                TranscriptTitleScanner.title(in: Data((line("First") + messageA + "\n" + line("Second")).utf8)),
                "Second", "the last record wins, as in the window"
            )
            t.expectEqual(
                TranscriptTitleScanner.title(in: Data((line("Same") + line("Same") + line("Same")).utf8)),
                "Same", "repeated identical records yield one title"
            )
            t.expectEqual(
                TranscriptTitleScanner.title(in: Data(("{not json}\n" + line("After")).utf8)),
                "After", "a malformed line is skipped"
            )
            t.expectNil(TranscriptTitleScanner.title(in: Data((messageA + "\n").utf8)), "no title, no name")
            t.expectNil(
                TranscriptTitleScanner.title(in: Data(String(line("Cut").dropLast(3)).utf8)),
                "a record cut by the read limit is not a title"
            )
        },

        // Lines are split on the byte, and a multibyte character in the middle
        // of a record must come out whole — the old character-wise split was
        // correct and slow; this one has to be correct and fast.
        TestCase("Splitting by byte keeps multibyte text whole and finds every line") { t in
            var tail = TranscriptTail()
            let titled = "{\"type\":\"ai-title\",\"sessionId\":\"s\",\"aiTitle\":\"✳ Wire it — naïve façade\"}\n"
            let entries = tail.consume(titled + messageA + "\n" + messageB + "\n")
            t.expectEqual(tail.title, "✳ Wire it — naïve façade", "the title survives intact")
            t.expectEqual(entries.count, 2, "both records")
            t.expectEqual(tail.carry, "", "ended on a boundary")

            let big = String(repeating: messageA + "\n", count: 2_000)
            var fresh = TranscriptTail()
            t.expectEqual(fresh.consume(big).count, 2_000, "two thousand lines in one chunk")
        },

        TestCase("A window on a long file starts near the end, on a whole line") { t in
            t.expectEqual(TranscriptWindow.initialOffset(fileSize: 100, window: 1_000), 0, "a file that fits starts at the top")
            t.expectEqual(TranscriptWindow.initialOffset(fileSize: 5_000, window: 1_000), 4_000, "otherwise a window before the end")
            let data = Data("tail of a record}\n{\"whole\":1}\n".utf8)
            t.expectEqual(String(decoding: TranscriptWindow.trimmedToLineStart(data), as: UTF8.self), "{\"whole\":1}\n", "the cut line goes")
            t.expect(TranscriptWindow.trimmedToLineStart(Data("no newline at all".utf8)).isEmpty, "nothing whole, nothing kept")
        },

        TestCase("A blank line between records changes nothing") { t in
            var tail = TranscriptTail()
            t.expectEqual(
                tail.consume(messageA + "\n\n" + messageB + "\n").count, 2, "entries"
            )
        },

        TestCase("Reset forgets the fragment and the title") { t in
            var tail = TranscriptTail()
            _ = tail.consume("{\"type\":\"ai-title\",\"sessionId\":\"s\",\"aiTitle\":\"N\"}\n{partial")
            tail.reset()
            t.expectEqual(tail.carry, "", "carry")
            t.expectNil(tail.title, "title")
        },
    ])
}

/// Recognizing our own messages on the way back.
///
/// A message sent from the chat window returns wearing a `task-notification`
/// origin — the same envelope a background agent gets. Without this, the user
/// would watch their own sentences appear as system chatter.
enum DeliveredMessageSuite {

    /// The real shape, recorded from a delivery on 2026-08-01.
    ///
    /// `content` is a **bare string**, not a list of blocks. The first version of
    /// this suite invented a list and passed happily against a shape Claude Code
    /// does not produce — the recorded record is in
    /// `Contracts/golden/delivered-message.json`.
    private static func notification(_ inner: String) -> String {
        let object: [String: Any] = [
            "type": "user",
            "uuid": "n1",
            "timestamp": "2026-08-01T09:00:00.000Z",
            "sessionId": "s1",
            "origin": ["kind": "task-notification"],
            "promptSource": "sdk",
            "message": ["role": "user", "content": inner],
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private static func wrapped(_ message: String) -> String {
        """
        <task-notification>
        <summary>\(Mailbox.rewakeSummary)</summary>
        </task-notification>
        <system-reminder>
        \(Mailbox.rewakePreamble) \(message)
        </system-reminder>
        """
    }

    static let suite = TestSuite("Delivered messages", [

        TestCase("A message we sent comes back as the user's own") { t in
            let entries = TranscriptDecoder.entries(
                fromLine: notification(wrapped("how far along are we?"))
            )
            t.expectEqual(entries.first?.kind, .human, "kind")
            t.expectEqual(entries.first?.text, "how far along are we?", "text")
        },

        TestCase("The envelope is stripped, all of it") { t in
            let entries = TranscriptDecoder.entries(fromLine: notification(wrapped("ciao")))
            let text = entries.first?.text ?? ""
            for fragment in ["<task-notification>", "</system-reminder>", "<summary>",
                             Mailbox.rewakePreamble] {
                t.expect(!text.contains(fragment), "leaked: \(fragment)")
            }
        },

        // The other direction, and the one that matters more: a notification that
        // is NOT ours must stay a note. Matching loosely here would relabel
        // somebody's background agent as a sentence the user wrote.
        TestCase("Somebody else's notification stays a note") { t in
            let entries = TranscriptDecoder.entries(fromLine: notification("""
            <task-notification>
            <summary>background shell finished</summary>
            </task-notification>
            """))
            t.expectEqual(entries.first?.kind, .note, "kind")
        },

        TestCase("A multi-line message survives the round trip") { t in
            let message = "first line\n\nthird line"
            let entries = TranscriptDecoder.entries(fromLine: notification(wrapped(message)))
            t.expectEqual(entries.first?.text, message, "text")
        },

        // The envelope exactly as Claude Code produced it, copied out of a real
        // delivery. Everything else in this suite is assembled from parts; this
        // one is the artefact, and it is what catches a wrapper that changes shape.
        TestCase("The recorded envelope decodes to what the user typed") { t in
            let recorded = "<task-notification>\n<summary>message from the clawd-light panel</summary>\n</task-notification>\n<system-reminder>\nThe user sent this from the clawd-light panel instead of the editor. Treat it as their next turn and reply to it directly: Read secret.txt and tell me the codeword.\n</system-reminder>"
            let entries = TranscriptDecoder.entries(fromLine: notification(recorded))
            t.expectEqual(entries.count, 1, "one entry")
            t.expectEqual(entries.first?.kind, .human, "kind")
            t.expectEqual(
                entries.first?.text, "Read secret.txt and tell me the codeword.", "text"
            )
        },

        TestCase("A message that only repeats the preamble is not a message") { t in
            let entries = TranscriptDecoder.entries(fromLine: notification(wrapped("   ")))
            t.expectEqual(entries.first?.kind, .note, "an empty body is not the user speaking")
        },
    ])
}
