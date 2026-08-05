import ClawdLightCore
import Foundation
import TestKit

/// The token's lifecycle across two startups.
///
/// This is the part with the worst consequences when it goes wrong — either the
/// endpoint stays open, or the secret survives having been readable — and it is
/// also the part the domain tests cannot touch, because it lives entirely in I/O.
///
/// Each case starts a **second instance** of the app against the same fake home,
/// on a different port, and watches what it decides to do.
enum TokenLifecycleSuite {

    static func suite(binaryURL: URL, home: URL, port: UInt16) -> TestSuite {
        TestSuite("E2E · token lifecycle", [

            TestCase("a restart reuses the existing token") { a in
                guard let before = readToken(in: home) else {
                    return a.fail("no token to reuse")
                }

                let second = AppUnderTest(binaryURL: binaryURL, port: port, home: home)
                defer { second.stopKeepingHome() }
                do { try second.startReusingHome() } catch {
                    return a.fail("second instance did not start: \(error)")
                }

                // Regenerating on every startup would invalidate every script
                // that saved the token, with nothing to justify it.
                a.expectEqual(second.tokenValue, before, "token")
            },

            TestCase("a token with permissions that are too wide gets regenerated") { a in
                guard let before = readToken(in: home) else {
                    return a.fail("no starting token")
                }

                let tokenURL = home.appendingPathComponent(".clawd-light/token")
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o644], ofItemAtPath: tokenURL.path
                )

                let second = AppUnderTest(binaryURL: binaryURL, port: port, home: home)
                defer { second.stopKeepingHome() }
                do { try second.startReusingHome() } catch {
                    return a.fail("second instance did not start: \(error)")
                }

                // A secret that has been readable by others must be considered
                // burned: repairing the permissions and keeping it would leave a
                // value in circulation that somebody may already have read.
                a.expect(
                    second.tokenValue != before,
                    "the token was not regenerated despite the wide permissions"
                )

                let attributes = try? FileManager.default.attributesOfItem(
                    atPath: tokenURL.path
                )
                let permissions = (attributes?[.posixPermissions] as? NSNumber)?.int16Value ?? 0
                a.expectEqual(permissions & 0o777, 0o600, "permissions of the new token")
            },

            TestCase("the old token is no longer valid after regeneration") { a in
                let second = AppUnderTest(binaryURL: binaryURL, port: port, home: home)
                defer { second.stopKeepingHome() }
                do { try second.startReusingHome() } catch {
                    return a.fail("second instance did not start: \(error)")
                }

                let result = second.raw(
                    method: "GET",
                    path: AppConfig.sessionsPath,
                    token: .some(String(repeating: "0", count: AccessToken.byteCount * 2))
                )
                a.expectEqual(result.status, 401, "status")
            },

            TestCase("a corrupted token on disk gets replaced") { a in
                let tokenURL = home.appendingPathComponent(".clawd-light/token")
                try? Data("this-is-not-a-token".utf8).write(to: tokenURL)
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: tokenURL.path
                )

                let second = AppUnderTest(binaryURL: binaryURL, port: port, home: home)
                defer { second.stopKeepingHome() }
                do { try second.startReusingHome() } catch {
                    return a.fail("second instance did not start: \(error)")
                }

                guard let token = second.tokenValue else {
                    return a.fail("no token after the replacement")
                }
                a.expect(AccessToken.isWellFormed(token), "malformed token: \(token)")

                // And it has to actually work, not just have the right shape.
                a.expectEqual(
                    second.raw(method: "GET", path: AppConfig.sessionsPath).status,
                    200,
                    "status with the new token"
                )
            },
        ])
    }

    private static func readToken(in home: URL) -> String? {
        let url = home.appendingPathComponent(".clawd-light/token")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)?.trimmed
    }
}
