import LampBoardCore
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
}

/// Interface measurements, gathered here so magic numbers don't scatter through
/// the views.
enum Layout {
    /// The traffic light itself.
    ///
    /// Eleven for most of this project's life, and two points too small: on a
    /// 27-inch display at arm's length the difference between the dimmed red of
    /// a resting session and the full red of a dead turn is a difference in
    /// brightness across eleven points, which is exactly the kind of judgement
    /// a glance from across the desk cannot make.
    static let dotSize: CGFloat = 13
    /// Thickness of the listening ring, drawn inside the dot. Enough to see from
    /// across a room, and it still leaves a core large enough to read the colour
    /// underneath — which is the whole point of a ring rather than a colour.
    static let listeningRing: CGFloat = 2.5
    /// The context ring, beside the light and slightly larger than it.
    ///
    /// Larger, and that is deliberate rather than an oversight: it has to hold a
    /// letter inside a stroked circle, and the letter was illegible at eleven
    /// points — reported from use, in exactly those words. The light keeps the
    /// eye anyway, because it is the only saturated thing on the row and this one
    /// is grey.
    static let contextRingSize: CGFloat = 16
    /// Three points of sixteen. Thick, and deliberately so: the first version
    /// was two points of eleven, and on screen the consumed arc did not separate
    /// from the track behind it — the ring read as a letter in a circle, which is
    /// half of what it is. Three points leaves ten of clear middle, which is
    /// still more than a capital needs.
    static let contextRingWidth: CGFloat = 3
    /// The letter in the middle of that ring.
    static let contextRingLetter: CGFloat = 8.5
    /// The gap between the light and its context ring.
    ///
    /// Tighter than the row's own spacing, because they are one thing said twice
    /// — this session's state, and this session's room — and because the seven
    /// points the row uses everywhere else are seven points off the name.
    static let dotToRing: CGFloat = 4
    static let rowHeight: CGFloat = 24
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

    /// The strip under the rows: the width control on the left, under the lights,
    /// and the legend and the menu on the right, under the drag handles.
    ///
    /// **It is one more row of the column, and that is the whole point.** At 19
    /// points with 9-point glyphs it was a hint that controls existed; at 22 it
    /// was controls in a band of its own height, which read — accurately — as a
    /// strip bolted underneath. It is now a hairline and a band exactly as tall
    /// as a row, so the footer belongs to the same rhythm as everything above it
    /// instead of interrupting it.
    static let footerHeight: CGFloat = footerRule + rowHeight
    /// The band the glyphs live in: one row, so their centres sit on the same
    /// pitch the lights do.
    static let footerBand: CGFloat = rowHeight
    /// The hairline that says where the rows end. Without it the glyphs float on
    /// the same surface as the column and read as debris; with it they are a
    /// region. One point, at a tenth of the primary colour: any stronger and it
    /// becomes a border, which this panel does not have anywhere else.
    static let footerRule: CGFloat = 1
    /// The glyphs down there. Same size as a row's name, and the same colour:
    /// they are part of the panel's text, not a toolbar bolted under it.
    ///
    /// All three are `.circle` variants, and that is not decoration. A gear, a
    /// question mark in a circle and a pair of loose diagonal arrows have the same
    /// point size and nothing else in common: the arrows are two thin marks with
    /// no bounding shape and an ink that hangs to one corner, so beside two round
    /// outlines they read as smaller, lower and unrelated. Enclosed, all three are
    /// 15 × 15, one silhouette, one weight — which is the difference between three
    /// glyphs and a set of controls.
    static let footerGlyph: CGFloat = 12

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
