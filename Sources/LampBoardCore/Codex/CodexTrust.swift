import Foundation

/// Whether Codex has been told to trust the hooks we registered.
///
/// The state this exists for is one a person meets and cannot diagnose: the
/// hooks are in `~/.codex/hooks.json`, `lampboard status` says they are
/// registered, and the row stays silent anyway. Codex will not run a hook it has
/// not been approved for, and **when it declines it says nothing** — not in a
/// log, not on screen.
///
/// It does record the approval, in its own configuration, one entry per event:
///
/// ```toml
/// [hooks.state."/Users/dev/.codex/hooks.json:permission_request:0:0"]
/// trusted_hash = "sha256:a1470e29…"
/// ```
///
/// Two things about that shape decide everything below.
///
/// **The key is ours to read.** It carries the path of the hooks file and the
/// name of the event, in snake_case where the file itself uses PascalCase. So
/// "is there any record of approval for this event?" is a question that can be
/// answered exactly.
///
/// **The hash is not.** Eight plausible inputs were tried against a real entry —
/// the command, the command with a newline, the hook object in four
/// serialisations, the script's own bytes, two concatenations — and none of them
/// reproduces it. The format is undocumented, and this project already has a rule
/// for undocumented formats: read what is legible and do not guess the rest.
///
/// So a record means the approval **happened**, not that it still holds. What
/// makes it hold is that the file has not changed since, and that is worth
/// knowing: running the installer twice was measured to produce a byte-identical
/// file, so a reinstall costs no trust. Changing the set of events, or the path
/// of the hook script — which is exactly what renaming this project did — does.
public enum CodexTrust {

    /// What can be said about one event.
    public enum State: Sendable, Equatable {
        /// Codex has a record of approving this hook. It ran at least once.
        case approved
        /// We registered the event and Codex has no record for it. This hook
        /// **will not run**, and that is certain rather than likely.
        case neverApproved
        /// The configuration could not be read. Not an answer, and never
        /// reported as one.
        case unknown
    }

    /// What to say about a whole set of events.
    ///
    /// It exists because the two callers that needed it wrote the three branches
    /// separately and one of them got it wrong: the list of events awaiting
    /// approval is empty both when they have all been approved **and when the
    /// configuration could not be read at all**, and the installer told a person
    /// with an unreadable config that Codex already trusted everything. A
    /// reassurance nobody can check is worse than a question.
    public enum Verdict: Sendable, Equatable {
        /// Every registered hook has a record of approval.
        case allApproved
        /// These will not run until somebody approves them in Codex.
        case waiting([String])
        /// The configuration could not be read, so nothing is known.
        case unreadable
    }

    public static func verdict(of states: [String: State]) -> Verdict {
        guard !states.isEmpty else { return .allApproved }
        // Unreadable wins over everything: a single unknown means the answer for
        // the others was read from nothing.
        if states.values.contains(.unknown) { return .unreadable }
        let waiting = states.filter { $0.value == .neverApproved }.keys.sorted()
        return waiting.isEmpty ? .allApproved : .waiting(waiting)
    }

    /// The state of every event, keyed by the name the hooks file uses.
    ///
    /// - Parameters:
    ///   - registered: the events we wrote into the hooks file, PascalCase.
    ///   - hooksFilePath: the file those events live in. Matched exactly, because
    ///     Codex reads hooks from more than one place and an approval recorded
    ///     for somebody else's file is not ours.
    ///   - configuration: the contents of `config.toml`, or `nil` when it could
    ///     not be read.
    public static func states(
        registered: [String], hooksFilePath: String, configuration: String?
    ) -> [String: State] {
        guard let configuration else {
            return Dictionary(uniqueKeysWithValues: registered.map { ($0, .unknown) })
        }
        let approved = approvedEvents(in: configuration, forFileAt: hooksFilePath)
        return Dictionary(uniqueKeysWithValues: registered.map { event in
            (event, approved.contains(snakeCased(event)) ? .approved : .neverApproved)
        })
    }

    /// The events named in `[hooks.state]` for one hooks file, snake_cased as
    /// Codex writes them.
    ///
    /// Deliberately a scan for table headers rather than a TOML parser. What is
    /// needed is one shape, the file belongs to somebody else, and a parser would
    /// turn every future field they add into a way for this to start failing.
    public static func approvedEvents(in configuration: String, forFileAt path: String) -> Set<String> {
        var events: Set<String> = []
        let prefix = "[hooks.state.\"\(path):"
        for line in configuration.split(separator: "\n") {
            let trimmed = String(line).trimmed
            guard trimmed.hasPrefix(prefix), trimmed.hasSuffix("\"]") else { continue }
            let rest = trimmed.dropFirst(prefix.count).dropLast(2)
            // What follows the path is `<event>:<index>:<index>`.
            guard let event = rest.split(separator: ":").first, !event.isEmpty else { continue }
            events.insert(String(event))
        }
        return events
    }

    /// `PermissionRequest` as Codex spells it in a state key.
    public static func snakeCased(_ event: String) -> String {
        var out = ""
        for (index, character) in event.enumerated() {
            if character.isUppercase, index > 0 { out.append("_") }
            out.append(Character(character.lowercased()))
        }
        return out
    }
}
