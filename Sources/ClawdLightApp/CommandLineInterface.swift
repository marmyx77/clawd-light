import AppKit
import ClawdLightCore
import Foundation

/// Commands callable from the terminal, useful for installing the hooks without
/// opening the interface and for diagnosing a configuration that isn't working.
enum CommandLineInterface {

    enum Command: Equatable {
        case run(port: UInt16, skipSetupPrompt: Bool, headless: Bool)
        case install(port: UInt16, includeToolEvents: Bool)
        case uninstall
        case status
        case selfTest(port: UInt16)
        case focus(workspaceName: String, dryRun: Bool)
        case next(port: UInt16)
        /// `nil` lists the assignments instead of opening one.
        case open(slot: Int?, port: UInt16)
        case newConversation(slot: Int?, port: UInt16)
        /// Reads a slot's conversation in a window of its own.
        case chat(slot: Int?, port: UInt16)
        case sessions(port: UInt16)
        case help
    }

    static func parse(_ arguments: [String]) -> Command {
        let args = Array(arguments.dropFirst())
        let port = portOption(in: args) ?? AppConfig.listenPort

        switch args.first {
        case "install-hooks":
            return .install(port: port, includeToolEvents: args.contains("--with-tool-events"))
        case "uninstall-hooks":
            return .uninstall
        case "status":
            return .status
        case "selftest", "doctor":
            return .selfTest(port: port)
        case "focus":
            return .focus(
                workspaceName: args.count > 1 && !args[1].hasPrefix("-") ? args[1] : "",
                dryRun: args.contains("--dry-run")
            )
        case "next":
            return .next(port: port)
        case "open":
            // A bare `open` lists what the slots address, which is the question
            // you have while deciding what to bind.
            return .open(
                slot: args.count > 1 ? Int(args[1]) : nil,
                port: port
            )
        case "new":
            return .newConversation(
                slot: args.count > 1 ? Int(args[1]) : nil,
                port: port
            )
        case "chat":
            return .chat(
                slot: args.count > 1 ? Int(args[1]) : nil,
                port: port
            )
        case "sessions":
            return .sessions(port: port)
        case "help", "--help", "-h":
            return .help
        case .some(let unknown) where unknown.hasPrefix("-") == false:
            return .help
        default:
            return .run(
                port: port,
                skipSetupPrompt: args.contains("--skip-setup-prompt"),
                headless: args.contains("--headless")
            )
        }
    }

    /// Runs the commands that don't need the interface.
    /// - Returns: the exit code, or `nil` when the app should start up.
    static func execute(_ command: Command) -> Int32? {
        switch command {
        case .run:
            return nil

        case .install(let port, let includeToolEvents):
            return runInstall(port: port, includeToolEvents: includeToolEvents)

        case .uninstall:
            return runUninstall()

        case .status:
            return runStatus()

        case .selfTest(let port):
            return SelfTest.run(port: port)

        case .focus(let workspaceName, let dryRun):
            return runFocus(workspaceName: workspaceName, dryRun: dryRun)

        case .next(let port):
            return runNext(port: port)

        case .open(let slot, let port):
            return runOpen(slot: slot, port: port)

        case .newConversation(let slot, let port):
            return runSlotCommand(
                slot: slot, port: port, verb: "new",
                request: LocalClient.newConversation,
                describe: { "New conversation in \($0)." }
            )

        case .chat(let slot, let port):
            return runSlotCommand(
                slot: slot, port: port, verb: "chat",
                request: LocalClient.chat,
                describe: { "Reading \($0)." }
            )

        case .sessions(let port):
            return runSessions(port: port)

        case .help:
            print(helpText)
            return 0
        }
    }

    // MARK: - Commands

    private static func runInstall(port: UInt16, includeToolEvents: Bool) -> Int32 {
        let installer = HookInstaller()
        do {
            let backup = try installer.install(port: port, includeToolEvents: includeToolEvents)
            print("Hooks installed for: \(installer.installedEvents().joined(separator: ", "))")
            print("Script: \(installer.scriptPath)")
            if let backup {
                print("Backup of settings.json: \(backup.path)")
            }
            print("\nClaude Code sessions that are already open pick up the new")
            print("configuration the next time they start.")
            return 0
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private static func runUninstall() -> Int32 {
        let installer = HookInstaller()
        do {
            let backup = try installer.uninstall()
            print("Hooks removed from ~/.claude/settings.json")
            if let backup {
                print("Backup: \(backup.path)")
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private static func runStatus() -> Int32 {
        let installer = HookInstaller()
        let events = installer.installedEvents()

        print("Hook script:  \(installer.scriptPath)")
        print("Registered:   \(events.isEmpty ? "no" : events.joined(separator: ", "))")

        let now = Date()
        let windows = IDEWindowReader().readWindows()
        let fresh = windows.filter { $0.isSupported }
        print("VS Code windows with Claude Code active: \(fresh.count)")
        for window in fresh {
            for folder in window.workspaceFolders {
                print("  · \(folder)")
            }
        }

        let live = LiveSessionReader().readLiveSessions()
        let hosted = live.filter(\.deservesTrafficLight)
        let resolved = hosted.filter {
            WorkspaceResolver.resolve(cwd: $0.cwd, in: windows, at: now) != nil
        }
        print()
        print("Claude Code sessions with a live process: \(live.count)")
        print("  of which inside VS Code:                \(hosted.count)")
        print("  of which with a recognized workspace:   \(resolved.count)  ← rows in the column")
        if hosted.count > resolved.count {
            print("  The others have a cwd that no lock in ~/.claude/ide/ contains.")
        }

        reportRemoteHosts()
        print("Accessibility permission: \(VSCodeFocuser.hasAccessibilityPermission ? "granted" : "MISSING")")

        let automation = VSCodeFocuser.checkAutomationPermission()
        print("Automation permission:    \(automation == nil ? "granted" : "MISSING")")
        if let automation {
            print("  \(automation.shortDescription)")
        }

        // Read the permissions above with a grain of salt: run from a terminal,
        // this command answers for the **responsible process** — the shell — and
        // not for the app. Treat it as a hint, not as proof; the proof is in the
        // log of the app started with CLAWD_LIGHT_DEBUG=1.
        printOptionalFeatures()
        return 0
    }

    /// The state of the features that start out switched off.
    ///
    /// They exist, but until somebody turns them on they never run — and that is
    /// the condition which, in this project, has produced more defects than any
    /// other. Making them visible is the first step towards testing them.
    private static func printOptionalFeatures() {
        let preferences = Preferences()
        print()
        print("OPTIONAL FEATURES (off by default)")

        print("  Notifications:    \(preferences.notificationsEnabled ? "on" : "off")")
        if let until = preferences.mutedUntil {
            print("                    muted until \(shortTime(until))")
        }
        if !preferences.mutedWorkspaces.isEmpty {
            print("                    \(preferences.mutedWorkspaces.count) projects muted")
        }


        print("  Presence:         \(preferences.presenceEnabled ? "on" : "off")")
        let presenceVariable = ProcessInfo.processInfo.environment["CLAUDE_CLIENT_PRESENCE_FILE"]
        if preferences.presenceEnabled && presenceVariable == nil {
            // On without the variable is the combination that does nothing and
            // doesn't say so: the file gets created and nobody reads it.
            print("                    WARNING: CLAUDE_CLIENT_PRESENCE_FILE is not set,")
            print("                    so Claude Code never reads the file and the feature is inert.")
            print("                    export CLAUDE_CLIENT_PRESENCE_FILE=\"\(AppConfig.presenceFileURL.path)\"")
        }

        switch LaunchAtLogin.availability {
        case .available:
            print("  Launch at login:  \(LaunchAtLogin.isEnabled ? "enabled" : "available, not enabled")")
        case .needsStableSignature:
            print("  Launch at login:  BLOCKED — a stable signature is required")
        case .needsBundle:
            print("  Launch at login:  not applicable (you are running the binary, not the app)")
        }

        print()
        print("  Turn them on from the panel menu (right-click on the margins).")
    }

    private static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Reproduces exactly what clicking a traffic light does, and reports which
    /// of the two strategies worked.
    ///
    /// Needed because the click, by its nature, cannot explain itself: either the
    /// window comes to the front or it doesn't, and the reason stays invisible.
    private static func runFocus(workspaceName: String, dryRun: Bool) -> Int32 {
        let windows = IDEWindowReader().readWindows()
        let open = windows
            .filter { $0.isSupported }
            .flatMap(\.workspaceFolders)
            .map { Workspace(path: $0) }

        guard !workspaceName.isEmpty else {
            print("Usage: clawd-light focus <workspace-name>\n")
            print("Workspaces currently open in VS Code:")
            for workspace in open.sorted(by: { $0.name < $1.name }) {
                print("  \(workspace.name)")
            }
            return 1
        }

        guard let workspace = open.first(where: {
            $0.name.caseInsensitiveCompare(workspaceName) == .orderedSame
        }) else {
            FileHandle.standardError.write(
                Data("No open workspace named «\(workspaceName)».\n".utf8)
            )
            return 1
        }

        print("Trying to activate «\(workspace.name)» (\(workspace.path))\n")

        // The titles are the only handle on the window: printing them makes
        // visible the case where the read returns nothing, which otherwise shows
        // up only as a click that does nothing.
        switch VSCodeFocuser.windowTitles() {
        case .failure(let error):
            print("✗ cannot read the window titles: \(error.shortDescription)\n")
        case .success(let titles) where titles.isEmpty:
            print("✗ accessibility sees no editor window at all")
            print("  This does not mean the project isn't open: it means macOS")
            print("  is not letting us read other applications' windows.")
            print("  Most frequent cause: the screen is locked.\n")
        case .success(let titles):
            print("VS Code windows seen (\(titles.count)):")
            for (index, title) in titles.enumerated() {
                let match = WindowTitleMatcher.bestMatch(
                    workspaceName: workspace.name, titles: titles
                )
                print("  \(match == index ? "→" : " ") [\(index + 1)] \(title)")
            }
            print()
        }

        if dryRun {
            // Deliberately stops here: this is for diagnosing without moving any
            // windows. Useful when you want to find out whether recognition works
            // without interrupting whatever the user is doing.
            print("(--dry-run: no window was activated)")
            return 0
        }

        switch VSCodeFocuser.focus(workspace: workspace) {
        case .raised:
            print("✓ window raised with AppleScript — this is the correct behavior")
            return 0

        case .activatedOnly(let reason):
            print("△ VS Code activated, but not the right window")
            print("  reason: \(reason.shortDescription)")
            print()
            print(reason.errorDescription ?? "")
            return 1

        case .failed(let error):
            print("✗ no activation at all")
            print("  reason: \(error.shortDescription)")
            print()
            print(error.errorDescription ?? "")
            return 1
        }
    }

    /// Raises the next waiting session by asking the running instance.
    private static func runNext(port: UInt16) -> Int32 {
        switch LocalClient.next(port: port) {
        case .success(let description):
            print(description.isEmpty ? "No session is waiting." : description)
            return description.isEmpty ? 1 : 0
        case .failure(let error):
            FileHandle.standardError.write(
                Data("\(error.localizedDescription)\n".utf8)
            )
            return 1
        }
    }

    /// Raises the project bound to a slot, or lists what the slots address.
    ///
    /// This is the command a keyboard shortcut binds to. It answers in three
    /// distinct ways on purpose — raised, empty, unreachable — because a key you
    /// press without looking has to tell you which of the three happened.
    private static func runOpen(slot: Int?, port: UInt16) -> Int32 {
        guard let slot else {
            return listSlots(port: port)
        }

        guard (1...AppConfig.maxSlots).contains(slot) else {
            FileHandle.standardError.write(
                Data("Slot must be a number from 1 to \(AppConfig.maxSlots).\n".utf8)
            )
            return 2
        }

        switch LocalClient.open(slot: slot, port: port) {
        case .success(let description):
            if description.isEmpty {
                // Not a failure: the slot exists, nothing is bound to it or the
                // project has no live session. Exit 1 so a shortcut can tell
                // "nothing happened" from "it worked".
                print("Slot \(slot) is empty.")
                return 1
            }
            print(description)
            return 0
        case .failure(let error):
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    /// Opens a new conversation in the project bound to a slot.
    ///
    /// Same three answers as `open`, for the same reason: bound to a key, it has
    /// to say which of them happened.
    /// The shape every slot-addressed command shares.
    ///
    /// `new` and `chat` differ only in which endpoint they call and what they say
    /// afterwards; everything else — the missing argument, the range, the empty
    /// slot, the three exit codes — is identical, and identical code written twice
    /// is identical code that drifts. `open` stays on its own because a bare
    /// `open` lists the assignments, which is a different command wearing the same
    /// name.
    ///
    /// The exit codes are the contract for whoever binds this to a key:
    /// `0` something happened · `1` the slot is empty or the panel isn't running ·
    /// `2` you asked for something impossible.
    private static func runSlotCommand(
        slot: Int?,
        port: UInt16,
        verb: String,
        request: (Int, UInt16) -> Result<String, LocalClient.ClientError>,
        describe: (String) -> String
    ) -> Int32 {
        guard let slot else {
            let usage = "Usage: clawd-light \(verb) <slot>. "
                + "See `clawd-light open` for the assignments.\n"
            FileHandle.standardError.write(Data(usage.utf8))
            return 2
        }
        guard (1...AppConfig.maxSlots).contains(slot) else {
            FileHandle.standardError.write(
                Data("Slot must be a number from 1 to \(AppConfig.maxSlots).\n".utf8)
            )
            return 2
        }

        switch request(slot, port) {
        case .success(let name):
            if name.isEmpty {
                print("Slot \(slot) is empty.")
                return 1
            }
            print(describe(name))
            return 0
        case .failure(let error):
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    /// What each slot currently opens, read from the running instance.
    private static func listSlots(port: UInt16) -> Int32 {
        switch LocalClient.sessions(port: port) {
        case .failure(let error):
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        case .success(let response):
            // One entry per slot: with grouping off a project has several
            // sessions and they all carry its slot, but a key opens one thing.
            var bySlot: [Int: SessionSnapshot] = [:]
            for session in response.sessions {
                guard let slot = session.slot else { continue }
                if bySlot[slot] == nil { bySlot[slot] = session }
            }
            let pinned = bySlot.keys.sorted().compactMap { bySlot[$0] }

            guard !pinned.isEmpty else {
                print("No slots assigned.")
                print()
                print("Right-click a row in the panel → «Pin to top, and bind a slot».")
                print("Pinned projects take slots 1, 2, 3… in the order you pin them,")
                print("and they keep them: that is what makes a bound key reliable.")
                return 0
            }

            let nameWidth = max(12, pinned.map(\.workspace.count).max() ?? 12)
            for session in pinned {
                print(
                    "\(session.slot ?? 0)  "
                        + session.workspace.padded(to: nameWidth + 2)
                        + session.status
                )
            }
            print()
            print("Bind these with: clawd-light open <n>")
            return 0
        }
    }

    /// Prints the column state exactly as the running instance sees it.
    private static func runSessions(port: UInt16) -> Int32 {
        switch LocalClient.sessions(port: port) {
        case .success(let response):
            guard !response.sessions.isEmpty else {
                print("No sessions in the column.")
                return 0
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM HH:mm"

            // The padding is explicit because `String(format:)` ignores the width
            // on `%@` placeholders: the columns came out jammed together, and a
            // ten-row list that doesn't line up cannot be read.
            let nameWidth = max(12, response.sessions.map(\.workspace.count).max() ?? 12)

            for session in response.sessions {
                let subagents = session.activeSubagents > 0 ? "  ×\(session.activeSubagents)" : ""
                print(
                    session.status.padded(to: 9)
                        + session.workspace.padded(to: nameWidth + 2)
                        + formatter.string(from: session.updatedAt)
                        + subagents
                )
            }
            return 0
        case .failure(let error):
            FileHandle.standardError.write(
                Data("\(error.localizedDescription)\n".utf8)
            )
            return 1
        }
    }

    // MARK: - Help

    private static var helpText: String {
        """
        clawd-light — floating traffic lights for Claude Code sessions in VS Code.

        USAGE
          clawd-light [--port N]              start the floating panel
          clawd-light install-hooks [options] register the hooks in ~/.claude/settings.json
          clawd-light uninstall-hooks         remove the registrations
          clawd-light status                  show the detected configuration
          clawd-light selftest                check the whole chain and report what's missing
          clawd-light focus <workspace>       reproduce the click and report which strategy worked
                                              (with no argument it lists the open workspaces,
                                               with --dry-run it diagnoses without activating anything)
          clawd-light sessions                print the column as the running app sees it
          clawd-light next                    raise the window of the next waiting session
          clawd-light open <n>                raise the project bound to slot n
                                              (with no argument, lists what the slots address)
          clawd-light new <n>                 open a new conversation in slot n's project
          clawd-light chat <n>                read slot n's conversation in its own window,
                                              without touching the editor
          clawd-light help                    show this text

        OPTIONS
          --port N              port of the local server (default \(AppConfig.listenPort))
          --with-tool-events    also register PreToolUse and PostToolUse. Makes yellow
                                more responsive mid-turn, at the cost of one process per
                                single tool call.
          --skip-setup-prompt   don't offer to install the hooks at startup.
                                Useful when launching the app automatically at login.
          --headless            start without the panel: server and realignment only.
                                Used by the end-to-end tests.

        ENVIRONMENT
          \(AppConfig.homeOverrideVariable)      moves every path the app uses under a different root.
                                Used by the tests so they never touch the real ~/.claude.

        SLOTS
          Pinning a project binds it to the next free slot, 1 to \(AppConfig.maxSlots), and it
          keeps that slot: the column reorders by urgency, the slots don't. That is
          what makes `clawd-light open 3` worth binding to a key.
          Assign them by right-clicking a row in the panel.

        STATES
          red        the session is at rest
          yellow     Claude is working
          amber      Claude is waiting for your permission (blinks)
          green      there is an answer to read

        READING WITHOUT SWITCHING
          ⌘+click on a row — or `clawd-light chat <n>` — opens the conversation in
          a window of its own, one per session, leaving VS Code where it is. It is
          read-only: the extension refuses to deliver a prompt to a session whose
          panel is already open, so answering still happens in the editor.

        Click a traffic light to open the corresponding VS Code window.
        Right-click on the panel for the menu.
        """
    }

    // MARK: - Helpers

    private static func portOption(in args: [String]) -> UInt16? {
        guard let index = args.firstIndex(of: "--port"),
              index + 1 < args.count,
              let value = UInt16(args[index + 1]) else {
            return nil
        }
        return value
    }

    /// What the other machines are saying, if any were configured.
    ///
    /// Printed because there is otherwise no way to tell "no remote sessions" from
    /// "the node never answered" — and those need opposite reactions.
    private static func reportRemoteHosts() {
        let hosts = RemoteHostList.parse(
            (try? String(contentsOf: AppConfig.remoteHostsFile, encoding: .utf8)) ?? ""
        )
        guard !hosts.isEmpty else {
            print("\nRemote hosts: none configured (\(AppConfig.remoteHostsFile.path))")
            return
        }
        print("\nRemote hosts (read over ssh, never written to):")
        for host in hosts {
            guard let sessions = RemoteSessionReader(host: host).readLiveSessions() else {
                print("  · \(host): NO ANSWER — asleep, or ssh cannot reach it")
                continue
            }
            let shown = sessions.filter(\.deservesTrafficLight)
            print("  · \(host): \(shown.count) sessions in the column"
                  + (sessions.count == shown.count ? "" : " (\(sessions.count - shown.count) not interactive)"))
            for session in shown {
                print("      \(session.cwd)")
            }
        }
    }

}
