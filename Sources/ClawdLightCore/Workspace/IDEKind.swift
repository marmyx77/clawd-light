import Foundation

/// An editor that can host a Claude Code session.
///
/// Needed because the name in the lock file is `vscode.env.appName`, and VS Code
/// forks write their own into it: a Cursor window with Claude Code active produces
/// a lock identical to VS Code's except for that field. Discarding it was not a
/// choice, it was a side effect.
///
/// The table is **deliberately short**. It only lists the editors whose triple
/// (declared name, bundle, process name) is known and whose window title format
/// matches VS Code's. Adding an editor on a hunch, one that can't be tested,
/// doesn't widen coverage: it creates a row you can see and a click that doesn't
/// work, which is worse than no row at all.
public struct IDEKind: Sendable, Equatable, Hashable {

    /// How the editor identifies itself in the lock (`ideName`).
    public let declaredName: String

    /// Bundle identifier, used to activate the app.
    public let bundleIdentifier: String

    /// Process name, which is what System Events uses to find its windows.
    public let processName: String

    public init(declaredName: String, bundleIdentifier: String, processName: String) {
        self.declaredName = declaredName
        self.bundleIdentifier = bundleIdentifier
        self.processName = processName
    }

    public static let visualStudioCode = IDEKind(
        declaredName: "Visual Studio Code",
        bundleIdentifier: "com.microsoft.VSCode",
        processName: "Code"
    )

    /// Cursor is a VS Code fork: same lock format, same title format
    /// (`file — folder — profile`), so window recognition works unchanged.
    /// Only the three names differ.
    public static let cursor = IDEKind(
        declaredName: "Cursor",
        bundleIdentifier: "com.todesktop.230313mzl4w4u92",
        processName: "Cursor"
    )

    public static let all: [IDEKind] = [.visualStudioCode, .cursor]

    /// The editor identifying itself by that name, if we know it.
    ///
    /// The comparison is by containment rather than equality: VS Code writes
    /// "Visual Studio Code" in the stable build and "Visual Studio Code - Insiders"
    /// in the beta, and the second has to be recognized as the first.
    public static func matching(declaredName: String) -> IDEKind? {
        let name = declaredName.trimmed
        guard !name.isEmpty else { return nil }
        return all.first { name.localizedCaseInsensitiveContains($0.declaredName) }
    }
}
