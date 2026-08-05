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

    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(StatusPalette.color(for: status))
            .frame(width: Layout.dotSize, height: Layout.dotSize)
            .opacity(currentOpacity)
            .shadow(
                color: StatusPalette.color(for: status).opacity(0.8),
                radius: StatusPalette.glowRadius(for: status)
            )
            .animation(blinkAnimation, value: dimmed)
            .onAppear { dimmed = blinks }
            .onChange(of: status) { _, _ in dimmed = blinks }
            .onChange(of: calm) { _, _ in dimmed = blinks }
    }

    private var blinks: Bool { status.shouldBlink && !calm }

    private var currentOpacity: Double {
        let base = StatusPalette.opacity(for: status)
        guard blinks, dimmed else { return base }
        return base * 0.25
    }

    private var blinkAnimation: Animation? {
        guard blinks else { return .easeInOut(duration: 0.2) }
        return .easeInOut(duration: AppConfig.blinkPeriod).repeatForever(autoreverses: true)
    }
}
