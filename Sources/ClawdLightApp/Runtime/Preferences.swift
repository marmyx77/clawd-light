import AppKit
import ClawdLightCore
import Foundation

/// Persisted panel preferences.
///
/// There are few of them and none carry consequences, so they live in
/// `UserDefaults` rather than a configuration file: losing them costs the user
/// nothing.
struct Preferences {
    private enum Key {
        static let compact = "panel.compact"
        static let originX = "panel.origin.x"
        static let originY = "panel.origin.y"
        static let setupPromptShown = "setup.promptShown"
        static let opensSessionTab = "click.opensSessionTab"
        static let groupByWorkspace = "panel.groupByWorkspace"
        static let onlyWaiting = "panel.onlyWaiting"
        /// Read only, as the seed of `rowOrder` for whoever upgrades from the
        /// pinned-rows version.
        static let pinnedWorkspaces = "panel.pinnedWorkspaces"
        static let rowOrder = "panel.rowOrder"
        static let hiddenWorkspaces = "panel.hiddenWorkspaces"
        static let mutedWorkspaces = "notify.mutedWorkspaces"
        static let notificationsEnabled = "notify.enabled"
        static let mutedUntil = "notify.mutedUntil"
        static let messageSendingEnabled = "chat.sendingEnabled"
        static let presenceEnabled = "presence.enabled"
        static let calmBlinkWorkspaces = "panel.calmBlink"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = Preferences.sharedDefaults) {
        self.defaults = defaults
    }

    /// Where the preferences end up.
    ///
    /// With `CLAWD_LIGHT_HOME` set, a separate domain is used, because the
    /// end-to-end tests launch the real app and without this detour their
    /// preferences would get mixed in with the user's: a test that switches a
    /// notification on would leave it switched on afterwards.
    static let sharedDefaults: UserDefaults = {
        guard AppConfig.isUsingHomeOverride else { return .standard }
        let suite = "com.clawdlight.app.test.\(AppConfig.homeDirectory.lastPathComponent)"
        return UserDefaults(suiteName: suite) ?? .standard
    }()

    var isCompact: Bool {
        get { defaults.bool(forKey: Key.compact) }
        nonmutating set { defaults.set(newValue, forKey: Key.compact) }
    }

    /// `true` when the click, after raising the window, also opens the session's
    /// tab. **Off by default.**
    ///
    /// It used to be on, and was switched off in the face of the evidence. Two
    /// defects, both visible only once raising the window actually started
    /// working — before that the deep link never fired, because it only fires
    /// after a successful raise:
    ///
    /// 1. VS Code asks for permission on **every** invocation ("Allow an
    ///    extension to open this URI?"). A click that asks for confirmation is
    ///    no longer a click.
    ///
    /// 2. The extension reuses the tab only if it already has one registered for
    ///    that session id (`sessionPanels.get(id)?.reveal()`); otherwise it
    ///    **creates a new one**. That always happens for integrated-terminal
    ///    sessions, which have no Claude panel at all. The result is one extra
    ///    empty tab per click.
    ///
    /// The click still keeps its promise — taking you to the right window —
    /// because that part is done by the accessibility raise, not by the deep
    /// link. Anyone who wants the tab too can switch it back on from the menu.
    var opensSessionTab: Bool {
        get { defaults.object(forKey: Key.opensSessionTab) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.opensSessionTab) }
    }

    /// `true` when the offer to install the hooks has already been shown.
    /// Somebody who declines once doesn't want it offered again at every startup.
    var wasSetupPromptShown: Bool {
        get { defaults.bool(forKey: Key.setupPromptShown) }
        nonmutating set { defaults.set(newValue, forKey: Key.setupPromptShown) }
    }

    // MARK: - Scale

    /// `true` when sessions from the same project share a single row.
    ///
    /// On by default, and the reason is in the real numbers: 22 distinct sessions
    /// across 12 windows. One row per session draws 22 targets for 12 raisable
    /// windows, and ten of those targets lead where another one already leads.
    var groupsByWorkspace: Bool {
        get { defaults.object(forKey: Key.groupByWorkspace) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.groupByWorkspace) }
    }

    /// `true` when the column shows only what is waiting for something.
    var showsOnlyWaiting: Bool {
        get { defaults.bool(forKey: Key.onlyWaiting) }
        nonmutating set { defaults.set(newValue, forKey: Key.onlyWaiting) }
    }

    /// The column's order, by project path. Position `i` is drawn `i`-th and is
    /// slot `i + 1`.
    ///
    /// Data the user arranged, not a derived value: it survives restarts as
    /// written, and `StateStore` gives every newly seen project a place at the
    /// bottom. Whoever upgrades from the pinned-rows version finds their pins at
    /// the top, in slot order — the pins *were* the arranged part of the old
    /// column, and everything else joins below as it is seen.
    var rowOrder: [String] {
        get {
            RowOrder.normalized(
                defaults.stringArray(forKey: Key.rowOrder)
                    ?? defaults.stringArray(forKey: Key.pinnedWorkspaces)
                    ?? []
            )
        }
        nonmutating set {
            defaults.set(RowOrder.normalized(newValue), forKey: Key.rowOrder)
        }
    }

    /// Projects collected into the summary row, by path.
    var hiddenWorkspaces: Set<String> {
        get { readSet(Key.hiddenWorkspaces) }
        nonmutating set { writeSet(newValue, to: Key.hiddenWorkspaces) }
    }

    /// Projects whose amber dot does not blink, by path.
    var calmBlinkWorkspaces: Set<String> {
        get { readSet(Key.calmBlinkWorkspaces) }
        nonmutating set { writeSet(newValue, to: Key.calmBlinkWorkspaces) }
    }

    // MARK: - Notifications

    /// `true` when the panel sends system notifications.
    ///
    /// **Off by default**, and not out of generic caution: switching it on makes
    /// the macOS authorization prompt appear, and a prompt should be shown when
    /// somebody has asked for it.
    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Key.notificationsEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    /// Projects that generate no notifications, by path.
    /// It silences the alerts, **never** the color.
    var mutedWorkspaces: Set<String> {
        get { readSet(Key.mutedWorkspaces) }
        nonmutating set { writeSet(newValue, to: Key.mutedWorkspaces) }
    }

    /// Moment until which every notification is suspended.
    var mutedUntil: Date? {
        get {
            let stamp = defaults.double(forKey: Key.mutedUntil)
            guard stamp > 0 else { return nil }
            let date = Date(timeIntervalSince1970: stamp)
            return date > Date() ? date : nil
        }
        nonmutating set {
            defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.mutedUntil)
        }
    }

    // MARK: - Integration

    /// `true` when the panel declares your presence at the Mac.
    /// **Off by default**: it inverts a Claude Code behavior.
    var presenceEnabled: Bool {
        get { defaults.bool(forKey: Key.presenceEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.presenceEnabled) }
    }

    /// `true` when the panel is allowed to send messages into sessions.
    ///
    /// **Off by default**, and it is the only feature here whose default is about
    /// safety rather than noise. Delivery works by leaving a file in
    /// `~/.clawd-light/inbox/`, and the reader is a shell script Claude Code
    /// spawns — it cannot know who wrote that file. Permissions keep other
    /// accounts out and cannot keep out anything running as you, so while this is
    /// on, any process on your machine can start a turn that speaks in your voice,
    /// with your tools.
    ///
    /// While it is off, the message listener is **not registered at all**: no
    /// hook, no listener, no mailbox. The chat window still reads everything.
    var messageSendingEnabled: Bool {
        get { defaults.bool(forKey: Key.messageSendingEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.messageSendingEnabled) }
    }

    // MARK: - Persisted sets

    /// Adds or removes an element from a set, returning the new value.
    /// Preferences are values: they get replaced, not modified in place.
    static func toggling(_ element: String, in set: Set<String>) -> Set<String> {
        set.contains(element) ? set.subtracting([element]) : set.union([element])
    }

    // The arrangement itself lives in `RowOrder`, in Core: deciding where a row
    // goes — and so which project a key addresses — is a domain decision, and
    // decisions that live in the shell are decisions no test can see.

    private func readSet(_ key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    private func writeSet(_ value: Set<String>, to key: String) {
        // Sorted: keeps the plist readable and any comparison stable.
        defaults.set(value.sorted(), forKey: key)
    }

    /// Saved panel position, if a valid one exists.
    var savedOrigin: NSPoint? {
        guard defaults.object(forKey: Key.originX) != nil,
              defaults.object(forKey: Key.originY) != nil else {
            return nil
        }
        return NSPoint(
            x: defaults.double(forKey: Key.originX),
            y: defaults.double(forKey: Key.originY)
        )
    }

    func saveOrigin(_ origin: NSPoint) {
        defaults.set(origin.x, forKey: Key.originX)
        defaults.set(origin.y, forKey: Key.originY)
    }

    /// Starting position: top right of the main screen, with enough margin not to
    /// end up under the menu bar.
    static func defaultOrigin(panelSize: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let visible = screen.visibleFrame
        return NSPoint(
            x: visible.maxX - panelSize.width - 16,
            y: visible.maxY - panelSize.height - 16
        )
    }

    /// Brings the panel back on screen when the saved position has ended up
    /// outside — which happens when an external monitor is disconnected.
    static func clamped(_ origin: NSPoint, panelSize: NSSize) -> NSPoint {
        let screens = NSScreen.screens
        let frame = NSRect(origin: origin, size: panelSize)

        if screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            return origin
        }
        return defaultOrigin(panelSize: panelSize)
    }
}
