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

        // The bridge may already hold the window if Epsilon started first.
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

    func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                preferences: preferences,
                actions: makeSettingsActions(),
                onClose: { [weak self] in
                    // Hand keyboard focus back to the calculator so Epsilon
                    // input keeps working after Settings closes.
                    self?.calculatorWindow.restoreCalculatorFocus()
                })
        }
        settingsWindowController?.show()
    }

    // MARK: - Attach

    private func attach(to window: NSWindow) {
        guard !hasAttached else { return }
        hasAttached = true

        // The bridge notification fires at the start of Epsilon's didInit(),
        // which then keeps configuring the window (style mask, title, aspect
        // ratio, frame autosave). Defer our setup one run-loop turn so it is
        // applied after Epsilon's and not overwritten by it.
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

        // The main menu and NSApp's Apple event handlers exist by now, since
        // SDL has finished launching the application.
        MenuBar.installSettingsItem(target: self, action: #selector(openSettingsAction(_:)))
        installReopenHandler()
        applyDockIconPolicy(preferences.showDockIcon)

        if preferences.launchWindowVisible {
            calculatorWindow.show()
        } else {
            calculatorWindow.hide()
        }

#if DEBUG
        // Debug aid: `NumWorks --show-settings` opens the Settings window
        // immediately, which is handy for automated UI verification.
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            openSettings()
        }
#endif
    }

    // MARK: - Preference observation

    /// Forwards preference changes to the window immediately. The toolbar's
    /// SwiftUI view observes Preferences directly for button-level changes.
    private func subscribeToPreferenceChanges() {
        preferences.$alwaysOnTop
            .dropFirst()
            .sink { [weak self] pinned in
                self?.calculatorWindow.setAlwaysOnTop(pinned)
                // The pin button must not keep keyboard focus away from the
                // calculator content.
                self?.calculatorWindow.restoreCalculatorFocus()
            }
            .store(in: &cancellables)

        preferences.$showTopBar
            .dropFirst()
            .sink { [weak self] _ in
                self?.calculatorWindow.updateToolbarVisibility()
            }
            .store(in: &cancellables)

        preferences.$windowStyle
            .dropFirst()
            .sink { [weak self] _ in
                self?.calculatorWindow.applyWindowStyle()
            }
            .store(in: &cancellables)

        preferences.$showDockIcon
            .dropFirst()
            .sink { [weak self] show in
                self?.applyDockIconPolicy(show)
            }
            .store(in: &cancellables)
    }

    // MARK: - Dock icon

    /// .regular shows the Dock icon; .accessory hides it while global
    /// shortcuts and the reopen handler keep working. macOS limitation:
    /// accessory apps have no menu bar, so Command-comma only works through
    /// the menu while the Dock icon is shown.
    private func applyDockIconPolicy(_ show: Bool) {
        let policy: NSApplication.ActivationPolicy = show ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)

        // Changing the policy deactivates the app; reactivate so whichever
        // window the user was interacting with stays usable.
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

    private func makeSettingsActions() -> SettingsActions {
        SettingsActions(
            centreWindow: { [weak self] in
                self?.calculatorWindow.centre()
            },
            resetWindowSize: { [weak self] in
                self?.calculatorWindow.resetSize()
            },
            resetWindowPosition: { [weak self] in
                self?.calculatorWindow.resetPosition()
            },
            restoreDefaultSettings: { [weak self] in
                // Preference sinks apply the changed behaviour immediately;
                // the saved window frame is intentionally left untouched.
                self?.preferences.resetToDefaults()
                self?.shortcutController?.resetShortcutsToDefaults()
            })
    }

    // MARK: - Dock reopen

    /// SDL owns the NSApplication delegate, so the Dock-icon "reopen" event
    /// is handled through NSAppleEventManager instead of the delegate. Must
    /// be installed after NSApplication finishes launching, or NSApp would
    /// overwrite the handler with its own.
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
