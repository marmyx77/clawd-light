import AppKit
import ClawdLightCore
import Combine
import SwiftUI

/// Holds panel, views and preferences together.
///
/// The height follows the number of rows: a widget that takes up space for rows
/// that don't exist is a widget the user moves into a corner and stops looking at.
@MainActor
final class PanelController {

    private let store: StateStore
    private let installer: HookInstaller
    private let preferences: Preferences
    private let panel: FloatingPanel

    private var compact: Bool
    private var cancellables = Set<AnyCancellable>()

    /// The extended window: the conversation list plus the selected conversation.
    /// Opened on request; the panel is the resting state.
    private lazy var chats = ChatWindowController(
        store: store,
        preferences: preferences
    ) { [weak self] session in
        self?.activate(session: session)
    }

    /// Called from outside to turn notifications on or off.
    /// Opens the Settings window; set by whoever owns it.
    var onOpenSettings: (() -> Void)?

    var onNotificationToggle: ((Bool) -> Void)?

    init(store: StateStore, installer: HookInstaller, preferences: Preferences = Preferences()) {
        self.store = store
        self.installer = installer
        self.preferences = preferences
        self.compact = preferences.isCompact

        let size = NSSize(
            width: Layout.width(compact: compact),
            height: Layout.height(rowCount: 0)
        )
        let origin = Preferences.clamped(
            preferences.savedOrigin ?? Preferences.defaultOrigin(panelSize: size),
            panelSize: size
        )
        self.panel = FloatingPanel(contentRect: NSRect(origin: origin, size: size))
    }

    // MARK: - Lifecycle

    func show() {
        // Before anything else. No chat window can be open at this instant, so
        // every marker on disk belongs to a previous run, and every message
        // listener still waiting on one is holding a process for a window that
        // died with it. Left unreaped they accumulate one per crash per session.
        chats.reapStaleMailboxes()

        rebuildContent()
        panel.orderFrontRegardless()
        logPanelState()
        observeStore()
        observePanelMoves()
    }

    func close() {
        chats.close()
        panel.close()
    }

    /// Opens the chat window for the project bound to a slot, for `chat <n>`.
    ///
    /// - Returns: what it opened, or `nil` when the slot holds nothing — the same
    ///   answer `open <n>` gives, for the same reason.
    @discardableResult
    func openChatInSlot(_ slot: Int) -> String? {
        let rendering = ColumnLayout.render(store.state, options: columnOptions)
        guard let row = rendering.row(inSlot: slot) else { return nil }
        openChat(in: row)
        return "\(row.displayName) — \(StatusPalette.label(for: row.status))"
    }

    /// `true` when the panel really is under the user's eyes.
    /// Used by the notification gate, which treats it as a hint rather than the
    /// truth: `occlusionState` knows how to lie.
    var isPanelVisible: Bool {
        panel.isVisible && panel.occlusionState.contains(.visible)
    }

    private func logPanelState() {
        Diagnostics.log("""
        panel: visible=\(panel.isVisible) frame=\(panel.frame) \
        alpha=\(panel.alphaValue) onActiveSpace=\(panel.isOnActiveSpace) \
        occlusion=\(panel.occlusionState.contains(.visible) ? "visible" : "occluded") \
        level=\(panel.level.rawValue) contentBounds=\(panel.contentView?.bounds ?? .zero) \
        policy=\(NSApp.activationPolicy().rawValue) screens=\(NSScreen.screens.count) \
        signature=\(CodeSignature.isAdHoc ? "ad-hoc" : "stable") \
        accessibility=\(VSCodeFocuser.hasAccessibilityPermission ? "granted" : "MISSING")
        """)
        // The permission has to be read **by the process that will use it**.
        // Asking from a terminal answers for Terminal: macOS attributes the access
        // to the "responsible process", which for a binary launched from a shell is
        // the shell. It is the same deception as verifying the matching with
        // `osascript` instead of `NSAppleScript` — different tool, different
        // answer, wrong conclusion.
    }

    // MARK: - Updating

    private func observeStore() {
        store.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                // A project seen for the first time has just been given a place
                // (`StateStore.givePlaces`). The view holds its options by value,
                // so it has to be rebuilt to learn about it; every other change
                // is a resize.
                if self.columnOptions != self.renderedOptions {
                    self.rebuildContent()
                } else {
                    self.resizeToFit(state)
                }
            }
            .store(in: &cancellables)
    }

    private func observePanelMoves() {
        NotificationCenter.default
            .publisher(for: NSWindow.didMoveNotification, object: panel)
            .sink { [weak self] _ in
                guard let self else { return }
                self.preferences.saveOrigin(self.panel.frame.origin)
            }
            .store(in: &cancellables)
    }

    /// The layout options derived from the preferences.
    private var columnOptions: ColumnOptions {
        ColumnOptions(
            grouped: preferences.groupsByWorkspace,
            onlyWaiting: preferences.showsOnlyWaiting,
            order: preferences.rowOrder,
            hidden: preferences.hiddenWorkspaces
        )
    }

    /// The options the current content was built with.
    private var renderedOptions: ColumnOptions?

    private func rebuildContent() {
        let root = PanelRootView(
            store: store,
            flags: panelFlags,
            options: columnOptions,
            mutedWorkspaces: preferences.mutedWorkspaces,
            calmWorkspaces: preferences.calmBlinkWorkspaces,
            actions: makeActions(),
            rowActions: makeRowActions()
        )
        panel.contentView = NSHostingView(rootView: root)
        renderedOptions = columnOptions
        resizeToFit(store.state)
    }

    private var panelFlags: PanelFlags {
        PanelFlags(
            compact: compact,
            opensSessionTab: preferences.opensSessionTab,
            grouped: preferences.groupsByWorkspace,
            onlyWaiting: preferences.showsOnlyWaiting,
            notificationsEnabled: preferences.notificationsEnabled,
            messageSendingEnabled: preferences.messageSendingEnabled,
            presenceEnabled: preferences.presenceEnabled,
            showsTerminalSessions: preferences.showsTerminalSessions,
            mutedUntil: preferences.mutedUntil,
            hasHidden: !preferences.hiddenWorkspaces.isEmpty,
            hooksInstalled: installer.isInstalled(),
            launchesAtLogin: LaunchAtLogin.isEnabled,
            canLaunchAtLogin: LaunchAtLogin.availability != .needsBundle
        )
    }

    /// Recomputes the height keeping the top edge fixed: the panel grows downwards,
    /// so the corner the user put it in doesn't move.
    private func resizeToFit(_ state: TrafficLightState) {
        let rendering = ColumnLayout.render(state, options: columnOptions)
        // The service rows — hidden summary, filter note — take up as much space
        // as the others and have to be counted, otherwise the last one ends up
        // clipped.
        let extras = (rendering.hidden != nil ? 1 : 0) + (rendering.filteredOut > 0 ? 1 : 0)
        resize(rowCount: rendering.rows.count + extras)
    }

    private func resize(rowCount: Int) {
        let size = NSSize(
            width: Layout.width(compact: compact),
            height: Layout.height(rowCount: rowCount)
        )
        guard size != panel.frame.size else { return }

        let top = panel.frame.maxY
        let origin = NSPoint(x: panel.frame.origin.x, y: top - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    // MARK: - Row actions

    private func makeRowActions() -> RowActions {
        RowActions(
            open: { [weak self] row in self?.activate(row, markSeen: true) },
            peek: { [weak self] row in self?.activate(row, markSeen: false) },
            markUnread: { [weak self] row in self?.markUnread(row) },
            move: { [weak self] row, offset in
                guard let self else { return }
                preferences.rowOrder = RowOrder.moving(
                    row.workspace.path, by: offset, among: visiblePaths(), in: preferences.rowOrder
                )
                rebuildContent()
            },
            place: { [weak self] row, index in
                guard let self else { return }
                preferences.rowOrder = RowOrder.placing(
                    row.workspace.path, at: index, among: visiblePaths(), in: preferences.rowOrder
                )
                rebuildContent()
            },
            toggleHidden: { [weak self] row in
                guard let self else { return }
                preferences.hiddenWorkspaces = Preferences.toggling(
                    row.workspace.path, in: preferences.hiddenWorkspaces
                )
                rebuildContent()
            },
            toggleMuted: { [weak self] row in
                guard let self else { return }
                preferences.mutedWorkspaces = Preferences.toggling(
                    row.workspace.path, in: preferences.mutedWorkspaces
                )
                rebuildContent()
            },
            toggleCalmBlink: { [weak self] row in
                guard let self else { return }
                preferences.calmBlinkWorkspaces = Preferences.toggling(
                    row.workspace.path, in: preferences.calmBlinkWorkspaces
                )
                rebuildContent()
            },
            newConversation: { [weak self] row in self?.newConversation(in: row) },
            openChat: { [weak self] row in self?.openChat(in: row) }
        )
    }

    /// The projects drawn right now, top to bottom: what a drag or a "move" is
    /// relative to. The full order also holds hidden, filtered and sessionless
    /// projects, which the user cannot see and therefore cannot mean.
    private func visiblePaths() -> [String] {
        ColumnLayout.render(store.state, options: columnOptions).rows.map(\.workspace.path)
    }

    /// Opens the row's conversation in a window of its own.
    ///
    /// It marks the row as seen exactly like a click on the editor would: reading
    /// the answer here is reading it. Leaving the row green because the reading
    /// happened in the wrong window would be a distinction only the code cares
    /// about.
    ///
    /// It opens the same session a click opens — `primary`, the most urgent one —
    /// so the two gestures never disagree about which conversation this row is.
    private func openChat(in row: ColumnRow) {
        for id in row.sessionIdsToClear { store.markSeen(sessionId: id) }
        chats.show(selecting: row.primary.id)
    }

    /// Opens the extended window without choosing a conversation, for the menu.
    func openExtendedWindow() {
        chats.show()
    }

    /// Brings the window to the front and, if asked, clears the unread state.
    ///
    /// `markSeen` false is alt+click: it raises the window and leaves the row as it
    /// is. It exists because `markedSeen` is irreversible and one click too many
    /// would erase an answer nobody ever read.
    /// - Parameter opensTab: `false` brings the window forward **without** opening
    ///   the session's tab. Needed by "new conversation", which would otherwise
    ///   open two: first the existing one and then the new one.
    private func activate(_ row: ColumnRow, markSeen: Bool, opensTab: Bool = true) {
        if markSeen {
            // Only the sessions that were in the most urgent state: you haven't
            // seen the others in the group, and clearing them would be a loss.
            for id in row.sessionIdsToClear { store.markSeen(sessionId: id) }
        }

        let session = row.primary

        // A terminal row's place is a terminal tab, found through the session's
        // process at click time (D25): its pid from the session file, the chain
        // up to the hosting application, that application's own way of selecting
        // a tab. Never an editor window of a folder that has none — and never a
        // modal: the session may simply have ended since the last poll.
        if session.origin == .terminal {
            activateTerminal(session)
            return
        }

        // A remote session's window, if it has one here, is the Remote-SSH window
        // of its folder; the focuser knows how to find it. The tab deep link is
        // off for it — the link goes to the local extension host, and this
        // session's is on the other machine. Off as well for a session the
        // extension did not start (`claude` in a terminal): the link would find
        // no tab for it and open a new one, which is the mess the widget exists
        // to avoid.
        let remoteHost = session.workspace.host
        let hasTab = remoteHost == nil && DeepLinkPolicy.opensTab(entrypoint: session.entrypoint)
        switch VSCodeFocuser.focus(
            workspace: session.workspace,
            sessionId: opensTab && hasTab ? session.id : nil
        ) {
        case .raised:
            store.clearError()

        case .activatedOnly(let reason):
            // VS Code is in front of the user: interrupting with a modal window
            // would be out of proportion. The reason stays in the context menu,
            // where you go looking for it once you notice you're in the wrong window.
            store.reportError(
                "Window not raised (\(reason.shortDescription)) — only VS Code was activated."
            )

        case .failed(let error):
            // Normal for a session driven from a terminal on the node: there is no
            // window here to raise, and a modal saying so would be true and
            // useless. The menu says where the session is instead.
            if let remoteHost {
                store.reportError(
                    "“\(session.workspace.name)” runs on \(remoteHost) — "
                        + "no Remote-SSH window of that folder is open here (\(error.shortDescription))."
                )
                return
            }
            store.reportError(error.shortDescription)
            Alerts.warn(
                title: "Cannot open “\(session.workspace.name)”",
                message: error.localizedDescription
            )
        }
    }

    /// The click on a terminal row: seat first, then the focuser for that seat.
    private func activateTerminal(_ session: SessionState) {
        let name = session.displayName
        let seat: Seat
        switch SeatResolver.resolve(sessionId: session.id) {
        case .failure(let error):
            store.reportError("“\(name)” cannot be raised — \(error.short).")
            return
        case .success(let found):
            seat = found
        }
        Diagnostics.log("seat of \(session.id.prefix(8)): \(seat.label)")

        let result: VSCodeFocuser.FocusResult
        if case .editor = seat {
            // An editor's own terminal, in a folder no window claims (an empty
            // window, say): the editor is the place, raised the way editor rows are.
            result = VSCodeFocuser.focus(workspace: session.workspace, sessionId: nil)
        } else {
            result = TerminalFocuser.focus(seat: seat)
        }

        switch result {
        case .raised:
            store.clearError()
        case .activatedOnly(let reason):
            store.reportError("“\(name)”: only \(seat.label) was activated (\(reason.shortDescription)).")
        case .failed(let error):
            store.reportError("“\(name)” runs in \(seat.label) — \(error.shortDescription).")
        }
    }

    /// Restores every cleared session in the row to "unread".
    private func markUnread(_ row: ColumnRow) {
        for session in row.sessions where session.status == .idle {
            store.markUnread(sessionId: session.id)
        }
    }

    /// Opens a new Claude tab in the row's project.
    ///
    /// The same deep link as the click, without the session parameter: with no
    /// `session` the extension opens a new conversation instead of reattaching to
    /// an existing one.
    private func newConversation(in row: ColumnRow) {
        // There is no tab to open one in: the deep link would land in whatever
        // editor window has the focus, which is a conversation in the wrong
        // project — the mess this gate exists to prevent.
        guard !row.isTerminal else {
            store.reportError("“\(row.displayName)” runs in a terminal — start the new conversation there.")
            return
        }
        activate(row, markSeen: false, opensTab: false)
        VSCodeFocuser.openNewConversation(in: row.workspace)
    }

    /// The next waiting session, for the shortcut and for `next`.
    /// - Returns: a description of what was raised, or `nil` when there was nothing.
    @discardableResult
    func activateNextWaiting() -> String? {
        let rendering = ColumnLayout.render(store.state, options: columnOptions)
        guard let row = rendering.rows.first(where: { $0.status.clearsOnFocus }) else {
            return nil
        }
        activate(row, markSeen: true)
        return "\(row.displayName) — \(StatusPalette.label(for: row.status))"
    }

    /// Raises the project bound to a slot, for `open <n>`.
    ///
    /// - Returns: a description of what was raised, or `nil` when the slot holds
    ///   nothing. Empty is an ordinary answer, not a failure: a project can be
    ///   pinned and have no live session at this moment. What must never happen
    ///   is opening the neighboring row instead — for a key pressed without
    ///   looking, that is the worst possible behavior.
    @discardableResult
    func activateSlot(_ slot: Int) -> String? {
        let rendering = ColumnLayout.render(store.state, options: columnOptions)
        guard let row = rendering.row(inSlot: slot) else { return nil }
        activate(row, markSeen: true)
        return "\(row.displayName) — \(StatusPalette.label(for: row.status))"
    }

    /// Opens a new conversation in the project bound to a slot, for `new <n>`.
    ///
    /// The Codex Micro has "start new chat" as a command key next to the Agent
    /// Keys; this is the same gesture, addressed the same way. It is the only one
    /// of its command keys that survives — the others act on a session already
    /// running, which the extension refuses (N7).
    ///
    /// - Returns: a description of where it opened, or `nil` when the slot holds
    ///   nothing. Silence rather than a guess, exactly like `activateSlot`.
    @discardableResult
    func newConversationInSlot(_ slot: Int) -> String? {
        let rendering = ColumnLayout.render(store.state, options: columnOptions)
        guard let row = rendering.row(inSlot: slot), !row.isTerminal else { return nil }
        newConversation(in: row)
        return row.displayName
    }

    /// What each slot currently addresses, for the CLI listing.
    func slotAssignments() -> [(slot: Int, name: String, status: String)] {
        ColumnLayout.render(store.state, options: columnOptions)
            .occupiedSlots
            .map { (slot: $0.slot, name: $0.row.displayName,
                    status: $0.row.status.rawValue) }
    }

    /// Opens the given session: used by the click on a notification.
    ///
    /// The synthetic row carries no slot, and that is correct rather than lazy:
    /// this row never reaches the column, it only exists to hand `activate` a
    /// workspace and a session to clear. A slot here would be a fact about a
    /// drawing that isn't being drawn.
    func activate(session: SessionState) {
        activate(
            ColumnRow(
                id: session.id,
                workspace: session.workspace,
                sessions: [session]
            ),
            markSeen: true
        )
    }

    // MARK: - Panel actions

    private func makeActions() -> PanelActions {
        PanelActions(
            openExtended: { [weak self] in self?.openExtendedWindow() },
            openSettings: { [weak self] in self?.onOpenSettings?() },
            toggleCompact: { [weak self] in self?.toggleCompact() },
            toggleSessionTab: { [weak self] in
                self?.preferences.opensSessionTab.toggle()
                self?.rebuildContent()
            },
            toggleGrouping: { [weak self] in
                self?.preferences.groupsByWorkspace.toggle()
                self?.rebuildContent()
            },
            toggleOnlyWaiting: { [weak self] in
                self?.preferences.showsOnlyWaiting.toggle()
                self?.rebuildContent()
            },
            toggleNotifications: { [weak self] in self?.toggleNotifications() },
            toggleMessageSending: { [weak self] in self?.toggleMessageSending() },
            togglePresence: { [weak self] in self?.togglePresence() },
            toggleTerminalSessions: { [weak self] in self?.toggleTerminalSessions() },
            muteForAnHour: { [weak self] in
                self?.preferences.mutedUntil = Date().addingTimeInterval(3600)
                self?.rebuildContent()
            },
            clearMute: { [weak self] in
                self?.preferences.mutedUntil = nil
                self?.rebuildContent()
            },
            toggleLaunchAtLogin: { [weak self] in self?.toggleLaunchAtLogin() },
            installHooks: { [weak self] in self?.installHooks() },
            uninstallHooks: { [weak self] in self?.uninstallHooks() },
            requestAccessibility: { VSCodeFocuser.requestAccessibilityPermission() },
            showHiddenAgain: { [weak self] in
                self?.preferences.hiddenWorkspaces = []
                self?.rebuildContent()
            },
            clearSessions: { [weak self] in self?.store.reset() },
            quit: { NSApp.terminate(nil) }
        )
    }

    private func toggleCompact() {
        compact.toggle()
        preferences.isCompact = compact
        rebuildContent()
    }

    /// Turning notifications on makes the system prompt appear, and this is the
    /// right moment: the user has just asked for the feature.
    private func toggleNotifications() {
        let wanted = !preferences.notificationsEnabled
        preferences.notificationsEnabled = wanted
        onNotificationToggle?(wanted)
        rebuildContent()
    }

    /// Turns answering from the panel on or off.
    ///
    /// Turning it **on** registers the delivery hook; turning it off removes it,
    /// so the resting state of a machine that never opted in has no listener, no
    /// mailbox and no way for anything to start a turn in the user's name.
    ///
    /// The dialog says what it costs, because this is the one switch here whose
    /// default is about safety rather than noise.
    private func toggleMessageSending() {
        let wanted = !preferences.messageSendingEnabled

        if wanted {
            guard Alerts.confirm(
                title: "Let the panel answer your sessions?",
                message: """
                You will be able to type and dictate into the conversation window, \
                and the message will reach the session at the end of its next turn.

                What it costs: delivery works through a file in ~/.clawd-light/inbox, \
                and the reader cannot tell who wrote it. While this is on, anything \
                running under your account can start a turn that speaks with your \
                voice and your tools. Other accounts on this Mac are kept out; \
                processes of your own cannot be.

                Off, there is no listener and no mailbox at all — and the window \
                still shows you every conversation.
                """,
                confirmTitle: "Turn on"
            ) else { return }
        }

        preferences.messageSendingEnabled = wanted
        reinstallHooksForMessageSending()
        rebuildContent()
    }

    /// Re-registers the hooks so the delivery listener follows the switch.
    private func reinstallHooksForMessageSending() {
        guard installer.isInstalled() else { return }
        do {
            try installer.install(includeMessageDelivery: preferences.messageSendingEnabled)
        } catch {
            store.reportError(error.localizedDescription)
        }
    }

    private func togglePresence() {
        let wanted = !preferences.presenceEnabled
        preferences.presenceEnabled = wanted

        if wanted {
            Alerts.info(
                title: "Phone push notifications suppressed while you're at the Mac",
                message: """
                Claude Code will skip the notifications on your phone for as long as \
                clawd-light declares your presence.

                For this to work, the CLAUDE_CLIENT_PRESENCE_FILE variable has to \
                point at \(AppConfig.presenceFileURL.path).

                Careful: if the detection gets it wrong, the result is not one \
                notification too many but a notification lost.
                """
            )
        }
        rebuildContent()
    }

    /// "Show terminal sessions" (D25). Off takes its rows away at once; on lets
    /// the next poll adopt what is there, within five seconds.
    private func toggleTerminalSessions() {
        let wanted = !preferences.showsTerminalSessions
        preferences.showsTerminalSessions = wanted
        if wanted {
            store.poll()
        } else {
            store.forgetTerminalSessions()
        }
        rebuildContent()
    }

    private func toggleLaunchAtLogin() {
        if let failure = LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled) {
            Alerts.warn(title: "Launch at login", message: failure)
        }
        rebuildContent()
    }

    private func installHooks() {
        guard Alerts.confirm(
            title: "Install the hooks in Claude Code?",
            message: """
            clawd-light will register \(HookConfigMerger.defaultEvents.count) hooks in \
            ~/.claude/settings.json so it knows when sessions change state.

            Existing hooks are preserved and a backup copy of the file is created. \
            Sessions that are already open pick up the new configuration the next \
            time they start.
            """,
            confirmTitle: "Install"
        ) else { return }

        do {
            let backup = try installer.install()
            rebuildContent()
            Alerts.info(
                title: "Hooks installed",
                message: backup.map { "Backup saved to \($0.lastPathComponent)." }
                    ?? "No previous file to save."
            )
        } catch {
            store.reportError(error.localizedDescription)
            Alerts.warn(title: "Installation failed", message: error.localizedDescription)
        }
    }

    private func uninstallHooks() {
        do {
            try installer.uninstall()
            rebuildContent()
            Alerts.info(
                title: "Hooks removed",
                message: "clawd-light will no longer receive signals from Claude Code."
            )
        } catch {
            store.reportError(error.localizedDescription)
            Alerts.warn(title: "Removal failed", message: error.localizedDescription)
        }
    }
}
