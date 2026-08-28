import ClawdLightCore
import Foundation

/// Asks GitHub what the latest release is. Nothing else.
///
/// Deliberately separate from the thing that installs: this one makes a request
/// and returns a value, so it can be wrong, slow or unreachable without any
/// consequence beyond a sentence on screen.
enum UpdateChecker {

    /// The version this build carries, from its own bundle.
    static var runningVersion: ReleaseVersion? {
        ReleaseVersion(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
    }

    static func check() async -> UpdateDecision {
        guard let current = runningVersion else {
            return .unreadable("this build does not say which version it is")
        }
        return await check(current: current)
    }

    static func check(current: ReleaseVersion) async -> UpdateDecision {
        var request = URLRequest(url: ReleaseFeed.latestReleaseURL)
        request.timeoutInterval = AppConfig.updateCheckTimeout
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub refuses anonymous requests without one, with a 403 that reads
        // like a rate limit and sends you looking in the wrong place.
        request.setValue("clawd-light/\(current)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                switch status {
                case 404:
                    // Not an error: it is what a project with no published
                    // release looks like, and "404" would send somebody to
                    // check their network.
                    return .unreadable("no release has been published yet")
                case 403:
                    // Almost always the anonymous hourly limit, and saying so
                    // saves the next half hour of looking at the network.
                    return .unreadable("GitHub is rate-limiting anonymous requests — try again later")
                default:
                    return .unreadable("GitHub answered \(status)")
                }
            }
            return ReleaseFeed.decide(payload: data, current: current)
        } catch {
            return .unreadable("could not reach GitHub: \(error.localizedDescription)")
        }
    }
}
