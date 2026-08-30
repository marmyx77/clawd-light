import LampBoardCore
import Foundation
import TestKit

/// The fault the panel can offer a button for.
///
/// These are checks on wording and destination rather than on arithmetic, and
/// they are here because both have already been wrong in a way that cost an
/// afternoon: a sentence that sends somebody to the wrong System Settings pane
/// is worse than no sentence, because they find a switch that is already on and
/// conclude the permission is fine.
enum PanelIssueSuite {

    static let suite = TestSuite("Panel issues", [

        TestCase("Each permission points at its own pane, and they are not the same one") { t in
            let accessibility = PanelIssue.accessibilityMissing.settingsURL?.absoluteString ?? ""
            let automation = PanelIssue.automationMissing(app: "System Events")
                .settingsURL?.absoluteString ?? ""

            t.expect(accessibility.contains("Privacy_Accessibility"), "accessibility pane")
            t.expect(automation.contains("Privacy_Automation"), "automation pane")
            t.expect(accessibility != automation, "two distinct panes")
        },

        TestCase("The strip's line is short enough for a 240-point panel") { t in
            // Measured against the width the panel actually has: the strip shares
            // it with a warning glyph and a button, so anything past this is
            // truncated and the user reads half a fault.
            for issue in [PanelIssue.accessibilityMissing,
                          .automationMissing(app: "System Events")] {
                t.expect(issue.summary.count <= 32, "“\(issue.summary)” fits")
                t.expect(!issue.summary.isEmpty, "and says something")
            }
        },

        TestCase("The explanation names the use, the cost of refusing, and the way back") { t in
            let text = PanelIssue.accessibilityMissing.explanation
            t.expect(text.contains("front"), "says what the permission is used for")
            t.expect(text.lowercased().contains("without it"), "says what refusing costs")
            t.expect(
                PanelIssue.accessibilityMissing.reassurance.lowercased().contains("turn this off"),
                "and that it is reversible"
            )
        },

        TestCase("The automation text names the application it is asked for") { t in
            // "Enable Automation" with no target is the sentence that sends people
            // to a pane with six applications listed and no idea which to touch.
            let issue = PanelIssue.automationMissing(app: "Ghostty")
            t.expect(issue.explanation.contains("Ghostty"), "the target is named")
            t.expect(
                !PanelIssue.automationMissing(app: "System Events").explanation.contains("Ghostty"),
                "and it is the one asked about"
            )
        },

        TestCase("The stale-entry cure clears every hidden record, not the visible one") { t in
            // Measured on a real install: four separate authorisation records for
            // com.lampboard.app, of which the list showed one, switched on, while
            // the running app held nothing. Removing the visible row is the advice
            // that does not work, so the text must carry the command that does.
            let cure = PanelIssue.staleEntryCure
            t.expect(cure.contains("tccutil reset Accessibility com.lampboard.app"),
                         "the accessibility record")
            t.expect(cure.contains("tccutil reset AppleEvents com.lampboard.app"),
                         "and the automation one, which is a separate database")
            t.expect(cure.lowercased().contains("not enough"),
                         "and it warns that “−” alone can leave records behind")

            // Three lines of shell in a dialog, with nothing saying they are shell,
            // is not an instruction: it is a puzzle handed to somebody whose app is
            // already not working. The text has to name the application and say
            // where it lives, because the person who needs this recipe is by
            // definition the one for whom nothing has gone to plan.
            t.expect(cure.contains("Terminal"), "it names the application")
            t.expect(cure.contains("Utilities"), "and says where to find it")
            t.expect(cure.lowercased().contains("press return"),
                         "and what to do once the lines are pasted")
        },

        TestCase("The explanation is a procedure, not a paragraph") { t in
            // The first version said “In System Settings, turn on the switch next
            // to LampBoard” and stopped there, which leaves the reader to find a
            // pane out of a few dozen. The button below the text opens the exact
            // page, so the text says so and numbers the steps around it.
            for issue in [PanelIssue.accessibilityMissing, .automationMissing(app: "Ghostty")] {
                let text = issue.explanation
                t.expect(text.contains("Privacy & Security"), "it names the pane")
                t.expect(text.contains("Open System Settings"),
                             "and the button that goes straight there")
                t.expect(text.contains("1.") && text.contains("2."),
                             "and it is numbered, so it can be followed")
            }
        },

        TestCase("Equality distinguishes the two, and the application within one") { t in
            t.expect(PanelIssue.accessibilityMissing == .accessibilityMissing, "same")
            t.expect(PanelIssue.accessibilityMissing != .automationMissing(app: "System Events"),
                         "different permissions")
            t.expect(PanelIssue.automationMissing(app: "Terminal")
                         != .automationMissing(app: "iTerm2"),
                         "different applications: the panel must re-offer the button")
        },
    ])
}

/// The tick that decides whether an interrupted click is still owed.
enum PermissionWaitSuite {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static let suite = TestSuite("Permission wait", [

        TestCase("Nothing yet, inside the window: hold the click") { t in
            t.expectEqual(
                PermissionWait.step(granted: false, now: t0, deadline: t0.addingTimeInterval(180)),
                .keepWaiting, "still waiting"
            )
        },

        TestCase("Granted: finish the click that was interrupted") { t in
            t.expectEqual(
                PermissionWait.step(granted: true, now: t0, deadline: t0.addingTimeInterval(180)),
                .finish, "the click is owed"
            )
        },

        TestCase("Past the window with nothing granted: let it go") { t in
            t.expectEqual(
                PermissionWait.step(granted: false, now: t0.addingTimeInterval(181),
                                    deadline: t0.addingTimeInterval(180)),
                .giveUp, "no timer outlives the intent"
            )
            t.expectEqual(
                PermissionWait.step(granted: false, now: t0.addingTimeInterval(180),
                                    deadline: t0.addingTimeInterval(180)),
                .giveUp, "the deadline itself is over"
            )
        },

        TestCase("Granted exactly as the window closes: finishing wins over giving up") { t in
            // The tie is the whole reason this is a function and not two ifs
            // scattered in a timer callback. Somebody who granted the permission
            // at the last second granted it, and a click is not less owed for
            // being answered late — dropping it here is indistinguishable, from
            // the outside, from the app ignoring the permission entirely.
            t.expectEqual(
                PermissionWait.step(granted: true, now: t0.addingTimeInterval(600),
                                    deadline: t0.addingTimeInterval(180)),
                .finish, "granted wins"
            )
        },
    ])
}
