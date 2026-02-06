import AppKit
import Combine
import KeyboardShortcuts

final class AppController: NSObject, NSWindowDelegate {
    static let shared = AppController()

    let windowManagement = WindowManagement()
    private var menuBarController: MenuBarController?
    private var cancellables = Set<AnyCancellable>()

    private var suppressFrameSaves = false
    private let windowFrameDefaultsKey = "MainWindowFrame"

    private override init() {
        super.init()
    }

    private func saveWindowFrame(_ window: NSWindow) {
        guard !suppressFrameSaves else { return }
        guard window.isVisible, !window.isMiniaturized else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: windowFrameDefaultsKey)
    }

    private func applyDockIconVisibility() {
        let show = Preferences.shared.showDockIcon
        let policy: NSApplication.ActivationPolicy = show ? .regular : .accessory

        if NSApp.activationPolicy() != policy {
            _ = NSApp.setActivationPolicy(policy)
        }

        if Preferences.shared.isAppVisible {
            windowManagement.show()
            if Preferences.shared.isPinned {
                windowManagement.setPinned(true)
            }
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func start() {
        updateMenuBarIcon()
        applyDockIconVisibility()

        KeyboardShortcuts.onKeyUp(for: .hideShowApp) { [weak self] in
            self?.toggleVisibility()
        }

        KeyboardShortcuts.onKeyUp(for: .pinUnpinApp) { [weak self] in
            self?.togglePinned()
        }

        windowManagement.setPinned(Preferences.shared.isPinned)

        if Preferences.shared.isAppVisible {
            windowManagement.show()
        }

        Preferences.shared.$isMenuBarIconEnabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarIcon()
            }
            .store(in: &cancellables)

        Preferences.shared.$isPinned
            .sink { [weak self] v in
                self?.windowManagement.setPinned(v)
            }
            .store(in: &cancellables)

        Preferences.shared.$showDockIcon
            .sink { [weak self] _ in
                self?.applyDockIconVisibility()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: windowManagement.nsWindow)
            .sink { [weak self] _ in
                guard let self else { return }
                if Preferences.shared.isPinned {
                    Preferences.shared.isAppVisible = self.windowManagement.isVisibleForUser
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { _ in
                if !Preferences.shared.isPinned {
                    Preferences.shared.isAppVisible = false
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                if Preferences.shared.isPinned {
                    Preferences.shared.isAppVisible = self.windowManagement.isVisibleForUser
                } else {
                    let anyVisibleWindow = NSApp.windows.contains { $0.isVisible }
                    Preferences.shared.isAppVisible = anyVisibleWindow
                }
            }
            .store(in: &cancellables)
    }

    private func updateMenuBarIcon() {
        if Preferences.shared.isMenuBarIconEnabled {
            if menuBarController == nil {
                menuBarController = MenuBarController(wm: windowManagement)
            }
        } else {
            menuBarController?.invalidate()
            menuBarController = nil
        }
    }

    func togglePinned() {
        Preferences.shared.isPinned.toggle()
        windowManagement.setPinned(Preferences.shared.isPinned)
        if Preferences.shared.isPinned {
            Preferences.shared.isAppVisible = windowManagement.isVisibleForUser
        }
    }

    func toggleVisibility() {
        let willShow = !Preferences.shared.isAppVisible

        suppressFrameSaves = true

        if willShow {
            windowManagement.setPinned(Preferences.shared.isPinned)
            windowManagement.show()
            NSApp.activate(ignoringOtherApps: true)
            Preferences.shared.isAppVisible = true
        } else {
            windowManagement.hide()
            Preferences.shared.isAppVisible = false
        }

        DispatchQueue.main.async { [weak self] in
            self?.suppressFrameSaves = false
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        saveWindowFrame(w)
    }

    func windowDidResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        saveWindowFrame(w)
        DispatchQueue.main.async { [weak self] in
            self?.saveWindowFrame(w)
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        saveWindowFrame(w)
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
