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
        case .working: return 3
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
    /// Long but common names ("docs-site") fit almost entirely:
    /// below this threshold, middle truncation makes them indistinguishable.
    static let expandedWidth: CGFloat = 240

    static func width(compact: Bool) -> CGFloat {
        compact ? compactWidth : expandedWidth
    }

    /// Height needed for `count` rows, capped at `maxVisibleRows`.
    static func height(rowCount: Int) -> CGFloat {
        let visible = min(max(rowCount, 1), AppConfig.maxVisibleRows)
        let rows = CGFloat(visible) * rowHeight + CGFloat(max(visible - 1, 0)) * rowSpacing
        return rows + panelPadding * 2
    }
}
