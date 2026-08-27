import ClawdLightCore
import SwiftUI

/// The actions a row's context menu can perform.
///
/// They are gathered into a type rather than passed one by one because there are
/// six of them and there will be more: a signature with six closures becomes
/// unreadable the first time a parameter is added in the middle.
struct RowActions {
    let open: (ColumnRow) -> Void
    let peek: (ColumnRow) -> Void
    let markUnread: (ColumnRow) -> Void
    /// Moves the row one place up (`-1`) or down (`+1`) among the rows shown.
    let move: (ColumnRow, Int) -> Void
    /// Puts the row at a position among the rows shown; what a drag ends with.
    let place: (ColumnRow, Int) -> Void
    let toggleHidden: (ColumnRow) -> Void
    let toggleMuted: (ColumnRow) -> Void
    let toggleCalmBlink: (ColumnRow) -> Void
    let newConversation: (ColumnRow) -> Void
    /// Opens the conversation in a window of its own, without touching VS Code.
    let openChat: (ColumnRow) -> Void
    /// Gives the row the name the user wants to read, by folder.
    let rename: (ColumnRow) -> Void
}

/// What the column tells a row about the drag in progress.
///
/// The drag is the column's business — it is the column that knows how many
/// rows there are and which one the pointer is over — so the row only draws
/// where it is told to and reports the handle's movement back.
struct RowDragState {
    /// Vertical displacement to draw the row at, in points.
    let offset: CGFloat
    /// `true` for the row under the pointer.
    let isDragged: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void
}

/// State of the preferences that concern one row.
struct RowFlags {
    let isHidden: Bool
    let isMuted: Bool
    let isCalm: Bool
    let notificationsEnabled: Bool
}

/// One row of the column: a light and, in expanded mode, the project name with
/// the time of the last activity.
struct TrafficLightRow: View {
    let row: ColumnRow
    let compact: Bool
    /// Reference moment for the time label, updated by the column.
    let now: Date
    let flags: RowFlags
    let actions: RowActions
    /// `nil` in compact mode, where there is no room for a handle.
    var drag: RowDragState? = nil

    @State private var hovering = false

    private var isDragged: Bool { drag?.isDragged ?? false }

    var body: some View {
        HStack(spacing: 7) {
            TrafficLightDot(status: row.status, calm: flags.isCalm)

            if !compact {
                // The slot number, which is the answer to "which key opens this".
                // Without it the binding is invisible and you have to count rows —
                // and counting rows is exactly what an address exists to avoid.
                if let slot = row.slot {
                    Text("\(slot)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(StatusPalette.timeColor)
                        .monospacedDigit()
                        .frame(width: 7)
                }

                // A terminal row says so, the way a remote one says where it is:
                // its click leads to a tab, not to an editor window.
                if row.isTerminal {
                    Image(systemName: "terminal")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(StatusPalette.timeColor)
                }

                Text(row.displayLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(StatusPalette.badgeForeground)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(StatusPalette.badgeBackground)
                        )
                        .fixedSize()
                }

                Spacer(minLength: 4)

                Text(timeLabel)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    // The hierarchy against the name comes from the font weight,
                    // not from fading the color: on a dark vibrant surface
                    // `.tertiary` becomes illegible, and a timestamp you can't
                    // read takes up space without saying anything.
                    .foregroundStyle(StatusPalette.timeColor)
                    .lineLimit(1)
                    // Stops a long name from squeezing out the timestamp: the
                    // timestamp has priority, it's the information read in passing.
                    .layoutPriority(1)
                    .monospacedDigit()

                if let drag {
                    handle(drag)
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Layout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(isDragged ? 0.18 : hovering ? 0.12 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: activate)
        .contextMenu { menu }
        .help(tooltip)
        // The row follows the pointer while it is the one being dragged, and steps
        // aside — animated — when another row is dragged past it.
        .offset(y: drag?.offset ?? 0)
        .zIndex(isDragged ? 1 : 0)
        .shadow(color: .black.opacity(isDragged ? 0.35 : 0), radius: isDragged ? 6 : 0, y: 2)
        .animation(isDragged ? nil : .easeOut(duration: 0.12), value: drag?.offset ?? 0)
    }

    /// The three lines on the right: where you grab the row to move it.
    ///
    /// Always drawn, dimly: a handle you have to hover to discover is a handle
    /// nobody discovers. The grab area underneath is an AppKit view (`DragHandle`)
    /// — a SwiftUI gesture here moved the panel instead of the row — and it also
    /// swallows a plain click, which is not a click on the row and must not open
    /// anything.
    private func handle(_ drag: RowDragState) -> some View {
        ZStack {
            DragHandle(onChanged: drag.onChanged, onEnded: drag.onEnded)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(hovering || drag.isDragged ? 0.6 : 0.3))
                .allowsHitTesting(false)
        }
        .frame(width: 14, height: Layout.rowHeight)
    }

    // MARK: - Interaction

    /// Alt+click peeks: it raises the window without consuming the green.
    ///
    /// `markedSeen` is irreversible by construction, and that is fine — but
    /// without an escape hatch one click too many erases an answer nobody read.
    /// The menu entry exists because a modifier nobody discovers is dead code.
    private func activate() {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command), !row.workspace.isRemote {
            activateChat()
        } else if modifiers.contains(.option) {
            actions.peek(row)
        } else {
            actions.open(row)
        }
    }

    /// ⌘+click opens the extended window on this conversation.
    ///
    /// The modifier and the menu entry both exist for the same reason alt+click
    /// does: the gesture is the fast path for people who know it, the menu is how
    /// anybody finds out it is there.
    private func activateChat() {
        actions.openChat(row)
    }

    @ViewBuilder
    private var menu: some View {
        // The transcript of a remote session is on the other machine, and a new
        // conversation opens in the local editor: neither entry can mean anything
        // for a row that lives elsewhere, so neither is offered.
        if !row.workspace.isRemote {
            Button("Read here — opens the conversations", action: { actions.openChat(row) })
        }
        Button("Open", action: { actions.open(row) })
        Button("Open without marking as read", action: { actions.peek(row) })

        if row.status == .idle {
            Button("Mark as unread", action: { actions.markUnread(row) })
        }

        Divider()

        // The drag with words, for whoever prefers a menu to a handle. Same
        // arrangement, same persistence.
        Button("Move up", action: { actions.move(row, -1) })
        Button("Move down", action: { actions.move(row, 1) })
        Button(row.alias == nil ? "Rename…" : "Rename… (“\(row.workspace.name)” underneath)",
               action: { actions.rename(row) })

        Button(flags.isHidden ? "✓ Hide" : "Hide",
               action: { actions.toggleHidden(row) })

        if row.status == .awaiting {
            Button(flags.isCalm ? "✓ Don't blink" : "Don't blink",
                   action: { actions.toggleCalmBlink(row) })
        }

        if flags.notificationsEnabled {
            Button(flags.isMuted ? "✓ Don't alert me for this project" : "Don't alert me for this project",
                   action: { actions.toggleMuted(row) })
        }

        // A terminal row has no tab to open a conversation in either.
        if !row.workspace.isRemote && !row.isTerminal {
            Divider()
            Button("New conversation here", action: { actions.newConversation(row) })
        }
    }

    // MARK: - Content

    /// The badge next to the name: how many sessions, or how many subagents.
    ///
    /// The two pieces of information don't share the same space, so the winner is
    /// the one saying something rarer: subagents at work explain *why* the row is
    /// yellow, the session count does not.
    private var badge: String? {
        if row.activeSubagents > 0 { return "×\(row.activeSubagents)" }
        if row.count > 1 { return "\(row.count)" }
        return nil
    }

    /// What the right-hand slot shows.
    ///
    /// Not always a timestamp, because the timestamp isn't always the useful
    /// information: on a working session what counts is *how long* (`42m` reads in
    /// half a second, `08:14` has to be computed), and on an interrupted turn what
    /// counts is *why*. The timestamp stays in the tooltip in both cases.
    private var timeLabel: String {
        switch row.status {
        case .working, .waiting:
            return CompactDuration.label(seconds: row.primary.statusDuration(at: now))
        case .failed:
            return (row.primary.failureReason ?? .unknown).shortLabel
        case .idle, .awaiting, .ready:
            return RelativeTime.label(for: row.updatedAt, now: now)
        }
    }

    /// An idle session dims, but stays readable: same reason the timestamp doesn't
    /// use the weak semantic hues over vibrancy.
    private var labelColor: Color {
        row.status == .idle ? Color.primary.opacity(0.72) : .primary
    }

    private var tooltip: String {
        var lines = [
            "\(row.displayLabel) — \(StatusPalette.label(for: row.status))",
            RelativeTime.detailedLabel(for: row.updatedAt, now: now),
        ]

        // A blue row has to say what is holding it, or a wait that lasts a day is
        // indistinguishable from a defect. "monitor ×2, shell" is the difference.
        if row.status == .waiting {
            let counts = row.primary.waitingOn.reduce(into: [(String, Int)]()) { acc, type in
                if let i = acc.firstIndex(where: { $0.0 == type }) { acc[i].1 += 1 } else { acc.append((type, 1)) }
            }
            if !counts.isEmpty {
                lines.append("waiting on " + counts.map { $0.1 > 1 ? "\($0.0) ×\($0.1)" : $0.0 }.joined(separator: ", "))
            }
        }

        if let slot = row.slot {
            lines.append("Slot \(slot) — clawd-light open \(slot)")
        }

        if row.count > 1 {
            lines.append("\(row.count) sessions in this project:")
            for session in row.sessions.prefix(8) {
                lines.append("  · \(StatusPalette.label(for: session.status))")
            }
            if row.count > 8 { lines.append("  · …and \(row.count - 8) more") }
        }

        if row.activeSubagents > 0 {
            lines.append("\(row.activeSubagents) subagents at work")
        }

        if row.status == .failed, let reason = row.primary.failureReason {
            lines.append(reason.detailedLabel)
        }

        if let message = row.primary.lastMessage {
            // On an interrupted turn `last_assistant_message` holds the error
            // text, not an answer: without the prefix it would look like
            // something Claude wrote for you.
            lines.append(row.status == .failed ? "Error: \(message)" : message)
        }

        if flags.isMuted { lines.append("Notifications muted for this project.") }

        lines.append("Click to open. ⌘+click for the conversations. Alt+click to keep the green.")
        if drag != nil { lines.append("Drag ≡ to reorder; the order is yours and does not change on its own.") }
        return lines.joined(separator: "\n")
    }
}
