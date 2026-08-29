import LampBoardCore
import Foundation

/// Waits for a permission to arrive, then finishes the click it interrupted.
///
/// Granting a TCC authorization notifies nobody. There is no callback and no
/// notification: `AXIsProcessTrusted()` simply starts answering differently, and
/// an app that only asks at click time will keep saying the same thing until the
/// next click. Measured on a real install: the permission was granted, the panel
/// went on showing the same complaint, and it took quitting and relaunching the
/// app to make it agree — which nobody would have guessed to do.
///
/// So the polling is not the point. The point is that the click made before the
/// interruption is the one the user still wants: asking them to make it again is
/// how a permission they have just granted feels like it changed nothing.
@MainActor
final class PermissionWatcher {

    private var timer: Timer?
    private var pending: (() -> Void)?
    private let isGranted: () -> Bool
    private let now: () -> Date

    /// - Parameter isGranted: the question asked on every tick. Injected so the
    ///   behaviour can be exercised without a real authorization database.
    init(
        isGranted: @escaping () -> Bool = { VSCodeFocuser.hasAccessibilityPermission },
        now: @escaping () -> Date = Date.init
    ) {
        self.isGranted = isGranted
        self.now = now
    }

    /// True while a click is being held for a permission.
    var isWaiting: Bool { timer != nil }

    /// Holds `retry` until the permission shows up, then runs `onArrival` and it.
    ///
    /// A second call replaces the first: the click being waited for is always the
    /// most recent one, and stacking them would raise a window the user asked for
    /// two minutes and three decisions ago.
    func watch(retry: @escaping () -> Void, onArrival: @escaping () -> Void) {
        stop()
        pending = retry

        let deadline = now().addingTimeInterval(AppConfig.permissionWatchWindow)
        let timer = Timer.scheduledTimer(
            withTimeInterval: AppConfig.permissionWatchInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.tick(deadline: deadline, onArrival: onArrival) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops waiting and forgets the pending click.
    func stop() {
        timer?.invalidate()
        timer = nil
        pending = nil
    }

    private func tick(deadline: Date, onArrival: () -> Void) {
        switch PermissionWait.step(granted: isGranted(), now: now(), deadline: deadline) {
        case .keepWaiting:
            return
        case .giveUp:
            // A watch with no end is a timer that runs for the rest of the day
            // because somebody clicked once and went to lunch. The click is not
            // lost when this expires — it is simply made again.
            stop()
        case .finish:
            let retry = pending
            stop()
            onArrival()
            retry?()
        }
    }
}
