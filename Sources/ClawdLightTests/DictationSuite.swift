import ClawdLightCore
import Foundation
import TestKit

/// Choosing the language dictation listens in.
///
/// Not a detail: the recogniser transcribes everything as the locale it was given,
/// so the wrong choice does not degrade politely — it produces confident nonsense.
enum DictationLocaleSuite {

    private static let supported = [
        Locale(identifier: "en_US"), Locale(identifier: "en_GB"),
        Locale(identifier: "it_IT"), Locale(identifier: "fr_FR"),
    ]

    static let suite = TestSuite("Dictation language", [

        TestCase("The exact language and region wins") { t in
            let chosen = DictationLocale.choose(preferred: ["it-IT", "en-US"], supported: supported)
            t.expectEqual(chosen?.identifier, "it_IT", "locale")
        },

        // Italian from another region beats English: the same language badly
        // regionalised is understood, a different language is not.
        TestCase("Failing the region, the language still wins") { t in
            let chosen = DictationLocale.choose(preferred: ["it-CH"], supported: supported)
            t.expectEqual(chosen?.language.languageCode?.identifier, "it", "language")
        },

        TestCase("Order of preference is respected") { t in
            let chosen = DictationLocale.choose(preferred: ["fr-FR", "it-IT"], supported: supported)
            t.expectEqual(chosen?.identifier, "fr_FR", "the first one that can be served")
        },

        // The case that must NOT fall back to English. Listening to Italian with
        // an English model produces fluent nonsense, and nothing downstream can
        // tell that it happened.
        TestCase("An unavailable language yields nothing, never English") { t in
            let chosen = DictationLocale.choose(
                preferred: ["ja-JP"], supported: [Locale(identifier: "en_US")]
            )
            t.expectNil(chosen, "silence beats confident nonsense")
        },

        TestCase("No languages at all is survivable") { t in
            t.expectNil(DictationLocale.choose(preferred: [], supported: supported))
            t.expectNil(DictationLocale.choose(preferred: ["it-IT"], supported: []))
        },
    ])
}

/// What the microphone button says about itself.
enum DictationAvailabilitySuite {

    static let suite = TestSuite("Dictation availability", [

        TestCase("Ready says nothing at all") { t in
            t.expectNil(DictationAvailability.ready(identifier: "it-IT").explanation)
        },

        TestCase("Every other state explains itself") { t in
            let states: [DictationAvailability] = [
                .needsDownload(identifier: "it-IT"), .downloading(fraction: 0.4),
                .unsupportedSystem, .noLanguage, .denied, .failed("boom"),
            ]
            for state in states {
                guard let explanation = state.explanation else {
                    return t.fail("silent state: \(state)")
                }
                t.expect(!explanation.isEmpty, "empty explanation for \(state)")
            }
        },

        // The button is drawn everywhere except where it could not work.
        TestCase("An old system is offered no button") { t in
            t.expect(!DictationAvailability.unsupportedSystem.isOffered, "must be hidden")
            t.expect(DictationAvailability.denied.isOffered, "denied is recoverable, so it stays")
            t.expect(DictationAvailability.ready(identifier: "it-IT").isOffered, "ready")
        },

        TestCase("A refusal points at where to undo it") { t in
            let explanation = DictationAvailability.denied.explanation ?? ""
            t.expect(explanation.contains("System Settings"), "no way back: \(explanation)")
        },
    ])
}
