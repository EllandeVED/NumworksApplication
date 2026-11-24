import AppKit
import Combine
import Sparkle

/// Sparkle owns progress, cancellation, installation, and error UI.
/// NumWorks adds the Applications requirement and one automatic-check timer.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = UpdateController()
    static let defaultPostLaunchCheckDelay: TimeInterval = 3
    private static let parkedSparkleInterval: TimeInterval = 365 * 24 * 60 * 60

    private var updater: SPUUpdater!
    private var userDriver: MoveRequiredUpdateDriver!
    private var automaticCheckTimer: Timer?
    private var canCheckObservation: NSKeyValueObservation?
    private var lastCheckObservation: NSKeyValueObservation?
    private var schedule = UpdateCheckSchedule()
    private var movePrompt = UpdateMovePromptState()
    private var movePromptScheduled = false
    private var activeCheck = false
    private var checkSucceeded = false
    private var checkAfterMove = UpdateRelaunch.requested(
        environment: ProcessInfo.processInfo.environment, isInstalled: Bundle.main.isInstalled)

    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var canCheckForUpdates = false
    /// Sparkle's last attempt time (including failed checks).
    @Published private(set) var lastUpdateCheckDate: Date?

    /// Restores Dock / activation policy after update UI forced `.regular`.
    var restoreActivationPolicy: (() -> Void)?

    private override init() {
        super.init()
        // This handoff belongs to the relocated process, not its children.
        unsetenv(UpdateRelaunch.environmentKey)
        userDriver = MoveRequiredUpdateDriver(hostBundle: .main, delegate: self)
        userDriver.moveRequired = { [weak self] item in
            self?.queueMoveRequired(for: item)
        }
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                             userDriver: userDriver, delegate: self)
        schedule = UpdateCheckSchedule(defaults: .standard,
                                       previousAttempt: updater.lastUpdateCheckDate)
        // Our single timer owns daily checks and retries. The delegate also
        // gates Sparkle's startup and cached-update checks against this schedule.
        updater.updateCheckInterval = Self.parkedSparkleInterval
        observeUpdater()
        do {
            try updater.start()
        } catch {
            NSLog("[NumWorks] Sparkle could not start: %@", error as NSError)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.userDriver.showUpdaterError(error, acknowledgement: {})
            }
        }
    }

    // MARK: - Checks and schedule

    @objc func checkForUpdates(_ sender: Any?) {
        guard updater.canCheckForUpdates, !isCheckingForUpdates,
              !movePrompt.isPresenting else { return }
        automaticCheckTimer?.invalidate()
        automaticCheckTimer = nil
        checkAfterMove = false
        // Sparkle can also bring an existing update back into focus.
        if !updater.sessionInProgress { isCheckingForUpdates = true }
        updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            updater.automaticallyChecksForUpdates = newValue
            scheduleAutomaticCheck()
        }
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(checkForUpdates(_:))
            || (canCheckForUpdates && !isCheckingForUpdates)
    }

    func schedulePostLaunchUpdateCheck(after delay: TimeInterval = 3) {
        // Called after the startup AppMover modal returns, even with auto checks
        // disabled. Update-specific prompts are independent of its reminder cap.
        movePrompt.startupComplete = true
        scheduleMovePrompt()
        scheduleAutomaticCheck(after: delay)
    }

    private func scheduleAutomaticCheck(after delay: TimeInterval = 3) {
        automaticCheckTimer?.invalidate()
        automaticCheckTimer = nil
        guard movePrompt.startupComplete, !UITesting.skipAutomaticUpdateChecks,
              !movePrompt.isPresenting, movePrompt.pendingVersion == nil,
              updater.canCheckForUpdates, !updater.sessionInProgress else { return }
        // Moving for an update is an explicit request, even with auto checks off.
        guard checkAfterMove || automaticallyChecksForUpdates else { return }
        let interval = max(0.5, delay, checkAfterMove ? 0 : schedule.delay(at: Date()))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.performScheduledCheck() }
        }
        timer.tolerance = min(60, interval / 10)
        RunLoop.main.add(timer, forMode: .default)
        automaticCheckTimer = timer
    }

    private func performScheduledCheck() {
        automaticCheckTimer = nil
        guard updater.canCheckForUpdates, !updater.sessionInProgress,
              !movePrompt.isPresenting else { return }
        if checkAfterMove {
            checkForUpdates(nil)
        } else if automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        }
    }

    private func observeUpdater() {
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshCheckingState()
                self.scheduleAutomaticCheck()
            }
        }
        lastCheckObservation = updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) {
            [weak self] _, _ in
            Task { @MainActor in self?.lastUpdateCheckDate = self?.updater.lastUpdateCheckDate }
        }
    }

    private func refreshCheckingState() {
        canCheckForUpdates = updater.canCheckForUpdates
            && !isCheckingForUpdates && !movePrompt.isPresenting
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }

    private func foundUpdateInformation() {
        if !checkSucceeded {
            checkSucceeded = true
            schedule.completed(succeeded: true, at: Date())
            schedule.save(to: .standard)
        }
        isCheckingForUpdates = false
        refreshCheckingState()
    }

    // MARK: - Move-first prompt

    private func queueMoveRequired(for update: SUAppcastItem) {
        movePrompt.request(version: update.displayVersionString)
        scheduleMovePrompt()
    }

    private func scheduleMovePrompt() {
        guard !movePromptScheduled, movePrompt.pendingVersion != nil else { return }
        movePromptScheduled = true
        // Default mode waits for modal UI to finish. A main-queue dispatch alone
        // can execute inside AppMover's nested modal loop.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.movePromptScheduled = false
                self.presentPendingMovePrompt()
            }
        }
    }

    private func presentPendingMovePrompt() {
        guard let version = movePrompt.takePending(
            sessionInProgress: updater.sessionInProgress) else { return }
        refreshCheckingState()
        activateForAlert()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Update Found"
        alert.informativeText = "NumWorks \(version) is available. Move NumWorks to the "
            + "Applications folder first so the update can be installed."
        alert.addButton(withTitle: "Move to Applications Folder")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            AppMover.moveIfNecessary(prompt: false, checkForUpdatesAfterMove: true)
        }
        movePrompt.finishedPresenting()
        refreshCheckingState()
        restoreActivationPolicy?()
        scheduleAutomaticCheck()
    }

    private func activateForAlert() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func isExpectedEnd(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SUSparkleErrorDomain && [
            Int(SUError.noUpdateError.rawValue), Int(SUError.installationCanceledError.rawValue),
            Int(SUError.installationAuthorizeLaterError.rawValue),
        ].contains(error.code)
    }

    // MARK: - SPUUpdaterDelegate (Sparkle invokes these on the main thread)

    nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        try MainActor.assumeIsolated {
            if updateCheck == .updatesInBackground {
                guard movePrompt.startupComplete, automaticallyChecksForUpdates,
                      !UITesting.skipAutomaticUpdateChecks, !movePrompt.isPresenting,
                      movePrompt.pendingVersion == nil, schedule.delay(at: Date()) == 0 else {
                    throw NSError(domain: SUSparkleErrorDomain,
                                  code: Int(SUError.installationCanceledError.rawValue),
                                  userInfo: [NSLocalizedDescriptionKey: "Automatic check deferred."])
                }
            }
            activeCheck = true
            checkSucceeded = false
            schedule.beganAttempt(at: Date())
            schedule.save(to: .standard)
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem,
                             updateCheck: SPUUpdateCheck) throws {
        try MainActor.assumeIsolated {
            foundUpdateInformation()
            guard Bundle.main.isInstalled else {
                queueMoveRequired(for: item)
                // Stop before automatic download / installation. Sparkle treats
                // this as a quiet cancellation and completes its own session.
                throw NSError(domain: SUSparkleErrorDomain,
                              code: Int(SUError.installationCanceledError.rawValue),
                              userInfo: [NSLocalizedDescriptionKey: "Move to Applications first."])
            }
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { foundUpdateInformation() }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        // Sparkle shows “up to date” for manual checks and stays quiet otherwise.
        MainActor.assumeIsolated { foundUpdateInformation() }
    }

    nonisolated func updater(_ updater: SPUUpdater,
                             didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        MainActor.assumeIsolated {
            if activeCheck && !checkSucceeded {
                schedule.completed(succeeded: false, at: Date())
                schedule.save(to: .standard)
            }
            activeCheck = false
            isCheckingForUpdates = false
            refreshCheckingState()
            if let error, !isExpectedEnd(error) {
                NSLog("[NumWorks] Sparkle check finished with error: %@", error as NSError)
                Telemetry.trackError(error)
            }
            scheduleMovePrompt()
            scheduleAutomaticCheck()
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated {
            Telemetry.track("update_downloaded", [
                "version": item.displayVersionString, "build": item.versionString,
            ])
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated {
            isCheckingForUpdates = false
            refreshCheckingState()
            activateForAlert()
        }
    }

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated {
            isCheckingForUpdates = false
            refreshCheckingState()
            activateForAlert()
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { restoreActivationPolicy?() }
    }
}
