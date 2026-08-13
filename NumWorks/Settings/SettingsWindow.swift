import AppKit
import SwiftUI

/// Creates and presents the single Settings window.
///
/// The app has a custom main entry point (Epsilon owns the run loop through
/// SDL), so the SwiftUI `Settings` scene is unavailable; a plain
/// NSWindowController hosting SwiftUI is used instead.
@MainActor
final class SettingsWindowController: NSWindowController {

    private let preferences: Preferences
    private let onClose: () -> Void
    private var closeObserver: NSObjectProtocol?

    init(preferences: Preferences, actions: SettingsActions, onClose: @escaping () -> Void) {
        self.preferences = preferences
        self.onClose = onClose

        let hosting = NSHostingController(
            rootView: SettingsRootView(preferences: preferences, actions: actions))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "NumWorks Settings"
        window.setAccessibilityIdentifier("settings-window")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onClose()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
    }

    /// Shows the window, or brings the existing one forward.
    func show() {
        guard let window else { return }
        // If the calculator is pinned at .floating level, a .normal-level
        // Settings window would open behind it; match the level so Settings
        // stays usable.
        window.level = preferences.alwaysOnTop ? .floating : .normal
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
