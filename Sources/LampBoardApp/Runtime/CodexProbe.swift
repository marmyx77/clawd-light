import Foundation

/// The Codex scanner, off the thread that draws and never running twice at once.
///
/// An `actor` and not a queue, because both properties are wanted and an actor
/// gives them together. The scanner is a class with caches of its own — the
/// first record of each rollout, the size each was last read at — and inside an
/// actor those are reached from one task at a time, by construction rather than
/// by discipline.
///
/// The reason it exists is a measurement. The probe spawns `lsof` over every
/// live `codex` pid, and the sweep it sat inside runs on the main actor every
/// five seconds: instrumented on this machine, with eighteen `codex` processes,
/// it was 80 milliseconds of a 150-millisecond pass. That is five frames the
/// panel could not draw, four times a minute, on a window whose whole job is to
/// be glanced at and dragged out of the way.
///
/// Serialising also answers the question the audit asked next: a probe that runs
/// long can no longer have a second one started on top of it.
actor CodexProbe {
    private let scanner = CodexProcessScanner()

    func scan() -> CodexScanResult {
        scanner.scan()
    }
}
