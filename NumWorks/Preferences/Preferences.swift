import AppKit
import Combine

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
        static let hideShowShortcutEnabled = "hideShowShortcutEnabled"
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
        Key.hideShowShortcutEnabled: true,
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
        hideShowShortcutEnabled = defaults.bool(forKey: Key.hideShowShortcutEnabled)
        windowStyle = defaults.string(forKey: Key.windowStyle)
            .flatMap(WindowStyle.init(rawValue:)) ?? .toolbar
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

    @Published var hideShowShortcutEnabled: Bool {
        didSet { defaults.set(hideShowShortcutEnabled, forKey: Key.hideShowShortcutEnabled) }
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

    func resetToDefaults() {
        showTopBar = true
        alwaysOnTop = false
        showPinButton = true
        showSettingsButton = true
        rememberWindowPosition = true
        rememberWindowSize = true
        hideShowShortcutEnabled = true
        windowStyle = .toolbar
        launchWindowVisible = true
        moveWindowToCurrentSpaceWhenShown = true
        savedWindowFrame = nil
    }
}
