import LampBoardCore
import SwiftUI

/// One conversation inside an opened block.
///
/// It shares three cells with the row above it so the panel keeps one vertical
/// rhythm: the dot sits inside the parent's dot column, the ring occupies the
/// parent's ring cell, and the name starts exactly where the parent's name
/// starts, with the same width. There is no indentation at all, and that is the
/// point: on a 240 point panel ten points of indent is a tenth of the field that
/// carries the identity. What gives the block its shape is the spine, drawn three
/// points inside the margin, where it costs nobody anything.
///
/// It draws less than a row on purpose. No slot, because a slot addresses a
/// project and conversations come and go. No glow and no blink: the parent
/// already blinks whenever a conversation inside it is waiting for an answer,
/// and three amber dots pulsing a centimetre apart is the Christmas tree the dot
/// was written to avoid.
struct SessionSubRow: View {
    let member: RowSession
    let now: Date
    let open: (RowSession) -> Void
    let rename: (RowSession) -> Void
    let renameLane: (RowSession) -> Void

    @State private var hovering = false

    private var session: SessionState { member.session }

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: Layout.dotToRing) {
                // Right-aligned inside the parent's 13 points, so a smaller dot
                // still hangs off the same column and the block reads as one
                // object rather than two lists side by side.
                TrafficLightDot(status: session.status, calm: true, listening: false)
                    .scaleEffect(Layout.subDotSize / Layout.dotSize)
                    .frame(width: Layout.dotSize, alignment: .trailing)

                ContextRing(reading: session.context)
            }

            Text(member.name)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(Color.primary.opacity(session.status == .idle ? 0.55 : 0.85))
                .lineLimit(1)
                .truncationMode(.middle)

            // Where it is actually true. On the parent this number is a sum
            // across the whole project, so three subagents in one conversation
            // and one each in three read the same; here it belongs to the line
            // that owns it.
            if session.activeSubagents > 0 {
                Text("×\(session.activeSubagents)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(StatusPalette.badgeForeground)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(StatusPalette.badgeBackground))
                    .fixedSize()
            }

            Spacer(minLength: 4)

            Text(timeLabel)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(StatusPalette.timeColor)
                .lineLimit(1)
                .layoutPriority(1)
                .monospacedDigit()

            AgentGrip(harness: session.harness)
        }
        .padding(.horizontal, 6)
        .frame(height: Layout.subRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.10 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { open(member) }
        .contextMenu {
            Button("Open this conversation") { open(member) }
            Divider()
            Button("Rename this conversation\u{2026}") { rename(member) }
            Button("Rename the \(session.harness.displayName) lane\u{2026}") { renameLane(member) }
        }
        .help("\(member.name) · \(session.status.label)")
    }

    /// The same rule the row uses: how long while it is going, why it stopped
    /// when it failed, and when otherwise.
    private var timeLabel: String {
        switch session.status {
        case .working, .waiting:
            return CompactDuration.label(seconds: session.statusDuration(at: now))
        case .failed:
            return (session.failureReason ?? .unknown).shortLabel
        case .idle, .awaiting, .ready:
            return RelativeTime.label(for: session.updatedAt, now: now)
        }
    }
}

/// The grip you drag a line by, tinted with the agent that owns it.
///
/// Six dots in two columns rather than three lines. Three horizontal lines are
/// also what a menu looks like, and this one is only ever a handle; a grip of
/// dots is the mark half the system uses for a sortable list and says nothing
/// else. It is also drawn brighter than the old one: the comment above the
/// handle said a mark you have to hover to find is a mark nobody finds, and then
/// drew it at 30 percent.
///
/// The colour is the last free space on the row, and it is far from the dot: the
/// grip sits in the last cell, two hundred points away, and every line has one.
/// A tint that is always there reads as a label, not as an alarm.
struct AgentGrip: View {
    let harness: Harness

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    dot
                    dot
                }
            }
        }
        .frame(width: 14, height: Layout.subRowHeight)
    }

    private var dot: some View {
        Circle()
            .fill(StatusPalette.agentTint(for: harness))
            .frame(width: 2, height: 2)
    }
}
