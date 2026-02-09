import AppKit
import Combine


enum MenuBarIconStyle: String {
    case outline
    case filled

    var assetName: String {
        switch self {
        case .outline: return "MenuBarIconOutline"
        case .filled:  return "MenuBarIconFilled"
        }
    }
}



final class MenuBarController: NSObject {
    private let wm: WindowManagement
    private let actions: MenuBarActions
    private var statusItem: NSStatusItem?

    deinit {
        invalidate()
    }

    private var cancellables = Set<AnyCancellable>()

    private(set) var iconStyle: MenuBarIconStyle = .outline
    private(set) var iconSize: CGFloat = 18

    init(wm: WindowManagement) {
        self.wm = wm
        self.actions = MenuBarActions(wm: wm)
        super.init()

        iconStyle = Preferences.shared.menuBarIconStyle
        iconSize = Preferences.shared.menuBarIconSize

        if Preferences.shared.isMenuBarIconEnabled {
            ensureStatusItem()
        }

        Preferences.shared.$isMenuBarIconEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                enabled ? self.ensureStatusItem() : self.removeStatusItem()
            }
            .store(in: &cancellables)

        Preferences.shared.$menuBarIconStyle
            .sink { [weak self] style in
                self?.setIconStyle(style)
            }
            .store(in: &cancellables)

        Preferences.shared.$menuBarIconSize
            .sink { [weak self] size in
                self?.setIconSize(size)
            }
            .store(in: &cancellables)
    }

    func invalidate() {
        cancellables.removeAll()
        if let b = statusItem?.button {
            b.target = nil
            b.action = nil
        }
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    func setIconStyle(_ style: MenuBarIconStyle) {
        iconStyle = style
        applyIcon()
    }

    func setIconSize(_ size: CGFloat) {
        iconSize = size
        applyIcon()
    }

    private func applyIcon() {
        guard let b = statusItem?.button else { return }
        let img = NSImage(named: iconStyle.assetName)
        img?.isTemplate = true
        if let img {
            img.size = NSSize(width: iconSize, height: iconSize)
        }
        b.imageScaling = .scaleProportionallyDown
        b.image = img
    }

    private func ensureStatusItem() {
        if statusItem != nil { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        if let b = item.button {
            b.target = self
            b.action = #selector(onStatusItemAction)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        applyIcon()
    }

    private func removeStatusItem() {
        if let b = statusItem?.button {
            b.target = nil
            b.action = nil
        }
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    @objc private func onStatusItemAction() {
        let isRight = NSApp.currentEvent?.type == .rightMouseUp
        if isRight {
            showMenu()
        } else {
            AppController.shared.toggleVisibility()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let pinTitle = Preferences.shared.isPinned ? "Unpin" : "Pin"
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(togglePinned), keyEquivalent: "")
        pinItem.target = self
        menu.addItem(pinItem)

        let visibilityTitle = Preferences.shared.isAppVisible ? "Hide" : "Show"
        let visibilityItem = NSMenuItem(title: visibilityTitle, action: #selector(toggleVisibility), keyEquivalent: "")
        visibilityItem.target = self
        menu.addItem(visibilityItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        guard let button = statusItem?.button, let event = NSApp.currentEvent else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func togglePinned() {
        AppController.shared.togglePinned()
    }

    @objc private func toggleVisibility() {
        AppController.shared.toggleVisibility()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        guard let item = NSApp.mainMenu?.firstSettingsMenuItem() else { return }
        guard let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    @objc private func quitApp() {
        AppController.shared.quit()
    }
}

private extension NSMenu {
    func firstSettingsMenuItem() -> NSMenuItem? {
        for item in items {
            if item.keyEquivalent == "," && item.keyEquivalentModifierMask.contains(.command) {
                return item
            }
            if let found = item.submenu?.firstSettingsMenuItem() {
                return found
            }
        }
        return nil
    }
}
