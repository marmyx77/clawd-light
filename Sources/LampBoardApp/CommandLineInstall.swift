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

    static func runUninstall() -> Int32 {
        let installer = HookInstaller()
        do {
            let backup = try installer.uninstall()
            print("Hooks removed from ~/.claude/settings.json")
            if let backup {
                print("Backup: \(backup.path)")
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
