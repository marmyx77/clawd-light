import Foundation

/// A fault the user can do something about, as a value rather than a sentence.
///
/// The panel used to carry only `lastError: String?`, and everything derived
/// from it — whether to offer a fix, which pane to open, what to say — had to be
/// guessed by reading the text back. So nothing was offered: the reason for a
/// click that went nowhere lived at the bottom of a context menu, three levels
/// away from the eye, and the first person to be defeated by that was the author
/// of the app, on a fresh install.
///
/// The distinction that matters is not "error / no error" but **can the person
/// looking at the panel fix this right now**. A missing permission can. A folder
/// with no window open cannot, and offering a button for it would be noise.
public enum PanelIssue: Equatable, Sendable {

    /// Privacy & Security › Accessibility. The click cannot choose a window.
    case accessibilityMissing

    /// Privacy & Security › Automation, for one specific target application.
    case automationMissing(app: String)

    /// What the strip under the traffic lights says.
    ///
    /// It has about thirty characters before the panel would have to grow, so
    /// this is not the explanation — it is the smallest true sentence that makes
    /// somebody press the button. The explanation is behind the button.
    public var summary: String {
        switch self {
        case .accessibilityMissing:
            return "Clicks can't raise windows"
        case .automationMissing:
            return "Clicks can't read window titles"
        }
    }

    /// The button beside it. A verb, because it does something.
    public var actionTitle: String { "Fix…" }

    /// The System Settings pane that grants it.
    ///
    /// Two different panes, and sending somebody to the wrong one is worse than
    /// sending them nowhere: they find a switch that is already on, conclude the
    /// permission is fine, and go looking for a fault that isn't there.
    public var settingsURL: URL? {
        switch self {
        case .accessibilityMissing:
            return URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .automationMissing:
            return URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        }
    }

    /// The full text of the sheet behind the button.
    ///
    /// Three things, in this order, because it is the order that gets a yes: what
    /// macOS will call it, the one thing we actually do with it, and what it
    /// costs to refuse. A permission whose refusal is not described reads as a
    /// permission whose cost is being hidden.
    public var explanation: String {
        switch self {
        case .accessibilityMissing:
            return """
                macOS calls this “controlling your computer”. clawd-light uses it \
                for one thing: to bring the editor window of the row you clicked to \
                the front.

                Without it a click still activates the editor, but cannot choose \
                which window — so you land wherever you were last.

                In System Settings, turn the switch on next to clawd-light.
                """
        case .automationMissing(let app):
            return """
                clawd-light needs to ask \(app) for the titles of its windows, to \
                tell your projects apart. It reads titles; it does not type, click \
                or change anything.

                Without it a click still activates the application, but cannot pick \
                the right window or tab.

                In System Settings, enable “\(app)” under clawd-light.
                """
        }
    }

    /// Said under the explanation, every time, because it is the sentence that
    /// makes the rest safe to accept.
    public var reassurance: String {
        "You can turn this off again at any time in the same place, and clawd-light "
            + "keeps working — only the click gets less precise."
    }

    /// The stale-entry cure.
    ///
    /// macOS keys these authorizations on the signature, not the name, so a copy
    /// signed differently — a build from source, a new certificate — leaves its
    /// own record behind. The list then shows one row called clawd-light with the
    /// switch **on** while the app that is running holds nothing, and the switch
    /// is believed over the app. Measured on a real install: four separate
    /// records for the same bundle identifier.
    ///
    /// Only shown when it applies, which is why it is not part of `explanation`.
    public static let staleEntryCure = """
        If clawd-light is already in the list with the switch on, macOS is \
        remembering an older copy of the app. Removing it with “−” may not be \
        enough — there can be several hidden records. This clears them all:

            tccutil reset Accessibility com.clawdlight.app
            tccutil reset AppleEvents com.clawdlight.app
            pkill -x clawd-light && open -a ClawdLight

        The relaunch is part of the cure: macOS keeps a running process's \
        accessibility session open until it exits, so without it clawd-light \
        goes on holding what you just took away. Then click a traffic light \
        again and answer the request.
        """
}
