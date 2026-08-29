import ClawdLightCore
import SwiftUI

/// Visual appearance of the five states.
///
/// The choice of colors is not decorative. With a dozen sessions open, the column
/// spends most of its time entirely red: if red shouted as loudly as green, the
/// eye would stop distinguishing the state that actually matters. So rest is
/// muted and brightness grows with urgency.
enum StatusPalette {

    static func color(for status: SessionStatus) -> Color {
        switch status {
        // `failed` shares the hue of `idle`: nothing is coming from either of them.
        // What tells them apart is brightness and glow, the same grammar the
        // palette already uses for urgency — so the difference reads in compact
        // mode too, where there is no text.
        case .idle, .failed:
            return Color(red: 0.85, green: 0.24, blue: 0.24)
        case .working:
            return Color(red: 0.98, green: 0.75, blue: 0.16)
        case .awaiting:
            return Color(red: 1.00, green: 0.45, blue: 0.10)
        case .ready:
            return Color(red: 0.20, green: 0.85, blue: 0.42)
        // The one cool hue in a warm palette, on purpose: everything else is a
        // shade of "attention", and this is the state that asks for none.
        case .waiting:
            return Color(red: 0.42, green: 0.66, blue: 0.98)
        }
    }

    /// Opacity at rest: the idle state stays readable without catching the eye.
    static func opacity(for status: SessionStatus) -> Double {
        status == .idle ? 0.45 : 1.0
    }

    /// Glow radius. Only the states asking for attention have one.
    static func glowRadius(for status: SessionStatus) -> CGFloat {
        switch status {
        case .idle: return 0
        case .working, .waiting: return 3
        case .awaiting, .ready, .failed: return 6
        }
    }

    /// Color of the timestamp in the row.
    ///
    /// `Color.primary` follows the system theme — white on dark, black on light —
    /// and the opacity is tuned to sit below the workspace name while staying
    /// readable. The weaker semantic hues (`.secondary`, `.tertiary`) over an
    /// `NSVisualEffectView` get attenuated a second time by vibrancy, and the
    /// result disappears.
    static let timeColor = Color.primary.opacity(0.62)

    /// The strip that says a click could not do its job.
    ///
    /// It borrows the `awaiting` hue rather than inventing one: the column already
    /// teaches that this shade means "this needs you", and a strip in a colour the
    /// panel has never used would read as belonging to some other application.
    static let warningTint = Color(red: 1.00, green: 0.45, blue: 0.10)

    /// The ring around a row that has something listening behind it.
    ///
    /// Exactly the `waiting` blue, and that is the whole idea: the column has
    /// already taught that this shade means "something is registered and nothing
    /// needs you". As a fill it says the row *is* that; as a ring it says the row
    /// *also* is that, without taking the colour that carries the news.
    static let listeningTint = Color(red: 0.42, green: 0.66, blue: 0.98)

    /// Text of the badge carrying the session or subagent count.
    static let badgeForeground = Color.primary.opacity(0.80)

    /// Badge background: enough to separate it from the name, not so much that it
    /// competes with the dot, which is the only thing meant to catch the eye.
    static let badgeBackground = Color.primary.opacity(0.14)

    /// The vertical rule marking a pinned project.
    static let pinMarker = Color.primary.opacity(0.35)

    static func label(for status: SessionStatus) -> String {
        switch status {
        case .idle: return "idle"
        case .working: return "working"
        case .waiting: return "waiting on background work"
        // Neutral with respect to the reason: it covers both the permission
        // request and a dialog opened by an MCP server, without having to
        // propagate the cause.
        case .awaiting: return "waiting for your answer"
        case .ready: return "answer ready"
        case .failed: return "turn interrupted"
        }
    }
}

/// Interface measurements, gathered here so magic numbers don't scatter through
/// the views.
enum Layout {
    static let dotSize: CGFloat = 11
    /// Thickness of the listening ring, drawn inside the dot. Two points of
    /// eleven: visible at a glance across a room, and it still leaves a core
    /// large enough to read the colour underneath.
    static let listeningRing: CGFloat = 2
    /// Thickness of the context ring, which is the same eleven points across as
    /// the dot and sits beside it. Two points again, and for the same reason:
    /// any thinner and the arc stops being readable at a glance, any thicker and
    /// there is no room left inside for the model's letter.
    static let contextRingWidth: CGFloat = 2
    static let rowHeight: CGFloat = 22
    static let rowSpacing: CGFloat = 2
    static let panelPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 12

    /// Width of the conversation list in the extended window.
    ///
    /// Wider than the panel's 240 because it carries a second line — what was
    /// last said — and a preview truncated to three words is not a preview.
    static let sidebarWidth: CGFloat = 260

    static let compactWidth: CGFloat = 35
    /// Wide enough for a readable workspace name plus the timestamp.
    /// Long but common names ("internal-admin-console") fit almost entirely:
    /// below this threshold, middle truncation makes them indistinguishable.
    static let expandedWidth: CGFloat = 240

    static func width(compact: Bool) -> CGFloat {
        compact ? compactWidth : expandedWidth
    }

    /// The strip under the rows that holds the gear — the visible door to the
    /// menu a right-click on the margins also opens. Small on purpose: it is a
    /// hint that the menu exists, not a toolbar.
    static let footerHeight: CGFloat = 19

    /// The line that appears only when a click could not raise a window.
    ///
    /// The panel grows by it rather than the strip overlapping a row: a widget
    /// that covers its own content to complain is worse than one that is a few
    /// points taller for as long as the fault lasts.
    static let issueStripHeight: CGFloat = 17

    /// Height needed for `count` rows, capped at `maxVisibleRows`, plus the footer
    /// and, while there is one, the issue strip.
    static func height(rowCount: Int, showsIssue: Bool = false) -> CGFloat {
        let visible = min(max(rowCount, 1), AppConfig.maxVisibleRows)
        let rows = CGFloat(visible) * rowHeight + CGFloat(max(visible - 1, 0)) * rowSpacing
        return rows + panelPadding * 2 + footerHeight + (showsIssue ? issueStripHeight : 0)
    }
}
