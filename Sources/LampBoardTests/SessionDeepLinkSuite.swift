import LampBoardCore
import Foundation
import TestKit

enum SessionDeepLinkSuite {

    static let suite = TestSuite("Deep link to the session tab", [

        TestCase("Builds the URL in the form the extension expects") { t in
            let url = SessionDeepLink.url(forSessionId: "f512ecae-4294-45bf-9cf1-fdf45a44dd79")

            t.expectEqual(
                url?.absoluteString,
                "vscode://Anthropic.claude-code/open?session=f512ecae-4294-45bf-9cf1-fdf45a44dd79"
            )
        },

        TestCase("Uses the extension's publisher.name identifier") { t in
            t.expectEqual(SessionDeepLink.extensionIdentifier, "Anthropic.claude-code")
        },

        TestCase("Trims the whitespace around the identifier") { t in
            let url = SessionDeepLink.url(forSessionId: "  abc-123  ")
            t.expectEqual(url?.absoluteString, "vscode://Anthropic.claude-code/open?session=abc-123")
        },

        // The link is resolved by the extension in the focused window; for a
        // session it does not host — `claude` started in a terminal — it finds
        // no tab and opens a new one. So the link goes only to sessions the
        // extension started. Unknown stays permitted: it is today's behaviour,
        // and a session adopted before its first hook has no entrypoint yet.
        TestCase("The tab is opened only for sessions the extension hosts") { t in
            t.expect(DeepLinkPolicy.opensTab(entrypoint: "claude-vscode"), "claude-vscode")
            t.expect(DeepLinkPolicy.opensTab(entrypoint: nil), "unknown")
            t.expect(!DeepLinkPolicy.opensTab(entrypoint: "cli"), "cli")
            t.expect(!DeepLinkPolicy.opensTab(entrypoint: "sdk-cli"), "sdk-cli")
            t.expect(!DeepLinkPolicy.opensTab(entrypoint: ""), "empty is not unknown, it is not the extension")
        },

        // An empty session id would open a NEW tab instead of the right one:
        // with no parameter the extension calls primaryEditor.open(undefined).
        TestCase("An empty identifier produces no URL") { t in
            t.expectNil(SessionDeepLink.url(forSessionId: ""), "empty string")
            t.expectNil(SessionDeepLink.url(forSessionId: "   "), "whitespace only")
        },

        TestCase("An identifier with special characters gets encoded") { t in
            let url = SessionDeepLink.url(forSessionId: "a b&c")
            guard let string = url?.absoluteString else { return t.fail("URL not built") }

            t.expect(!string.contains("a b&c"), "the value was not encoded: \(string)")
            t.expect(string.hasPrefix("vscode://Anthropic.claude-code/open?session="), "wrong prefix")
        },
    ])
}
