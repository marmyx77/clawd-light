/// Where the panel lives: a window of its own, or under a lamp in the menu bar.
///
/// TWO HOMES, NOT TWO PRODUCTS
/// The column is the same column in both, drawn by the same view from the same
/// rendering. What changes is where the window sits, what it floats above, and
/// whether looking elsewhere puts it away. Anything that behaved differently
/// between the two would be a second product to keep true, and this project has
/// one column with one meaning.
///
/// WHY THE DROP-DOWN CANNOT ALSO BE ALWAYS ON TOP
/// A drop-down closes when you click elsewhere. That is what makes it a
/// drop-down rather than a window that happens to hang off an icon, and it is
/// the whole of the difference between the two homes: floating stays until you
/// put it away, the menu bar goes away when you look elsewhere. A click on a row
/// does the same thing in both, and so does everything in the menus.
///
/// THE ICON IS NOT THE SAME QUESTION
/// Whether the lamp sits in the menu bar is a separate switch, because somebody
/// who keeps the panel floating all day may still want the lamp up there for the
/// moments the panel is behind a full-screen window. Only one direction is
/// forced: a panel that lives in the menu bar needs the icon, because nothing
/// else could bring it back.
public enum PanelHome: String, Sendable, Equatable, CaseIterable, Codable {

    /// A window of its own, above other windows, staying where it was put.
    case floating

    /// Under the menu bar lamp, opened and closed by clicking it.
    case menuBar

    public var other: PanelHome { self == .floating ? .menuBar : .floating }

    /// Whether this home puts the panel away when the pointer goes elsewhere.
    public var closesWhenUnfocused: Bool { self == .menuBar }

    /// Whether this home needs the menu bar lamp to exist.
    public var requiresMenuBarIcon: Bool { self == .menuBar }

    /// What the footer button says it will do.
    public var moveAwayVerb: String {
        self == .floating
            ? "Put the panel in the menu bar: it opens and closes from the lamp up there"
            : "Bring the panel back to its own window: it stays in front until you put it away"
    }
}
