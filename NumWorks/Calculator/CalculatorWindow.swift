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
        // Tokens capture nothing, safe to clean up off the main actor.
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var isAttached: Bool { window != nil }

    /// Whether the calculator is currently visible on the active Space.
    /// A window covered by other windows still counts as visible.
    var isVisibleOnActiveSpace: Bool {
        guard let window else { return false }
        return window.isVisible && window.isOnActiveSpace
    }

    // MARK: - Attach

    /// Called once the Epsilon NSWindow becomes available. Applies chrome,
    /// constraints, the saved frame and all current preferences.
    func attach(to window: NSWindow, toolbarActions: ToolbarActions) {
        guard self.window !== window else { return }
        detachObservers()
        self.window = window
        self.toolbarActions = toolbarActions

        // Epsilon enabled AppKit frame autosaving ("Calculator"); disable it
        // so our preference-controlled persistence is the single authority.
        window.setFrameAutosaveName("")

        window.styleMask.insert(.resizable)
        window.isMovable = true

        WindowSizing.applyConstraints(to: window)
        restoreFrame()
        // Keep AppKit's stored "Calculator" frame in sync with ours: Epsilon
        // re-enables autosaving early in the next launch, and a stale value
        // there would briefly restore the wrong frame before we take over.
        window.saveFrame(usingName: "Calculator")
        applyPreferences()
        observeWindowNotifications(for: window)
    }

    // MARK: - Visibility

    /// Shows the calculator on the active Space, activates NumWorks and
    /// makes the window key so SDL keeps receiving keyboard events.
    func show() {
        guard let window else { return }
        // moveToActiveSpace only takes effect while the window is being
        // ordered in, so it can stay set permanently without the window
        // appearing on every Space (unlike canJoinAllSpaces).
        if preferences.moveWindowToCurrentSpaceWhenShown {
            window.collectionBehavior.insert(.moveToActiveSpace)
        } else {
            window.collectionBehavior.remove(.moveToActiveSpace)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        restoreCalculatorFocus()
    }

    /// Hides the window without closing it: the SDL window and the Epsilon
    /// loop keep running, only the on-screen presence goes away.
    func hide() {
        window?.orderOut(nil)
    }

    /// Hides when visible on the current Space; shows otherwise. A window
    /// stranded on another Space therefore behaves as "show".
    func toggleVisibility() {
        if isVisibleOnActiveSpace {
            hide()
        } else {
            show()
        }
    }

    func bringToFront() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
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
        // Keep the top-left corner in place while resizing.
        frame.origin.y += frame.height - newSize.height
        frame.size = newSize
        window.setFrame(frame, display: true, animate: true)
        saveFrameIfEnabled()
    }

    func resetPosition() {
        centre()
    }

    // MARK: - Preferences

    /// Applies every preference that maps onto window state.
    func applyPreferences() {
        setAlwaysOnTop(preferences.alwaysOnTop)
        applyWindowStyle()
    }

    func setAlwaysOnTop(_ pinned: Bool) {
        window?.level = pinned ? .floating : .normal
    }

    /// Applies the current window style and toolbar visibility.
    func applyWindowStyle() {
        guard let window else { return }
        // Minimal is a placeholder; treat it as native (see WindowStyle).
        let style = preferences.windowStyle.isAvailable
            ? preferences.windowStyle : .native
        style.applyChrome(to: window)
        updateToolbarVisibility()
    }

    func updateToolbarVisibility() {
        guard let window else { return }
        let style = preferences.windowStyle.isAvailable
            ? preferences.windowStyle : .native
        let wantsToolbar = style.usesAccessoryToolbar && preferences.showTopBar
        if wantsToolbar, let toolbarActions {
            toolbar.attach(to: window, preferences: preferences, actions: toolbarActions)
        } else {
            toolbar.detach()
        }
    }

    // MARK: - Focus

    /// SDL listens for key events through the window's content view. Toolbar
    /// buttons and the Settings window can move first-responder status away;
    /// this hands it back so calculator keyboard input keeps working.
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
            rememberPosition: preferences.rememberWindowPosition,
            rememberSize: preferences.rememberWindowSize,
            window: window)
        window.setFrame(frame, display: true)
    }

    private func saveFrameIfEnabled() {
        guard let window else { return }
        guard preferences.rememberWindowPosition || preferences.rememberWindowSize else {
            return
        }
        preferences.savedWindowFrame = WindowSizing.encode(frame: window.frame)
    }

    private func observeWindowNotifications(for window: NSWindow) {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didEndLiveResizeNotification,
        ]
        for name in names {
            windowObservers.append(center.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.saveFrameIfEnabled()
                }
            })
        }
        // Recompute the maximum size when the window lands on another screen.
        windowObservers.append(center.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let window = self?.window else { return }
                WindowSizing.applyConstraints(to: window)
            }
        })
    }

    private func detachObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }
}
