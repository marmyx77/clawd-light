import LampBoardCore
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
    /// Opens the folder the session is working in, in the Finder.
    let revealInFinder: (ColumnRow) -> Void
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
    @State private var hoveringFolder = false

    private var isDragged: Bool { drag?.isDragged ?? false }

    var body: some View {
        HStack(spacing: 7) {
            // The light and its ring travel together, closer to each other than
            // to anything else: same session, two questions.
            HStack(spacing: Layout.dotToRing) {
                TrafficLightDot(status: row.status, calm: flags.isCalm, listening: row.listeners > 0)

                if !compact {
                    ring
                }
            }

            if !compact {
                // A terminal row says so, the way a remote one says where it is:
                // its click leads to a tab, not to an editor window.
                if row.isTerminal {
                    Image(systemName: "terminal")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(StatusPalette.timeColor)
                }

                Text(row.displayLabel)
                    // Twelve points, not eleven. The point came out of the
                    // timestamp: `yesterday` was 49.83 points of a field this one
                    // shares, `1d` is 13.04, and the tooltip says the word. Even
                    // on the rows that kept the widest label — `14:56`, `22/07` —
                    // the name loses two points and gains a size.
                    .font(.system(size: 12, weight: .medium, design: .rounded))
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
                    .font(.system(size: 12, weight: .regular, design: .rounded))
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

                // Appears under the pointer and takes eighteen points off the
                // name while it is there. That cost is the whole argument: the
                // alternative was carrying it on every row for ever, on rows
                // where it cannot even work — a session on another machine has a
                // path, and it is not a path on this Mac.
                if hovering, !row.workspace.isRemote {
                    folderButton
                }

                if let drag {
                    handle(drag)
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .padding(.horizontal, 6)
        .frame(height: Layout.rowHeight)
        // Compact mode is thirty-five points of panel with one eleven-point dot
        // in it: leading alignment left that dot two points off the centre line,
        // which on a column of twelve rows reads as a column that is crooked.
        .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(isDragged ? 0.18 : hovering ? 0.12 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: activate)
        .contextMenu { menu }
        .tooltip(RowSummary.of(row, now: now, muted: flags.isMuted))
        // The row follows the pointer while it is the one being dragged, and steps
        // aside — animated — when another row is dragged past it.
        .offset(y: drag?.offset ?? 0)
        .zIndex(isDragged ? 1 : 0)
        .shadow(color: .black.opacity(isDragged ? 0.35 : 0), radius: isDragged ? 6 : 0, y: 2)
        .animation(isDragged ? nil : .easeOut(duration: 0.12), value: drag?.offset ?? 0)
    }

    /// How full this session's context is, and on which model.
    ///
    /// It took the cell the slot number used to have: the slot answers "which key
    /// opens this" once and never changes, and it reads well enough in the
    /// tooltip. This changes while you work, and it is what decides whether a
    /// large task starts here or in a new session.
    ///
    /// Drawn on every row, including the ones with nothing read yet — a cell that
    /// appeared and disappeared would move the names of half the column sideways
    /// every time a session replied.
    private var ring: some View {
        ContextRing(reading: row.context)
    }

    /// The folder this session is working in, one click away.
    ///
    /// Drawn only while the pointer is on the row. A permanent icon would be
    /// eighteen points off every name — measured: 100.87 becomes 82.87, which is
    /// where the names were before this afternoon's work gave the width back —
    /// and it would have to disappear on remote rows anyway, which is the same
    /// jump with worse timing.
    private var folderButton: some View {
        Button {
            actions.revealInFinder(row)
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(hoveringFolder ? 0.85 : 0.45))
                .frame(width: 13, height: Layout.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringFolder = $0 }
        .transition(.opacity)
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
        } else if modifiers.contains(.shift), !row.workspace.isRemote {
            // The fast path for the glyph that only appears on hover. Both exist
            // for the same reason the other two modifiers do: the gesture is for
            // whoever knows it, the menu is how anybody finds out it is there.
            actions.revealInFinder(row)
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

        // Absent, not disabled, on a row that lives elsewhere: the folder is on
        // that machine, and a greyed entry would still be a promise.
        if !row.workspace.isRemote {
            Button("Show in Finder", action: { actions.revealInFinder(row) })
        }

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

}
