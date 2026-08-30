import AppKit
import LampBoardCore
import Foundation

/// Errors while bringing a window to the front.
///
/// Accessibility and Automation are two **distinct** TCC authorizations, granted
/// in two different System Settings panes. Confusing them sends the user off to
/// check a switch that is already on.
enum FocusError: LocalizedError, Equatable {
    /// `AXIsProcessTrusted()` is false: Privacy & Security › Accessibility is missing.
    case accessibilityDenied

    /// The application refused the Apple Event: Privacy & Security ›
    /// Automation › lampboard › *that application* is missing. System Events
    /// for editor windows; a terminal application for its own tabs.
    case automationDenied(app: String = "System Events")

    case vsCodeNotRunning
    case windowNotFound(String)

    /// System Events returned **no** windows at all, while still responding.
    ///
    /// This is a different case from "the window I'm looking for isn't there",
    /// and confusing them sends you hunting in the wrong place: here the problem
    /// is not that the project isn't open, it's that accessibility can't see the
    /// editor. The most frequent cause is a locked screen, which restricts AX
    /// access to other applications' windows while still letting System Events
    /// answer simple questions.
    case noWindowsVisible(String)

    case scriptFailed(String)
    case activationFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return """
            The Accessibility permission is missing.

            System Settings › Privacy & Security › Accessibility → \
            add lampboard and turn the switch on.

            \(PanelIssue.staleEntryCure)
            """
        case .automationDenied(let app):
            return """
            The Automation permission is missing.

            System Settings › Privacy & Security › Automation → \
            lampboard → enable “\(app)”.

            This is a different permission from Accessibility: both are required.
            """
        case .vsCodeNotRunning:
            return "Visual Studio Code is not running."
        case .windowNotFound(let name):
            return "No editor window for “\(name)”."
        case .noWindowsVisible(let name):
            return """
            The editor is running but accessibility can't see any of its windows, \
            so the one for “\(name)” cannot be raised.

            This happens with a locked screen: macOS restricts access to other \
            applications' windows. If the screen is unlocked, remove and re-add \
            lampboard in System Settings › Privacy & Security › Accessibility.
            """
        case .scriptFailed(let reason):
            return "Window activation failed: \(reason)"
        case .activationFailed(let reason):
            return "Cannot bring VS Code to the front: \(reason)"
        }
    }

    /// The same fault as something the panel can act on, when it is one.
    ///
    /// Only the two permissions map to an issue. "No window for that folder" is
    /// a true statement about the world, not a thing to press a button about,
    /// and giving it one would train the eye to ignore the strip.
    var panelIssue: PanelIssue? {
        switch self {
        case .accessibilityDenied: return .accessibilityMissing
        case .automationDenied(let app): return .automationMissing(app: app)
        default: return nil
        }
    }

    /// Compact text for the log and for the combined message.
    var shortDescription: String {
        switch self {
        case .accessibilityDenied: return "Accessibility permission missing"
        case .automationDenied(let app): return "Automation permission for \(app) missing"
        case .vsCodeNotRunning: return "VS Code not running"
        case .windowNotFound(let name): return "no window for “\(name)”"
        case .noWindowsVisible: return "accessibility sees no windows"
        case .scriptFailed(let reason): return "AppleScript failed: \(reason)"
        case .activationFailed(let reason): return "activation failed: \(reason)"
        }
    }
}

/// Brings the VS Code window hosting a workspace to the front.
///
/// VS Code exposes no AppleScript dictionary, so everything goes through System
/// Events. The strategy has two stages, in this order for a precise reason:
/// AppleScript raises *exactly* the existing window, whereas `open` works without
/// permissions but may open a new one. The precise one is tried first.
enum VSCodeFocuser {

    /// The editor hosting that project **right now**.
    ///
    /// It is re-read from the locks at click time rather than carried along in the
    /// state: hours can pass between the signal and the click, and in between the
    /// same folder may have been closed in one editor and reopened in another. It
    /// costs one directory read, and only whoever clicks pays for it.
    ///
    /// When nothing is found it falls back to VS Code, which is by far the most
    /// frequent case.
    static func kind(hosting workspace: Workspace) -> IDEKind {
        WorkspaceResolver.window(
            hosting: workspace.path, in: IDEWindowReader().readWindows(), at: Date()
        )?.window.kind ?? .visualStudioCode
    }

    /// Outcome of an activation attempt.
    ///
    /// The three cases must stay distinct because they deserve different reactions:
    /// one silence, one a note in the menu, one an alert. Flattening them into an
    /// `Error?` has already produced two bugs — an alert shown after a success, and
    /// then a silent failure where nothing happened and nobody said so.
    enum FocusResult {
        /// The exact window was brought to the front.
        case raised

        /// Only the app was activated: you are in VS Code but possibly in the wrong
        /// window. Carries the reason nothing better could be done.
        case activatedOnly(reason: FocusError)

        /// Nothing could be done at all.
        case failed(FocusError)
    }

    /// Brings the window hosting the workspace to the front.
    ///
    /// The order of the steps is written out explicitly rather than hidden behind
    /// a helper: an earlier version buried the fallback inside an `@autoclosure`
    /// and the call site ran it regardless, opening an extra window on every
    /// successful click.
    /// - Parameter sessionId: when present, the Claude tab of that session is
    ///   opened as well once the window has been raised.
    @discardableResult
    static func focus(workspace: Workspace, sessionId: String? = nil) -> FocusResult {
        let ide = kind(hosting: workspace)
        guard isRunning(ide) else { return .failed(.vsCodeNotRunning) }

        // A session on another machine is driven, when it is driven from here at
        // all, from a Remote-SSH window of its folder. That window is raised by
        // title like any other; two things are deliberately not done. No tab deep
        // link — the link goes to the local extension host, and this session's is
        // on the other machine. And no fallback activation — bringing the editor
        // forward with no window of that folder open helps nobody, and the caller
        // has something better to say: where the session is.
        if let host = workspace.host {
            if let error = raiseViaAccessibility(
                workspaceName: workspace.name, ide: ide,
                remoteLabels: RemoteHostAddresses.labels(for: host)
            ) {
                return .failed(error)
            }
            return .raised
        }

        // Strategy 1: raise exactly the window hosting the workspace.
        guard let primaryError = raiseViaAccessibility(
            workspaceName: workspace.name, ide: ide
        ) else {
            if let sessionId { openSessionTab(sessionId: sessionId, ide: ide) }
            return .raised
        }

        Diagnostics.log("AppleScript failed (\(primaryError.shortDescription)): falling back")

        // Strategy 2: just bring the editor to the front.
        if let fallbackError = activate(ide) {
            Diagnostics.log("activation failed too: \(fallbackError.shortDescription)")
            return .failed(primaryError)
        }

        return .activatedOnly(reason: primaryError)
    }

    // MARK: - Permissions

    /// `true` when the app holds the Accessibility permission.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Checks the Automation permission by attempting a harmless Apple Event.
    ///
    /// There is no API to query it without using it: the first attempt is also
    /// what makes the system prompt appear.
    static func checkAutomationPermission() -> FocusError? {
        if case .failure(let error) = runAppleScript(
            "tell application \"System Events\" to get name of first process"
        ) {
            return error
        }
        return nil
    }

    /// Shows the system prompt for the Accessibility permission.
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Strategy 1: System Events

    /// - Parameter remoteLabels: when present, only Remote-SSH windows are
    ///   considered, and one labelled with any of these names wins.
    private static func raiseViaAccessibility(
        workspaceName: String, ide: IDEKind, remoteLabels: [String]? = nil
    ) -> FocusError? {
        guard hasAccessibilityPermission else { return .accessibilityDenied }

        let titles: [String]
        switch windowTitles(of: ide) {
        case .failure(let error):
            return error
        case .success(let found):
            titles = found
        }

        // Zero titles does not mean "the project isn't open": it means accessibility
        // isn't seeing the editor. Telling the two cases apart changes where you go
        // looking, and it is the difference between reopening a folder and checking
        // a permission.
        guard !titles.isEmpty else { return .noWindowsVisible(workspaceName) }

        let match = remoteLabels.map { labels in
            WindowTitleMatcher.bestRemoteMatch(
                workspaceName: workspaceName, titles: titles, hostLabels: labels
            )
        } ?? WindowTitleMatcher.bestMatch(workspaceName: workspaceName, titles: titles)
        guard let index = match else {
            return .windowNotFound(workspaceName)
        }

        // The window is raised **by title**, not by index.
        //
        // This is where the defect lived that brought up the wrong window every
        // other time. The two operations — reading the titles and raising — are two
        // distinct Apple Events, and the list the first one returns is in depth
        // order: frontmost first. Between one call and the next that order
        // **changes on its own** — the focus only has to move, which is exactly
        // what is happening while you click a floating panel. The index computed
        // against the first list therefore ended up pointing at another window:
        // typically the last one used before switching applications.
        //
        // A title, by contrast, is an identity rather than a position: if the
        // windows reorder in the meantime, it doesn't matter. Recognition stays in
        // Swift — verifiable without opening anything — and all AppleScript
        // receives is the name to look for.
        let chosen = titles[index]
        Diagnostics.log("window chosen out of \(titles.count): “\(chosen)”")

        let script = """
        tell application "System Events"
            tell process "\(ide.processName)"
                set candidate to (every window whose name is "\(AppleScriptString.escaped(chosen))")
                if (count of candidate) is 0 then error "title vanished" number -1728
                perform action "AXRaise" of item 1 of candidate
            end tell
        end tell
        tell application id "\(ide.bundleIdentifier)" to activate
        """

        if case .failure(let error) = runAppleScript(script) { return error }
        return nil
    }

    // MARK: - Session tab

    /// Opens the session's Claude tab through the extension's deep link.
    ///
    /// It runs **only once the right window is already in front**, and never as a
    /// fallback. The extension opens the link in whichever window holds the focus
    /// at that moment: if that were the wrong window, not finding the session there
    /// it would open a new tab for it — creating precisely the mess this widget
    /// exists to avoid.
    ///
    /// A failure here is not reported: the window is in front of the user anyway,
    /// which is the bulk of what the click promises.
    private static func openSessionTab(sessionId: String, ide: IDEKind) {
        guard Preferences().opensSessionTab,
              let url = SessionDeepLink.url(forSessionId: sessionId)
        else {
            return
        }
        openDeepLink(url, ide: ide)
    }

    /// Opens a new Claude conversation in the focused window.
    ///
    /// The same deep link, **without** the session parameter: the extension, finding
    /// none to reattach to, opens a new one.
    ///
    /// As with the tab, this must only be invoked once the right window is already
    /// in front: the link lands wherever the focus is, and getting the window wrong
    /// here means creating a conversation in the wrong project.
    static func openNewConversation(in workspace: Workspace) {
        guard let url = SessionDeepLink.newConversationURL else { return }
        openDeepLink(url, ide: kind(hosting: workspace))
    }

    private static func openDeepLink(_ url: URL, ide: IDEKind) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", ide.bundleIdentifier, url.absoluteString]

        do {
            try process.run()
        } catch {
            Diagnostics.log("opening the deep link failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Strategy 2: activating the app

    /// Brings the editor to the front without opening or closing anything.
    ///
    /// Two details, both learned the hard way:
    ///
    /// - It goes through `/usr/bin/open` rather than `NSRunningApplication.activate()`.
    ///   The latter, invoked from an *accessory* app that isn't frontmost, is
    ///   ignored by macOS — and still returns `true`, so the caller believes it
    ///   activated the app when nothing happened. `open` is a system process and
    ///   does have the right to activate.
    ///
    /// - No path among the arguments. `open -b <bundle> <folder>` asks VS Code to
    ///   *open* that folder, and when it doesn't recognize it as already open it
    ///   materializes a new window for it. Without a path it merely activates the app.
    ///
    /// - The wait has a deadline. This runs on the thread that draws the panel,
    ///   and `open` hands the request to LaunchServices, which may have to start
    ///   an application that is not running. Fifteen seconds is generous for
    ///   that and finite, which the previous `waitUntilExit()` was not.
    private static func activate(_ ide: IDEKind) -> FocusError? {
        do {
            let result = try Command.run(
                "/usr/bin/open", ["-b", ide.bundleIdentifier],
                deadline: AppConfig.focusActivationTimeout
            )
            return result.succeeded ? nil : .activationFailed("open returned \(result.status)")
        } catch let failure as Command.Failure {
            return .activationFailed(failure.explanation)
        } catch {
            return .activationFailed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func isRunning(_ ide: IDEKind) -> Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: ide.bundleIdentifier)
            .isEmpty
    }

    /// Titles of the VS Code windows, in the order System Events returns them.
    ///
    /// The read goes through the descriptor's elements rather than `stringValue`.
    /// The reason is that AppleScript returns a **list** here, and on a list
    /// `stringValue` is `nil`: an earlier version split it on `", "` and always got
    /// a single empty element, so no window was ever recognized and the click
    /// always fell back to the second strategy. Note that `osascript` from the
    /// terminal serializes the list into text instead: checking the behavior with
    /// that — as had been done — proves nothing about `NSAppleScript`.
    static func windowTitles(of ide: IDEKind = .visualStudioCode) -> Result<[String], FocusError> {
        let source = "tell application \"System Events\" to tell process "
            + "\"\(ide.processName)\" to get name of every window"

        switch runAppleScript(source) {
        case .failure(let error):
            return .failure(error)

        case .success(let descriptor):
            // A list of strings: the normal case with several windows open.
            if descriptor.numberOfItems > 0 {
                let titles = (1...descriptor.numberOfItems).compactMap {
                    descriptor.atIndex($0)?.stringValue
                }
                return .success(titles)
            }
            // With a single window AppleScript may return a plain string.
            if let single = descriptor.stringValue, !single.isEmpty {
                return .success([single])
            }
            return .success([])
        }
    }

    /// - Parameter app: the application the script talks to — what a refusal
    ///   has to name, since the permission is granted per application.
    static func runAppleScript(
        _ source: String, app: String = "System Events"
    ) -> Result<NSAppleEventDescriptor, FocusError> {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(.scriptFailed("script does not compile"))
        }
        let output = script.executeAndReturnError(&error)

        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "error \(code)"

            switch code {
            // -1743: the user has not authorized sending Apple Events.
            // -1744: authorization not requested yet.
            case -1743, -1744:
                return .failure(.automationDenied(app: app))
            // -25211: the accessibility API is disabled for this process.
            case -25211:
                return .failure(.accessibilityDenied)
            default:
                return .failure(.scriptFailed("\(message) (code \(code))"))
            }
        }
        return .success(output)
    }
}
