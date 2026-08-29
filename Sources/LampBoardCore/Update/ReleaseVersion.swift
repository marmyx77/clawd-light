import Foundation

/// A released version, ordered.
///
/// String comparison is wrong here in a way that only shows up later: `"0.10.0"`
/// sorts before `"0.9.0"`, so the tenth release would look older than the ninth
/// and the update would silently stop being offered. Three integers, compared as
/// integers.
public struct ReleaseVersion: Equatable, Comparable, Sendable, CustomStringConvertible {

    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Reads `0.2.0`, `v0.2.0`, `0.2` or `1`. Anything else is not a version.
    ///
    /// Tolerant about the shape because a tag is typed by a person, strict about
    /// the content: a component that is not a number makes the whole thing
    /// unreadable rather than zero. "Unreadable" leads to "no update offered",
    /// which is the safe direction; a silent zero would make every release look
    /// like a downgrade.
    public init?(_ raw: String?) {
        guard var text = raw?.trimmed, !text.isEmpty else { return nil }
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }

        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part) else {
                return nil
            }
            numbers.append(value)
        }
        while numbers.count < 3 { numbers.append(0) }

        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
