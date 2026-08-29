import Foundation

/// Which language dictation should listen in.
///
/// Not a detail. The recognizer is handed one locale and transcribes everything as
/// that language, so choosing `en-US` for somebody speaking Italian does not
/// degrade politely — it produces confident nonsense.
///
/// The rule, in order: the exact language **and** region the user prefers, then
/// the same language in any region, then nothing. Falling back to English at the
/// end would be the confident-nonsense case, so the last step is a refusal the
/// interface can explain.
public enum DictationLocale {

    /// Picks a locale to listen in.
    ///
    /// - Parameters:
    ///   - preferred: the user's languages, most wanted first, as identifiers
    ///     (`Locale.preferredLanguages` gives exactly this).
    ///   - supported: what the recognizer can do.
    /// - Returns: the locale to use, or `nil` when none of the user's languages
    ///   is available.
    public static func choose(preferred: [String], supported: [Locale]) -> Locale? {
        let candidates = preferred.map(Locale.init(identifier:))

        // Exact language + region. `it-IT` beats `it-CH` for somebody who asked
        // for `it-IT`, and the difference is audible.
        for candidate in candidates {
            if let match = supported.first(where: {
                $0.language.languageCode == candidate.language.languageCode
                    && $0.region == candidate.region
                    && candidate.region != nil
            }) {
                return match
            }
        }

        // Same language, any region. An Italian speaker is better served by
        // Italian from another region than by another language entirely.
        for candidate in candidates {
            if let match = supported.first(where: {
                $0.language.languageCode == candidate.language.languageCode
            }) {
                return match
            }
        }

        return nil
    }
}

/// What the microphone button is able to do right now.
///
/// One value, so the interface never has to combine three separate facts —
/// permission, model, system version — and get the combination wrong.
public enum DictationAvailability: Sendable, Equatable {
    /// Ready to listen, in this language.
    case ready(identifier: String)
    /// The language model has to be fetched first.
    case needsDownload(identifier: String)
    /// Downloading it now.
    case downloading(fraction: Double)
    /// The system is older than the API. The button simply does not appear.
    case unsupportedSystem
    /// None of the user's languages is available.
    case noLanguage
    /// The user said no to the microphone.
    case denied
    /// Something else went wrong, with the reason.
    case failed(String)

    /// What to tell the user, or `nil` when there is nothing to say.
    public var explanation: String? {
        switch self {
        case .ready:
            return nil
        case .needsDownload(let identifier):
            return "the \(identifier) dictation model has to be downloaded first"
        case .downloading(let fraction):
            return "downloading the dictation model — \(Int(fraction * 100))%"
        case .unsupportedSystem:
            return "dictation needs macOS 26"
        case .noLanguage:
            return "no dictation model for any of your languages"
        case .denied:
            return "microphone access was refused — System Settings › Privacy & Security › Microphone"
        case .failed(let reason):
            return "dictation failed: \(reason)"
        }
    }

    /// `true` when the button should be shown at all.
    ///
    /// A button that cannot work is worse than no button: it invites a click and
    /// answers with nothing.
    public var isOffered: Bool {
        self != .unsupportedSystem
    }
}
