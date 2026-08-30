import LampBoardCore
import TestKit

/// Which Codex a session runs in, and what that lets a click promise.
///
/// The surface is read from the executable holding the rollout open, which is a
/// fact about this machine. The alternative was the rollout's own `originator`,
/// seen as four different strings in one week inside a format its own
/// documentation calls unstable.
enum CodexSurfaceSuite {

    static let suite = TestSuite("Codex surface", [

        TestCase("The three surfaces are told apart by their binary") { t in
            t.expectEqual(
                CodexSurface.of(executable: "/Applications/ChatGPT.app/Contents/Resources/codex"),
                .chatgptApp, "the desktop application"
            )
            t.expectEqual(
                CodexSurface.of(
                    executable: "/Users/dev/.vscode/extensions/openai.chatgpt-26.825.51511-darwin-arm64/bin/macos-aarch64/codex"
                ),
                .editorExtension, "the editor extension"
            )
            t.expectEqual(
                CodexSurface.of(executable: "/opt/homebrew/Caskroom/codex/0.151.0/bin/codex"),
                .commandLine, "a codex of its own"
            )
        },

        TestCase("A folder called ChatGPT.app does not make a terminal into an app") { t in
            // This case was written to prove the matching was safe and proved the
            // opposite: a bare segment named `ChatGPT.app` is a folder anybody can
            // make, and a project called that would have turned every terminal
            // session inside it into the desktop application. What is matched now
            // is the bundle's own shape.
            t.expectEqual(
                CodexSurface.of(executable: "/Users/dev/Projects/ChatGPT.app/bin/codex"),
                .commandLine, "a folder with that name is still a folder"
            )
            t.expectEqual(
                CodexSurface.of(executable: "/Users/dev/tools/ChatGPT.app/Contents/MacOS/codex"),
                .chatgptApp, "and a real bundle is one wherever it was installed"
            )
        },

        TestCase("Something unreadable is unknown, never guessed into a surface") { t in
            t.expectEqual(CodexSurface.of(executable: ""), .unknown, "no path")
            t.expectEqual(CodexSurface.of(executable: "/usr/local/bin/something-else"), .unknown,
                          "not codex at all")
        },

        TestCase("Only the surfaces that are an application name one") { t in
            // A `codex` from Homebrew is not raised by opening a bundle: the window
            // belongs to the terminal it is typed in, and the same binary runs in
            // Terminal, Ghostty, tmux and VS Code's own terminal.
            t.expectEqual(CodexSurface.chatgptApp.bundleIdentifier, "com.openai.codex", "the app")
            t.expect(CodexSurface.commandLine.bundleIdentifier == nil, "not the command line")
            t.expect(CodexSurface.editorExtension.bundleIdentifier == nil, "not the extension")
            t.expect(CodexSurface.unknown.bundleIdentifier == nil, "and never a guess")
        },

        TestCase("The surface survives the round trip through the session") { t in
            // It travels on `entrypoint`, which already carries `claude-vscode` for
            // the other harness, so the prefix is what keeps the two vocabularies
            // from colliding.
            for surface in CodexSurface.allCases {
                t.expectEqual(CodexSurface.named(entrypoint: surface.entrypoint), surface,
                              surface.label)
            }
            t.expect(CodexSurface.named(entrypoint: "claude-vscode") == nil,
                     "the other harness is not a Codex surface")
            t.expect(CodexSurface.named(entrypoint: nil) == nil, "and neither is nothing")
        },

        TestCase("A surface this build has never heard of is unknown, not nil") { t in
            // A row still exists for it and still shows its state; what it must not
            // do is promise a window. Returning nothing here would send it down the
            // path meant for the other harness, which is the promise.
            t.expectEqual(CodexSurface.named(entrypoint: "codex-hologram"), .unknown, "still Codex")
        },

        TestCase("Focus is decided by the executable only where that settles it") { t in
            t.expect(CodexSurface.chatgptApp.focusIsDecidedByExecutable, "one application")
            t.expect(CodexSurface.editorExtension.focusIsDecidedByExecutable, "one editor")
            t.expect(!CodexSurface.commandLine.focusIsDecidedByExecutable,
                     "the ancestry decides where a terminal session is typed")
            t.expect(!CodexSurface.unknown.focusIsDecidedByExecutable, "and nothing decides this")
        },
    ])
}
