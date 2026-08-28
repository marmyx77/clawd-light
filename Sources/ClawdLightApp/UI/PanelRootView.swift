import ClawdLightCore
import SwiftUI

/// Actions offered by the panel's context menu.
struct PanelActions {
    /// Opens the extended window — the conversation list plus a conversation.
    let openExtended: () -> Void
    /// Opens the Settings window: what does not fit in this menu.
    let openSettings: () -> Void
    let toggleCompact: () -> Void
    let toggleSessionTab: () -> Void
    let toggleGrouping: () -> Void
    let toggleOnlyWaiting: () -> Void
    let toggleNotifications: () -> Void
    let toggleMessageSending: () -> Void
    let togglePresence: () -> Void
    let toggleTerminalSessions: () -> Void
    let muteForAnHour: () -> Void
    let clearMute: () -> Void
    let toggleLaunchAtLogin: () -> Void
    let installHooks: () -> Void
    let uninstallHooks: () -> Void
    let requestAccessibility: () -> Void
    /// The strip's button: explain the permission, then open the pane that grants it.
    let fixIssue: (PanelIssue) -> Void
    let showHiddenAgain: () -> Void
    let clearSessions: () -> Void
    let quit: () -> Void
}

/// The menu's checkmarks, gathered together so twelve of them don't travel separately.
struct PanelFlags {
    let compact: Bool
    let opensSessionTab: Bool
    let grouped: Bool
    let onlyWaiting: Bool
    let notificationsEnabled: Bool
    let messageSendingEnabled: Bool
    let presenceEnabled: Bool
    let showsTerminalSessions: Bool
    let mutedUntil: Date?
    let hasHidden: Bool
    let hooksInstalled: Bool
    let launchesAtLogin: Bool
    let canLaunchAtLogin: Bool
}

/// Root of the SwiftUI hierarchy hosted inside the floating panel.
struct PanelRootView: View {
    @ObservedObject var store: StateStore
    let flags: PanelFlags
    let options: ColumnOptions
    let mutedWorkspaces: Set<String>
    let calmWorkspaces: Set<String>
    let actions: PanelActions
    let rowActions: RowActions

    @State private var hoveringGear = false

    var body: some View {
        VStack(spacing: 0) {
            TrafficLightColumn(
                store: store,
                compact: flags.compact,
                options: options,
                notificationsEnabled: flags.notificationsEnabled,
                mutedWorkspaces: mutedWorkspaces,
                calmWorkspaces: calmWorkspaces,
                actions: rowActions,
                onRevealHidden: actions.showHiddenAgain
            )
            issueStrip
            footer
        }
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        // The panel menu stays reachable from the margins: over the rows it is
        // shadowed by the row menu, which is more specific and therefore takes the
        // right precedence. The global entries are not duplicated into every row
        // because a fifteen-item menu cannot be read.
        .contextMenu { menu }
    }

    /// The one line that says a click went nowhere, where the eye already is.
    ///
    /// This used to live only at the bottom of the context menu, and the result
    /// was measured on a fresh install: the click activated the editor without
    /// choosing a window, which reads as a half-working app rather than a missing
    /// permission, and the sentence explaining it was three levels away. Nobody
    /// opens a context menu to find out why something they just did worked oddly.
    ///
    /// It appears only for faults the person can fix from here, and it disappears
    /// by itself the moment the permission arrives.
    @ViewBuilder
    private var issueStrip: some View {
        if let issue = store.issue {
            Button { actions.fixIssue(issue) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(StatusPalette.warningTint)

                    // In compact mode the panel is thirty-five points wide: the
                    // triangle is the whole message, and the strip is the button.
                    // A word squeezed in there would be truncated to two letters,
                    // which says less than the glyph alone.
                    if !flags.compact {
                        Text(issue.summary)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(0.65))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 4)

                        Text(issue.actionTitle)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(StatusPalette.warningTint)
                    }
                }
                .padding(.horizontal, flags.compact ? 4 : Layout.panelPadding + 6)
                .frame(maxWidth: .infinity, alignment: flags.compact ? .center : .leading)
                .frame(height: Layout.issueStripHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(issue.summary + " — click to fix")
        }
    }

    /// The gear under the rows: the same menu as a right-click on the margins,
    /// behind a left-click on something you can see. A menu that exists only
    /// behind a right-click on an empty edge is a menu nobody finds — reported
    /// by use, after a week of not finding it.
    private var footer: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button(action: openMenuUnderPointer) {
                // Drawn exactly like the rows' drag handles — same weight,
                // same translucency, same column — so it reads as one more
                // affordance of the panel, not as a control from elsewhere.
                Image(systemName: "gearshape")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(hoveringGear ? 0.55 : 0.2))
                    .frame(width: 14, height: Layout.footerHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Options and Settings — the same menu as a right-click on the panel's edge")
            .onHover { hoveringGear = $0 }
            // Centred in compact mode, where there is no "right"; otherwise
            // under the drag handles, fourteen points from the edge like them.
            if flags.compact { Spacer(minLength: 0) }
        }
        .padding(.horizontal, flags.compact ? 0 : Layout.panelPadding + 6)
        // Three points more below than above: asked for, and right — the
        // glyph sits nearer the rows than the edge.
        .padding(.bottom, 3)
        .frame(height: Layout.footerHeight)
    }

    /// Opens the panel's context menu where the pointer is.
    ///
    /// Not a SwiftUI `Menu`: a pop-up button carries the metrics of a control —
    /// its own height, its own label offset — and however it was framed the
    /// gear came out low and cut. The context menu already exists on the root
    /// view; a synthetic right-click at the pointer is all it takes to open it,
    /// and the gear stays a plain glyph the size of the handles.
    private func openMenuUnderPointer() {
        guard let window = NSApp.windows.first(where: { $0 is FloatingPanel }) else { return }
        let location = window.mouseLocationOutsideOfEventStream
        for type in [NSEvent.EventType.rightMouseDown, .rightMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) else { return }
            window.sendEvent(event)
        }
    }

    @ViewBuilder
    private var menu: some View {
        // First, and on its own, because it is the only entry that opens something
        // rather than changing how this panel looks. Everything below it is a
        // setting; this is the door.
        Button("Open the conversations…", action: actions.openExtended)
        Button("Settings…", action: actions.openSettings)

        Divider()

        Button(check(flags.compact, "Traffic lights only"), action: actions.toggleCompact)
        Button(check(flags.grouped, "One row per project"), action: actions.toggleGrouping)
        Button(check(flags.onlyWaiting, "Show only what's waiting"), action: actions.toggleOnlyWaiting)
        Button(check(flags.showsTerminalSessions, "Show terminal sessions"), action: actions.toggleTerminalSessions)
        // The wording says what it costs, not just what it does: VS Code asks for
        // confirmation on every invocation, and for sessions with no Claude panel —
        // the integrated-terminal ones — the extension opens a new tab instead of
        // reusing one.
        Button(
            check(flags.opensSessionTab, "Click also opens the tab (VS Code asks for confirmation)"),
            action: actions.toggleSessionTab
        )

        if flags.hasHidden {
            Button("Bring hidden projects back into the column", action: actions.showHiddenAgain)
        }

        Divider()

        Button(check(flags.notificationsEnabled, "Alert me when a session gets blocked"),
               action: actions.toggleNotifications)

        if flags.notificationsEnabled {
            if let until = flags.mutedUntil {
                Button("Resume alerts (muted until \(Self.time(until)))",
                       action: actions.clearMute)
            } else {
                Button("Mute alerts for one hour", action: actions.muteForAnHour)
            }
        }

        Button(check(flags.presenceEnabled, "Suppress phone push notifications while I'm at the Mac"),
               action: actions.togglePresence)

        Divider()

        if flags.hooksInstalled {
            Button(
                check(flags.messageSendingEnabled, "Let the panel answer your sessions…"),
                action: actions.toggleMessageSending
            )

            Button("Remove the hooks from Claude Code", action: actions.uninstallHooks)
        } else {
            Button("Install the hooks in Claude Code…", action: actions.installHooks)
        }

        if flags.canLaunchAtLogin {
            Button(check(flags.launchesAtLogin, "Launch at login"), action: actions.toggleLaunchAtLogin)
        }

        if !VSCodeFocuser.hasAccessibilityPermission {
            Button("Grant the Accessibility permission…", action: actions.requestAccessibility)
        }

        Button("Clear the list", action: actions.clearSessions)

        if let error = store.lastError {
            Divider()
            Text(error)
        }

        Divider()

        Button("Quit clawd-light", action: actions.quit)
    }

    /// Switch entries are distinguished by a checkmark.
    /// SwiftUI offers no `Toggle` inside `contextMenu` that looks right here.
    private func check(_ on: Bool, _ title: String) -> String {
        on ? "✓ \(title)" : title
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

/// Translucent panel background.
private struct PanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
