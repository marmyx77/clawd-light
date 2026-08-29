import ClawdLightCore
import SwiftUI

/// The column of traffic lights: one row per project, or per session when
/// grouping is off.
struct TrafficLightColumn: View {
    @ObservedObject var store: StateStore
    let compact: Bool
    let options: ColumnOptions
    let notificationsEnabled: Bool
    let mutedWorkspaces: Set<String>
    let calmWorkspaces: Set<String>
    let actions: RowActions
    let onRevealHidden: () -> Void

    /// Reference moment for the time labels.
    ///
    /// A reference that advances on its own is needed: session state doesn't
    /// change at midnight, but the label does — a "23:50" has to become
    /// "yesterday" without waiting for the next hook signal.
    @State private var now = Date()

    /// One minute is the longest step that guarantees the label changes within a
    /// minute of the day rolling over.
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// The drag in progress: which row, and how far the handle has travelled.
    ///
    /// Only the id is kept, not the row's index. Rows can appear or leave while
    /// the pointer is down — a session ends, a project is seen for the first time
    /// — and an index remembered at mouse-down would then point at the wrong row.
    /// The index is looked up on every render instead.
    @State private var drag: ColumnDrag?

    private struct ColumnDrag: Equatable {
        let rowId: String
        var translation: CGFloat
    }

    /// The distance between two rows' baselines.
    private static let pitch = Layout.rowHeight + Layout.rowSpacing

    private var rendering: ColumnRendering {
        ColumnLayout.render(store.state, options: options)
    }

    var body: some View {
        let rendering = self.rendering

        return Group {
            if rendering.rows.isEmpty && rendering.hidden == nil {
                emptyState(filteredOut: rendering.filteredOut)
            } else {
                content(rendering)
            }
        }
        .padding(Layout.panelPadding)
        .frame(width: Layout.width(compact: compact))
        .onReceive(tick) { now = $0 }
    }

    // MARK: - Rows

    private func content(_ rendering: ColumnRendering) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Layout.rowSpacing) {
                ForEach(Array(rendering.rows.enumerated()), id: \.element.id) { index, row in
                    TrafficLightRow(
                        row: row,
                        compact: compact,
                        now: now,
                        flags: flags(for: row),
                        actions: actions,
                        drag: compact ? nil : dragState(for: row, at: index, in: rendering.rows)
                    )
                }

                if let hidden = rendering.hidden {
                    HiddenSummaryRow(
                        summary: hidden,
                        compact: compact,
                        onReveal: onRevealHidden
                    )
                }

                if rendering.filteredOut > 0 {
                    filterNote(count: rendering.filteredOut)
                }
            }
        }
        .scrollDisabled(rendering.rows.count <= AppConfig.maxVisibleRows)
    }

    // MARK: - Reordering

    /// Where the dragged row would land if released now.
    private func target(of drag: ColumnDrag, in rows: [ColumnRow]) -> (start: Int, end: Int)? {
        guard let start = rows.firstIndex(where: { $0.id == drag.rowId }) else { return nil }
        let steps = Int((drag.translation / Self.pitch).rounded())
        return (start, min(max(start + steps, 0), rows.count - 1))
    }

    /// What this row draws during a drag, and how it reports one of its own.
    ///
    /// The dragged row follows the pointer, clamped to the column. Every row
    /// between its origin and its destination steps one pitch aside, so the gap
    /// travels with the pointer and the drop lands where the eye expects.
    private func dragState(for row: ColumnRow, at index: Int, in rows: [ColumnRow]) -> RowDragState {
        var offset: CGFloat = 0
        var dragged = false
        if let drag, let (start, end) = target(of: drag, in: rows) {
            if drag.rowId == row.id {
                dragged = true
                let lowest = -CGFloat(start) * Self.pitch
                let highest = CGFloat(rows.count - 1 - start) * Self.pitch
                offset = min(max(drag.translation, lowest), highest)
            } else if start < end, index > start, index <= end {
                offset = -Self.pitch
            } else if start > end, index >= end, index < start {
                offset = Self.pitch
            }
        }
        return RowDragState(
            offset: offset,
            isDragged: dragged,
            onChanged: { translation in
                if drag == nil {
                    drag = ColumnDrag(rowId: row.id, translation: translation)
                } else if drag?.rowId == row.id {
                    drag?.translation = translation
                }
            },
            onEnded: {
                guard let current = drag, current.rowId == row.id else { return }
                drag = nil
                guard let (start, end) = target(of: current, in: rows), start != end else { return }
                actions.place(row, end)
            }
        )
    }

    private func flags(for row: ColumnRow) -> RowFlags {
        RowFlags(
            isHidden: options.hidden.contains(row.workspace.path),
            isMuted: mutedWorkspaces.contains(row.workspace.path),
            isCalm: calmWorkspaces.contains(row.workspace.path),
            notificationsEnabled: notificationsEnabled
        )
    }

    /// How many sessions the filter is keeping out.
    ///
    /// Without this row the filter would lie by omission: a column with two rows
    /// would look like it says "there are two sessions", when what it says is
    /// "two need attention".
    private func filterNote(count: Int) -> some View {
        HStack(spacing: 7) {
            if compact {
                Text("\(count)")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(StatusPalette.timeColor)
                    .frame(maxWidth: .infinity)
            } else {
                Text("and \(count) more with nothing new")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(StatusPalette.timeColor)
                    .lineLimit(1)
            }
        }
        .frame(height: Layout.rowHeight * 0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .tooltip("The “only what's waiting” filter is hiding \(count) sessions that are idle or working.")
    }

    /// No sessions seen yet: almost always means the hooks aren't installed.
    private func emptyState(filteredOut: Int) -> some View {
        HStack(spacing: 7) {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                .frame(width: Layout.dotSize, height: Layout.dotSize)

            if !compact {
                Text(filteredOut > 0 ? "none waiting" : "waiting for sessions")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .frame(height: Layout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .tooltip(
            filteredOut > 0
                ? "The “only what's waiting” filter is on and \(filteredOut) sessions are asking for nothing."
                : "No sessions detected.\nIf Claude Code is running, check that the hooks are installed (right-click menu)."
        )
    }
}

/// The row summarizing the projects that were set aside.
///
/// **It lights up** when a hidden session asks for attention. That is not an
/// aesthetic detail: without it, "hide" would become "forget", which is exactly
/// the harm this panel exists to prevent.
private struct HiddenSummaryRow: View {
    let summary: HiddenSummary
    let compact: Bool
    let onReveal: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            if summary.needsAttention {
                TrafficLightDot(status: summary.status)
            } else {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                    .frame(width: Layout.dotSize, height: Layout.dotSize)
            }

            if !compact {
                Text("\(summary.sessionCount) hidden")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(StatusPalette.timeColor)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Layout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.12 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onReveal)
        .tooltip(tooltip)
    }

    private var tooltip: String {
        var lines = ["Hidden projects: \(summary.workspaceNames.joined(separator: ", "))"]
        if summary.needsAttention {
            lines.append("One of them: \(StatusPalette.label(for: summary.status)).")
        }
        lines.append("Click to bring them all back into the column.")
        return lines.joined(separator: "\n")
    }
}
