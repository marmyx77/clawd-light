import LampBoardCore
import Darwin
import Foundation

/// Reads a process's ancestry from the kernel.
///
/// `sysctl(KERN_PROC_PID)` gives the parent, the controlling terminal and the
/// start time; `proc_pidpath` the executable; `KERN_PROCARGS2` the arguments,
/// which only the zellij server needs (its session name is there). No `ps`, no
/// shell: one syscall per ancestor, and nothing that could be parsed wrongly.
enum ProcessTree {
    struct Info {
        let ppid: pid_t
        let tty: String?
        let startedAt: Date
    }

    /// At most this many hops: a real chain is four or five long, and a walk that
    /// does not end is a cycle the kernel would never produce.
    static let maxDepth = 12

    static func info(of pid: pid_t) -> Info? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, UInt32(mib.count), &proc, &size, nil, 0) == 0, size > 0, proc.kp_proc.p_pid == pid else {
            return nil
        }
        var tty: String?
        let device = proc.kp_eproc.e_tdev
        if device != dev_t(bitPattern: UInt32.max), let name = devname(device, S_IFCHR) {
            tty = String(cString: name)
        }
        let start = proc.kp_proc.p_starttime
        return Info(
            ppid: proc.kp_eproc.e_ppid,
            tty: tty,
            startedAt: Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
        )
    }

    static func path(of pid: pid_t) -> String {
        // PROC_PIDPATHINFO_MAXSIZE is a macro Swift does not see: 4 × MAXPATHLEN.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }

    /// The process's arguments, `argv[0]` included; empty when the kernel refuses
    /// (another user's process) or the layout is not what `KERN_PROCARGS2` promises.
    static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return [] }

        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var cursor = MemoryLayout<Int32>.size
        // The executable path, then padding NULs, then argc NUL-terminated strings.
        while cursor < size, buffer[cursor] != 0 { cursor += 1 }
        while cursor < size, buffer[cursor] == 0 { cursor += 1 }

        var arguments: [String] = []
        while arguments.count < argc, cursor < size {
            let start = cursor
            while cursor < size, buffer[cursor] != 0 { cursor += 1 }
            arguments.append(String(decoding: buffer[start..<cursor], as: UTF8.self))
            cursor += 1
        }
        return arguments
    }

    /// Every process whose command name is `name`, as the kernel abbreviates it
    /// (`p_comm`, sixteen characters). The zellij clients, for a server.
    static func pids(named name: String) -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride + 16
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: count)
        var actual = count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &buffer, &actual, nil, 0) == 0 else { return [] }
        let found = actual / MemoryLayout<kinfo_proc>.stride
        return buffer.prefix(found).compactMap { proc in
            let text = withUnsafeBytes(of: proc.kp_proc.p_comm) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            return text == name ? proc.kp_proc.p_pid : nil
        }
    }

    /// The chain from `pid` upwards, `pid` first, stopping at launchd or at a
    /// process the kernel will not describe.
    static func ancestry(of pid: pid_t) -> [ProcessAncestor] {
        var chain: [ProcessAncestor] = []
        var current = pid
        while current > 1, chain.count < maxDepth, let info = info(of: current) {
            let path = path(of: current)
            let wantsArguments = (path as NSString).lastPathComponent == "zellij"
            chain.append(ProcessAncestor(
                pid: current, ppid: info.ppid, executablePath: path,
                arguments: wantsArguments ? arguments(of: current) : [],
                tty: info.tty
            ))
            current = info.ppid
        }
        return chain
    }
}
