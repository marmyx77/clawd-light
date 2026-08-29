import LampBoardCore
import Foundation
import TestKit

/// The token protecting the read endpoint.
enum AccessTokenSuite {

    static let suite = TestSuite("Access token", [

        TestCase("A generated token has the expected shape") { t in
            let token = AccessToken.generate()
            t.expectEqual(token.count, AccessToken.byteCount * 2, "length")
            t.expect(AccessToken.isWellFormed(token), "shape: \(token)")
        },

        TestCase("Two generated tokens don't coincide") { t in
            // This doesn't prove the quality of the generator, but it catches the
            // case where it isn't using one at all.
            let tokens = Set((0..<50).map { _ in AccessToken.generate() })
            t.expectEqual(tokens.count, 50, "distinct tokens")
        },

        TestCase("The right token is accepted") { t in
            let token = AccessToken.generate()
            t.expect(AccessToken.matches(token, expected: token), "must accept")
        },

        TestCase("A wrong token is rejected") { t in
            let token = AccessToken.generate()
            t.expect(
                !AccessToken.matches(AccessToken.generate(), expected: token),
                "must not accept"
            )
        },

        TestCase("A missing token is rejected") { t in
            t.expect(!AccessToken.matches(nil, expected: AccessToken.generate()), "nil")
        },

        TestCase("A correct prefix is not enough") { t in
            let token = AccessToken.generate()
            t.expect(
                !AccessToken.matches(String(token.prefix(40)), expected: token),
                "prefix accepted"
            )
        },

        TestCase("A longer token with the right prefix is not enough") { t in
            let token = AccessToken.generate()
            t.expect(!AccessToken.matches(token + "00", expected: token), "suffix ignored")
        },

        TestCase("An empty expected value authorizes nobody") { t in
            // The edge case that matters: if the token had never been loaded, an
            // empty string must not become a universal key.
            t.expect(!AccessToken.matches("", expected: ""), "empty against empty")
            t.expect(!AccessToken.matches("something", expected: ""), "empty expected")
        },

        TestCase("A non-hexadecimal shape is recognized as malformed") { t in
            t.expect(!AccessToken.isWellFormed("zz" + String(repeating: "a", count: 46)), "letters")
            t.expect(!AccessToken.isWellFormed("abc"), "too short")
            t.expect(
                !AccessToken.isWellFormed(String(repeating: "A", count: 48)),
                "uppercase"
            )
        },
    ])
}
