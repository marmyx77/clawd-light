import ClawdLightCore
import SwiftUI

/// Actions offered by the panel's context menu.
struct PanelActions {
    /// Opens the extended window — the conversation list plus a conversation.
    let openExtended: () -> Void
    let toggleCompact: () -> Void
    let toggleSessionTab: () -> Void
    let toggleGrouping: () -> Void
    let toggleOnlyWaiting: () -> Void
    let toggleNotifications: () -> Void
    let toggleMessageSending: () -> Void
    let togglePresence: () -> Void
    let muteForAnHour: () -> Void
    let clearMute: () -> Void
    let toggleLaunchAtLogin: () -> Void
    let installHooks: () -> Void
    let uninstallHooks: () -> Void
    let requestAccessibility: () -> Void
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

    var body: some View {
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

    @ViewBuilder
    private var menu: some View {
        // First, and on its own, because it is the only entry that opens something
        // rather than changing how this panel looks. Everything below it is a
        // setting; this is the door.
        Button("Open the conversations…", action: actions.openExtended)

        Divider()

        Button(check(flags.compact, "Traffic lights only"), action: actions.toggleCompact)
        Button(check(flags.grouped, "One row per project"), action: actions.toggleGrouping)
        Button(check(flags.onlyWaiting, "Show only what's waiting"), action: actions.toggleOnlyWaiting)
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
