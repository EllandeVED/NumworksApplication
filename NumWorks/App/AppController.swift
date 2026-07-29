import AppKit
import Combine
import CoreServices

/// Application coordinator. Owns the shared model and controller instances
/// and wires them together; window styling and settings UI live in their own
/// types.
@MainActor
final class AppController: NSObject {

    let preferences: Preferences
    let calculatorWindow: CalculatorWindow

    private var shortcutController: ShortcutController?
    private var settingsWindowController: SettingsWindowController?
    private var statusItemController: StatusItemController?
    private var bridgeObserver: NSObjectProtocol?
    private var hasAttached = false
    private var cancellables = Set<AnyCancellable>()

    override init() {
        preferences = Preferences()
        calculatorWindow = CalculatorWindow(preferences: preferences)
        super.init()
    }

    deinit {
        if let bridgeObserver {
            NotificationCenter.default.removeObserver(bridgeObserver)
        }
    }

    /// Called from main.swift before Epsilon takes over the main thread.
    /// Safe to call once only; guarded to avoid duplicate observers.
    func start() {
        guard bridgeObserver == nil else { return }

        // Always start unpinned; the user can enable Always on Top during the session.
        preferences.alwaysOnTop = false

        // Keep Sparkle alive for the whole process (weak delegates inside).
        _ = UpdateController.shared

        shortcutController = ShortcutController(
            preferences: preferences,
            toggleCalculator: { [weak self] in
                self?.toggleCalculator()
            },
            toggleAlwaysOnTop: { [weak self] in
                self?.togglePin()
            })
        subscribeToPreferenceChanges()

        bridgeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.EpsilonWindowDidBecomeAvailable,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow else { return }
                self?.attach(to: window)
            }
        }

        if let window = EpsilonBridge.calculatorWindow {
            attach(to: window)
        }
    }

    // MARK: - Actions

    func toggleCalculator() {
        calculatorWindow.toggleVisibility()
    }

    func togglePin() {
        preferences.alwaysOnTop.toggle()
    }

    func quit() {
        // EpsilonBridge swizzles SDLApplication.terminate: so this actually
        // exits after SDL_QUIT (needed for Quit and Sparkle).
        NSApp.terminate(nil)
    }

    func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                preferences: preferences,
                actions: makeSettingsActions(),
                onClose: { [weak self] in
                    self?.handleSettingsClosed()
                })
        }
        settingsWindowController?.show()
        // Keep the Dock icon while Settings is open so the user never loses it.
        applyDockIconPolicy(effectiveShowDockIcon: true)
    }

    private func handleSettingsClosed() {
        calculatorWindow.restoreCalculatorFocus()
        applyDockIconPolicy(effectiveShowDockIcon: preferences.showDockIcon)
    }

    private var isSettingsVisible: Bool {
        settingsWindowController?.window?.isVisible == true
    }

    // MARK: - Attach

    private func attach(to window: NSWindow) {
        guard !hasAttached else { return }
        hasAttached = true

        // Keep invisible until performAttach restores the frame. Epsilon also
        // sets alpha to 0 in didInit; this covers the race before that runs.
        window.alphaValue = 0
        window.isRestorable = false
        window.setFrameAutosaveName("")

        DispatchQueue.main.async { [self] in
            performAttach(to: window)
        }
    }

    private func performAttach(to window: NSWindow) {
#if DEBUG
        NSLog("[NumWorks] Attaching to Epsilon window: %@", window)
#endif

        let toolbarActions = ToolbarActions(
            togglePin: { [weak self] in
                self?.togglePin()
            },
            openSettings: { [weak self] in
                self?.openSettings()
            })
        calculatorWindow.attach(to: window, toolbarActions: toolbarActions)

        // Ensure Dock / app switcher use the asset-catalog AppIcon (About
        // already did; the Dock sometimes kept a stale generic template).
        NSApp.applicationIconImage = AppInfo.applicationIcon

        MenuBar.installSettingsItem(target: self, action: #selector(openSettingsAction(_:)))
        MenuBar.installCheckForUpdatesItem(
            target: UpdateController.shared,
            action: #selector(UpdateController.checkForUpdates(_:)))
        MenuBar.installQuitItem(target: self, action: #selector(quitAction(_:)))
        installReopenHandler()
        installStatusItem()
        applyDockIconPolicy(effectiveShowDockIcon: preferences.showDockIcon)

        if preferences.launchWindowVisible {
            calculatorWindow.show()
        } else {
            calculatorWindow.hide()
        }
        // Reveal only after the saved frame and chrome are applied.
        window.alphaValue = 1

        // After the window is up, offer AppMover’s confirmation once on first launch.
        DispatchQueue.main.async { [weak self] in
            self?.offerMoveToApplicationsIfNeeded()
        }

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            openSettings()
        }
#endif
    }

    private func offerMoveToApplicationsIfNeeded() {
        guard !preferences.didOfferMoveToApplications else { return }
        preferences.didOfferMoveToApplications = true
        AppMover.moveIfNecessary(prompt: true)
    }

    private func installStatusItem() {
        guard statusItemController == nil else { return }
        statusItemController = StatusItemController(
            preferences: preferences,
            actions: .init(
                togglePin: { [weak self] in self?.togglePin() },
                toggleVisibility: { [weak self] in self?.toggleCalculator() },
                openSettings: { [weak self] in self?.openSettings() },
                quit: { [weak self] in self?.quit() },
                isPinned: { [weak self] in self?.preferences.alwaysOnTop ?? false },
                isVisible: { [weak self] in
                    self?.calculatorWindow.isVisibleOnActiveSpace ?? false
                }))
    }

    // MARK: - Preference observation

    private func subscribeToPreferenceChanges() {
        preferences.$alwaysOnTop
            .dropFirst()
            .sink { [weak self] pinned in
                self?.calculatorWindow.setAlwaysOnTop(pinned)
                self?.calculatorWindow.restoreCalculatorFocus()
            }
            .store(in: &cancellables)

        preferences.$windowStyle
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Apply chrome + toolbar immediately, even if the calculator
                // is currently hidden, so switching Native ↔ Toolbar never
                // waits for the next show.
                self?.calculatorWindow.applyWindowStyle()
            }
            .store(in: &cancellables)

        preferences.$showDockIcon
            .dropFirst()
            .sink { [weak self] show in
                guard let self else { return }
                // Defer hiding while Settings is open / key.
                if !show && self.isSettingsVisible {
                    self.applyDockIconPolicy(effectiveShowDockIcon: true)
                } else {
                    self.applyDockIconPolicy(effectiveShowDockIcon: show)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Dock icon

    /// .regular shows the Dock icon; .accessory hides it. While Settings is
    /// open the Dock icon is forced visible so the user never loses access.
    private func applyDockIconPolicy(effectiveShowDockIcon show: Bool) {
        let policy: NSApplication.ActivationPolicy = show ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }

        // Switching activation policy can reset the Dock tile to a generic
        // template. Always re-apply the asset-catalog AppIcon whenever the
        // Dock icon is (or becomes) visible — including the temporary show
        // while Settings is open with “Show Dock icon” disabled.
        if show {
            NSApp.applicationIconImage = AppInfo.applicationIcon
        }

        NSApp.activate(ignoringOtherApps: true)
        if let settingsWindow = settingsWindowController?.window, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
        } else {
            calculatorWindow.restoreCalculatorFocus()
        }
    }

    // MARK: - Settings plumbing

    @objc private func openSettingsAction(_ sender: Any?) {
        openSettings()
    }

    @objc private func quitAction(_ sender: Any?) {
        quit()
    }

    private func makeSettingsActions() -> SettingsActions {
        SettingsActions(
            restoreDefaultSettings: { [weak self] in
                self?.preferences.resetToDefaults()
                self?.shortcutController?.resetShortcutsToDefaults()
                UpdateController.shared.automaticallyChecksForUpdates = true
            },
            checkForUpdates: {
                UpdateController.shared.checkForUpdates(nil)
            })
    }

    // MARK: - Dock reopen

    private func installReopenHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleReopen(_:replyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEReopenApplication))
    }

    @objc private func handleReopen(
        _ event: NSAppleEventDescriptor,
        replyEvent: NSAppleEventDescriptor
    ) {
        if !calculatorWindow.isVisibleOnActiveSpace {
            calculatorWindow.show()
        }
    }
}
