import LampBoardCore
import Foundation
import TestKit

/// The names the user gives to rows: shown, never believed by anything that
/// finds windows or files.
enum RowNamesSuite {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private static func session(_ id: String, path: String, origin: SessionOrigin = .editor, title: String? = nil) -> SessionState {
        SessionState(id: id, status: .idle, workspace: Workspace(path: path), updatedAt: t0, statusSince: t0, origin: origin, title: title)
    }

    static let suite = TestSuite("Row names", [

        TestCase("Each agent in a folder can carry its own name") { t in
            // Two rows for one folder need two names, or they are told apart only
            // by one letter inside a sixteen-point ring. Renaming one leaves the
            // other alone.
            var names: [String: String] = [:]
            names = RowNames.renaming("/dev/project", harness: .claudeCode, to: "Design", in: names)
            names = RowNames.renaming("/dev/project", harness: .codex, to: "Migration", in: names)
            t.expectEqual(RowNames.name(of: "/dev/project", harness: .claudeCode, in: names),
                          "Design", "the Claude row")
            t.expectEqual(RowNames.name(of: "/dev/project", harness: .codex, in: names),
                          "Migration", "the Codex row")
        },

        TestCase("A name given to the folder still covers both") { t in
            // Every name set before rows could split is stored against the folder
            // alone. Dropping those would rename somebody's whole column back to
            // its folder names on the release that introduced the split, so the
            // plain key stays readable as the fallback for a row that has no name
            // of its own.
            let names = ["/dev/project": "Virgilio"]
            t.expectEqual(RowNames.name(of: "/dev/project", harness: .claudeCode, in: names),
                          "Virgilio", "Claude")
            t.expectEqual(RowNames.name(of: "/dev/project", harness: .codex, in: names),
                          "Virgilio", "and Codex")
        },

        TestCase("Naming one agent does not disturb the folder's own name") { t in
            var names = ["/dev/project": "Virgilio"]
            names = RowNames.renaming("/dev/project", harness: .codex, to: "Migration", in: names)
            t.expectEqual(RowNames.name(of: "/dev/project", harness: .codex, in: names),
                          "Migration", "the renamed one")
            t.expectEqual(RowNames.name(of: "/dev/project", harness: .claudeCode, in: names),
                          "Virgilio", "the other keeps the folder's name")
        },

        TestCase("An empty name gives a row back the folder's name") { t in
            var names = ["/dev/project": "Virgilio"]
            names = RowNames.renaming("/dev/project", harness: .codex, to: "Migration", in: names)
            names = RowNames.renaming("/dev/project", harness: .codex, to: "", in: names)
            t.expectEqual(RowNames.name(of: "/dev/project", harness: .codex, in: names),
                          "Virgilio", "back to the fallback, not to nothing")
        },

        TestCase("A name is stored by normalised folder, trimmed, bounded; blank removes it") { t in
            var names = RowNames.renaming("/dev/project/", to: "  Events  ", in: [:])
            t.expectEqual(names["/dev/project"], "Events", "normalised key, trimmed value")
            t.expectEqual(RowNames.name(of: "/dev/project", in: names), "Events", "read back either way")
            t.expectEqual(RowNames.name(of: "/dev/project/", in: names), "Events", "trailing slash")

            names = RowNames.renaming("/dev/project", to: String(repeating: "x", count: 100), in: names)
            t.expectEqual(names["/dev/project"]?.count, RowNames.maxLength, "bounded")

            names = RowNames.renaming("/dev/project", to: "   ", in: names)
            t.expectNil(names["/dev/project"], "blank means back to the original")
            t.expectNil(RowNames.name(of: "/dev/other", in: names), "unknown folder")
        },

        TestCase("The name wins on the row, over the folder and over a terminal row's title") { t in
            let state = TrafficLightState(sessions: [
                "a": session("a", path: "/dev/project"),
                "b": session("b", path: "/Users/dev", origin: .terminal, title: "Wire it"),
                "c": session("c", path: "/dev/plain"),
            ])
            let options = ColumnOptions(names: ["/dev/project": "Events", "/Users/dev": "Home box"])
            let rows = ColumnLayout.render(state, options: options).rows
            func row(_ path: String) -> ColumnRow? { rows.first { $0.workspace.path == path } }

            t.expectEqual(row("/dev/project")?.displayName, "Events", "named folder")
            t.expectEqual(row("/Users/dev")?.displayName, "Home box", "the name beats the title")
            t.expectEqual(row("/dev/plain")?.displayName, "plain", "unnamed rows keep the folder")
            t.expectEqual(row("/dev/project")?.workspace.name, "project", "the workspace itself is untouched")
        },

        TestCase("Hidden rows are summarised by their given names") { t in
            let state = TrafficLightState(sessions: ["a": session("a", path: "/dev/project")])
            let rendering = ColumnLayout.render(
                state, options: ColumnOptions(hidden: ["/dev/project"], names: ["/dev/project": "Events"])
            )
            t.expectEqual(rendering.hidden?.workspaceNames, ["Events"], "summary")
        },

        TestCase("The read endpoint publishes the label next to the folder") { t in
            let snapshot = SessionsCodec.snapshot(of: session("a", path: "/dev/project"), alias: "Events")
            t.expectEqual(snapshot.label, "Events", "label")
            t.expectEqual(snapshot.workspace, "project", "workspace stays the folder")
            t.expectEqual(SessionsCodec.snapshot(of: session("b", path: "/dev/project")).label, "project", "no name, the folder")
            t.expectEqual(
                SessionsCodec.snapshot(of: session("c", path: "/Users/dev", origin: .terminal, title: "Wire it")).label,
                "Wire it", "no name, a lone terminal row's title"
            )
        },
    ])
}
