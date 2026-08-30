import AppKit
import LampBoardCore
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
        static let remoteHosts = "remote.hosts"
        static let hiddenWorkspaces = "panel.hiddenWorkspaces"
        static let mutedWorkspaces = "notify.mutedWorkspaces"
        static let notificationsEnabled = "notify.enabled"
        static let mutedUntil = "notify.mutedUntil"
        static let messageSendingEnabled = "chat.sendingEnabled"
        static let presenceEnabled = "presence.enabled"
        static let terminalSessions = "terminal.sessions"
        static let rowNames = "panel.rowNames"
        static let calmBlinkWorkspaces = "panel.calmBlink"
        static let expandedRows = "panel.expandedRows"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = Preferences.sharedDefaults) {
        self.defaults = defaults
    }

    /// Where the preferences end up.
    ///
    /// With `LAMPBOARD_HOME` set, a separate domain is used, because the
    /// end-to-end tests launch the real app and without this detour their
    /// preferences would get mixed in with the user's: a test that switches a
    /// notification on would leave it switched on afterwards.
    static let sharedDefaults: UserDefaults = {
        guard AppConfig.isUsingHomeOverride else { return .standard }
        let suite = "com.lampboard.app.test.\(AppConfig.homeDirectory.lastPathComponent)"
        return UserDefaults(suiteName: suite) ?? .standard
    }()

    /// The preference domain this app had before it was renamed.
    ///
    /// `UserDefaults.standard` is keyed on the bundle identifier, so renaming the
    /// bundle does not move preferences: it hides them. Everything the user chose
    /// is still on disk under the old name and simply never read again.
    private static let legacyDomain = "com.clawdlight.app"

    /// Marks that the one-time import has happened, so it never runs twice.
    private static let migrationKey = "migrated.from.clawdlight"

    /// Brings across everything the previous name held, once.
    ///
    /// This is not housekeeping. What lives here is the part of the app that is
    /// **the user's**: the names they gave the rows, the order they dragged them
    /// into, where on the screen they put the panel, whether notifications are
    /// on. A rename that silently discarded that would be indistinguishable, from
    /// where they sit, from the app forgetting who they are — and the row names
    /// in particular took real thought to write and are nowhere else on disk.
    ///
    /// Everything is copied, not a chosen subset. The domain holds window frames
    /// and other keys AppKit writes without asking anybody, and a migration that
    /// listed what to carry would drop each new key added after it was written,
    /// silently, in exactly the way nobody notices for a year.
    ///
    /// It runs before anything reads a preference, so the first read already sees
    /// the imported value. That ordering is the whole of the correctness here: a
    /// getter that imports on first read — `remoteHosts` has one — will otherwise
    /// have already written its empty default and closed the door.
    static func migrateFromPreviousName(into defaults: UserDefaults = Preferences.sharedDefaults) {
        guard !AppConfig.isUsingHomeOverride else { return }
        guard !defaults.bool(forKey: migrationKey) else { return }
        defer { defaults.set(true, forKey: migrationKey) }

        guard let legacy = UserDefaults(suiteName: legacyDomain),
              let values = legacy.persistentDomain(forName: legacyDomain),
              !values.isEmpty
        else { return }

        var imported = 0
        for (key, value) in values where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            imported += 1
        }
        Diagnostics.log("preferences: imported \(imported) keys from \(legacyDomain)")
    }

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

    /// Machines whose sessions join the column, by the name ssh knows them under.
    ///
    /// Set in the Settings window; validated on both sides of the store, because
    /// a name becomes an argument to `ssh`. Whoever upgrades from the file-based
    /// version finds the hosts of `~/.lampboard/remotes` imported the first time
    /// this is read — the one write a getter is allowed, and it happens once —
    /// and the file is not consulted again.
    var remoteHosts: [String] {
        get {
            if let stored = defaults.stringArray(forKey: Key.remoteHosts) {
                return stored.filter(RemoteHostList.isUsable)
            }
            let imported = RemoteHostList.parse(
                (try? String(contentsOf: AppConfig.remoteHostsFile, encoding: .utf8)) ?? ""
            )
            defaults.set(imported, forKey: Key.remoteHosts)
            return imported
        }
        nonmutating set {
            var seen = Set<String>()
            defaults.set(
                newValue.map { $0.trimmed }.filter { RemoteHostList.isUsable($0) && seen.insert($0).inserted },
                forKey: Key.remoteHosts
            )
        }
    }

    /// The names the user gave to rows, by folder (`RowNames`).
    var rowNames: [String: String] {
        get { (defaults.dictionary(forKey: Key.rowNames) as? [String: String]) ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Key.rowNames) }
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

    /// Rows the user opened to see the sessions inside, by row id.
    ///
    /// By row id and not by folder, because a folder can hold a Claude row and a
    /// Codex row and each is opened on its own. The id already carries both.
    ///
    /// A row stays in here even when its project drops back to a single session.
    /// Opening is a statement about the project, "I want to see inside this one",
    /// not about how many sessions it happens to hold right now: an opening that
    /// evaporated on its own would not come back when a second session started,
    /// and that is the worse surprise.
    var expandedRows: Set<String> {
        get { readSet(Key.expandedRows) }
        nonmutating set { writeSet(newValue, to: Key.expandedRows) }
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

    /// Whether sessions in folders no editor claims — `claude` in a terminal —
    /// get rows (D25). Off by default: the first click on one asks for an
    /// Automation permission for that terminal application (D8).
    var showsTerminalSessions: Bool {
        get { defaults.bool(forKey: Key.terminalSessions) }
        nonmutating set { defaults.set(newValue, forKey: Key.terminalSessions) }
    }

    /// `true` when the panel is allowed to send messages into sessions.
    ///
    /// **Off by default**, and it is the only feature here whose default is about
    /// safety rather than noise. Delivery works by leaving a file in
    /// `~/.lampboard/inbox/`, and the reader is a shell script Claude Code
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
