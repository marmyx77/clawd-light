import ClawdLightCore
import SwiftUI

/// The blink, as a modifier for a view that exists **only while it blinks**.
///
/// `repeatForever` has no off switch. SwiftUI stops such an animation only by
/// replacing it with another animation on the same value — and a render that no
/// longer touches that value replaces nothing. That is how an idle row blinked
/// red for nine hours: the opacity had gone back to rest, unanimated, one render
/// before the code that meant to stop the blink ran, so the stop found nothing
/// to stop (see 07-traps, "The blink that outlived its state").
///
/// The rule is therefore structural rather than clever: attach this to a view
/// that is *removed* when the blinking should end, never toggle it in place.
/// Removal takes the animation with it; nothing else does so reliably.
struct Blinking: ViewModifier {
    /// Opacity at the low end of the cycle. The high end is the view's own.
    let dimmedOpacity: Double

    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? dimmedOpacity : 1)
            .animation(
                .easeInOut(duration: AppConfig.blinkPeriod).repeatForever(autoreverses: true),
                value: dimmed
            )
            .onAppear { dimmed = true }
    }
}

extension View {
    /// Blinks between the view's own opacity and `dimmedOpacity` for as long as
    /// the view exists. Put it behind an `if`: the `else` branch is the off switch.
    func blinking(to dimmedOpacity: Double) -> some View {
        modifier(Blinking(dimmedOpacity: dimmedOpacity))
    }
}
