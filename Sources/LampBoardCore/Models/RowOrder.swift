import Foundation

/// The order of the column, as the user arranged it.
///
/// The column does not sort itself (D23). Every project has a place — the one it
/// got when first seen, or the one it was dragged to — and keeps it whatever its
/// state does. That makes one list the source for two things that used to be
/// separate: where a row is drawn, and which key opens it. Position `i` is slot
/// `i + 1`, for the first `AppConfig.maxSlots` positions.
///
/// It lives in Core because deciding where a row goes is a decision, and
/// decisions in the shell are decisions no test can see.
public enum RowOrder {

    /// The order with every path in `paths` given a place.
    ///
    /// Known paths keep theirs. Unknown ones are appended, by name, so that a
    /// project seen for the first time lands at the bottom and stays there:
    /// appending is the one arrangement that moves nothing the user has already
    /// learned. Deterministic on purpose — it runs on every state change and has
    /// to answer the same for the same input, or the column would drift.
    public static func absorbing(_ paths: some Sequence<String>, into order: [String]) -> [String] {
        let known = Set(order)
        let fresh = Set(paths).subtracting(known).sorted { lhs, rhs in
            let byName = Workspace(path: lhs).name.localizedStandardCompare(Workspace(path: rhs).name)
            return byName == .orderedSame ? lhs < rhs : byName == .orderedAscending
        }
        return fresh.isEmpty ? order : order + fresh
    }

    /// The order with `path` at position `index` among `visible`, expressed in
    /// the full list.
    ///
    /// A drag happens in the column, and the column shows a subset: hidden
    /// projects, filtered rows and projects with no live session are absent. So
    /// the target is a position among what is visible, and it is translated into
    /// the full order by anchoring on a visible neighbour — `path` goes right
    /// before the row that will follow it, or right after the last visible row
    /// when dropped at the bottom. What is not shown keeps its place relative to
    /// its visible neighbours. `index` is clamped; `visible` may repeat a path
    /// (grouping off draws one row per session) and is deduplicated.
    public static func placing(
        _ path: String, at index: Int, among visible: [String], in order: [String]
    ) -> [String] {
        var rest = order.filter { $0 != path }
        let others = uniqued(visible).filter { $0 != path }
        let target = min(max(index, 0), others.count)

        let insertion: Int
        if target < others.count, let anchor = rest.firstIndex(of: others[target]) {
            insertion = anchor
        } else if target >= others.count, let last = others.last, let anchor = rest.firstIndex(of: last) {
            insertion = anchor + 1
        } else {
            insertion = rest.count
        }
        rest.insert(path, at: insertion)
        return rest
    }

    /// Moves `path` one place up (`-1`) or down (`+1`) among `visible`.
    ///
    /// Past either edge the list comes back unchanged rather than clamped, so a
    /// menu entry at the edge does nothing instead of pretending.
    public static func moving(
        _ path: String, by offset: Int, among visible: [String], in order: [String]
    ) -> [String] {
        let shown = uniqued(visible)
        guard let current = shown.firstIndex(of: path) else { return order }
        let target = current + offset
        guard shown.indices.contains(target) else { return order }
        return placing(path, at: target, among: shown, in: order)
    }

    /// The slot a project holds: its 1-based position, when within `limit`.
    public static func slot(of path: String, in order: [String], limit: Int) -> Int? {
        guard let index = order.firstIndex(of: path), index < limit else { return nil }
        return index + 1
    }

    /// Where a project sorts: its position, or after every known one.
    public static func position(of path: String, in order: [String]) -> Int {
        order.firstIndex(of: path) ?? Int.max
    }

    /// The list with duplicates dropped, first occurrence kept.
    ///
    /// Applied on the way in from storage: nothing downstream should have to
    /// wonder whether a project holds two places.
    public static func normalized(_ order: [String]) -> [String] {
        uniqued(order)
    }

    private static func uniqued(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }
}
