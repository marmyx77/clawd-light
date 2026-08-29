import ClawdLightCore
import Foundation

/// The names a Remote-SSH window may carry for a configured host.
///
/// VS Code labels such a window `[SSH: x]`, where `x` is whatever the user typed
/// to connect — the alias from `~/.ssh/config` one day, the address the next.
/// The panel knows the host by one name only. So the click asks for every name
/// the host answers to: the configured one, the `HostName` ssh resolves the alias
/// to, and the addresses either of them resolves to. Read at click time, not
/// cached: a VPN address can change between two clicks and a lookup is cheap.
enum RemoteHostAddresses {

    static func labels(for host: String) -> [String] {
        var labels = [host]
        // `user@box` is how ssh is told who to be; the window shows only the box.
        let bare = host.split(separator: "@").last.map(String.init) ?? host
        if bare != host { labels.append(bare) }
        if let configured = sshHostName(for: bare), !labels.contains(configured) {
            labels.append(configured)
            labels += resolve(configured)
        }
        labels += resolve(bare)

        var seen = Set<String>()
        return labels.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// What `ssh -G` says the alias stands for, or `nil` when it is not an alias.
    ///
    /// `-G` prints the effective configuration without connecting, so this costs
    /// a process and no network. The name has passed `RemoteHostList.isUsable`;
    /// it cannot be read as an option.
    static func sshHostName(for host: String) -> String? {
        let text: String
        do {
            // No network, but `ssh -G` still reads every included config file,
            // and one of those can sit on a mount that has gone away.
            text = try Command.run(
                "/usr/bin/ssh", ["-G", host],
                deadline: AppConfig.focusProbeTimeout,
                capturingStandardError: false
            ).output
        } catch {
            return nil
        }
        for line in text.split(separator: "\n") where line.hasPrefix("hostname ") {
            let value = line.dropFirst("hostname ".count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty || value.caseInsensitiveCompare(host) == .orderedSame ? nil : value
        }
        return nil
    }

    /// The numeric addresses `name` resolves to, in the order the resolver gives them.
    static func resolve(_ name: String) -> [String] {
        var hints = addrinfo()
        hints.ai_socktype = Int32(SOCK_STREAM)
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(name, nil, &hints, &list) == 0, let first = list else { return [] }
        defer { freeaddrinfo(first) }

        var found: [String] = []
        var node: UnsafeMutablePointer<addrinfo>? = first
        while let current = node {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                current.pointee.ai_addr, current.pointee.ai_addrlen,
                &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST
            ) == 0 {
                found.append(String(cString: buffer))
            }
            node = current.pointee.ai_next
        }
        return found
    }
}
