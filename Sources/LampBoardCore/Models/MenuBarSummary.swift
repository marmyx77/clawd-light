/// What the menu bar icon shows, derived from the column it stands for.
///
/// WHY IT IS COMPUTED FROM THE RENDERING AND NOT FROM THE STATE
/// The icon is a summary of the column, never a second reading of the same
/// facts. Grouping, the "only what's waiting" filter and the hidden set all
/// change which rows a person can see, and an icon computed from
/// `TrafficLightState` would answer for rows the column is not showing. Then
/// the two disagree, and the one that is wrong is the one with no room to
/// explain itself.
///
/// So it takes a `ColumnRendering` — the same value the panel draws — and the
/// only question it answers is: of what the column is showing, what is the most
/// urgent thing, and how many of them are there.
///
/// HIDDEN ROWS COUNT
/// A hidden project is not a forgotten one: the column keeps a summary line that
/// lights up when something in it needs attention, for the reason spelled out in
/// D4. An icon that ignored the hidden set would be the "hide means forget"
/// failure, moved into the menu bar where it is even harder to notice.
public struct MenuBarSummary: Sendable, Equatable {

    /// The most urgent status the column is showing, or `nil` when it shows
    /// nothing at all.
    public let lamp: SessionStatus?

    /// How many rows carry that status. One is the common case; the number is
    /// what makes three blocked sessions readable as three.
    public let count: Int

    /// Whether the icon should blink.
    ///
    /// The three states that clear on a click are the three that mean *there is
    /// news here nobody has taken in*: a session blocked on an answer, a turn
    /// that finished and has not been read, a turn that died. Those are exactly
    /// the states whose row a click puts back to rest, so the icon stops
    /// blinking for the same reason and at the same moment the row stops.
    ///
    /// Yellow and blue never blink, and neither does rest. A blink that fired
    /// while a session was merely working would be on for most of the day, and a
    /// signal that is always on is not a signal.
    public let blinks: Bool

    /// Every status the column is showing, with how many rows carry it. The
    /// tooltip reads this; the icon reads `lamp` and `count`.
    public let counts: [SessionStatus: Int]

    /// `true` when there is no session at all. The icon draws its quiet shape.
    public var isEmpty: Bool { lamp == nil }

    /// `true` when there is news: something a click would clear.
    public var needsAttention: Bool { lamp?.clearsOnFocus == true }

    public init(lamp: SessionStatus?, count: Int, blinks: Bool, counts: [SessionStatus: Int]) {
        self.lamp = lamp
        self.count = count
        self.blinks = blinks
        self.counts = counts
    }

    /// Nothing to show: the column is empty.
    public static let empty = MenuBarSummary(lamp: nil, count: 0, blinks: false, counts: [:])

    /// - Parameters:
    ///   - rendering: what the column is showing right now.
    ///   - calmWorkspaces: projects whose blinking the user switched off. They
    ///     still colour the icon, because *Don't blink* silences the movement and
    ///     not the state — the same distinction the dot makes.
    public static func of(
        rendering: ColumnRendering,
        calmWorkspaces: Set<String> = []
    ) -> MenuBarSummary {
        var counts: [SessionStatus: Int] = [:]
        var loudest: SessionStatus?

        for row in rendering.rows {
            counts[row.status, default: 0] += 1
            if loudest == nil || row.status.urgencyRank < loudest!.urgencyRank {
                loudest = row.status
            }
        }

        // The hidden summary is one line in the column and it counts as one row
        // here, carrying the most urgent status among the projects behind it.
        if let hidden = rendering.hidden {
            counts[hidden.status, default: 0] += 1
            if loudest == nil || hidden.status.urgencyRank < loudest!.urgencyRank {
                loudest = hidden.status
            }
        }

        guard let lamp = loudest else { return .empty }

        // A blink needs at least one row in that state that was not silenced.
        // Every row silenced and the icon holds the colour steady, which is what
        // *Don't blink* asks for on a row and means no differently up here.
        let blinks = lamp.clearsOnFocus && rendering.rows.contains {
            $0.status == lamp && !calmWorkspaces.contains($0.workspace.key)
        }

        return MenuBarSummary(
            lamp: lamp,
            count: counts[lamp] ?? 0,
            blinks: blinks || (lamp.clearsOnFocus && rendering.hidden?.status == lamp),
            counts: counts
        )
    }

    /// The sentence the icon carries as its tooltip.
    ///
    /// Ordered by urgency, like the legend, and it names the state rather than
    /// the colour: somebody reading a tooltip has already failed to read the
    /// colour, so repeating it would be answering a question they did not ask.
    public var tooltip: String {
        guard lamp != nil else { return "LampBoard: no sessions" }
        let parts = SessionStatus.allCases
            .sorted { $0.urgencyRank < $1.urgencyRank }
            .compactMap { status -> String? in
                guard let n = counts[status], n > 0 else { return nil }
                return "\(n) \(status.label)"
            }
        return "LampBoard: " + parts.joined(separator: ", ")
    }
}
