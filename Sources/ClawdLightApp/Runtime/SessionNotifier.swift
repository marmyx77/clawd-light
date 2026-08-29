import AppKit
import ClawdLightCore
import Combine
import Foundation
import UserNotifications

/// Sends a system notification when a session gets **blocked**.
///
/// Only `awaiting`, never `ready`. That distinction is the whole feature: a ready
/// answer can wait until you look at it, a permission cannot — until you answer,
/// that work is stopped. Notifying on green as well, with a dozen sessions open,
/// would produce tens of alerts a day, and a channel that alerts too often gets
/// switched off within two days. Then the real blocks would stop arriving too.
@MainActor
final class SessionNotifier {

    private let store: StateStore
    private let preferences: Preferences
    private let onOpen: (SessionState) -> Void

    /// The sessions an alert has already gone out for.
    ///
    /// Without a memory, every state recomputation would resend the same
    /// notification: the column updates continuously, and a repeated notification
    /// is worse than no notification.
    private var announced: Set<String> = []

    private var cancellables = Set<AnyCancellable>()
    private var isPanelVisible: () -> Bool = { false }
    private var authorized = false

    init(
        store: StateStore,
        preferences: Preferences,
        onOpen: @escaping (SessionState) -> Void
    ) {
        self.store = store
        self.preferences = preferences
        self.onOpen = onOpen
    }

    func start(isPanelVisible: @escaping () -> Bool) {
        self.isPanelVisible = isPanelVisible

        store.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.react(to: state) }
            .store(in: &cancellables)

        // Authorization is requested only when the feature is on: asking at
        // startup would put a system dialog in front of somebody who never wanted
        // it, and at that point the most likely answer is "no" forever.
        if preferences.notificationsEnabled { requestAuthorization() }
    }

    /// Requests permission to notify. To be invoked when the user turns the switch
    /// on, that is, while they are there reading the dialog.
    func requestAuthorization(then completion: ((Bool) -> Void)? = nil) {
        guard Bundle.main.bundleIdentifier != nil else {
            // Outside a bundle `UNUserNotificationCenter` is unusable and trying
            // would terminate the process. This happens when the bare binary is
            // launched from a terminal.
            Diagnostics.log("notifications unavailable: the app is not running as a bundle")
            completion?(false)
            return
        }

        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
                Task { @MainActor in
                    self?.authorized = granted
                    // The outcome is logged **always**, not just on failure. An
                    // accessory app is never frontmost, and the authorization
                    // dialog may not appear at all: without this line "denied" and
                    // "never asked" are indistinguishable from the outside, and you
                    // end up hunting for the defect in delivery.
                    Diagnostics.log(
                        "notification authorization: \(granted ? "GRANTED" : "DENIED")"
                            + (error.map { " — \($0.localizedDescription)" } ?? "")
                    )
                    completion?(granted)
                }
            }
    }

    // MARK: - Reacting to state changes

    private func react(to state: TrafficLightState) {
        let blocked = state.sessions.values.filter { $0.status == .awaiting }
        let blockedIds = Set(blocked.map(\.id))

        // Anything that has become unblocked is a candidate again: if it blocks
        // tomorrow, that is a new event and deserves a new alert.
        announced.formIntersection(blockedIds)

        // With the feature off we still take note of what is already blocked.
        // Without that, switching it on with ten stalled sessions would fire ten
        // notifications at once — precisely the burst that makes people disable a
        // channel and never re-enable it.
        //
        // What gets notified is a **transition**, not a state: whatever was already
        // that way before you asked to be told is not news.
        guard preferences.notificationsEnabled else {
            announced.formUnion(blockedIds)
            return
        }

        for session in blocked where !announced.contains(session.id) {
            announced.insert(session.id)
            guard passesGate(session) else { continue }
            deliver(session)
        }
    }

    /// The gate deciding whether the alert is really needed.
    ///
    /// Only the **explicit** silences remain: the ones the user asked for.
    ///
    /// There used to be a presence condition too — no alert if the panel is
    /// visible and you touched the Mac recently — and it was removed in the face
    /// of the evidence. The reasoning looked sound: if you're looking at the
    /// screen, you can already see the amber dot. But the panel is **floating**,
    /// which means it is on screen by construction; and if you're at the Mac,
    /// you're active. The two conditions were therefore almost always true
    /// together, and the result was an inert feature: you switched it on and
    /// nothing ever arrived.
    ///
    /// Measured, not deduced: the first test notification ended up in the log as
    /// "suppressed (panel visible, idle for 62s)" while the user was in another
    /// application, waiting for it.
    ///
    /// "Visible" does not mean "looked at". A two-hundred-pixel panel in the
    /// corner of three screens is on screen and out of attention, and that is
    /// exactly the situation where a notification is needed.
    ///
    /// What stands in its place: the memory that avoids duplicates, the per-project
    /// silence and the timed one. Three **explicit** checks, which the user chooses
    /// and can see — instead of one implicit check that swallows alerts silently.
    private func passesGate(_ session: SessionState) -> Bool {
        if let until = preferences.mutedUntil, until > Date() {
            Diagnostics.log("notification suppressed (muted until \(until)): \(session.workspace.name)")
            return false
        }
        if preferences.mutedWorkspaces.contains(session.workspace.path) {
            Diagnostics.log("notification suppressed (project muted): \(session.workspace.name)")
            return false
        }

        return true
    }

    private func deliver(_ session: SessionState) {
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = RowNames.name(of: session.workspace.path, in: preferences.rowNames) ?? session.displayName
        // Not `lastMessage`, and this is a correction rather than a preference.
        // A `Notification` payload carries no `last_assistant_message`, and
        // `with(lastMessage:)` keeps the previous value when the new one is
        // absent — so the row still holds the reply from the turn *before* the
        // question. Quoting it here presented the previous answer as the thing
        // being asked about, which is the worst kind of wrong: fluent, specific,
        // and false. The session's own title is current by construction; where
        // there is none, the plain sentence says only what is true.
        content.body = session.title.map { "Waiting for your answer — \($0)" }
            ?? "Waiting for your answer."
        content.sound = .default
        // Carries the session id: clicking the notification has to take you *there*,
        // not generically to the app.
        content.userInfo = ["sessionId": session.id]

        let request = UNNotificationRequest(
            identifier: "clawd-light.awaiting.\(session.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            Task { @MainActor in
                if let error {
                    Diagnostics.log("notification NOT delivered: \(error.localizedDescription)")
                } else {
                    Diagnostics.log("notification delivered: \(session.workspace.name)")
                }
            }
        }
    }

    /// Opens the session named by a notification that was clicked.
    func handleActivation(sessionId: String) {
        guard let session = store.state.sessions[sessionId] else { return }
        onOpen(session)
    }

    // MARK: - User presence

    /// Seconds elapsed since the last keyboard or mouse event.
    ///
    /// `CGEventSource` answers even an accessory app without extra permissions:
    /// it does not read *what* was pressed, only *when*.
    static func secondsSinceLastInput() -> TimeInterval {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .scrollWheel]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .greatestFiniteMagnitude
    }
}
