import AppKit
import Combine
#if canImport(LaunchAtLogin)
import LaunchAtLogin
#endif

/// Central preferences model. This is the only type in the app that reads or
/// writes UserDefaults; every other feature goes through it.
@MainActor
final class Preferences: ObservableObject {

    private enum Key {
        static let showTopBar = "showTopBar"
        static let alwaysOnTop = "alwaysOnTop"
        static let showPinButton = "showPinButton"
        static let showSettingsButton = "showSettingsButton"
        static let rememberWindowPosition = "rememberWindowPosition"
        static let rememberWindowSize = "rememberWindowSize"
        static let shortcutsEnabled = "shortcutsEnabled"
        static let showDockIcon = "showDockIcon"
        static let windowStyle = "windowStyle"
        static let launchWindowVisible = "launchWindowVisible"
        static let moveWindowToCurrentSpaceWhenShown = "moveWindowToCurrentSpaceWhenShown"
        static let savedWindowFrame = "savedWindowFrame"
    }

    private static let defaultValues: [String: Any] = [
        Key.showTopBar: true,
        Key.alwaysOnTop: false,
        Key.showPinButton: true,
        Key.showSettingsButton: true,
        Key.rememberWindowPosition: true,
        Key.rememberWindowSize: true,
        Key.shortcutsEnabled: true,
        Key.showDockIcon: true,
        Key.windowStyle: WindowStyle.toolbar.rawValue,
        Key.launchWindowVisible: true,
        Key.moveWindowToCurrentSpaceWhenShown: true,
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Self.defaultValues)

        showTopBar = defaults.bool(forKey: Key.showTopBar)
        alwaysOnTop = defaults.bool(forKey: Key.alwaysOnTop)
        showPinButton = defaults.bool(forKey: Key.showPinButton)
        showSettingsButton = defaults.bool(forKey: Key.showSettingsButton)
        rememberWindowPosition = defaults.bool(forKey: Key.rememberWindowPosition)
        rememberWindowSize = defaults.bool(forKey: Key.rememberWindowSize)
        shortcutsEnabled = defaults.bool(forKey: Key.shortcutsEnabled)
        showDockIcon = defaults.bool(forKey: Key.showDockIcon)
        launchAtLogin = Self.systemLaunchAtLogin
        // Coerce unavailable styles (minimal) so the Settings picker, which
        // only offers the available styles, never shows an empty selection.
        let storedStyle = defaults.string(forKey: Key.windowStyle)
            .flatMap(WindowStyle.init(rawValue:)) ?? .toolbar
        windowStyle = storedStyle.isAvailable ? storedStyle : .toolbar
        launchWindowVisible = defaults.bool(forKey: Key.launchWindowVisible)
        moveWindowToCurrentSpaceWhenShown =
            defaults.bool(forKey: Key.moveWindowToCurrentSpaceWhenShown)
        savedWindowFrame = defaults.string(forKey: Key.savedWindowFrame)
    }

    // MARK: - Settings

    @Published var showTopBar: Bool {
        didSet { defaults.set(showTopBar, forKey: Key.showTopBar) }
    }

    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Key.alwaysOnTop) }
    }

    @Published var showPinButton: Bool {
        didSet { defaults.set(showPinButton, forKey: Key.showPinButton) }
    }

    @Published var showSettingsButton: Bool {
        didSet { defaults.set(showSettingsButton, forKey: Key.showSettingsButton) }
    }

    @Published var rememberWindowPosition: Bool {
        didSet { defaults.set(rememberWindowPosition, forKey: Key.rememberWindowPosition) }
    }

    @Published var rememberWindowSize: Bool {
        didSet { defaults.set(rememberWindowSize, forKey: Key.rememberWindowSize) }
    }

    /// Master switch for both global keyboard shortcuts.
    @Published var shortcutsEnabled: Bool {
        didSet { defaults.set(shortcutsEnabled, forKey: Key.shortcutsEnabled) }
    }

    /// Whether the app appears in the Dock (NSApp activation policy .regular
    /// vs .accessory). Applied by AppController.
    @Published var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Key.showDockIcon) }
    }

    /// Login-item registration. The system (via the LaunchAtLogin package /
    /// SMAppService) is the source of truth, so this is deliberately not
    /// persisted in UserDefaults; the value is read back from the system at
    /// startup and written through on change.
    @Published var launchAtLogin: Bool {
        didSet { Self.systemLaunchAtLogin = launchAtLogin }
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

    // MARK: - Window frame persistence (not shown in the Settings UI)

    /// The last saved calculator window frame, encoded with NSStringFromRect.
    /// Managed by CalculatorWindow; not user-facing.
    var savedWindowFrame: String? {
        didSet { defaults.set(savedWindowFrame, forKey: Key.savedWindowFrame) }
    }

    // MARK: - Reset

    /// Restores every application preference to its default value. The saved
    /// window frame is deliberately left untouched: window position and size
    /// have their own dedicated reset buttons in Settings.
    func resetToDefaults() {
        showTopBar = true
        alwaysOnTop = false
        showPinButton = true
        showSettingsButton = true
        rememberWindowPosition = true
        rememberWindowSize = true
        shortcutsEnabled = true
        showDockIcon = true
        launchAtLogin = false
        windowStyle = .toolbar
        launchWindowVisible = true
        moveWindowToCurrentSpaceWhenShown = true
    }
}
