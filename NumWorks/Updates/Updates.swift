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

    /// Standard Sparkle controller: automatic background checks + UI.
    private(set) var updaterController: SPUStandardUpdaterController!

    /// User preference for scheduled background checks. Kept as local published
    /// state so Settings does not flicker when a manual check is in progress
    /// (Sparkle temporarily clears `canCheckForUpdates` during a session).
    @Published var automaticallyChecksForUpdates: Bool = true {
        didSet {
            guard !isApplyingSparkleValue else { return }
            let updater = updaterController.updater
            if updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates {
                updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
        }
    }

    /// Whether Sparkle will accept a user-initiated check right now.
    @Published private(set) var canCheckForUpdates = false

    /// App is under an Applications directory (required for Sparkle installs).
    @Published private(set) var isInstalledInApplications = false

    private var isApplyingSparkleValue = false
    private var canCheckObservation: NSKeyValueObservation?
    private var automaticChecksObservation: NSKeyValueObservation?

    private override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self)

        isInstalledInApplications = Bundle.main.isInstalled
        applySparkleAutomaticChecksToPublished()
        refreshCanCheckForUpdates()

        let updater = updaterController.updater
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshCanCheckForUpdates()
            }
        }
        automaticChecksObservation = updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.applySparkleAutomaticChecksToPublished()
            }
        }
    }

    /// User-initiated “Check for Updates…” (menu / Settings).
    @objc func checkForUpdates(_ sender: Any?) {
        guard isInstalledInApplications else { return }
        updaterController.checkForUpdates(sender)
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) {
            return canCheckForUpdates
        }
        return true
    }

    private func applySparkleAutomaticChecksToPublished() {
        let value = updaterController.updater.automaticallyChecksForUpdates
        guard automaticallyChecksForUpdates != value else { return }
        isApplyingSparkleValue = true
        automaticallyChecksForUpdates = value
        isApplyingSparkleValue = false
    }

    private func refreshCanCheckForUpdates() {
        canCheckForUpdates =
            isInstalledInApplications && updaterController.updater.canCheckForUpdates
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
