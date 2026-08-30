import LampBoardCore
import Foundation
import TestKit

/// A Claude Desktop conversation becoming a row, and **staying** one after its
/// turn ends.
///
/// This chain exists because of a defect that no unit test could have caught and
/// no hook could have reported. The first version of the surface asked the
/// question every other row asks — which session file names a live process? —
/// and a Claude Desktop agent process lives exactly one turn. The row appeared
/// while the model worked and vanished at the moment there was an answer to
/// read, which is the one moment this panel exists for.
///
/// So the fixture here is a turn, played in the order the application plays it:
/// the conversation is written, the transcript grows a tool call, then an
/// answer, and the agent's session file comes and goes around it. Nothing sends
/// a signal. A Claude Desktop session runs with its own `CLAUDE_CONFIG_DIR` and
/// never reads the hooks on this machine, so if the row is wrong here there is
/// nothing to correct it.
enum ClaudeDesktopE2ESuite {

    private static let conversation = "local_e2e-desktop-1"
    private static let transcriptId = "e2e-desktop-transcript-1"
    private static let folder = "/tmp/lampboard-e2e-desktop-client"

    private static func home(in appHome: URL) -> URL {
        ClaudeDesktop.sessionsRoot(inHome: appHome)
            .appendingPathComponent("org", isDirectory: true)
            .appendingPathComponent("account", isDirectory: true)
            .appendingPathComponent(conversation, isDirectory: true)
    }

    /// The index beside the conversation's home, in the shape measured on a
    /// running one. `resolvedFolderKinds` is the application's own answer to
    /// whether the work is happening on this Mac.
    private static func writeIndex(
        in appHome: URL, at moment: Date, archived: Bool = false
    ) throws {
        let session = home(in: appHome)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let index = """
        {"sessionId":"\(conversation)","cliSessionId":"\(transcriptId)",
         "cwd":"\(session.path)/outputs",
         "userSelectedFolders":["\(folder)"],
         "resolvedFolderKinds":[{"display":"\(folder)","kind":"local"}],
         "title":"Turn under test","model":"claude-opus-5",
         "isArchived":\(archived),
         "lastActivityAt":\(Int(moment.timeIntervalSince1970 * 1000))}
        """
        try index.write(
            to: ClaudeDesktop.indexPath(forHome: session), atomically: true, encoding: .utf8
        )
    }

    private static func writeTranscript(in appHome: URL, lines: [String]) throws {
        let directory = home(in: appHome)
            .appendingPathComponent(".claude/projects/-tmp-client", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(
            to: directory.appendingPathComponent("\(transcriptId).jsonl"),
            atomically: true, encoding: .utf8
        )
    }

    /// The file the application writes when it starts a turn and removes when
    /// that turn's process exits. Our own pid, because it has to be alive.
    private static func writeSessionFile(in appHome: URL) throws {
        let directory = home(in: appHome).appendingPathComponent(".claude/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        try #"{"pid":\#(pid),"sessionId":"\#(transcriptId)","cwd":"\#(folder)","kind":"interactive","entrypoint":"local-agent"}"#
            .write(
                to: directory.appendingPathComponent("\(pid).json"),
                atomically: true, encoding: .utf8
            )
    }

    private static func removeSessionFiles(in appHome: URL) {
        try? FileManager.default.removeItem(
            at: home(in: appHome).appendingPathComponent(".claude/sessions", isDirectory: true)
        )
    }

    private static func stamp(_ moment: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: moment)
    }

    static func suite(app: AppUnderTest) -> TestSuite {
        TestSuite("E2E · a Claude Desktop turn, start to finish", [

            TestCase("a conversation nobody announced becomes a row, and it is working") { a in
                let started = Date()
                do {
                    try writeIndex(in: app.home, at: started)
                    try writeTranscript(in: app.home, lines: [
                        #"{"type":"user","message":{"role":"user","content":"look at this"},"timestamp":"\#(stamp(started))"}"#,
                        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read"}]},"timestamp":"\#(stamp(started.addingTimeInterval(1)))"}"#,
                    ])
                    try writeSessionFile(in: app.home)
                } catch {
                    a.expect(false, "the fixture could not be set up: \(error)")
                    return
                }

                a.expect(
                    app.waitUntil { app.session(id: transcriptId) != nil },
                    "no hook was sent, and the row still has to arrive"
                )
                let session = app.session(id: transcriptId)
                a.expectEqual(session?.status, "working", "a tool call is the middle of a turn")
                a.expectEqual(session?.entrypoint, ClaudeDesktop.entrypoint,
                              "what tells a click to raise the application")
                a.expectEqual(session?.workspace, "lampboard-e2e-desktop-client",
                              "the folder the application resolved as local, never the session's cwd")
                a.expectEqual(session?.title, "Turn under test", "the name the conversation gave itself")
            },

            TestCase("the turn ends, its process goes, and the row goes green") { a in
                // The defect, played exactly as it happened. The application
                // removes the session file when the turn's process exits — here,
                // between the answer being written and the next sweep. Built on
                // that file, the row disappeared at this line.
                let answered = Date().addingTimeInterval(2)
                do {
                    try writeTranscript(in: app.home, lines: [
                        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read"}]},"timestamp":"\#(stamp(answered.addingTimeInterval(-1)))"}"#,
                        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Here is what I found."}]},"timestamp":"\#(stamp(answered))"}"#,
                        // Bookkeeping written around the session, not by it. It
                        // moves the file and says nothing about whose floor it is.
                        #"{"type":"last-prompt","lastPrompt":"look at this"}"#,
                    ])
                    try writeIndex(in: app.home, at: answered)
                } catch {
                    a.expect(false, "the fixture could not be advanced: \(error)")
                    return
                }
                removeSessionFiles(in: app.home)

                a.expect(
                    app.waitUntil { app.session(id: transcriptId)?.status == "ready" },
                    "the answer nobody has read is green, and the row is still there"
                )
            },

            TestCase("a new turn takes the row back before the transcript has caught up") { a in
                // A model that has just been asked a question has written
                // nothing yet, so the transcript still ends in the previous
                // answer. Reading it alone, the first seconds of every turn are
                // the end of the last one: the process holding the session file
                // is what says otherwise.
                guard (try? writeSessionFile(in: app.home)) != nil else {
                    a.expect(false, "the fixture could not be advanced")
                    return
                }
                defer { removeSessionFiles(in: app.home) }

                a.expect(
                    app.waitUntil { app.session(id: transcriptId)?.status == "working" },
                    "a turn in flight outranks the transcript behind it"
                )
            },

            TestCase("filing the conversation away takes its row with it") { a in
                // Archiving is the person saying they are done with it, and it
                // is the ending this surface gets: there is no process whose
                // exit could mean anything.
                a.expect(app.waitUntil { app.session(id: transcriptId) != nil }, "it is still there")
                guard (try? writeIndex(in: app.home, at: Date(), archived: true)) != nil else {
                    a.expect(false, "the fixture could not be advanced")
                    return
                }
                a.expect(
                    app.waitUntil { app.session(id: transcriptId) == nil },
                    "the conversation is filed, so the row goes"
                )
            },
        ])
    }
}
