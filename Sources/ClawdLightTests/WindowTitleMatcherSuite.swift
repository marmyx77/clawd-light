import ClawdLightCore
import TestKit

enum WindowTitleMatcherSuite {

    /// Titles captured from VS Code windows actually open on a machine, with the
    /// project names anonymized. What matters is the **shape**: the truncated
    /// context segment, the em dash separators, the optional profile segment, and
    /// the pairs of names that share a prefix.
    private static let realTitles = [
        "Find session for project… — acme-portal",
        "Build floating Mac traff… — clawd-light — Claude Minimal",
        "Read documentation and s… — docs-site — Claude Minimal",
        "analyze the project — Checkout — Claude Minimal",
        "Read project and sessio… — holiday-planner — Claude Minimal",
        "It wouldn't make sense t… — budget-tracker — Claude Minimal",
        "not happy with the … — stargazer — Claude Minimal",
        "Project analysis and gap… — event-tracker — Claude Minimal",
        "Claude Code — policy-literacy — Claude Minimal",
        "ok merge it — marketing-site — Claude Minimal",
        "tsconfig.base.json — os-platform — Claude Minimal",
        ".gitignore — lab-plugin",
        "Proposal_Compliance_Review.docx — compliance-course — Claude Minimal",
    ]

    static let suite = TestSuite("VS Code window recognition", [

        TestCase("Finds the window among the ones actually open") { t in
            t.expectEqual(
                WindowTitleMatcher.bestMatch(workspaceName: "clawd-light", titles: realTitles), 1
            )
            t.expectEqual(
                WindowTitleMatcher.bestMatch(workspaceName: "stargazer", titles: realTitles), 6
            )
            t.expectEqual(
                WindowTitleMatcher.bestMatch(workspaceName: "compliance-course", titles: realTitles), 12
            )
        },

        TestCase("Finds a window with no profile segment") { t in
            t.expectEqual(
                WindowTitleMatcher.bestMatch(workspaceName: "acme-portal", titles: realTitles), 0
            )
            t.expectEqual(
                WindowTitleMatcher.bestMatch(workspaceName: "lab-plugin", titles: realTitles), 11
            )
        },

        TestCase("Returns nil when the workspace isn't open") { t in
            t.expectNil(
                WindowTitleMatcher.bestMatch(workspaceName: "nonexistent-project", titles: realTitles)
            )
        },

        // The case that makes a plain `contains` unreliable.
        TestCase("Does not confuse two workspaces with similar names") { t in
            let titles = [
                "file.ts — clawd-light-old — Claude",
                "file.ts — clawd-light — Claude",
            ]
            t.expectEqual(WindowTitleMatcher.bestMatch(workspaceName: "clawd-light", titles: titles), 1)
            t.expectEqual(
                WindowTitleMatcher.bestMatch(workspaceName: "clawd-light-old", titles: titles), 0
            )
        },

        TestCase("An exact match beats a partial one") { t in
            let titles = [
                "something about stargazer in the file name — other-project — Claude",
                "index.ts — stargazer — Claude",
            ]
            t.expectEqual(WindowTitleMatcher.bestMatch(workspaceName: "stargazer", titles: titles), 1)
        },

        TestCase("Handles workspaces with spaces in the name") { t in
            let titles = ["README.md — My Project — Claude"]
            t.expectEqual(
                WindowTitleMatcher.bestMatch(workspaceName: "My Project", titles: titles), 0
            )
        },

        TestCase("Recognizes custom separators too") { t in
            let titles = ["README.md | clawd-light | Claude"]
            t.expectEqual(
                WindowTitleMatcher.bestMatch(workspaceName: "clawd-light", titles: titles), 0
            )
        },

        TestCase("The comparison ignores case") { t in
            let titles = ["README.md — ClawdLight — Claude"]
            t.expectEqual(
                WindowTitleMatcher.bestMatch(workspaceName: "clawdlight", titles: titles), 0
            )
        },

        TestCase("An empty name matches nothing") { t in
            t.expectNil(WindowTitleMatcher.bestMatch(workspaceName: "", titles: realTitles))
            t.expectNil(WindowTitleMatcher.bestMatch(workspaceName: "   ", titles: realTitles))
        },

        TestCase("An empty title list returns nil") { t in
            t.expectNil(WindowTitleMatcher.bestMatch(workspaceName: "clawd-light", titles: []))
        },
    ])
}
