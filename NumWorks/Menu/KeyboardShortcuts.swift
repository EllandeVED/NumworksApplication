import AppKit
#if canImport(KeyboardShortcuts)
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global show/hide shortcut. Default: Option + Command + N.
    static let toggleCalculator = Self(
        "toggleCalculator",
        default: .init(.n, modifiers: [.option, .command]))

    /// Global always-on-top shortcut. Default: Option + Command + P.
    static let toggleAlwaysOnTop = Self(
        "toggleAlwaysOnTop",
        default: .init(.p, modifiers: [.option, .command]))
}
#endif

/// Wraps the KeyboardShortcuts package (sindresorhus/KeyboardShortcuts).
///
/// The package registers Carbon hot keys, so the shortcuts work while any
/// application is active and need no accessibility permission. Recorder
/// changes made in Settings persist automatically inside the package.
/// Handlers are registered once, in init; AppController owns the single
/// instance, so no duplicate handlers can accumulate.
@MainActor
final class ShortcutController {

    private let preferences: Preferences
    private let toggleCalculator: () -> Void
    private let toggleAlwaysOnTop: () -> Void

    init(
        preferences: Preferences,
        toggleCalculator: @escaping () -> Void,
        toggleAlwaysOnTop: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.toggleCalculator = toggleCalculator
        self.toggleAlwaysOnTop = toggleAlwaysOnTop

#if canImport(KeyboardShortcuts)
        // The package invokes handlers on the main thread. Enablement is
        // checked at invocation time so the preference applies immediately.
        KeyboardShortcuts.onKeyUp(for: .toggleCalculator) { [weak self] in
            guard let self, self.preferences.shortcutsEnabled else { return }
            self.toggleCalculator()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleAlwaysOnTop) { [weak self] in
            guard let self, self.preferences.shortcutsEnabled else { return }
            self.toggleAlwaysOnTop()
        }
#endif
    }

    /// Restores both default shortcuts (⌥⌘N and ⌥⌘P).
    func resetShortcutsToDefaults() {
#if canImport(KeyboardShortcuts)
        KeyboardShortcuts.reset(.toggleCalculator, .toggleAlwaysOnTop)
#endif
    }
}
