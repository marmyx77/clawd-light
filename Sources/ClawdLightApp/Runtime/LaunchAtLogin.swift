import ClawdLightCore
import Foundation
import ServiceManagement

/// Automatic launch at login.
///
/// **It refuses to register when the app is ad-hoc signed**, and that is not a
/// theoretical precaution: with that signature every rebuild produces a different
/// identity, macOS registers a brand-new app each time, and orphaned records pile
/// up in Settings that the user cannot trace back to anything. It has already
/// happened in this project — with a login item registered by a process that then
/// failed to remove it.
///
/// With a stable certificate (`Scripts/create-signing-identity.sh`) the problem
/// doesn't exist and the menu entry unlocks on its own.
enum LaunchAtLogin {

    enum Availability: Equatable {
        case available
        case needsStableSignature
        case needsBundle

        var explanation: String? {
            switch self {
            case .available:
                return nil
            case .needsStableSignature:
                return """
                Launch at login requires a stable signature.

                With an ad-hoc signature every rebuild creates a new identity, \
                macOS registers a different app each time, and orphaned entries \
                are left behind in Settings › General › Login Items.

                Run ./Scripts/create-signing-identity.sh once and rebuild with \
                ./Scripts/build-app.sh.
                """
            case .needsBundle:
                return "Launch at login only works when you run ClawdLight.app, not the bare binary."
            }
        }
    }

    /// Whether the feature is usable in this installation.
    static var availability: Availability {
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundleURL.pathExtension == "app"
        else {
            return .needsBundle
        }
        return CodeSignature.isAdHoc ? .needsStableSignature : .available
    }

    static var isEnabled: Bool {
        guard availability == .available else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Turns launch at login on or off.
    /// - Returns: an error message, or `nil` when it worked.
    static func setEnabled(_ enabled: Bool) -> String? {
        guard availability == .available else {
            return availability.explanation
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Cannot \(enabled ? "register" : "remove") launch at login: "
                + error.localizedDescription
        }
    }
}

/// How the running binary is signed.
enum CodeSignature {

    /// `true` when the signature is ad-hoc, that is, tied to the binary's hash.
    ///
    /// Read via `codesign -dv`: the `Signature=adhoc` line only appears in that
    /// case. It is read exactly once at startup — spawning a process for every
    /// query would be out of proportion.
    static let isAdHoc: Bool = {
        // Read at startup, on the thread that is about to draw the panel: a
        // `codesign` that does not return would mean an app that never appears,
        // with nothing on screen to say why.
        let output = (try? Command.run(
            "/usr/bin/codesign", ["-dv", Bundle.main.bundleURL.path],
            deadline: AppConfig.focusProbeTimeout
        ).output) ?? ""
        // When in doubt assume ad-hoc: the feature stays locked, which is the
        // harmless failure of the two.
        guard !output.isEmpty else { return true }
        return output.contains("Signature=adhoc")
    }()
}
