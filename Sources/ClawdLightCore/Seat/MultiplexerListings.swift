import Foundation

/// A Unix socket as `lsof -nP -U -a -p <pid>` lists it.
///
/// `DEVICE` is the socket's own kernel address; `NAME` is either the path it is
/// bound to or `->0x…`, its peer's address. A client is paired with a server
/// when the client's peer is one of the server's own addresses — measured on a
/// zellij server and its client, and the pairing the plan first ruled out
/// because the wrong column had been read.
public struct UnixSocket: Sendable, Equatable {
    public let pid: Int32
    public let address: String
    public let peer: String?
    public let path: String?

    public init(pid: Int32, address: String, peer: String?, path: String?) {
        self.pid = pid
        self.address = address
        self.peer = peer
        self.path = path
    }
}

public enum LsofUnixSockets {
    /// Parses `lsof -nP -U -a -p …` output. The header line and anything that
    /// is not a Unix socket row are skipped; nothing here can fail loudly, and
    /// an empty result means "no pairing", never a crash.
    public static func parse(_ output: String) -> [UnixSocket] {
        output.split(separator: "\n").compactMap { line in
            let columns = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // COMMAND PID USER FD TYPE DEVICE SIZE/OFF [NODE] [NAME]: macOS prints
            // no NODE for a Unix socket, Linux does, so NAME is found by shape —
            // the first column after the size that is a path or a peer.
            guard columns.count >= 7, columns[4] == "unix", let pid = Int32(columns[1]),
                  columns[5].hasPrefix("0x")
            else { return nil }
            let name = columns.dropFirst(6).first { $0.hasPrefix("->") || $0.hasPrefix("/") } ?? ""
            let peer = name.hasPrefix("->") ? String(name.dropFirst(2)) : nil
            let path = name.hasPrefix("/") ? name : nil
            return UnixSocket(pid: pid, address: columns[5], peer: peer, path: path)
        }
    }

    /// Among `clients`, the pids connected to any of `server`'s sockets.
    public static func clientPids(of server: [UnixSocket], among clients: [UnixSocket]) -> [Int32] {
        let own = Set(server.map(\.address))
        var seen = Set<Int32>()
        return clients.compactMap { socket in
            guard let peer = socket.peer, own.contains(peer), seen.insert(socket.pid).inserted else { return nil }
            return socket.pid
        }
    }
}

/// What tmux says about its panes and clients, with the formats this app asks for.
public enum TmuxListing {
    public struct Pane: Sendable, Equatable {
        public let tty: String
        public let shellPid: Int32
        /// `session:window.pane`, the target `select-window`/`select-pane` take.
        public let target: String
        public var session: String { String(target.prefix { $0 != ":" }) }
        public var window: String { String(target.prefix { $0 != "." }) }
    }

    public struct Client: Sendable, Equatable {
        public let tty: String
        public let pid: Int32
        public let session: String
    }

    /// The format string for `tmux list-panes -a -F`.
    public static let paneFormat = "#{pane_tty}\t#{pane_pid}\t#{session_name}:#{window_index}.#{pane_index}"
    /// The format string for `tmux list-clients -F`.
    public static let clientFormat = "#{client_tty}\t#{client_pid}\t#{session_name}"

    public static func panes(_ output: String) -> [Pane] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, let tty = TTYName.normalized(fields[0]), let pid = Int32(fields[1]),
                  isTarget(fields[2])
            else { return nil }
            return Pane(tty: tty, shellPid: pid, target: fields[2])
        }
    }

    public static func clients(_ output: String) -> [Client] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, let tty = TTYName.normalized(fields[0]), let pid = Int32(fields[1]),
                  isSessionName(fields[2])
            else { return nil }
            return Client(tty: tty, pid: pid, session: fields[2])
        }
    }

    /// Targets and names go back to tmux as arguments: validated, since they
    /// come from tmux's own output and an argument list is not a shell, but a
    /// name that starts with a dash would still be read as an option.
    static func isTarget(_ text: String) -> Bool {
        text.range(of: "^[A-Za-z0-9._-]{1,128}:[0-9]{1,6}\\.[0-9]{1,6}$", options: .regularExpression) != nil
            && !text.hasPrefix("-")
    }

    static func isSessionName(_ text: String) -> Bool {
        text.range(of: "^[A-Za-z0-9._-]{1,128}$", options: .regularExpression) != nil && !text.hasPrefix("-")
    }
}
