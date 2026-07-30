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

    /// Minimum time between automatic launch checks.
    private static let minimumAutomaticCheckInterval: TimeInterval = 60 * 60 * 24

    /// Park Sparkle’s own timer so it does not also fire on its schedule.
    /// We drive automatic checks from `schedulePostLaunchUpdateCheck`.
    private static let parkedSparkleInterval: TimeInterval = 60 * 60 * 24 * 365

    /// Default delay after AppMover (or attach) before an automatic check.
    static let defaultPostLaunchCheckDelay: TimeInterval = 3

    /// Standard Sparkle controller: automatic background checks + UI.
    private(set) var updaterController: SPUStandardUpdaterController!

    private var postLaunchCheckTimer: Timer?
    /// User tapped Check for Updates while outside Applications — we use the
    /// background check path so we can show a move-required alert instead of
    /// Sparkle’s install UI.
    private var pendingNotInstalledUserCheck = false

    private override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self)

        // Disable Sparkle’s built-in schedule; AppController triggers launch checks.
        parkSparkleAutomaticSchedule()
    }

    /// User-initiated “Check for Updates…” (menu / Settings).
    @objc func checkForUpdates(_ sender: Any?) {
        postLaunchCheckTimer?.invalidate()
        postLaunchCheckTimer = nil

        if Bundle.main.isInstalled {
            pendingNotInstalledUserCheck = false
            updaterController.checkForUpdates(sender)
        } else {
            // Still query the appcast; if an update exists, show move warning.
            pendingNotInstalledUserCheck = true
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    /// Mirrors Sparkle’s `SUEnableAutomaticChecks` (default true via Info.plist).
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set {
            updaterController.updater.automaticallyChecksForUpdates = newValue
            parkSparkleAutomaticSchedule()
            if !newValue {
                postLaunchCheckTimer?.invalidate()
                postLaunchCheckTimer = nil
            }
        }
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) {
            return canCheckForUpdates
        }
        return true
    }

    // MARK: - Post-launch schedule

    /// Call after AppMover has finished (or been skipped) so alerts do not stack.
    func schedulePostLaunchUpdateCheck(
        after delay: TimeInterval = UpdateController.defaultPostLaunchCheckDelay
    ) {
        postLaunchCheckTimer?.invalidate()
        postLaunchCheckTimer = nil

        parkSparkleAutomaticSchedule()
        guard automaticallyChecksForUpdates else { return }

        let timer = Timer(timeInterval: max(delay, 0.5), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performPostLaunchCheck()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        postLaunchCheckTimer = timer
    }

    private func parkSparkleAutomaticSchedule() {
        updaterController.updater.updateCheckInterval = Self.parkedSparkleInterval
    }

    private func performPostLaunchCheck() {
        postLaunchCheckTimer = nil
        guard automaticallyChecksForUpdates else { return }
        guard updaterController.updater.canCheckForUpdates else { return }

        if let last = updaterController.updater.lastUpdateCheckDate,
           Date().timeIntervalSince(last) < Self.minimumAutomaticCheckInterval {
            return
        }

        // Same path as a background check so not-in-Applications gets our warning UI.
        updaterController.updater.checkForUpdatesInBackground()
    }

    private func presentMoveRequiredForUpdate(_ update: SUAppcastItem) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Update Found"
        alert.informativeText =
            "NumWorks \(update.displayVersionString) is available, but updates can only be installed "
            + "when the app lives in the Applications folder."
        alert.addButton(withTitle: "Move to Applications Folder")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        // End the Sparkle session we intercepted via gentle reminders.
        updaterController.userDriver.dismissUpdateInstallation()
        if response == .alertFirstButtonReturn {
            AppMover.moveIfNecessary(prompt: false)
        }
    }

    private func presentUpToDateWhileNotInstalled() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "You’re up to date"
        alert.informativeText =
            "NumWorks \(AppInfo.appVersion) is the latest version. "
            + "Move the app to Applications so future updates can install automatically."
        alert.addButton(withTitle: "Move to Applications Folder")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            AppMover.moveIfNecessary(prompt: false)
        }
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        // Handled in the user-driver callbacks when not installed.
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error?) {
        DispatchQueue.main.async {
            guard UpdateController.shared.pendingNotInstalledUserCheck else { return }
            UpdateController.shared.pendingNotInstalledUserCheck = false
            UpdateController.shared.presentUpToDateWhileNotInstalled()
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        NSLog(
            "[NumWorks] Sparkle will install update %@ (%@)",
            item.displayVersionString,
            item.versionString)

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
        DispatchQueue.main.async {
            UpdateController.shared.pendingNotInstalledUserCheck = false
        }
    }

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Outside Applications we show our own “move required” alert instead.
        Bundle.main.isInstalled
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        DispatchQueue.main.async {
            if Bundle.main.isInstalled {
                UpdateController.shared.pendingNotInstalledUserCheck = false
                if NSApp.activationPolicy() != .regular {
                    NSApp.setActivationPolicy(.regular)
                }
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            // Scheduled path (handleShowingUpdate == false) or background check
            // after a user tap while not installed.
            UpdateController.shared.pendingNotInstalledUserCheck = false
            UpdateController.shared.presentMoveRequiredForUpdate(update)
        }
    }
}
