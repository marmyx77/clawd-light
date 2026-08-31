import LampBoardCore
import Foundation
import TestKit

/// The state a person meets and cannot diagnose: registered, and silent anyway.
///
/// Every fixture here is the shape measured in a real `~/.codex/config.toml`,
/// with the paths made anonymous. On the machine it was read from, eight events
/// were registered and eight had a record of approval.
enum CodexTrustSuite {

    private static let hooksPath = "/Users/dev/.codex/hooks.json"

    private static let configuration = """
    model = "gpt-5"

    [hooks.state."/Users/dev/.codex/hooks.json:permission_request:0:0"]
    trusted_hash = "sha256:a1470e297f4e1ceb3a8f55d4470024be662b0ecb4785078c39989cdb20969619"
    [hooks.state."/Users/dev/.codex/hooks.json:stop:0:0"]
    trusted_hash = "sha256:d9b14a9352bf0820655e1c22884c31512c477638ac4d5d2ea2c82ba053d12fd0"
    [hooks.state."/Users/dev/.codex/hooks.json:user_prompt_submit:0:0"]
    trusted_hash = "sha256:2a30e4d0065f79a7403dadd6857ad79f17b895fcbd1d6e4d0ee5be267bdac8a1"
    """

    static let suite = TestSuite("Codex trust", [

        TestCase("An event with no record of approval will not run, and that is certain") { t in
            // The whole point. `SubagentStart` is registered and Codex has never
            // been asked about it, so that hook is silent — and silence is
            // exactly what Codex gives when it declines, in a log or on screen.
            let states = CodexTrust.states(
                registered: ["Stop", "SubagentStart", "UserPromptSubmit"],
                hooksFilePath: hooksPath, configuration: configuration
            )
            t.expectEqual(states["Stop"], .approved, "approved at some point")
            t.expectEqual(states["UserPromptSubmit"], .approved, "and so was this one")
            t.expectEqual(states["SubagentStart"], .neverApproved, "this one never was")
        },

        TestCase("The event name is translated the way Codex writes it") { t in
            // The hooks file says `PermissionRequest`; the state key says
            // `permission_request`. Compared without the translation every event
            // reads as never approved, which is an alarm that cries every time.
            t.expectEqual(CodexTrust.snakeCased("PermissionRequest"), "permission_request", "two words")
            t.expectEqual(CodexTrust.snakeCased("Stop"), "stop", "one word")
            t.expectEqual(CodexTrust.snakeCased("SubagentStop"), "subagent_stop", "and this one")
        },

        TestCase("An approval recorded for somebody else's file is not ours") { t in
            // Codex reads hooks from more than one place. A record naming a
            // different hooks file says nothing about the one we wrote.
            let states = CodexTrust.states(
                registered: ["Stop"], hooksFilePath: "/Users/dev/project/.codex/hooks.json",
                configuration: configuration
            )
            t.expectEqual(states["Stop"], .neverApproved, "a different file, a different question")
        },

        TestCase("A configuration nobody could read answers nothing") { t in
            // Never `neverApproved`: that would put an alarm on every machine
            // where the file is merely absent, and an alarm that is usually
            // wrong is one nobody reads.
            let states = CodexTrust.states(
                registered: ["Stop", "PostToolUse"], hooksFilePath: hooksPath, configuration: nil
            )
            t.expectEqual(states["Stop"], .unknown, "not an answer")
            t.expectEqual(states["PostToolUse"], .unknown, "and not one here either")

            let empty = CodexTrust.states(
                registered: ["Stop"], hooksFilePath: hooksPath, configuration: ""
            )
            t.expectEqual(empty["Stop"], .neverApproved,
                          "but a file that is there and says nothing is an answer")
        },

        TestCase("An unreadable configuration is never reported as approval") { t in
            // The mistake this case exists for was mine, and it was found by
            // running the installer against a machine with no Codex config: the
            // list of events awaiting approval is empty when they have all been
            // approved **and** when nothing could be read, and the installer
            // printed "Codex already trusts every hook registered here".
            //
            // A reassurance nobody can check is worse than a question.
            let unreadable = CodexTrust.states(
                registered: ["Stop", "PostToolUse"], hooksFilePath: hooksPath, configuration: nil
            )
            t.expectEqual(CodexTrust.verdict(of: unreadable), .unreadable, "not approval")

            let approved = CodexTrust.states(
                registered: ["Stop"], hooksFilePath: hooksPath, configuration: configuration
            )
            t.expectEqual(CodexTrust.verdict(of: approved), .allApproved, "this one is")

            let mixed = CodexTrust.states(
                registered: ["Stop", "SubagentStart"], hooksFilePath: hooksPath,
                configuration: configuration
            )
            t.expectEqual(CodexTrust.verdict(of: mixed), .waiting(["SubagentStart"]),
                          "and this one names what is missing")

            // Nothing registered is nothing to approve, which is not a warning.
            t.expectEqual(CodexTrust.verdict(of: [:]), .allApproved, "nothing to wait for")
        },

        TestCase("Only a state header counts, not a line that resembles one") { t in
            // The reader scans for table headers rather than parsing TOML: the
            // file belongs to somebody else and a parser would turn every field
            // they add into a way for this to start failing. The cost is that it
            // has to be strict about what a header looks like.
            let noise = """
            comment = "[hooks.state.\\"/Users/dev/.codex/hooks.json:stop:0:0\\"] not a header"
            [hooks.state."/Users/dev/.codex/hooks.json:post_tool_use:0:0"]
            """
            let states = CodexTrust.states(
                registered: ["Stop", "PostToolUse"], hooksFilePath: hooksPath, configuration: noise
            )
            t.expectEqual(states["Stop"], .neverApproved, "a quoted mention is not an approval")
            t.expectEqual(states["PostToolUse"], .approved, "the real header is")
        },
    ])
}
