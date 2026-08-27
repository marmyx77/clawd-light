import Foundation

/// One process on the way up from a session to whatever hosts it.
///
/// Read by the shell (`ProcessTree`), classified here: what a chain means is a
/// decision, and decisions in the shell are decisions no test can see.
public struct ProcessAncestor: Sendable, Equatable {
    public let pid: Int32
    public let ppid: Int32

    /// Absolute path of the executable, as the kernel reports it.
    public let executablePath: String

    /// The process's arguments, when the reader could get them; the zellij
    /// server names its session there. Empty otherwise.
    public let arguments: [String]

    /// The controlling terminal as a device path (`/dev/ttys003`), or `nil` for
    /// a process with none — a GUI application, a detached server.
    public let tty: String?

    public init(pid: Int32, ppid: Int32, executablePath: String, arguments: [String] = [], tty: String?) {
        self.pid = pid
        self.ppid = ppid
        self.executablePath = executablePath
        self.arguments = arguments
        self.tty = tty.flatMap(TTYName.normalized)
    }

    /// The last path component of the executable.
    public var executableName: String {
        (executablePath as NSString).lastPathComponent
    }

    /// The `.app` bundle the executable lives in, if any: `/Applications/Terminal.app`.
    public var bundlePath: String? {
        let components = executablePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return components[...index].joined(separator: "/")
    }

    /// The bundle's name without the extension: `Terminal`, `Code Helper (Plugin)`.
    public var bundleName: String? {
        bundlePath.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
    }
}

/// tty names come in two shapes — `ttys003` from the kernel, `/dev/ttys003` from
/// AppleScript dictionaries and tmux — and are compared in one.
///
/// The normalised form is also the **only** form that may cross into a script or
/// an argument list: anything that does not match the pattern is refused, not
/// escaped. A tty is the one string from the process table that reaches an
/// AppleScript source, and a pattern is a smaller thing to trust than an escaper.
public enum TTYName {
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmed
        let name = trimmed.hasPrefix("/dev/") ? String(trimmed.dropFirst(5)) : trimmed
        guard name.range(of: "^ttys[0-9]{1,4}$", options: .regularExpression) != nil else { return nil }
        return "/dev/" + name
    }
}
