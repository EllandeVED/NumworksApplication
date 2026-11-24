import AppKit
import SwiftUI

@MainActor
final class SettingsWindowActivity: ObservableObject {
    @Published var isVisible = false
}

private struct SettingsWindowVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var settingsWindowVisible: Bool {
        get { self[SettingsWindowVisibleKey.self] }
        set { self[SettingsWindowVisibleKey.self] = newValue }
    }
}

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
    private let activity = SettingsWindowActivity()
    private var visibilityObservers: [NSObjectProtocol] = []
    private var isPresented = false

    init(preferences: Preferences, actions: SettingsActions, onClose: @escaping () -> Void) {
        self.preferences = preferences
        self.onClose = onClose

        let hosting = NSHostingController(
            rootView: SettingsRootView(preferences: preferences, activity: activity, actions: actions))
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
                self?.isPresented = false
                self?.activity.isVisible = false
                self?.onClose()
            }
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            visibilityObservers.append(center.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateVisibility() }
            })
        }
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            visibilityObservers.append(center.addObserver(
                forName: name, object: NSApp, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateVisibility() }
            })
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
        for observer in visibilityObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Shows the window, or brings the existing one forward.
    func show() {
        guard let window else { return }
        isPresented = true
        syncLevelWithPin(preferences.alwaysOnTop)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        updateVisibility()
    }

    private func updateVisibility() {
        guard let window else { activity.isVisible = false; return }
        activity.isVisible = isPresented && window.isVisible && !window.isMiniaturized && !NSApp.isHidden
            && window.occlusionState.contains(.visible)
    }

    /// If the calculator is pinned at `.floating`, Settings must match or it
    /// opens behind the calculator.
    func syncLevelWithPin(_ pinned: Bool) {
        window?.level = pinned ? .floating : .normal
    }
}
