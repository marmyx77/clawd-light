import ClawdLightCore
import Foundation
import TestKit

/// The mailbox: what may be sent, and what may become a path.
enum MailboxSuite {

    static let suite = TestSuite("Mailbox", [

        // A session id arrives from Claude Code and from HTTP requests, and it is
        // about to be concatenated into a filename. This is the whole defence.
        TestCase("A session id that is not one is refused") { t in
            let hostile = [
                "../../../etc/passwd",
                "a/b",
                "..",
                "with space",
                "semi;colon",
                "$(whoami)",
                "short",                               // under the length floor
                String(repeating: "a", count: 65),     // over the ceiling
                "",
                "unicodé-abcdefgh",
            ]
            for id in hostile {
                t.expect(!Mailbox.isValidSessionId(id), "accepted: \(id)")
                t.expectNil(Mailbox.paths(for: id), "produced paths for: \(id)")
            }
        },

        TestCase("A real session id is accepted") { t in
            t.expect(
                Mailbox.isValidSessionId("f512ecae-4294-45bf-9cf1-fdf45a44dd79"),
                "a uuid must be usable"
            )
            guard let paths = Mailbox.paths(for: "f512ecae-4294-45bf-9cf1-fdf45a44dd79") else {
                return t.fail("no paths for a valid id")
            }
            t.expect(paths.open.path.hasSuffix(".open"), "open marker")
            t.expect(paths.message.path.hasSuffix(".msg"), "message")
            t.expect(paths.pid.path.hasSuffix(".pid"), "pid")
            // All three inside the mailbox and nowhere else.
            for url in [paths.open, paths.message, paths.pid] {
                t.expectEqual(
                    url.deletingLastPathComponent().standardizedFileURL.path,
                    Mailbox.directory.standardizedFileURL.path,
                    "escaped the mailbox: \(url.path)"
                )
            }
        },

        // Empty is refused rather than ignored: delivering it would wake a session
        // to say nothing, and a turn is not free on a busy project.
        TestCase("An empty message is refused") { t in
            for text in ["", "   ", "\n\n", "\t"] {
                guard case .failure(let error) = Mailbox.validate(text) else {
                    return t.fail("accepted whitespace: \(text.debugDescription)")
                }
                t.expectEqual(error, .empty, "reason")
            }
        },

        TestCase("A message is trimmed but otherwise left alone") { t in
            guard case .success(let text) = Mailbox.validate("  ciao\n\nmondo  ") else {
                return t.fail("refused a normal message")
            }
            t.expectEqual(text, "ciao\n\nmondo", "the inside is preserved")
        },

        // Refused rather than truncated: half a pasted stack trace is worse than
        // a clear no, because nothing afterwards says it was cut.
        TestCase("An oversized message is refused, not truncated") { t in
            let huge = String(repeating: "x", count: Mailbox.maxMessageBytes + 1)
            guard case .failure(let error) = Mailbox.validate(huge) else {
                return t.fail("accepted an oversized message")
            }
            guard case .tooLarge = error else {
                return t.fail("wrong reason: \(error)")
            }
        },

        TestCase("The size limit counts bytes, not characters") { t in
            // Emoji are four bytes each: a message that fits by character count
            // can still overflow the file we are about to write.
            let emoji = String(repeating: "🙂", count: Mailbox.maxMessageBytes / 2)
            t.expect(emoji.count < Mailbox.maxMessageBytes, "fits by characters")
            guard case .failure = Mailbox.validate(emoji) else {
                return t.fail("accepted \(emoji.utf8.count) bytes")
            }
        },
    ])
}

/// The listener script, and the promises its shape makes.
enum RewakeScriptSuite {

    private static let script = RewakeScriptBuilder.script(inboxPath: "/tmp/inbox")

    static let suite = TestSuite("Rewake listener script", [

        // The two lines the whole feature rests on. Without the flag the process
        // is killed with the turn; without exit 2 the message is never sent.
        TestCase("It carries the flag and the exit code that make it work") { t in
            t.expect(script.contains("asyncRewake"), "the hook option is not mentioned")
            t.expect(script.contains("exit 2"), "the send is missing")
        },

        // A hook that fails can interrupt a Claude Code turn. Every path out of
        // the script except the deliberate one has to be a success.
        TestCase("Every other way out is exit 0") { t in
            let exits = script
                .split(separator: "\n")
                .map { String($0).trimmed }
                .filter { $0.hasPrefix("exit ") }
            t.expect(!exits.isEmpty, "no exits at all?")
            for line in exits {
                t.expect(line == "exit 0" || line == "exit 2", "unexpected exit: \(line)")
            }
            t.expect(exits.filter { $0 == "exit 2" }.count == 1, "exactly one send")
        },

        TestCase("It refuses to arm without an open chat window") { t in
            t.expect(script.contains(".open"), "the arming marker is not checked")
        },

        // Three defences against a process that outlives everything: it only arms
        // for an open window, it gives up, and it stands down for a peer.
        TestCase("It cannot wait for ever, and not in company") { t in
            t.expect(script.contains("MAX_WAIT"), "no upper bound on the wait")
            t.expect(
                script.contains(String(RewakeScriptBuilder.maxWaitSeconds)),
                "the bound is not the one the app documents"
            )
            t.expect(script.contains("kill -0"), "no check for an existing listener")
            t.expect(script.contains("trap"), "the pid file is not cleaned up on exit")
        },

        TestCase("It claims the message before delivering it") { t in
            guard let removal = script.range(of: "rm -f \"$MSG\""),
                  let send = script.range(of: "printf '%s' \"$TEXT\"")
            else {
                return t.fail("the claim-then-send shape is gone")
            }
            // Delivering first and deleting after would resend the message if the
            // process died in between, and a duplicate reads as the user repeating
            // themselves.
            t.expect(removal.lowerBound < send.lowerBound, "delivers before claiming")
        },

        TestCase("The session id it extracts cannot be a path") { t in
            // The pattern is anchored to the shape of a uuid, so a surprising
            // payload yields nothing rather than something usable as a filename.
            t.expect(script.contains("[A-Za-z0-9-]"), "the id pattern is not restricted")
        },
    ])
}

/// Registering the second `Stop` hook without disturbing the first.
enum RewakeRegistrationSuite {

    private static let hookPath = "/Users/dev/.clawd-light/hook.sh"
    private static let rewakePath = "/Users/dev/.clawd-light/rewake.sh"

    private static func entries(in settings: [String: Any], event: String) -> [[String: Any]] {
        let groups = (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
    }

    static let suite = TestSuite("Rewake registration", [

        TestCase("Stop carries both hooks, and only Stop") { t in
            let settings = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath
            )
            let stop = entries(in: settings, event: "Stop")
            t.expectEqual(stop.count, 2, "two hooks on Stop")
            t.expect(
                stop.contains { $0["command"] as? String == rewakePath },
                "the listener is not registered"
            )
            // Anywhere else it would block a turn for no reason at all.
            for event in HookConfigMerger.defaultEvents where event != "Stop" {
                t.expect(
                    !entries(in: settings, event: event)
                        .contains { $0["command"] as? String == rewakePath },
                    "the listener leaked onto \(event)"
                )
            }
        },

        TestCase("The traffic light hook keeps its timeout, the listener has none") { t in
            let settings = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath
            )
            let stop = entries(in: settings, event: "Stop")
            let light = stop.first { $0["command"] as? String == hookPath }
            let listener = stop.first { $0["command"] as? String == rewakePath }

            t.expect(light?["timeout"] != nil, "the traffic light hook lost its timeout")
            // A timeout here would be a statement about a mechanism we do not
            // control: harmless until a release starts honouring it and kills
            // every listener three seconds in.
            t.expectNil(listener?["timeout"], "the listener must carry no timeout")
            t.expectEqual(listener?["asyncRewake"] as? Bool, true, "asyncRewake")
        },

        // The preamble is what tells a delivered message apart from a background
        // agent reporting in, on the way back. Change it in one place only.
        TestCase("The preamble registered is the one the decoder looks for") { t in
            let settings = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath
            )
            let listener = entries(in: settings, event: "Stop")
                .first { $0["command"] as? String == rewakePath }
            t.expectEqual(
                listener?["rewakeMessage"] as? String, Mailbox.rewakePreamble, "preamble"
            )
        },

        TestCase("Uninstalling removes both") { t in
            let installed = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath
            )
            let cleaned = HookConfigMerger.uninstall(
                from: installed, scriptPaths: [hookPath, rewakePath]
            )
            t.expectNil(cleaned["hooks"], "registrations left behind: \(cleaned)")
        },

        // The failure this guards against: uninstall that only knows the traffic
        // light path leaves a listener spawning a process at the end of every turn
        // for a panel that no longer exists.
        TestCase("Uninstalling only the traffic light leaves the listener behind") { t in
            let installed = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath
            )
            let partial = HookConfigMerger.uninstall(from: installed, scriptPath: hookPath)
            t.expect(
                entries(in: partial, event: "Stop")
                    .contains { $0["command"] as? String == rewakePath },
                "this test documents why uninstall takes both paths"
            )
        },

        TestCase("Without a listener path nothing changes") { t in
            let settings = HookConfigMerger.install(into: [:], scriptPath: hookPath)
            t.expectEqual(entries(in: settings, event: "Stop").count, 1, "only the light")
        },

        TestCase("A hook belonging to somebody else is preserved") { t in
            let theirs: [String: Any] = [
                "hooks": ["Stop": [["hooks": [["type": "command", "command": "/opt/theirs.sh"]]]]]
            ]
            let settings = HookConfigMerger.install(
                into: theirs, scriptPath: hookPath, rewakeScriptPath: rewakePath
            )
            t.expect(
                entries(in: settings, event: "Stop")
                    .contains { $0["command"] as? String == "/opt/theirs.sh" },
                "we ate somebody else's hook"
            )
        },
    ])
}

/// The mailbox is a capability, not a scratch directory.
enum MailboxPermissionSuite {

    static let suite = TestSuite("Mailbox permissions", [

        // Dropping a file in the mailbox starts a turn in a Claude Code session:
        // it speaks in the user's voice with their tools. The HTTP server already
        // demands a token for the much milder act of raising a window, so the
        // guard here cannot be looser than the one on the token file.
        TestCase("Owner only, exactly like the access token") { t in
            t.expectEqual(Mailbox.directoryPermissions, 0o700, "directory")
            t.expectEqual(Mailbox.filePermissions, 0o600, "files")
        },

        TestCase("The directory is created narrow, and repaired if it was wide") { t in
            let root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("clawd-mailbox-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }

            setenv(AppConfig.homeOverrideVariable, root.path, 1)
            defer { unsetenv(AppConfig.homeOverrideVariable) }

            // Left wide open by an earlier version, or by somebody's umask.
            try? FileManager.default.createDirectory(
                at: Mailbox.directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            try? Mailbox.ensureDirectory(using: .default)

            let mode = (try? FileManager.default.attributesOfItem(
                atPath: Mailbox.directory.path
            ))?[.posixPermissions] as? NSNumber
            t.expectEqual(mode?.int16Value, 0o700, "the wide directory was not repaired")
        },
    ])
}

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

/// Clearing up after a previous run, without eating what the user wrote.
enum MailboxReapSuite {

    private static let a = "aaaaaaaa-0000-0000-0000-00000000000a"
    private static let b = "bbbbbbbb-0000-0000-0000-00000000000b"

    static let suite = TestSuite("Mailbox reaping", [

        TestCase("A conversation with nothing waiting is released") { t in
            let verdict = MailboxReaper.verdict(forFileNames: ["\(a).open", "\(a).pid"])
            t.expectEqual(verdict.cleared, 1, "cleared")
            t.expectEqual(verdict.delete, ["\(a).open", "\(a).pid"], "both go")
            t.expect(verdict.keptArmed.isEmpty, "nothing to keep")
        },

        // The defect this suite exists for. Quitting the app used to destroy a
        // message that had been dictated, accepted, and was waiting for a sleeping
        // session to stir.
        TestCase("An undelivered message keeps its conversation armed") { t in
            let verdict = MailboxReaper.verdict(
                forFileNames: ["\(a).open", "\(a).msg", "\(a).pid"]
            )
            t.expectEqual(verdict.cleared, 0, "nothing may be cleared")
            t.expectEqual(verdict.keptArmed, [a], "kept armed")
            t.expect(!verdict.delete.contains("\(a).msg"), "the message must never be deleted")
            // And the marker must survive with it: without it no listener will ever
            // arm, so keeping the message alone would be keeping a message nobody
            // can collect.
            t.expect(!verdict.delete.contains("\(a).open"), "the marker must survive too")
            t.expect(verdict.delete.contains("\(a).pid"), "the pid died with the app")
        },

        TestCase("One waiting conversation does not save the others") { t in
            let verdict = MailboxReaper.verdict(
                forFileNames: ["\(a).open", "\(a).msg", "\(b).open", "\(b).pid"]
            )
            t.expectEqual(verdict.cleared, 1, "only b")
            t.expectEqual(verdict.keptArmed, [a], "only a is armed")
            t.expect(verdict.delete.contains("\(b).open"), "b had nothing waiting")
            t.expect(!verdict.delete.contains("\(a).open"), "a did")
        },

        TestCase("Files that are none of our business are left alone") { t in
            let verdict = MailboxReaper.verdict(
                forFileNames: ["writer.log", ".DS_Store", "\(a).open"]
            )
            t.expectEqual(verdict.delete, ["\(a).open"], "only ours")
        },

        TestCase("An empty mailbox is not an error") { t in
            let verdict = MailboxReaper.verdict(forFileNames: [])
            t.expectEqual(verdict.cleared, 0, "cleared")
            t.expect(verdict.delete.isEmpty && verdict.keptArmed.isEmpty, "nothing at all")
        },
    ])
}

/// Sending is off unless the user turned it on.
enum MailboxDisabledSuite {

    static let suite = TestSuite("Sending off by default", [

        // Not a nicety. Dropping a file in the mailbox starts a turn that speaks
        // in the user's voice with their tools, and the reader — a shell script
        // Claude Code spawns — cannot tell who wrote it. Off is the safe state.
        TestCase("A refusal names itself and says where the switch is") { t in
            let description = MailboxError.disabled.description
            t.expect(!description.isEmpty, "silent refusal")
            t.expect(description.contains("panel menu"), "no way to act on it: \(description)")
        },

        TestCase("Disabled is a distinct outcome, not a generic failure") { t in
            // The window shows different words for "off" and "no window open", and
            // conflating them would send somebody hunting the wrong thing.
            t.expect(MailboxError.disabled != MailboxError.notDelivered("x"), "distinct")
            t.expect(MailboxError.disabled != MailboxError.empty, "distinct")
        },
    ])
}

/// Turning message delivery off has to actually remove it.
enum MessageDeliverySwitchSuite {

    private static let hookPath = "/Users/dev/.clawd-light/hook.sh"
    private static let rewakePath = "/Users/dev/.clawd-light/rewake.sh"

    private static func registered(_ settings: [String: Any]) -> [String] {
        let groups = (settings["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
    }

    static let suite = TestSuite("Message delivery switch", [

        TestCase("On registers the listener") { t in
            let settings = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath,
                registerMessageDelivery: true
            )
            t.expect(registered(settings).contains(rewakePath), "listener")
        },

        // The defect this suite exists for. Passing no path meant the cleanup did
        // not know about the listener, so switching off left it registered and
        // running while the interface reported it was off.
        TestCase("Off removes a listener that was already there") { t in
            let on = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath,
                registerMessageDelivery: true
            )
            let off = HookConfigMerger.install(
                into: on, scriptPath: hookPath, rewakeScriptPath: rewakePath,
                registerMessageDelivery: false
            )
            t.expect(!registered(off).contains(rewakePath), "the listener must be gone")
            t.expect(registered(off).contains(hookPath), "the traffic light stays")
        },

        TestCase("Off twice is still off") { t in
            let settings = HookConfigMerger.install(
                into: [:], scriptPath: hookPath, rewakeScriptPath: rewakePath,
                registerMessageDelivery: false
            )
            t.expectEqual(registered(settings), [hookPath], "only the traffic light")
        },
    ])
}
