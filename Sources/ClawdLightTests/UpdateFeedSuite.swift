import ClawdLightCore
import Foundation
import TestKit

/// Reading the published release, and refusing everything else.
///
/// This is the code that chooses what gets downloaded and run on a machine where
/// the app holds the Accessibility permission, so the cases below are mostly
/// about saying no.
enum UpdateFeedSuite {
    private static let current = ReleaseVersion(major: 0, minor: 1, patch: 0)

    private static func payload(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private static func release(
        tag: String,
        assetName: String = "ClawdLight-0.2.0.dmg",
        url: String = ReleaseFeed.downloadPrefix + "v0.2.0/ClawdLight-0.2.0.dmg",
        extra: [String: Any] = [:]
    ) -> Data {
        var object: [String: Any] = [
            "tag_name": tag,
            "assets": [["name": assetName, "browser_download_url": url]],
        ]
        object.merge(extra) { _, new in new }
        return payload(object)
    }

    static let suite = TestSuite("Update feed", [

        TestCase("Versions are ordered as numbers, not as text") { t in
            // The failure this prevents only appears at the tenth release, by
            // which time nobody is looking: "0.10.0" < "0.9.0" as strings, so the
            // update quietly stops being offered.
            let ninth = ReleaseVersion("0.9.0")!
            let tenth = ReleaseVersion("0.10.0")!
            t.expect(tenth > ninth, "0.10.0 must be newer than 0.9.0")
            t.expect(ReleaseVersion("v1.0.0")! > ReleaseVersion("0.99.99")!, "major wins")
            t.expectEqual(ReleaseVersion("0.2")?.description, "0.2.0", "short forms fill out")
        },

        TestCase("A tag that is not a version is unreadable, never zero") { t in
            for tag in ["latest", "0.x.1", "", "1.2.3.4", "v", "0..1"] {
                t.expectNil(ReleaseVersion(tag), "“\(tag)”")
            }
            // And unreadable must lead to no offer, not to an offer of 0.0.0.
            guard case .unreadable = ReleaseFeed.decide(
                payload: release(tag: "nightly"), current: current
            ) else { return t.fail("a nameless version must not become an update") }
        },

        TestCase("A newer release with its disk image is offered") { t in
            guard case .available(let version, let url) = ReleaseFeed.decide(
                payload: release(tag: "v0.2.0"), current: current
            ) else { return t.fail("not offered") }
            t.expectEqual(version.description, "0.2.0", "version")
            t.expect(url.absoluteString.hasPrefix(ReleaseFeed.downloadPrefix), "pinned host")
        },

        TestCase("The same version, or an older one, is not an update") { t in
            for tag in ["v0.1.0", "v0.0.9"] {
                guard case .upToDate = ReleaseFeed.decide(
                    payload: release(tag: tag), current: current
                ) else { return t.fail("“\(tag)” offered as an update") }
            }
        },

        TestCase("A download pointing anywhere else is refused") { t in
            // The check that matters most. An answer arriving over HTTPS is still
            // only an answer: if this field could name any host, whoever could
            // influence it would be choosing the code that runs here.
            for hostile in [
                "https://evil.example/ClawdLight.dmg",
                "http://github.com/marmyx77/clawd-light/releases/download/v0.2.0/x.dmg",
                "https://github.com/someone-else/clawd-light/releases/download/v0.2.0/x.dmg",
                "https://github.com.evil.example/marmyx77/clawd-light/releases/download/v0.2.0/x.dmg",
            ] {
                guard case .unreadable = ReleaseFeed.decide(
                    payload: release(tag: "v0.2.0", url: hostile), current: current
                ) else { return t.fail("accepted a download from \(hostile)") }
            }
        },

        TestCase("Something that is not a disk image is not an update") { t in
            guard case .unreadable = ReleaseFeed.decide(
                payload: release(
                    tag: "v0.2.0", assetName: "ClawdLight-0.2.0.zip",
                    url: ReleaseFeed.downloadPrefix + "v0.2.0/ClawdLight-0.2.0.zip"),
                current: current
            ) else { return t.fail("a non-dmg asset was offered") }
        },

        TestCase("Drafts and pre-releases are published without being offered") { t in
            // They exist for exactly this: something can be on the releases page
            // and still not be what everybody should be running.
            for flag in ["draft", "prerelease"] {
                guard case .upToDate = ReleaseFeed.decide(
                    payload: release(tag: "v0.2.0", extra: [flag: true]), current: current
                ) else { return t.fail("a \(flag) was offered as an update") }
            }
        },

        TestCase("Nonsense in place of an answer is unreadable, not an update") { t in
            for data in [Data(), Data("not json".utf8), payload(["unexpected": 1])] {
                guard case .unreadable = ReleaseFeed.decide(payload: data, current: current) else {
                    return t.fail("garbage accepted")
                }
            }
        },
    ])
}
