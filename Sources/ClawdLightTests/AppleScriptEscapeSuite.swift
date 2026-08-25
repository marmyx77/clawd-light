import ClawdLightCore
import Foundation
import TestKit

/// Escaping window titles inside an AppleScript string.
///
/// The title comes from VS Code and contains a file name, that is, text the user
/// controls. Ever since the window is raised **by title** instead of by index,
/// that text ends up inside a script's source: a file called `say "hello".txt`
/// would close the string halfway through and turn the rest of the name into code
/// to execute.
enum AppleScriptEscapeSuite {

    static let suite = TestSuite("Escaping titles in AppleScript", [

        TestCase("A normal title stays identical") { t in
            let title = "Build floating Mac traff… — clawd-light — Claude Minimal"
            t.expectEqual(AppleScriptString.escaped(title), title)
        },

        TestCase("Quotes get escaped") { t in
            t.expectEqual(
                AppleScriptString.escaped(#"say "hello".txt — project"#),
                #"say \"hello\".txt — project"#
            )
        },

        TestCase("Backslashes get escaped first") { t in
            // Were they escaped after the quotes, the backslash added by the
            // escaping would itself get escaped and the result would be wrong.
            t.expectEqual(AppleScriptString.escaped(#"a\b"#), #"a\\b"#)
            t.expectEqual(AppleScriptString.escaped(#"a\"b"#), #"a\\\"b"#)
        },

        TestCase("A title with typographic characters only is left alone") { t in
            let title = "“quotes” and… ellipses — dashes"
            t.expectEqual(AppleScriptString.escaped(title), title)
        },

        TestCase("An attempt to break out of the string does not work") { t in
            // The case that matters: close the string and append a command.
            let hostile = #"x" & (do shell script "rm -rf ~") & ""#
            let escaped = AppleScriptString.escaped(hostile)
            // No quote is left unescaped: every `"` is preceded by a `\`.
            var previous: Character = " "
            for character in escaped {
                if character == "\"" {
                    t.expectEqual(previous, "\\", "unescaped quote in \(escaped)")
                }
                previous = character
            }
        },

        TestCase("An empty string stays empty") { t in
            t.expectEqual(AppleScriptString.escaped(""), "")
        },
    ])
}
