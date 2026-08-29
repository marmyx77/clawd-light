import Foundation

/// Why a reverse tunnel could not bind its port, when the answer is on this Mac.
///
/// WHY THIS EXISTS
/// `ssh -R` with `ExitOnForwardFailure=yes` refuses to start when the port is
/// already bound on the far side, and says so: *"remote port forwarding failed
/// for listen port 31000"*. Read literally, that sentence points at the other
/// machine, and this app repeated it — *"the port could not be bound there"*.
///
/// Measured, on the day it mattered: the port was held by **this app's own
/// tunnel from a previous run**. Killing the panel with `pkill` — which is what
/// the build script itself prints as the way to restart it — leaves the `ssh`
/// child alive and reparented to launchd, still holding the forward. The new
/// instance then asks for the same port, is refused, and reports the failure
/// against a remote machine that has done nothing wrong. Two hours of "retrying
/// in 60 s", once a minute, with the cause sitting in the local process table.
///
/// So when the bind fails, the local process table is read, and if one of our
/// own forwards is holding that port the message says which pid and what to do
/// about it. Nothing is killed automatically: another instance of the panel is
/// a legitimate owner of that port, and a tool that silently kills processes it
/// believes are stale is a tool nobody should run.
public enum TunnelRefusal {

    /// One line of `ps -ax -o pid=,ppid=,command=`.
    public struct RunningProcess: Sendable, Equatable {
        public let pid: Int32
        public let parent: Int32
        public let command: String

        public init(pid: Int32, parent: Int32, command: String) {
            self.pid = pid
            self.parent = parent
            self.command = command
        }

        /// Orphans are reparented to pid 1, and an orphan is the case worth
        /// naming: it belongs to nobody and will never be cleaned up.
        public var isOrphan: Bool { parent == 1 }
    }

    /// `true` when ssh refused because the far end would not give up the port.
    public static func mentionsBindFailure(_ stderr: String) -> Bool {
        stderr.localizedCaseInsensitiveContains("remote port forwarding failed")
            || stderr.localizedCaseInsensitiveContains("port forwarding failed")
    }

    /// Reads `ps` output into processes. Malformed lines are skipped, never guessed.
    public static func parse(_ listing: String) -> [RunningProcess] {
        listing.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3,
                  let pid = Int32(fields[0]),
                  let parent = Int32(fields[1])
            else { return nil }
            let command = fields.dropFirst(2).joined(separator: " ")
            return RunningProcess(pid: pid, parent: parent, command: command)
        }
    }

    /// Our own forwards of `port`, whoever owns them.
    ///
    /// Matched on the forward specification rather than on the word `ssh`: the
    /// string `-R 127.0.0.1:31000:` is ours by construction, and matching the
    /// binary name would also catch an ssh the user is running by hand.
    public static func holders(of port: UInt16, among processes: [RunningProcess]) -> [RunningProcess] {
        let specification = "-R 127.0.0.1:\(port):"
        return processes.filter { $0.command.contains(specification) }
    }

    /// The sentence to show, or `nil` when this Mac has nothing to add.
    public static func diagnosis(port: UInt16, among processes: [RunningProcess]) -> String? {
        let ours = holders(of: port, among: processes)
        guard let held = ours.first(where: \.isOrphan) ?? ours.first else { return nil }

        if held.isOrphan {
            return "port \(port) is held by a tunnel this app left behind "
                + "(pid \(held.pid)) — `kill \(held.pid)` and it will reconnect"
        }
        return "port \(port) is held by another clawd-light (pid \(held.pid))"
    }
}
