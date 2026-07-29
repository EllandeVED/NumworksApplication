import AppKit
import Combine

/// Single owner of all behaviour applied to the Epsilon NSWindow.
///
/// The window itself is created and owned by Epsilon's SDL backend; it is
/// stored weakly here and must never be closed or destroyed by this class.
/// SDL also installs its own NSWindowDelegate, which we must not replace, so
/// all observation goes through NotificationCenter.
@MainActor
final class CalculatorWindow {

    private(set) weak var window: NSWindow?

    private let preferences: Preferences
    private let toolbar = CalculatorToolbarController()
    private var toolbarActions: ToolbarActions?
    private var windowObservers: [NSObjectProtocol] = []

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    deinit {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var isAttached: Bool { window != nil }

    /// Whether the calculator is currently visible on the active Space.
    var isVisibleOnActiveSpace: Bool {
        guard let window else { return false }
        return window.isVisible && window.isOnActiveSpace
    }

    // MARK: - Attach

    func attach(to window: NSWindow, toolbarActions: ToolbarActions) {
        guard self.window !== window else { return }
        detachObservers()
        self.window = window
        self.toolbarActions = toolbarActions

        window.isRestorable = false
        window.setFrameAutosaveName("")
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame Calculator")

        window.styleMask.insert(.resizable)
        window.isMovable = true

        WindowSizing.applyConstraints(to: window)
        restoreFrame()
        applyPreferences()
        observeWindowNotifications(for: window)
    }

    // MARK: - Visibility

    func show() {
        guard let window else { return }
        if preferences.moveWindowToCurrentSpaceWhenShown {
            window.collectionBehavior.insert(.moveToActiveSpace)
        } else {
            window.collectionBehavior.remove(.moveToActiveSpace)
        }

        // Wake the simulator before ordering front so the next main-thread
        // iteration presents promptly (epsilon_main shares this thread).
        EpsilonBridge.isSimulatorActive = true
        window.alphaValue = 1

        // Always activate — including .accessory (menu-bar-only) mode. Skipping
        // activate left the previously focused app’s window above ours.
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        if let contentView = window.contentView {
            window.makeFirstResponder(contentView)
        }
    }

    func hide() {
        // Leave the AppKit toolbar accessory attached. Creating/destroying it
        // on every toggle was unnecessary once SwiftUI/ViewBridge was removed.
        EpsilonBridge.isSimulatorActive = false
        window?.orderOut(nil)
    }

    func toggleVisibility() {
        guard let window else { return }
        // If already on-screen but behind something else, bring forward instead
        // of hiding — matches menu-bar calculator expectations.
        if window.isVisible && window.isOnActiveSpace && isFrontmostCalculator(window) {
            hide()
        } else {
            show()
        }
    }

    /// True when the calculator is the focused front window (safe to hide).
    private func isFrontmostCalculator(_ window: NSWindow) -> Bool {
        NSApp.isActive && window.isKeyWindow
    }

    func bringToFront() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    func centre() {
        guard let window else { return }
        let origin = WindowSizing.centeredFrame(
            contentSize: window.contentRect(forFrameRect: window.frame).size,
            window: window).origin
        window.setFrameOrigin(origin)
        saveFrameIfEnabled()
    }

    func resetSize() {
        guard let window else { return }
        var frame = window.frame
        let newSize = window.frameRect(forContentRect:
            NSRect(origin: .zero, size: WindowSizing.defaultContentSize)).size
        frame.origin.y += frame.height - newSize.height
        frame.size = newSize
        window.setFrame(frame, display: true, animate: true)
        saveFrameIfEnabled()
    }

    func resetPosition() {
        centre()
    }

    // MARK: - Preferences

    func applyPreferences() {
        setAlwaysOnTop(preferences.alwaysOnTop)
        applyWindowStyle()
    }

    func setAlwaysOnTop(_ pinned: Bool) {
        window?.level = pinned ? .floating : .normal
        toolbar.refresh()
    }

    /// Applies chrome + toolbar for the current style immediately.
    func applyWindowStyle() {
        guard let window else { return }
        let style = preferences.windowStyle.isAvailable
            ? preferences.windowStyle : .native
        let previousWidth = max(
            window.contentLayoutRect.width,
            WindowSizing.minimumContentSize.width)

        style.applyChrome(to: window)
        updateToolbarVisibility()
        normalizeContentSize(of: window, width: previousWidth)
        window.displayIfNeeded()
    }

    func updateToolbarVisibility() {
        guard let window else { return }
        let style = preferences.windowStyle.isAvailable
            ? preferences.windowStyle : .native
        if style.usesAccessoryToolbar, let toolbarActions {
            toolbar.attach(to: window, preferences: preferences, actions: toolbarActions)
        } else {
            toolbar.detach(from: window)
        }
    }

    private func normalizeContentSize(of window: NSWindow, width: CGFloat) {
        let size = WindowSizing.contentSize(forWidth: width)
        window.contentAspectRatio = WindowSizing.defaultContentSize
        WindowSizing.applyConstraints(to: window)
        window.setContentSize(size)
    }

    // MARK: - Focus

    func restoreCalculatorFocus() {
        guard let window, window.isVisible else { return }
        if !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }
        if let contentView = window.contentView {
            window.makeFirstResponder(contentView)
        }
    }

    // MARK: - Frame persistence

    private func restoreFrame() {
        guard let window else { return }
        let saved = preferences.savedWindowFrame.flatMap(WindowSizing.decode(frameString:))
        let frame = WindowSizing.restorationFrame(
            savedFrame: saved,
            rememberPosition: true,
            rememberSize: true,
            window: window)
        window.setFrame(frame, display: true)
    }

    private func saveFrameIfEnabled() {
        guard let window else { return }
        preferences.savedWindowFrame = WindowSizing.encode(frame: window.frame)
    }

    private func observeWindowNotifications(for window: NSWindow) {
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            windowObservers.append(center.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.saveFrameIfEnabled()
                }
            })
        }
        windowObservers.append(center.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let window = self?.window else { return }
                WindowSizing.applyConstraints(to: window)
            }
        })
        // Do not pause on occlusion: covering the calculator with another
        // window must not freeze the main thread / feel like a hide glitch.
        // Pause only via show()/hide() (orderOut).
    }

    private func detachObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }
}
