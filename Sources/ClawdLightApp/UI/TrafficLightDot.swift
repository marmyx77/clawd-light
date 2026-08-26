import ClawdLightCore
import SwiftUI

/// A single traffic light.
///
/// Blinking is reserved for the state that blocks the work: if green blinked too,
/// with twelve sessions open the screen would turn into a Christmas tree and
/// neither signal would be noticed any more.
struct TrafficLightDot: View {
    let status: SessionStatus

    /// `true` when the dot stays lit steadily instead of blinking.
    ///
    /// What gets silenced is the **movement**, not the signal: the amber color
    /// stays. Blinking in peripheral vision is impossible to ignore, and that is
    /// exactly what is wanted — until you're working next to a session that has
    /// been waiting for half an hour and you don't intend to answer yet.
    var calm: Bool = false

    /// Two views, not one view with two behaviours.
    ///
    /// The first version toggled a `@State` flag on the same circle and relied on
    /// SwiftUI to cancel the `repeatForever` animation when the flag went back.
    /// It did not: the render that ends the amber changes the *status*, and the
    /// opacity returns to rest in that same render, unanimated; by the time the
    /// flag flips there is no opacity change left to animate, so the running
    /// animation is never replaced and keeps pulsing under every colour that
    /// follows — yellow, green, and finally the red of an idle row.
    ///
    /// Here the blinking dot is a different view. When the status stops blinking
    /// the view is removed, and a removed view takes its animations with it.
    var body: some View {
        if status.shouldBlink && !calm {
            glowing(circle.blinking(to: 0.25)).transition(.identity)
        } else {
            glowing(circle).transition(.identity)
        }
    }

    private var color: Color { StatusPalette.color(for: status) }

    private var circle: some View {
        Circle()
            .fill(color)
            .frame(width: Layout.dotSize, height: Layout.dotSize)
            .opacity(StatusPalette.opacity(for: status))
    }

    private func glowing<Dot: View>(_ dot: Dot) -> some View {
        dot.shadow(color: color.opacity(0.8), radius: StatusPalette.glowRadius(for: status))
    }
}
