import LampBoardCore
import SwiftUI

/// How full the session's context is, and which model is holding it.
///
/// WHY IT REPLACED THE SLOT NUMBER
/// The cell to the left of the name used to carry the row's keyboard slot — a
/// number that never changes, on a row whose position never changes either (D23).
/// It answered a question nobody asks twice. The saturation is the opposite kind
/// of fact: it moves while you work, it decides whether to start a large task
/// here or in a fresh session, and until now the only way to know it was to open
/// the session and ask. The slot did not disappear; it moved into the tooltip,
/// where a fact you look up once belongs.
///
/// WHY IT IS MONOCHROME
/// Six states already own the colour in this panel, and a ring that turned red
/// near the end would be a seventh voice competing with them — at exactly the
/// moment the row's own colour matters most. The arc says how much, the letter
/// says which model, and neither shouts.
///
/// THE THREE SILENCES ARE NOT THE SAME SILENCE
/// A dashed track means nothing has been read yet — a session that has not
/// replied, a transcript that is not there. A solid track with a dimmed letter
/// means a figure was read and is known to be wrong: the session was compacted
/// since, so the number describes a conversation that no longer exists. An `n`
/// means the model is one this build has no window for. An empty ring saying all
/// three would read as "there is room", which is the one thing none of them says.
struct ContextRing: View {
    let reading: ContextReading?

    var body: some View {
        ZStack {
            track
            if let fraction = reading?.fraction {
                Circle()
                    .inset(by: Layout.contextRingWidth / 2)
                    .trim(from: 0, to: fraction)
                    .stroke(arcColor, style: StrokeStyle(lineWidth: Layout.contextRingWidth))
                    // From the top, clockwise, like every gauge anybody has ever
                    // read. SwiftUI starts a trimmed circle at three o'clock.
                    .rotationEffect(.degrees(-90))
            }
            if let reading {
                Text(reading.modelInitial)
                    .font(.system(size: Layout.contextRingLetter, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(reading.fraction == nil ? 0.38 : 0.85))
            }
        }
        .frame(width: Layout.contextRingSize, height: Layout.contextRingSize)
    }

    /// Solid once something has been read; dashed while nothing has.
    @ViewBuilder
    private var track: some View {
        if reading == nil {
            Circle()
                .inset(by: Layout.contextRingWidth / 2)
                .stroke(
                    Color.primary.opacity(0.24),
                    style: StrokeStyle(lineWidth: Layout.contextRingWidth, dash: [1.6, 1.6])
                )
        } else {
            Circle()
                .strokeBorder(Color.primary.opacity(0.20), lineWidth: Layout.contextRingWidth)
        }
    }

    /// A floor is drawn fainter than an exact reading.
    ///
    /// Same grammar the label uses with its `≥`: the arc is where the context has
    /// certainly reached, and the paler ink says the true edge is somewhere past
    /// it. Fainter rather than longer — drawing the uncertainty as extra arc would
    /// invent tokens nobody counted.
    private var arcColor: Color {
        // Against a track at 0.20. The first pair — 0.16 and 0.78 — was measured
        // on screen and the arc did not separate from the circle it sits on: on a
        // vibrant surface the difference between two translucent whites is
        // smaller than it is on paper.
        Color.primary.opacity(reading?.confidence == .floor ? 0.62 : 0.92)
    }
}
