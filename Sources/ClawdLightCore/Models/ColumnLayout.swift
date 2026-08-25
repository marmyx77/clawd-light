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

    /// The row's keyboard slot, 1-based, or `nil` when it has none.
    ///
    /// A slot is what makes a row **addressable**: bind a key to slot 3 and it
    /// keeps meaning the same project tomorrow. That is the whole difficulty —
    /// the column reorders by urgency continuously, so a key bound to "the third
    /// row" would point somewhere new every minute, and a shortcut that acts on
    /// the wrong session is worse than no shortcut.
    ///
    /// Slots therefore come from pinning, which the user chooses and which does
    /// not move on its own. Pinned means two things at once, coherently: keep it
    /// on top, and give it a key.
    public let slot: Int?

    /// `true` when the project is pinned to the top. Equivalent to having a slot.
    public var isPinned: Bool { slot != nil }

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

    /// Pinned project paths, **in slot order**. Position `i` is slot `i + 1`.
    ///
    /// An ordered list and not a set, because the order is the feature: it is
    /// what a bound key addresses. A `Set` would have made slot numbers depend
    /// on hashing, which is the definition of an address you cannot rely on.
    public let pinned: [String]

    public let hidden: Set<String>

    public init(
        grouped: Bool = true,
        onlyWaiting: Bool = false,
        pinned: [String] = [],
        hidden: Set<String> = []
    ) {
        self.grouped = grouped
        self.onlyWaiting = onlyWaiting
        self.pinned = pinned
        self.hidden = hidden
    }

    public static let plain = ColumnOptions(grouped: false)

    /// The slot a project holds, 1-based, or `nil`.
    func slot(for path: String) -> Int? {
        SlotAssignment.slot(of: path, in: pinned)
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
    /// Empty is a normal outcome, not an error: a project can be pinned and have
    /// no live session right now. The caller has to say "slot 3 is empty" rather
    /// than open something else — opening the neighbor would be the worst
    /// possible behavior for a key you press without looking.
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

        // The filter leaves pinned projects alone: pinning one means wanting to
        // see it always, and a filter that hides it drains pinning of its meaning.
        let filtered = options.onlyWaiting
            ? grouped.filter { $0.isPinned || $0.status.clearsOnFocus }
            : grouped

        let removed = grouped.filter { row in !filtered.contains { $0.id == row.id } }

        return ColumnRendering(
            rows: sorted(filtered),
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

    /// Pinned first **in slot order**, then urgency, then the longest wait.
    ///
    /// Slot order, and not urgency, among the pinned rows: a key bound to slot 3
    /// has to find the same project there tomorrow. Sorting them by urgency would
    /// make the top of the column shuffle exactly like the rest, and an address
    /// that moves is not an address.
    ///
    /// The price is visible and accepted: a pinned project that starts asking for
    /// attention does **not** rise above the other pinned ones. It still lights
    /// up, and it is still above everything unpinned.
    ///
    /// The name stays as the final tie-break: without it, two equivalent rows
    /// could swap places between updates, and in peripheral vision movement is
    /// the worst defect there is.
    private static func sorted(_ rows: [ColumnRow]) -> [ColumnRow] {
        rows.sorted { lhs, rhs in
            switch (lhs.slot, rhs.slot) {
            case let (left?, right?) where left != right: return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            // Equal slots — which happens with grouping off, where a project has
            // several rows — and both unpinned fall through to the usual order.
            default: break
            }
            if lhs.status.urgencyRank != rhs.status.urgencyRank {
                return lhs.status.urgencyRank < rhs.status.urgencyRank
            }
            if lhs.statusSince != rhs.statusSince { return lhs.statusSince < rhs.statusSince }
            if lhs.workspace.name != rhs.workspace.name {
                return lhs.workspace.name.localizedStandardCompare(rhs.workspace.name)
                    == .orderedAscending
            }
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
