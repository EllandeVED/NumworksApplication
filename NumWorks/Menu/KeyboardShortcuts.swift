import AppKit
#if canImport(KeyboardShortcuts)
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global show/hide shortcut. Default: Option + Command + N.
    static let toggleCalculator = Self(
        "toggleCalculator",
        default: .init(.n, modifiers: [.option, .command]))
}
#endif

/// Wraps the KeyboardShortcuts package (sindresorhus/KeyboardShortcuts).
///
/// The package registers a Carbon hot key, so the shortcut works while any
/// application is active and needs no accessibility permission. Handlers are
/// registered once, in init; AppController owns the single instance, so no
/// duplicate handlers can accumulate.
@MainActor
final class ShortcutController {

    private let preferences: Preferences
    private let toggleCalculator: () -> Void

    init(preferences: Preferences, toggleCalculator: @escaping () -> Void) {
        self.preferences = preferences
        self.toggleCalculator = toggleCalculator

#if canImport(KeyboardShortcuts)
        // The package invokes handlers on the main thread. Enablement is
        // checked at invocation time so the preference applies immediately.
        KeyboardShortcuts.onKeyUp(for: .toggleCalculator) { [weak self] in
            guard let self, self.preferences.hideShowShortcutEnabled else { return }
            self.toggleCalculator()
        }
#endif
    }

    /// Restores the default Option + Command + N shortcut.
    func resetShortcutToDefault() {
#if canImport(KeyboardShortcuts)
        KeyboardShortcuts.reset(.toggleCalculator)
#endif
    }
}
