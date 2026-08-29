import AppKit

/// Opens the Finder **inside** the folder a session is working in.
///
/// `open` and not `activateFileViewerSelecting`. The second reveals the folder
/// selected inside its parent — the ⌘⇧R gesture, "show me where this is" — and
/// that is the wrong question here: you already know where the project is, you
/// want to be in it. Asked for in those words, after the first version opened
/// `Development` with a folder highlighted inside it.
///
/// Nothing here is guarded by a permission: opening a folder is not an Apple
/// Event, so this works on a build with no Accessibility — which is exactly the
/// kind of build the panel is iterated on.
///
/// Never called for a row on another machine. `/home/dev/.notes` exists, and it
/// does not exist here; the glyph, the menu entry and the `⇧` in the tooltip's
/// help line are all absent there rather than disabled.
///
/// It lives in a file of its own for an unglamorous reason: adding it to
/// `PanelController` took that file to 787 lines against a self-imposed limit of
/// 800, and the file was already the longest in the project.
enum FinderReveal {

    static func open(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
