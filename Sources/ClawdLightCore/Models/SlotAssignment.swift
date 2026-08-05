import Foundation

/// Which project a keyboard slot addresses.
///
/// A slot is an **address**: bind a key to slot 3 and it has to still mean the
/// same project tomorrow. That is the whole difficulty of the feature, because
/// the column itself reorders by urgency continuously — a key bound to "the third
/// row" would point somewhere new every minute, and a shortcut that acts on the
/// wrong session is worse than no shortcut.
///
/// So the order is not derived from anything the app observes. It is a list the
/// user arranges, and these are the only two operations that change it.
public enum SlotAssignment {

    /// Adds a project at the first free slot, or removes it.
    ///
    /// Adding appends: projects already bound to a key keep the key they had.
    /// Removing **compacts** — everything below shifts up one slot.
    ///
    /// Compacting re-addresses the rows below, which for an address is a real
    /// cost. It is accepted because it follows an explicit action, unlike the
    /// reordering this design exists to avoid, which used to happen on its own
    /// every time a session changed state. `moving` is there for anyone who wants
    /// a different arrangement without unbinding.
    ///
    /// - Parameter limit: how many slots exist. Adding beyond it is ignored
    ///   rather than silently dropping the oldest: quietly unbinding a key the
    ///   user is still pressing is the kind of surprise this type exists to avoid.
    public static func toggling(_ path: String, in slots: [String], limit: Int) -> [String] {
        guard !slots.contains(path) else {
            return slots.filter { $0 != path }
        }
        guard slots.count < limit else { return slots }
        return slots + [path]
    }

    /// Moves a project one place towards slot 1 (`-1`) or away from it (`+1`).
    ///
    /// An out-of-range move returns the list unchanged rather than clamping, so a
    /// menu entry at either edge simply does nothing instead of pretending.
    public static func moving(_ path: String, by offset: Int, in slots: [String]) -> [String] {
        guard let from = slots.firstIndex(of: path) else { return slots }
        let to = from + offset
        guard slots.indices.contains(to) else { return slots }
        var moved = slots
        moved.swapAt(from, to)
        return moved
    }

    /// The list with duplicates dropped and capped to `limit`.
    ///
    /// Applied on the way in from storage: nothing downstream should have to
    /// wonder whether a project holds two slots.
    public static func normalized(_ slots: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        return Array(slots.filter { seen.insert($0).inserted }.prefix(limit))
    }

    /// The slot a project holds, 1-based, or `nil`.
    public static func slot(of path: String, in slots: [String]) -> Int? {
        slots.firstIndex(of: path).map { $0 + 1 }
    }
}
