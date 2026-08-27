import Foundation

/// One row drawn in the column.
///
/// It does not map one-to-one onto a session: when grouping is on, a row
/// represents a **project**, and all of its sessions live inside it.
public struct ColumnRow: Sendable, Equatable, Identifiable {
    /// Stable across redraws: the project path when grouping, the session id
    /// otherwise. If it moved, SwiftUI would rebuild the rows from scratch on
    /// every update and the panel would flicker.
    public let id: String

    public let workspace: Workspace

    /// The row's sessions, most urgent first.
    public let sessions: [SessionState]

    /// The row's keyboard slot: its position in the user's order, 1-based, for
    /// the first `AppConfig.maxSlots` positions; `nil` below them.
    ///
    /// A slot is what makes a row **addressable**: bind a key to slot 3 and it
    /// keeps meaning the same project tomorrow. The column does not reorder
    /// itself (D23), so the position *is* the address — the same list decides
    /// where the row is drawn and what the key opens, and the two cannot disagree.
    public let slot: Int?

    public init(id: String, workspace: Workspace, sessions: [SessionState], slot: Int? = nil) {
        self.id = id
        self.workspace = workspace
        self.sessions = sessions
        self.slot = slot
    }

    /// The state the dot shows: the most urgent one in the group.
    public var status: SessionStatus { primary.status }

    /// The session a click opens.
    ///
    /// The most urgent one, not the most recent: if one session in a project is
    /// waiting for a permission and another has finished, the click has to take
    /// you where something is blocked.
    public var primary: SessionState {
        sessions.first ?? SessionState(
            id: id, status: .idle, workspace: workspace, updatedAt: .distantPast,
            statusSince: .distantPast
        )
    }

    /// How many sessions it contains.
    public var count: Int { sessions.count }

    /// Sum of the active subagents in the row.
    public var activeSubagents: Int { sessions.reduce(0) { $0 + $1.activeSubagents } }

    /// The moment since which the row has been in its current state.
    public var statusSince: Date { primary.statusSince }

    /// The most recent activity seen in the row.
    public var updatedAt: Date { sessions.map(\.updatedAt).max() ?? primary.updatedAt }

    /// The sessions a click must clear.
    ///
    /// Only the ones that were **in the most urgent state**, not all of them.
    /// Without this limit, opening a project where one session is waiting for a
    /// permission and another has an answer ready would mark both as seen, and
    /// the unread answer would vanish without ever being read: grouping would
    /// become a loss of information instead of a reduction in noise.
    public var sessionIdsToClear: [String] {
        let urgent = status
        return sessions.filter { $0.status == urgent }.map(\.id)
    }
}

/// How the rows should be laid out.
public struct ColumnOptions: Sendable, Equatable {
    public let grouped: Bool
    public let onlyWaiting: Bool

    /// Project paths in the user's order. Position `i` is drawn `i`-th and is
    /// slot `i + 1`.
    ///
    /// An ordered list and not a set, because the order is the feature: it is
    /// where the rows are and what a bound key addresses. A `Set` would have made
    /// both depend on hashing, which is the definition of a place you cannot rely on.
    public let order: [String]

    public let hidden: Set<String>

    public init(
        grouped: Bool = true,
        onlyWaiting: Bool = false,
        order: [String] = [],
        hidden: Set<String> = []
    ) {
        self.grouped = grouped
        self.onlyWaiting = onlyWaiting
        self.order = order
        self.hidden = hidden
    }

    public static let plain = ColumnOptions(grouped: false)

    /// The slot a project holds, 1-based, or `nil`.
    func slot(for path: String) -> Int? {
        RowOrder.slot(of: path, in: order, limit: AppConfig.maxSlots)
    }

    /// Where a project sorts; unknown ones after every known one.
    func position(for path: String) -> Int {
        RowOrder.position(of: path, in: order)
    }
}

/// What stays out of the column, summarized in a single row.
public struct HiddenSummary: Sendable, Equatable {
    /// How many sessions were set aside.
    public let sessionCount: Int

    /// The most urgent state among the hidden ones.
    public let status: SessionStatus

    /// The projects involved, by name, in order.
    public let workspaceNames: [String]

    /// `true` when something in there is asking for attention.
    ///
    /// Not a nicety: it is what stops "hide" from causing the very harm the panel
    /// exists to prevent. Without this row, hiding a project would mean no longer
    /// knowing when it needs you.
    public var needsAttention: Bool { status.clearsOnFocus }
}

/// The result of the computation: what is visible and what was set aside.
public struct ColumnRendering: Sendable, Equatable {
    public let rows: [ColumnRow]
    public let hidden: HiddenSummary?

    /// How many sessions the "only what's waiting" filter excluded.
    /// Worth stating, rather than letting you believe there are no others.
    public let filteredOut: Int

    public static let empty = ColumnRendering(rows: [], hidden: nil, filteredOut: 0)

    /// The row a bound key should open, or `nil` when that slot is empty.
    ///
    /// Empty is a normal outcome, not an error: a project can hold a place in the
    /// order and have no live session right now. The caller has to say "slot 3 is
    /// empty" rather than open something else — opening the neighbor would be the
    /// worst possible behavior for a key you press without looking.
    ///
    /// With grouping off several rows share a slot; the most urgent wins, which
    /// is what `sorted` already put first and what a click on the group does.
    public func row(inSlot slot: Int) -> ColumnRow? {
        rows.first { $0.slot == slot }
    }

    /// The slots that currently have a row, in order, one entry per slot.
    ///
    /// Deduplicated on purpose: with grouping off a project has several rows and
    /// they all carry its slot, but the listing has to answer "what does key 3
    /// open", which is one thing.
    public var occupiedSlots: [(slot: Int, row: ColumnRow)] {
        var seen = Set<Int>()
        return rows.compactMap { row in
            guard let slot = row.slot, seen.insert(slot).inserted else { return nil }
            return (slot: slot, row: row)
        }
    }
}

/// Turns the state into the list of rows to draw.
///
/// A pure function: same state and same options, same rows. All the logic of the
/// "scale" phase lives here, where it can be verified without drawing anything.
public enum ColumnLayout {

    public static func render(
        _ state: TrafficLightState,
        options: ColumnOptions
    ) -> ColumnRendering {
        let all = state.ordered
        guard !all.isEmpty else { return .empty }

        let visible = all.filter { !options.hidden.contains($0.workspace.path) }
        let putAside = all.filter { options.hidden.contains($0.workspace.path) }

        let grouped = options.grouped
            ? group(visible, options: options)
            : ungrouped(visible, options: options)

        let filtered = options.onlyWaiting
            ? grouped.filter { $0.status.clearsOnFocus }
            : grouped

        let removed = grouped.filter { row in !filtered.contains { $0.id == row.id } }

        return ColumnRendering(
            rows: sorted(filtered, options: options),
            hidden: summary(of: putAside),
            filteredOut: removed.reduce(0) { $0 + $1.count }
        )
    }

    // MARK: - Building the rows

    private static func group(_ sessions: [SessionState], options: ColumnOptions) -> [ColumnRow] {
        var byWorkspace: [String: [SessionState]] = [:]
        for session in sessions {
            byWorkspace[session.workspace.path, default: []].append(session)
        }

        return byWorkspace.map { path, members in
            // `state.ordered` arrives already sorted by urgency, and grouping
            // preserves that order: the first one is the most urgent.
            ColumnRow(
                id: path,
                workspace: members[0].workspace,
                sessions: members,
                slot: options.slot(for: path)
            )
        }
    }

    /// Without grouping, several rows of the same project share its slot.
    ///
    /// That is deliberate: the slot addresses a **project**, and the key must
    /// take you to the same place whether or not grouping is on. Addressing
    /// resolves the ambiguity the same way a click does — the most urgent row wins.
    private static func ungrouped(_ sessions: [SessionState], options: ColumnOptions) -> [ColumnRow] {
        sessions.map { session in
            ColumnRow(
                id: session.id,
                workspace: session.workspace,
                sessions: [session],
                slot: options.slot(for: session.workspace.path)
            )
        }
    }

    // MARK: - Ordering

    /// The user's order, and nothing else moves a row.
    ///
    /// Urgency stays out of this on purpose (D23). A column that re-sorts itself
    /// has to be re-read every time it changes, a green that jumps to the top
    /// pushes every other row down by one, and a row that moves under the pointer
    /// is how the wrong session gets opened. A row that needs you still lights up
    /// — where it always is.
    ///
    /// A project not yet in the order — possible for one render, before the store
    /// gives it a place — sorts after every known one, by name. With grouping
    /// off a project has several rows at the same position; among them the most
    /// urgent comes first, so the click and the key agree about which one they
    /// mean, then the longest wait, then the id, so nothing jitters between updates.
    private static func sorted(_ rows: [ColumnRow], options: ColumnOptions) -> [ColumnRow] {
        rows.sorted { lhs, rhs in
            let left = options.position(for: lhs.workspace.path)
            let right = options.position(for: rhs.workspace.path)
            if left != right { return left < right }
            if lhs.workspace.path != rhs.workspace.path {
                let byName = lhs.workspace.name.localizedStandardCompare(rhs.workspace.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                return lhs.workspace.path < rhs.workspace.path
            }
            if lhs.status.urgencyRank != rhs.status.urgencyRank {
                return lhs.status.urgencyRank < rhs.status.urgencyRank
            }
            if lhs.statusSince != rhs.statusSince { return lhs.statusSince < rhs.statusSince }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Summary of what's hidden

    private static func summary(of sessions: [SessionState]) -> HiddenSummary? {
        guard !sessions.isEmpty else { return nil }

        let mostUrgent = sessions
            .map(\.status)
            .min { $0.urgencyRank < $1.urgencyRank } ?? .idle

        let names = Set(sessions.map(\.workspace.name)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }

        return HiddenSummary(
            sessionCount: sessions.count,
            status: mostUrgent,
            workspaceNames: names
        )
    }
}
