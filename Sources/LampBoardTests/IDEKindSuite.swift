import LampBoardCore
import Foundation
import TestKit

/// Recognizing the editor from the name it writes into the lock.
enum IDEKindSuite {

    static let suite = TestSuite("Editor recognition", [

        TestCase("Recognizes Visual Studio Code") { t in
            t.expectEqual(IDEKind.matching(declaredName: "Visual Studio Code"), .visualStudioCode)
        },

        TestCase("Recognizes the Insiders build as VS Code") { t in
            // `vscode.env.appName` in the beta is "Visual Studio Code - Insiders",
            // and comparing for equality discarded it.
            t.expectEqual(
                IDEKind.matching(declaredName: "Visual Studio Code - Insiders"),
                .visualStudioCode
            )
        },

        TestCase("Recognizes Cursor") { t in
            t.expectEqual(IDEKind.matching(declaredName: "Cursor"), .cursor)
        },

        TestCase("Does not recognize an unknown editor") { t in
            t.expectNil(IDEKind.matching(declaredName: "Zed"))
            t.expectNil(IDEKind.matching(declaredName: ""))
            t.expectNil(IDEKind.matching(declaredName: "   "))
        },

        TestCase("Every editor has a distinct bundle and process") { t in
            let bundles = Set(IDEKind.all.map(\.bundleIdentifier))
            let processes = Set(IDEKind.all.map(\.processName))
            // Two editors sharing a bundle would mean activating the wrong
            // application on every click on either of them.
            t.expectEqual(bundles.count, IDEKind.all.count, "distinct bundles")
            t.expectEqual(processes.count, IDEKind.all.count, "distinct processes")
        },

        TestCase("The bundle identifiers are the real ones") { t in
            t.expectEqual(IDEKind.visualStudioCode.bundleIdentifier, "com.microsoft.VSCode")
            // Cursor ships through ToDesktop: the bundle doesn't contain the
            // product name, so it's the kind of constant that has to be verified
            // rather than guessed. Read from /Applications/Cursor.app/Contents/Info.plist.
            t.expectEqual(IDEKind.cursor.bundleIdentifier, "com.todesktop.230313mzl4w4u92")
        },

        TestCase("VS Code's process name is not the app name") { t in
            // System Events looks for the process, which is called "Code": using
            // "Visual Studio Code" finds no windows at all.
            t.expectEqual(IDEKind.visualStudioCode.processName, "Code")
            t.expectEqual(IDEKind.cursor.processName, "Cursor")
        },
    ])
}
