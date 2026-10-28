import AppKit
import Combine
#if canImport(LaunchAtLogin)
import LaunchAtLogin
#endif

/// Central preferences model for app settings. Feature code should go through
/// this type rather than writing keys ad hoc (Sparkle / KeyboardShortcuts /
/// LaunchAtLogin keep their own stores).
@MainActor
final class Preferences: ObservableObject {

    private enum Key {
        static let alwaysOnTop = "alwaysOnTop"
        static let showPinButton = "showPinButton"
        static let showSettingsButton = "showSettingsButton"
        static let shortcutsEnabled = "shortcutsEnabled"
        static let showDockIcon = "showDockIcon"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let menuBarIconStyle = "menuBarIconStyle"
        static let windowStyle = "windowStyle"
        static let launchWindowVisible = "launchWindowVisible"
        static let moveWindowToCurrentSpaceWhenShown = "moveWindowToCurrentSpaceWhenShown"
        static let savedWindowFrame = "savedWindowFrame"
        static let appMoverOfferVersion = "appMoverOfferVersion"
        static let appMoverOfferCount = "appMoverOfferCount"
        static let telemetryEnabled = "telemetryEnabled"
        static let telemetryFirstLaunchVersion = "telemetryFirstLaunchVersion"
        /// Marks that launch-at-login was set explicitly (or via our default-on).
        static let launchAtLoginConfigured = "launchAtLoginConfigured"
    }

    /// How many AppMover prompts to show per app version when not in Applications.
    static let appMoverOffersPerVersion = 2

    private static let defaultValues: [String: Any] = [
        Key.alwaysOnTop: false,
        Key.showPinButton: true,
        Key.showSettingsButton: true,
        Key.shortcutsEnabled: true,
        Key.showDockIcon: true,
        Key.showMenuBarIcon: true,
        Key.menuBarIconStyle: MenuBarIconStyle.filled.rawValue,
        Key.windowStyle: WindowStyle.toolbar.rawValue,
        Key.launchWindowVisible: false,
        Key.moveWindowToCurrentSpaceWhenShown: true,
        Key.appMoverOfferCount: 0,
        Key.telemetryEnabled: true,
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Self.defaultValues)

        alwaysOnTop = defaults.bool(forKey: Key.alwaysOnTop)
        showPinButton = defaults.bool(forKey: Key.showPinButton)
        showSettingsButton = defaults.bool(forKey: Key.showSettingsButton)
        shortcutsEnabled = defaults.bool(forKey: Key.shortcutsEnabled)
        showDockIcon = defaults.bool(forKey: Key.showDockIcon)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        menuBarIconStyle = defaults.string(forKey: Key.menuBarIconStyle)
            .flatMap(MenuBarIconStyle.init(rawValue:)) ?? .filled
        if defaults.object(forKey: Key.launchAtLoginConfigured) == nil {
            // Fresh install only: default launch-at-login on. Upgrades keep
            // whatever Login Items already say (including an explicit off).
            let isUpgrade = defaults.object(forKey: Key.showDockIcon) != nil
                || defaults.object(forKey: Key.windowStyle) != nil
                || defaults.object(forKey: Key.showMenuBarIcon) != nil
            if !isUpgrade {
                Self.systemLaunchAtLogin = true
            }
            defaults.set(true, forKey: Key.launchAtLoginConfigured)
        }
        launchAtLogin = Self.systemLaunchAtLogin
        let storedStyle = defaults.string(forKey: Key.windowStyle)
            .flatMap(WindowStyle.init(rawValue:)) ?? .toolbar
        windowStyle = storedStyle.isAvailable ? storedStyle : .toolbar
        launchWindowVisible = defaults.bool(forKey: Key.launchWindowVisible)
        moveWindowToCurrentSpaceWhenShown =
            defaults.bool(forKey: Key.moveWindowToCurrentSpaceWhenShown)
        telemetryEnabled = defaults.bool(forKey: Key.telemetryEnabled)
        savedWindowFrame = defaults.string(forKey: Key.savedWindowFrame)
    }

    // MARK: - Settings

    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Key.alwaysOnTop) }
    }

    @Published var showPinButton: Bool {
        didSet { defaults.set(showPinButton, forKey: Key.showPinButton) }
    }

    @Published var showSettingsButton: Bool {
        didSet { defaults.set(showSettingsButton, forKey: Key.showSettingsButton) }
    }

    @Published var shortcutsEnabled: Bool {
        didSet { defaults.set(shortcutsEnabled, forKey: Key.shortcutsEnabled) }
    }

    @Published var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: Key.showDockIcon)
            // LSUIElement app: keep at least one way to reach the UI.
            if !showDockIcon && !showMenuBarIcon {
                showMenuBarIcon = true
            }
        }
    }

    @Published var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon)
            if !showMenuBarIcon && !showDockIcon {
                showDockIcon = true
            }
        }
    }

    @Published var menuBarIconStyle: MenuBarIconStyle {
        didSet { defaults.set(menuBarIconStyle.rawValue, forKey: Key.menuBarIconStyle) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            Self.systemLaunchAtLogin = launchAtLogin
            defaults.set(true, forKey: Key.launchAtLoginConfigured)
        }
    }

    static var isLaunchAtLoginAvailable: Bool {
#if canImport(LaunchAtLogin)
        return true
#else
        return false
#endif
    }

    private static var systemLaunchAtLogin: Bool {
        get {
#if canImport(LaunchAtLogin)
            return LaunchAtLogin.isEnabled
#else
            return false
#endif
        }
        set {
#if canImport(LaunchAtLogin)
            LaunchAtLogin.isEnabled = newValue
#endif
        }
    }

    @Published var windowStyle: WindowStyle {
        didSet { defaults.set(windowStyle.rawValue, forKey: Key.windowStyle) }
    }

    @Published var launchWindowVisible: Bool {
        didSet { defaults.set(launchWindowVisible, forKey: Key.launchWindowVisible) }
    }

    @Published var moveWindowToCurrentSpaceWhenShown: Bool {
        didSet {
            defaults.set(
                moveWindowToCurrentSpaceWhenShown,
                forKey: Key.moveWindowToCurrentSpaceWhenShown)
        }
    }

    /// Anonymous Aptabase usage/error reports. Opt-out; off means nothing is sent.
    @Published var telemetryEnabled: Bool {
        didSet {
            defaults.set(telemetryEnabled, forKey: Key.telemetryEnabled)
            Telemetry.applyPreferenceChange()
        }
    }

    /// Last `AppInfo.appVersion` for which `first_launch` was sent (not a Settings UI field).
    var telemetryFirstLaunchVersion: String? {
        get { defaults.string(forKey: Key.telemetryFirstLaunchVersion) }
        set { defaults.set(newValue, forKey: Key.telemetryFirstLaunchVersion) }
    }

    // MARK: - Window frame persistence (not shown in the Settings UI)

    var savedWindowFrame: String? {
        didSet { defaults.set(savedWindowFrame, forKey: Key.savedWindowFrame) }
    }

    // MARK: - AppMover (not shown in Settings)

    /// Version string used for the two-offer-per-version counter.
    /// Tests may override; production leaves the default (`AppInfo.appVersion`).
    var appMoverVersionProvider: () -> String = { AppInfo.appVersion }

    /// Reset the two-launch offer counter when the marketing/build version changes
    /// (including after Sparkle updates).
    func synchronizeAppMoverOffers(withVersion version: String) {
        let previous = defaults.string(forKey: Key.appMoverOfferVersion)
        guard previous != version else { return }
        defaults.set(version, forKey: Key.appMoverOfferVersion)
        defaults.set(0, forKey: Key.appMoverOfferCount)
    }

    /// Whether we should still show the Move-to-Applications prompt this launch.
    var shouldOfferAppMover: Bool {
        synchronizeAppMoverOffers(withVersion: appMoverVersionProvider())
        return defaults.integer(forKey: Key.appMoverOfferCount) < Self.appMoverOffersPerVersion
    }

    func recordAppMoverOfferShown() {
        synchronizeAppMoverOffers(withVersion: appMoverVersionProvider())
        let next = defaults.integer(forKey: Key.appMoverOfferCount) + 1
        defaults.set(next, forKey: Key.appMoverOfferCount)
    }

    // MARK: - Reset

    func resetToDefaults() {
        alwaysOnTop = false
        showPinButton = true
        showSettingsButton = true
        shortcutsEnabled = true
        showDockIcon = true
        showMenuBarIcon = true
        menuBarIconStyle = .filled
        launchAtLogin = true
        windowStyle = .toolbar
        launchWindowVisible = false
        moveWindowToCurrentSpaceWhenShown = true
        telemetryEnabled = true
    }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case outline
    case filled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .outline: return "Outline"
        case .filled: return "Filled"
        }
    }

    var imageName: String {
        switch self {
        case .outline: return "MenuBarIconOutline"
        case .filled: return "MenuBarIconFilled"
        }
    }
}
