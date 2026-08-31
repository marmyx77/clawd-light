import Foundation

/// Where one realignment pass spent its time.
///
/// Added because an audit said the sweep was too slow for the thread that draws
/// and neither of us could settle it by reading. The first measurement said 244
/// milliseconds, every five seconds, in the steady state and not only at the
/// cold start — which is fifteen frames the panel cannot draw, on a window whose
/// whole job is to be glanced at and dragged.
///
/// A total alone would not have said what to move. The four phases here are the
/// four things that touch the disk or another process, so the number names the
/// work rather than the symptom.
struct SweepCost {
    var live: TimeInterval = 0
    var windows: TimeInterval = 0
    var desktop: TimeInterval = 0
    var codex: TimeInterval = 0

    /// Runs `body`, charging what it took to `phase`.
    @discardableResult
    mutating func spending<T>(
        _ phase: WritableKeyPath<SweepCost, TimeInterval>, _ body: () -> T
    ) -> T {
        let started = Date()
        let value = body()
        self[keyPath: phase] += Date().timeIntervalSince(started)
        return value
    }

    /// The line that goes in the log: the total first, then whatever is worth
    /// naming inside it.
    func describing(_ total: TimeInterval) -> String {
        let phases: [(String, TimeInterval)] = [
            ("sessions", live), ("windows", windows), ("desktop", desktop), ("codex", codex),
        ]
        let named = phases
            .filter { $0.1 * 1000 >= 1 }
            .map { String(format: "%@ %.0f", $0.0, $0.1 * 1000) }
            .joined(separator: ", ")
        let rest = total - phases.reduce(0) { $0 + $1.1 }
        return String(format: "%.0f ms", total * 1000)
            + (named.isEmpty ? "" : " (\(named)")
            + (named.isEmpty ? "" : String(format: ", the rest %.0f)", rest * 1000))
    }
}

/// What the sweeps have cost so far, kept across passes.
///
/// Separate from `SweepCost` because one is a measurement of a single pass and
/// this is the memory of all of them, and separate from `StateStore` because
/// that file is at the ceiling the project sets itself and bookkeeping about the
/// store is not the store.
enum SweepLog {
    private static var worst: TimeInterval = 0
    private static var count = 0
    private static var total: TimeInterval = 0

    /// Passes slower than this are named individually. Roughly three frames:
    /// below it nobody could see the pause, above it somebody could.
    private static let notable: TimeInterval = 0.05

    static func record(from started: Date, _ cost: SweepCost) {
        guard Diagnostics.isEnabled else { return }
        let elapsed = Date().timeIntervalSince(started)
        count += 1
        total += elapsed
        if elapsed > worst {
            worst = elapsed
            Diagnostics.log("sweep: \(cost.describing(elapsed)), the longest so far")
        } else if elapsed > notable {
            Diagnostics.log("sweep: \(cost.describing(elapsed))")
        }
        // A periodic average, because a worst case alone cannot say whether a
        // pause is the cold start or the shape of every pass.
        if count % 60 == 0 {
            Diagnostics.log(String(
                format: "sweep: %d passes, %.0f ms on average, %.0f ms at worst",
                count, total / Double(count) * 1000, worst * 1000
            ))
        }
    }
}
