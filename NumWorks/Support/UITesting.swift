import Foundation

/// Launch-argument / environment hooks used by XCTest (and optional manual Debug runs).
///
/// UI tests always pass `--ui-testing`. Hosted unit tests set `XCTestConfigurationFilePath`,
/// which we also treat as testing so AppMover / Sparkle never block the suite.
enum UITesting {

    /// Master switch: XCTest host/UI launch, or explicit `--ui-testing`.
    static var isEnabled: Bool {
        if argumentsContain("--ui-testing") { return true }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return false
    }

    /// Skip the Move-to-Applications modal unless `--allow-app-mover` is set.
    static var skipAppMover: Bool {
        isEnabled && !argumentsContain("--allow-app-mover")
    }

    /// Skip post-launch Sparkle checks unless `--allow-update-checks` is set.
    static var skipAutomaticUpdateChecks: Bool {
        isEnabled && !argumentsContain("--allow-update-checks")
    }

    /// Open Settings after attach (`--show-settings`, or by default under `--ui-testing`).
    /// Settings is a normal AppKit window; the SDL calculator often never appears in
    /// Accessibility, so Settings is the readiness surface for UI tests.
    static var shouldOpenSettingsOnLaunch: Bool {
        guard isEnabled || isDebugBuild else { return false }
        if argumentsContain("--no-settings") { return false }
        if argumentsContain("--show-settings") { return true }
        return isEnabled
    }

    /// Show the calculator after attach (`--show-calculator`).
    static var shouldShowCalculatorOnLaunch: Bool {
        guard isEnabled || isDebugBuild else { return false }
        return argumentsContain("--show-calculator")
    }

    /// Optional Settings tab from `--settings-tab=<name>`.
    static var settingsTabArgument: SettingsTab? {
        guard isEnabled || isDebugBuild else { return nil }
        for argument in ProcessInfo.processInfo.arguments {
            guard argument.hasPrefix("--settings-tab=") else { continue }
            let raw = String(argument.dropFirst("--settings-tab=".count))
            return SettingsTab(rawValue: raw)
        }
        return nil
    }

    // MARK: - Private

    private static var isDebugBuild: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    private static func argumentsContain(_ flag: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
    }
}
