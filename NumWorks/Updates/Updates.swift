import AppKit
import Sparkle

/// Owns the Sparkle updater for the lifetime of the app.
///
/// Created programmatically because NumWorks has a custom `main.swift` entry
/// point (no MainMenu.xib). Keep a strong reference — Sparkle holds its
/// delegates weakly.
///
/// Quit/relaunch compatibility with Epsilon’s SDL `terminate:` override is
/// handled in `EpsilonBridge.installProcessExitOnTerminate` — do **not** force
/// `exit` from `willInstallUpdate`, or Sparkle’s Installer XPC can die before
/// Autoupdate is armed.
@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {

    static let shared = UpdateController()

    /// Standard Sparkle controller: automatic background checks + UI.
    private(set) var updaterController: SPUStandardUpdaterController!

    private override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self)
    }

    /// User-initiated “Check for Updates…” (menu / Settings).
    @objc func checkForUpdates(_ sender: Any?) {
        guard Bundle.main.isInstalled else { return }
        updaterController.checkForUpdates(sender)
    }

    var canCheckForUpdates: Bool {
        Bundle.main.isInstalled && updaterController.updater.canCheckForUpdates
    }

    /// Mirrors Sparkle’s `SUEnableAutomaticChecks` (default true via Info.plist).
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) {
            return canCheckForUpdates
        }
        return true
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        NSLog(
            "[NumWorks] Sparkle will install update %@ (%@)",
            item.displayVersionString,
            item.versionString)

        // Make the app easier for Sparkle’s progress agent to see/activate.
        // Actual process exit comes from the SDL terminate: swizzle when the
        // agent sends a soft quit.
        DispatchQueue.main.async {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain,
           nsError.code == Int(SUError.noUpdateError.rawValue) {
            return
        }
        NSLog("[NumWorks] Sparkle aborted: %@", nsError)
    }

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        DispatchQueue.main.async {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
