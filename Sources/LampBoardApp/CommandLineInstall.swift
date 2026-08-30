import LampBoardCore
import Foundation

/// The two commands that write to somebody else's configuration file.
///
/// Split out of `CommandLineInterface` when it reached the 800-line ceiling, and
/// this is the seam that was already there: everything else in that file reads
/// state or raises a window, while these two edit `~/.claude/settings.json` and
/// `~/.codex/hooks.json` — files a person relies on every day and did not write
/// for us.
extension CommandLineInterface {
    static func runInstall(port: UInt16, includeToolEvents: Bool) -> Int32 {
        let installer = HookInstaller()
        do {
            let backup = try installer.install(port: port, includeToolEvents: includeToolEvents)
            print("Hooks installed for: \(installer.installedEvents().joined(separator: ", "))")
            print("Script: \(installer.scriptPath)")
            if let backup {
                print("Backup of settings.json: \(backup.path)")
            }
            print("\nClaude Code sessions that are already open pick up the new")
            print("configuration the next time they start.")

            // Codex is installed alongside, and only where it is actually
            // present: writing a hooks file into a directory nobody has ever
            // used would leave a configuration for a program that is not there.
            if FileManager.default.fileExists(atPath: AppConfig.codexDirectory.path) {
                let codex = HookInstaller.codex()
                do {
                    try codex.install(port: port, includeToolEvents: includeToolEvents)
                    let events = codex.installedEvents().joined(separator: ", ")
                    print("\nCodex hooks installed for: \(events)")
                    print("Script: \(codex.scriptPath)")
                    print("\n\(HookInstaller.codexTrustNotice)")
                } catch {
                    // A failure here must not undo the Claude Code install that
                    // already succeeded. One harness working is a normal state,
                    // and the message says which one did not.
                    print("\nCodex hooks were not installed: \(error.localizedDescription)")
                }
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    /// Removes what was installed, from **both** configurations.
    ///
    /// It used to remove only Claude Code's, which left Codex calling a script
    /// that was still there for a program that was gone. Worse, it did it while
    /// reporting success, and the Homebrew caveat promises a removal this command
    /// is the whole of.
    ///
    /// A harness that was never configured is not a failure: `uninstall` on a file
    /// that does not exist has nothing to do and says so by doing nothing.
    static func runUninstall() -> Int32 {
        var failed = false

        for (label, installer, path) in [
            ("Claude Code", HookInstaller(), AppConfig.claudeSettingsURL),
            ("Codex", HookInstaller.codex(), AppConfig.codexHooksURL),
        ] {
            guard FileManager.default.fileExists(atPath: path.path) else {
                print("\(label): nothing to remove, \(shortPath(path)) is not there.")
                continue
            }
            do {
                let backup = try installer.uninstall()
                print("\(label): hooks removed from \(shortPath(path))")
                if let backup { print("  Backup: \(backup.path)") }
            } catch {
                // Said per harness rather than as one verdict. A partial failure
                // reported as success is how a hook survives an uninstall and
                // calls a script nobody expects to be called.
                FileHandle.standardError.write(
                    Data("\(label): NOT removed: \(error.localizedDescription)\n".utf8)
                )
                failed = true
            }
        }

        return failed ? 1 : 0
    }

    /// A path with the home written as a tilde.
    private static func shortPath(_ url: URL) -> String {
        let home = AppConfig.homeDirectory.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// The probe behind the Codex scanner, run by hand.
///
/// It exists because "the signed bundle can read another process's open files"
/// had to be **shown** before anything was built on it, not argued from the fact
/// that a neighbouring call already works. Sandboxing, the hardened runtime and
/// the entitlements a release is signed with are exactly the kind of boundary
/// that moves under a plan without telling it.
///
/// Kept after the spike because it is also the answer to "why does LampBoard not
/// see my Codex session": it prints the evidence, or says which part of it is
/// missing.
extension CommandLineInterface {
    static func runCodexProbe() -> Int32 {
        print("Codex sessions this process can prove are alive")
        print("Sessions root: \(AppConfig.codexSessionsDirectory.path)")

        let pids = ProcessTree.pids(named: "codex")
        print("Live codex processes: \(pids.isEmpty ? "none" : pids.map(String.init).joined(separator: ", "))")

        switch CodexProcessScanner().scan() {
        case .unavailable(let reason):
            print("\nThe probe could not answer: \(reason)")
            print("That is not the same as no sessions: nothing was ruled out.")
            return 1

        case .observed(let evidence) where evidence.isEmpty:
            print("\nNo process is holding a rollout open.")
            print("A rollout on disk is a session that existed; only an open one is alive.")
            return 0

        case .observed(let evidence):
            print("")
            for item in evidence {
                print("  pid \(item.pid)  \(item.surface.label)")
                print("    folder:     \(item.meta.cwd)")
                print("    session:    \(item.meta.sessionId)")
                print("    rollout:    \(item.rolloutPath)")
                print("    executable: \(item.executable)")
                print("    focus from the executable: \(item.surface.focusIsDecidedByExecutable ? "yes" : "no, the ancestry decides")")
            }
            return 0
        }
    }
}
