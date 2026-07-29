import AppKit
import Combine

/// Additions to the main menu that SDL creates during startup.
@MainActor
enum MenuBar {

    /// Inserts “Check for Updates…” into the application menu.
    static func installCheckForUpdatesItem(target: AnyObject, action: Selector) {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }
        guard !appMenu.items.contains(where: { $0.action == action }) else { return }

        let item = NSMenuItem(title: "Check for Updates…", action: action, keyEquivalent: "")
        item.target = target

        // Place after Settings (which we insert near the top).
        let settingsIndex = appMenu.items.firstIndex(where: {
            $0.title.hasPrefix("Settings")
        })
        let index = settingsIndex.map { $0 + 2 } ?? min(4, appMenu.items.count)
        appMenu.insertItem(item, at: min(index, appMenu.items.count))
    }

    /// Inserts a standard "Settings…" (Command-comma) item into the
    /// application menu. Must run after SDL has built the main menu, i.e.
    /// once the Epsilon window is available. Safe to call more than once.
    static func installSettingsItem(target: AnyObject, action: Selector) {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }
        guard !appMenu.items.contains(where: { $0.action == action }) else { return }

        let item = NSMenuItem(title: "Settings…", action: action, keyEquivalent: ",")
        item.target = target

        let index = min(2, appMenu.items.count)
        appMenu.insertItem(item, at: index)
        appMenu.insertItem(.separator(), at: index + 1)
    }

    /// Ensures Quit (Command-Q) is present in the application menu.
    static func installQuitItem(target: AnyObject, action: Selector) {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }
        if appMenu.items.contains(where: {
            $0.action == action || $0.keyEquivalent == "q"
        }) {
            // Retarget existing Quit to our handler if needed.
            if let existing = appMenu.items.first(where: { $0.keyEquivalent == "q" }) {
                existing.target = target
                existing.action = action
            }
            return
        }

        appMenu.addItem(.separator())
        let item = NSMenuItem(title: "Quit NumWorks", action: action, keyEquivalent: "q")
        item.target = target
        appMenu.addItem(item)
    }
}

/// Owns the NSStatusItem in the system menu bar.
@MainActor
final class StatusItemController: NSObject {

    private let preferences: Preferences
    private let actions: StatusItemActions
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var isToggling = false

    struct StatusItemActions {
        let togglePin: () -> Void
        let toggleVisibility: () -> Void
        let openSettings: () -> Void
        let quit: () -> Void
        let isPinned: () -> Bool
        let isVisible: () -> Bool
    }

    init(preferences: Preferences, actions: StatusItemActions) {
        self.preferences = preferences
        self.actions = actions
        super.init()

        preferences.$showMenuBarIcon
            .sink { [weak self] enabled in
                enabled ? self?.install() : self?.remove()
            }
            .store(in: &cancellables)

        preferences.$menuBarIconStyle
            .removeDuplicates()
            .sink { [weak self] _ in
                // Apply on the current main-actor turn so the status item
                // updates as soon as the Settings radio changes.
                self?.applyIcon()
            }
            .store(in: &cancellables)

        if preferences.showMenuBarIcon {
            install()
        }
    }

    private func install() {
        guard statusItem == nil else {
            applyIcon()
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: 28)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        applyIcon()
    }

    private func remove() {
        if let button = statusItem?.button {
            button.target = nil
            button.action = nil
        }
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    private func applyIcon() {
        guard let button = statusItem?.button else { return }
        guard let source = NSImage(named: preferences.menuBarIconStyle.imageName) else {
            button.image = nil
            return
        }
        // Clear first so AppKit doesn’t keep the previous template cached on
        // the button (style changes otherwise only appeared after a click).
        button.image = nil

        let image = NSImage(size: NSSize(width: 22, height: 22))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: image.size),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0)
        image.unlockFocus()
        image.isTemplate = true

        button.image = image
        button.imageScaling = .scaleProportionallyDown
        button.needsDisplay = true
        button.displayIfNeeded()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(with: NSApp.currentEvent)
            return
        }
        // Immediate, re-entrancy-safe toggle. No delay — AppKit toolbar no
        // longer involves ViewBridge, so rapid clicks are safe.
        guard !isToggling else { return }
        isToggling = true
        actions.toggleVisibility()
        isToggling = false
    }

    private func showMenu(with event: NSEvent?) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let pin = NSMenuItem(
            title: actions.isPinned() ? "Unpin" : "Pin",
            action: #selector(pinAction),
            keyEquivalent: "")
        pin.target = self
        menu.addItem(pin)

        let visibility = NSMenuItem(
            title: actions.isVisible() ? "Hide" : "Show",
            action: #selector(visibilityAction),
            keyEquivalent: "")
        visibility.target = self
        menu.addItem(visibility)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(settingsAction),
            keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(quitAction),
            keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)

        guard let button = statusItem?.button else { return }
        if let event {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        } else {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
        }
    }

    @objc private func pinAction() { actions.togglePin() }
    @objc private func visibilityAction() { actions.toggleVisibility() }
    @objc private func settingsAction() { actions.openSettings() }
    @objc private func quitAction() { actions.quit() }
}
