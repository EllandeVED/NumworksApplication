import AppKit
import Combine

/// Forwards `NSWindowDelegate` to SDL’s delegate, but maps close (red button /
/// Cmd-W) to hide so the process keeps running for the menu bar and shortcuts.
final class CalculatorCloseInterceptor: NSObject, NSWindowDelegate {
    weak var previous: NSWindowDelegate?
    var onRequestHide: (() -> Void)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onRequestHide?()
        return false
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(windowShouldClose(_:)) {
            return true
        }
        if let previous, previous.responds(to: aSelector) {
            return true
        }
        return super.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let previous, previous.responds(to: aSelector) {
            return previous
        }
        return super.forwardingTarget(for: aSelector)
    }
}

/// Behaviour applied to the Epsilon NSWindow (owned by SDL, stored weakly).
/// Close is intercepted via `CalculatorCloseInterceptor`; other delegate
/// messages are forwarded.
@MainActor
final class CalculatorWindow {

    private(set) weak var window: NSWindow?

    private let preferences: Preferences
    private let toolbar = CalculatorToolbarController()
    private let trafficLights = NativeTrafficLightsController()
    private var toolbarActions: ToolbarActions?
    private var windowObservers: [NSObjectProtocol] = []
    private let workspaceCenter = NSWorkspace.shared.notificationCenter
    private var workspaceObservers: [NSObjectProtocol] = []
    private let closeInterceptor = CalculatorCloseInterceptor()
    /// Invalidates focus work when a newer show/hide request arrives.
    private var visibilityRequestID: UInt = 0

    init(preferences: Preferences) {
        self.preferences = preferences
        closeInterceptor.onRequestHide = { [weak self] in
            self?.hide()
        }
    }

    deinit {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in workspaceObservers {
            workspaceCenter.removeObserver(observer)
        }
    }

    var isAttached: Bool { window != nil }

    /// Whether the calculator is currently visible on the active Space.
    var isVisibleOnActiveSpace: Bool {
        guard let window else { return false }
        return EpsilonBridge.isSimulatorActive && window.isVisible && window.isOnActiveSpace
    }

    // MARK: - Attach

    func attach(to window: NSWindow, toolbarActions: ToolbarActions) {
        guard self.window !== window else { return }
        detachObservers()
        trafficLights.invalidate()
        self.window = window
        self.toolbarActions = toolbarActions

        window.isRestorable = false
        window.setFrameAutosaveName("")
        window.isReleasedWhenClosed = false
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame Calculator")
        window.setAccessibilityIdentifier("calculator-window")

        window.styleMask.insert(.resizable)
        window.isMovable = true

        installCloseInterceptor(on: window)

        WindowSizing.applyConstraints(to: window)
        restoreFrame()
        applyPreferences()
        observeWindowNotifications(for: window)
    }

    private func installCloseInterceptor(on window: NSWindow) {
        let current = window.delegate
        if current !== closeInterceptor {
            closeInterceptor.previous = current
            window.delegate = closeInterceptor
        }
    }

    // MARK: - Visibility

    /// App that was frontmost before we activated for a user show — restored on hide.
    private var previousFrontAppPID: pid_t?

    /// Hide only when the calculator is already the focused front window on this Space.
    /// Otherwise treat as “not up” (bring to front / show) — menu bar, shortcut, and
    /// context menu all share this rule for stable one-click behavior.
    var prefersHideOnToggle: Bool {
        guard let window else { return false }
        return isVisibleOnActiveSpace && isFrontmostCalculator(window)
    }

    /// User-driven show (menu bar / shortcut). Remembers the previous app for hide.
    func showFromUser() {
        if window != nil { Telemetry.noteCalculatorUsed() }
        rememberPreviousFrontAppIfNeeded()
        let requestID = visibilityRequestID &+ 1
        show()
        // SDL + status-item activation can leave the window unfocused on the first
        // pass; a same-turn follow-up makes one click enough when fully hidden.
        DispatchQueue.main.async { [weak self] in
            self?.finishShowingIfNeeded(requestID: requestID)
        }
    }

    /// User-driven hide. Optionally returns focus to the app that was frontmost
    /// before we showed (e.g. Safari), instead of leaving NumWorks active.
    func hideFromUser(yieldFocus: Bool) {
        hide()
        guard !EpsilonBridge.isSimulatorActive else { return }
        if yieldFocus {
            yieldFocusToPreviousFrontApp()
        } else {
            previousFrontAppPID = nil
        }
    }

    func toggleFromUser(yieldFocusOnHide: Bool) {
        if prefersHideOnToggle {
            hideFromUser(yieldFocus: yieldFocusOnHide)
        } else {
            showFromUser()
        }
    }

    func show() {
        guard let window else { return }
        visibilityRequestID &+= 1
        let requestID = visibilityRequestID
        // Wake before ordering front. Record intent before AppKit can deliver
        // activation/focus callbacks (epsilon_main shares this thread).
        EpsilonBridge.isSimulatorActive = true
        installCloseInterceptor(on: window)

        if preferences.moveWindowToCurrentSpaceWhenShown {
            window.collectionBehavior.insert(.moveToActiveSpace)
        } else {
            window.collectionBehavior.remove(.moveToActiveSpace)
        }

        window.alphaValue = 1

        // Always activate — including .accessory (menu-bar-only) mode. Skipping
        // activate left the previously focused app’s window above ours.
        guard visibilityRequestID == requestID else { return }
        NSApp.activate(ignoringOtherApps: true)
        guard visibilityRequestID == requestID else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        guard visibilityRequestID == requestID else { return }
        window.orderFrontRegardless()
        guard visibilityRequestID == requestID else { return }
        window.makeKeyAndOrderFront(nil)
        guard visibilityRequestID == requestID else { return }
        if let contentView = window.contentView, window.firstResponder !== contentView {
            window.makeFirstResponder(contentView)
        }
        let style = preferences.windowStyle.isAvailable
            ? preferences.windowStyle : .native
        trafficLights.apply(hoverUntilPointerNearby: style == .native, to: window)
        EpsilonBridge.refreshSimulatorVisibility()
    }

    func hide() {
        visibilityRequestID &+= 1
        // Leave the AppKit toolbar accessory attached. Creating/destroying it
        // on every toggle was unnecessary once SwiftUI/ViewBridge was removed.
        EpsilonBridge.isSimulatorActive = false
        trafficLights.pause()
        window?.orderOut(nil)
    }

    /// True when the calculator is the focused front window (safe to hide).
    private func isFrontmostCalculator(_ window: NSWindow) -> Bool {
        NSApp.isActive && window.isKeyWindow
    }

    private func rememberPreviousFrontAppIfNeeded() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        if front.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        previousFrontAppPID = front.processIdentifier
    }

    private func yieldFocusToPreviousFrontApp() {
        defer { previousFrontAppPID = nil }
        guard let pid = previousFrontAppPID,
              let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated
        else { return }
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func finishShowingIfNeeded(requestID: UInt) {
        guard visibilityRequestID == requestID, EpsilonBridge.isSimulatorActive,
              let window, window.isVisible else { return }
        if !NSApp.isActive || !window.isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            guard visibilityRequestID == requestID else { return }
            window.makeKeyAndOrderFront(nil)
            if let contentView = window.contentView {
                window.makeFirstResponder(contentView)
            }
        }
        EpsilonBridge.refreshSimulatorVisibility()
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

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            style.applyChrome(to: window)
            updateToolbarVisibility()
            normalizeContentSize(of: window, width: previousWidth)
            trafficLights.apply(
                hoverUntilPointerNearby: style == .native,
                to: window)
            installCloseInterceptor(on: window)
        }
    }

    func updateToolbarVisibility() {
        guard let window, let toolbarActions else { return }
        let style = preferences.windowStyle.isAvailable
            ? preferences.windowStyle : .native

        if style.usesAccessoryToolbar {
            toolbar.attach(to: window, preferences: preferences, actions: toolbarActions)
            toolbar.setVisible(true)
        } else if toolbar.isAttached {
            // Keep installed; hiding avoids title-bar tear-down on the next flip.
            toolbar.setVisible(false)
        }
    }

    private func normalizeContentSize(of window: NSWindow, width: CGFloat) {
        let size = WindowSizing.contentSize(forWidth: width)
        window.contentAspectRatio = WindowSizing.defaultContentSize
        WindowSizing.applyConstraints(to: window)
        let current = window.contentLayoutRect.size
        if abs(current.width - size.width) > 0.5
            || abs(current.height - size.height) > 0.5 {
            window.setContentSize(size)
        }
    }

    // MARK: - Focus

    func restoreCalculatorFocus() {
        guard EpsilonBridge.isSimulatorActive, let window, window.isVisible else { return }
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
        let frame = WindowSizing.restorationFrame(savedFrame: saved, window: window)
        window.setFrame(frame, display: true)
    }

    private func saveFrame() {
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
                    self?.saveFrame()
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
        // Visibility only gates rendering and cosmetic timers. AppKit keeps
        // servicing native input even while the calculator is fully hidden.
        for name in [NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            windowObservers.append(center.addObserver(
                forName: name, object: window, queue: .main
            ) { _ in
                EpsilonBridge.refreshSimulatorVisibility()
            })
        }
        for name in [NSApplication.didBecomeActiveNotification,
                     NSApplication.didResignActiveNotification,
                     NSApplication.didHideNotification,
                     NSApplication.didUnhideNotification] {
            windowObservers.append(center.addObserver(
                forName: name, object: NSApp, queue: .main
            ) { _ in
                EpsilonBridge.refreshSimulatorVisibility()
            })
        }
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            EpsilonBridge.refreshSimulatorVisibility()
        })
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            workspaceObservers.append(workspaceCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { _ in EpsilonBridge.simulatorDisplaySleeping = true })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            workspaceObservers.append(workspaceCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { _ in EpsilonBridge.simulatorDisplaySleeping = false })
        }
        EpsilonBridge.refreshSimulatorVisibility()
    }

    private func detachObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
        for observer in workspaceObservers {
            workspaceCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }
}
