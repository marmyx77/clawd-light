import Foundation

/// A path as the filesystem itself spells it.
///
/// Two programs can name the same folder differently and both be right. The
/// default APFS volume is case-insensitive and case-preserving: `cd
/// ~/development/turing` succeeds and leaves `$PWD` spelled the way it was
/// typed, which is the spelling a shell hands to its terminal, while everything
/// that reads the folder from the kernel — `lsof`, a process's working
/// directory — gets the capital the folder was created with. Compared as
/// strings the two are different folders. They are one folder.
///
/// Measured, not supposed: Ghostty listed a live tab as
/// `/Users/…/development/turing` while the session running in it reported
/// `/Users/…/Development/turing`, and the click fell through to merely
/// activating the application instead of raising the tab.
///
/// `realpath(3)` answers by walking the filesystem, so it settles the spelling
/// **and** the links on the way — `/var` to `/private/var` included, which
/// Foundation's `resolvingSymlinksInPath` deliberately leaves alone. That
/// second half is the same trap this project already fell into once, one level
/// down, when the Codex scanner matched nothing and said so quietly.
///
/// A path naming nothing comes back normalised and otherwise untouched, which
/// is what makes this safe to apply anywhere: nothing is invented, and a
/// fixture that names no real folder is compared exactly as it was before.
public enum CanonicalPath {

    /// The path the filesystem would print for this one.
    public static func of(_ path: String) -> String {
        let normalized = PathNormalizer.normalize(path)
        guard !normalized.isEmpty, let resolved = realpath(normalized, nil) else { return normalized }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// `true` when two paths name the same folder, however each is spelled.
    ///
    /// Two empty paths are **not** the same place: an empty working directory is
    /// a terminal that has not reported one — Ghostty learns it from the shell's
    /// OSC 7 and a program started as its command has no shell — and matching
    /// those to each other would turn silence into a claim.
    public static func same(_ one: String, _ other: String) -> Bool {
        guard !one.trimmed.isEmpty, !other.trimmed.isEmpty else { return false }
        return of(one) == of(other)
    }
}
