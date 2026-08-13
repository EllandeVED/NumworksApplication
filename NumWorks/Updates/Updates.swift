import AppKit
import Combine
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
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {

    static let shared = UpdateController()

    private static let minimumAutomaticCheckInterval: TimeInterval = 60 * 60 * 24
    private static let parkedSparkleInterval: TimeInterval = 60 * 60 * 24 * 365
    /// Hard cap so the Settings spinner never spins forever.
    private static let userCheckTimeout: TimeInterval = 20
    static let defaultPostLaunchCheckDelay: TimeInterval = 3

    private(set) var updaterController: SPUStandardUpdaterController!

    private var postLaunchCheckTimer: Timer?
    private var checkTimeoutTimer: Timer?
    private var canCheckObservation: NSKeyValueObservation?

    /// What feedback the current user-initiated check still owes the UI.
    private enum PendingUserCheck {
        case none
        /// Outside Applications — we probe with `checkForUpdateInformation` and show our alerts.
        case notInstalled
        /// In Applications — Sparkle’s standard UI; we only track the Settings spinner.
        case installed
    }

    private var pendingUserCheck: PendingUserCheck = .none

    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var canCheckForUpdates = true

    private var updater: SPUUpdater { updaterController.updater }

    private override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self)
        parkSparkleAutomaticSchedule()
        observeCanCheckForUpdates()
    }

    // MARK: - User-initiated check

    @objc func checkForUpdates(_ sender: Any?) {
        guard !isCheckingForUpdates else { return }

        postLaunchCheckTimer?.invalidate()
        postLaunchCheckTimer = nil

        if updater.sessionInProgress {
            presentCheckFailed(
                "An update check is already running. Try again in a moment.")
            return
        }
        guard updater.canCheckForUpdates else {
            presentCheckFailed(
                "Updates can’t be checked right now. Try again in a moment.")
            return
        }

        if Bundle.main.isInstalled {
            pendingUserCheck = .installed
            beginChecking()
            updaterController.checkForUpdates(sender)
        } else {
            // Probe only — Sparkle’s install UI can’t run outside Applications.
            pendingUserCheck = .notInstalled
            beginChecking()
            updater.checkForUpdateInformation()
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            updater.automaticallyChecksForUpdates = newValue
            parkSparkleAutomaticSchedule()
            if !newValue {
                postLaunchCheckTimer?.invalidate()
                postLaunchCheckTimer = nil
            }
        }
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) {
            return canCheckForUpdates && !isCheckingForUpdates
        }
        return true
    }

    // MARK: - Checking state

    private func beginChecking() {
        isCheckingForUpdates = true
        checkTimeoutTimer?.invalidate()
        let timer = Timer(timeInterval: Self.userCheckTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleCheckTimeout()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        checkTimeoutTimer = timer
    }

    private func finishChecking() {
        checkTimeoutTimer?.invalidate()
        checkTimeoutTimer = nil
        isCheckingForUpdates = false
        canCheckForUpdates = updater.canCheckForUpdates
    }

    private func handleCheckTimeout() {
        guard isCheckingForUpdates else { return }
        let pending = pendingUserCheck
        pendingUserCheck = .none
        finishChecking()
        updaterController.userDriver.dismissUpdateInstallation()
        if pending != .none {
            presentCheckFailed(
                "The update check timed out. Check your network connection and try again.")
        }
    }

    private func observeCanCheckForUpdates() {
        canCheckObservation = updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                guard let self else { return }
                // Don’t re-enable the button while our spinner is up.
                self.canCheckForUpdates =
                    updater.canCheckForUpdates && !self.isCheckingForUpdates
            }
        }
    }

    // MARK: - Post-launch schedule

    func schedulePostLaunchUpdateCheck(
        after delay: TimeInterval = UpdateController.defaultPostLaunchCheckDelay
    ) {
        postLaunchCheckTimer?.invalidate()
        postLaunchCheckTimer = nil

        parkSparkleAutomaticSchedule()
        guard !UITesting.skipAutomaticUpdateChecks else { return }
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
        updater.updateCheckInterval = Self.parkedSparkleInterval
    }

    private func performPostLaunchCheck() {
        postLaunchCheckTimer = nil
        guard automaticallyChecksForUpdates else { return }
        guard updater.canCheckForUpdates, !updater.sessionInProgress else { return }
        guard !isCheckingForUpdates else { return }

        if let last = updater.lastUpdateCheckDate,
           Date().timeIntervalSince(last) < Self.minimumAutomaticCheckInterval {
            return
        }

        updater.checkForUpdatesInBackground()
    }

    // MARK: - Alerts

    private func presentMoveRequiredForUpdate(_ update: SUAppcastItem) {
        activateForAlert()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Update Found"
        alert.informativeText =
            "NumWorks \(update.displayVersionString) is available, but updates can only be installed "
            + "when the app lives in the Applications folder."
        alert.addButton(withTitle: "Move to Applications Folder")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        updaterController.userDriver.dismissUpdateInstallation()
        canCheckForUpdates = updater.canCheckForUpdates
        if response == .alertFirstButtonReturn {
            AppMover.moveIfNecessary(prompt: false)
        }
    }

    private func presentUpToDateWhileNotInstalled() {
        activateForAlert()
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
        canCheckForUpdates = updater.canCheckForUpdates
    }

    private func presentCheckFailed(_ message: String) {
        activateForAlert()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t Check for Updates"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        canCheckForUpdates = updater.canCheckForUpdates
    }

    private func activateForAlert() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func isNoUpdateError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SUSparkleErrorDomain
            && nsError.code == Int(SUError.noUpdateError.rawValue)
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            let controller = UpdateController.shared
            switch controller.pendingUserCheck {
            case .notInstalled:
                controller.pendingUserCheck = .none
                controller.finishChecking()
                controller.presentMoveRequiredForUpdate(item)
            case .installed, .none:
                break
            }
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error?) {
        DispatchQueue.main.async {
            let controller = UpdateController.shared
            switch controller.pendingUserCheck {
            case .notInstalled:
                controller.pendingUserCheck = .none
                controller.finishChecking()
                controller.presentUpToDateWhileNotInstalled()
            case .installed:
                // Sparkle presents its own “up to date” UI.
                controller.pendingUserCheck = .none
                controller.finishChecking()
            case .none:
                break
            }
        }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        DispatchQueue.main.async {
            let controller = UpdateController.shared
            // Do not clear `.notInstalled` here — didFind / didNotFind own that
            // popup. Clearing early caused “spinner stops, no alert”.
            switch controller.pendingUserCheck {
            case .notInstalled:
                if let error, !controller.isNoUpdateError(error) {
                    controller.pendingUserCheck = .none
                    controller.finishChecking()
                    controller.presentCheckFailed(error.localizedDescription)
                }
            case .installed:
                controller.pendingUserCheck = .none
                controller.finishChecking()
            case .none:
                if controller.isCheckingForUpdates {
                    controller.finishChecking()
                }
            }

            if let error, !controller.isNoUpdateError(error) {
                NSLog("[NumWorks] Sparkle cycle finished with error: %@", error as NSError)
            }
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        NSLog(
            "[NumWorks] Sparkle will install update %@ (%@)",
            item.displayVersionString,
            item.versionString)
        DispatchQueue.main.async {
            let controller = UpdateController.shared
            controller.pendingUserCheck = .none
            controller.finishChecking()
            controller.activateForAlert()
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
            let controller = UpdateController.shared
            let shouldAlert = controller.pendingUserCheck != .none
            controller.pendingUserCheck = .none
            controller.finishChecking()
            if shouldAlert {
                controller.presentCheckFailed(nsError.localizedDescription)
            }
        }
    }

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        Bundle.main.isInstalled
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        DispatchQueue.main.async {
            let controller = UpdateController.shared
            if Bundle.main.isInstalled {
                // Sparkle is showing its update UI — drop our spinner.
                if controller.pendingUserCheck == .installed {
                    controller.pendingUserCheck = .none
                    controller.finishChecking()
                }
                controller.activateForAlert()
                return
            }

            // Outside Applications: always our move-required alert.
            if controller.pendingUserCheck == .notInstalled {
                controller.pendingUserCheck = .none
                controller.finishChecking()
            }
            controller.presentMoveRequiredForUpdate(update)
        }
    }
}
