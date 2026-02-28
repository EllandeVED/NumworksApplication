import Foundation
import CoreGraphics

final class Preferences: ObservableObject {
    static let shared = Preferences()
    // UserDefaults keys used to persist *current settings*
    private enum Keys {
        static let menuBarIconStyle = "prefs.menuBarIconStyle"
        static let menuBarIconSize = "prefs.menuBarIconSize"
        static let isMenuBarIconEnabled = "prefs.isMenuBarIconEnabled"
        static let showPinButtonOnCalculator = "prefs.showPinButtonOnCalculator"
        static let showDockIcon = "prefs.showDockIcon"
        static let isPinned = "prefs.isPinned"
        static let webInjectionDisabled = "prefs.webInjectionDisabled"
        static let calculatorImageHidden = "prefs.calculatorImageHidden"
        static let checkForAppUpdatesAutomatically = "prefs.checkForAppUpdatesAutomatically"
        static let checkForEpsilonUpdatesAutomatically = "prefs.checkForEpsilonUpdatesAutomatically"
        static let use3DCalculatorImage = "prefs.use3DCalculatorImage"
    }

    // MARK: - Current settings (persisted)
    // These properties represent the *current user-selected settings*.
    // Any change is immediately written to UserDefaults in `didSet`.
    @Published var menuBarIconStyle: MenuBarIconStyle {
        didSet { d.set(menuBarIconStyle.rawValue, forKey: Keys.menuBarIconStyle) }
    }

    @Published var menuBarIconSize: CGFloat {
        didSet { d.set(Double(menuBarIconSize), forKey: Keys.menuBarIconSize) }
    }

    @Published var isMenuBarIconEnabled: Bool {
        didSet { d.set(isMenuBarIconEnabled, forKey: Keys.isMenuBarIconEnabled) }
    }

    @Published var showPinButtonOnCalculator: Bool {
        didSet { d.set(showPinButtonOnCalculator, forKey: Keys.showPinButtonOnCalculator) }
    }

    @Published var showDockIcon: Bool {
        didSet { d.set(showDockIcon, forKey: Keys.showDockIcon) }
    }

    @Published var isPinned: Bool {
        didSet { d.set(isPinned, forKey: Keys.isPinned) }
    }

    @Published var webInjectionDisabled: Bool {
        didSet { d.set(webInjectionDisabled, forKey: Keys.webInjectionDisabled) }
    }

    @Published var calculatorImageHidden: Bool {
        didSet { d.set(calculatorImageHidden, forKey: Keys.calculatorImageHidden) }
    }

    @Published var checkForAppUpdatesAutomatically: Bool {
        didSet { d.set(checkForAppUpdatesAutomatically, forKey: Keys.checkForAppUpdatesAutomatically) }
    }

    @Published var checkForEpsilonUpdatesAutomatically: Bool {
        didSet { d.set(checkForEpsilonUpdatesAutomatically, forKey: Keys.checkForEpsilonUpdatesAutomatically) }
    }

    @Published var use3DCalculatorImage: Bool {
        didSet { d.set(use3DCalculatorImage, forKey: Keys.use3DCalculatorImage) }
    }

    // MARK: - Session-only state (not persisted)
    // These values describe the current runtime state only
    // and are intentionally NOT stored in UserDefaults.
    @Published var isAppVisible: Bool = true

    private let d = UserDefaults.standard

    private init() {
        // MARK: - Initialization
        // On first launch: UserDefaults has no values → defaults are used.
        // On subsequent launches: stored values are loaded as the current settings.

        // Default menu bar icon style: .filled
        let styleRaw = d.string(forKey: Keys.menuBarIconStyle) ?? MenuBarIconStyle.filled.rawValue
        menuBarIconStyle = MenuBarIconStyle(rawValue: styleRaw) ?? .filled

        // Default menu bar icon size: 20pt
        let size = d.object(forKey: Keys.menuBarIconSize) as? Double ?? 20
        menuBarIconSize = CGFloat(size)

        // Default boolean settings used only on first launch
        isMenuBarIconEnabled = d.object(forKey: Keys.isMenuBarIconEnabled) as? Bool ?? true
        showPinButtonOnCalculator = d.object(forKey: Keys.showPinButtonOnCalculator) as? Bool ?? true
        showDockIcon = d.object(forKey: Keys.showDockIcon) as? Bool ?? true
        isPinned = d.object(forKey: Keys.isPinned) as? Bool ?? false
        webInjectionDisabled = d.object(forKey: Keys.webInjectionDisabled) as? Bool ?? false
        calculatorImageHidden = d.object(forKey: Keys.calculatorImageHidden) as? Bool ?? false
        checkForAppUpdatesAutomatically = d.object(forKey: Keys.checkForAppUpdatesAutomatically) as? Bool ?? true
        checkForEpsilonUpdatesAutomatically = d.object(forKey: Keys.checkForEpsilonUpdatesAutomatically) as? Bool ?? true
        use3DCalculatorImage = d.object(forKey: Keys.use3DCalculatorImage) as? Bool ?? true
    }
}
