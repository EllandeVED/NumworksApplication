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
        item.keyEquivalentModifierMask = [.command]
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

    /// Width of the clickable status-item slot (points). Independent of icon art size.
    private static let itemLength: CGFloat = 20
    /// Drawn template size — keep this stable when tweaking `itemLength`.
    private static let iconSize: CGFloat = 22

    private let preferences: Preferences
    private let actions: StatusItemActions
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    /// Snapshot of hide-vs-show taken on mouseDown so activate/reopen cannot
    /// invert the click before mouseUp runs.
    private var pendingShouldShow: Bool?
    private var ignoreReopenUntil = Date.distantPast
    private var cachedIcons: [MenuBarIconStyle: NSImage] = [:]

    struct StatusItemActions {
        let togglePin: () -> Void
        let showCalculator: () -> Void
        let hideCalculator: () -> Void
        let toggleVisibility: () -> Void
        let openSettings: () -> Void
        let quit: () -> Void
        let isPinned: () -> Bool
        let isVisible: () -> Bool
        let prefersHideOnToggle: () -> Bool
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
        let item = NSStatusBar.system.statusItem(withLength: Self.itemLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseUp])
            // Don’t scale the template down to the slot — hitbox and art stay independent.
            button.imageScaling = .scaleNone
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
        let style = preferences.menuBarIconStyle
        if let cached = cachedIcons[style] {
            if button.image !== cached {
                button.image = cached
            }
            return
        }
        guard let source = NSImage(named: style.imageName) else {
            button.image = nil
            return
        }

        let side = Self.iconSize
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0)
        image.unlockFocus()
        image.isTemplate = true
        cachedIcons[style] = image

        button.image = image
        button.imageScaling = .scaleNone
    }

    private var buttonWindow: NSWindow? { statusItem?.button?.window }

    func isEventFromStatusItem(_ event: NSEvent?) -> Bool {
        if Date() < ignoreReopenUntil { return true }
        guard let event, let buttonWindow else { return false }
        return event.window === buttonWindow
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let type = NSApp.currentEvent?.type
        if type == .rightMouseUp {
            pendingShouldShow = nil
            showMenu(with: NSApp.currentEvent)
            return
        }
        if type == .leftMouseDown {
            pendingShouldShow = !actions.prefersHideOnToggle()
            ignoreReopenUntil = Date().addingTimeInterval(0.45)
            return
        }
        ignoreReopenUntil = Date().addingTimeInterval(0.45)
        // Same show/hide as the shortcut — but use the mouse-down snapshot so a
        // reopen Apple Event from this click cannot invert hide ↔ show.
        if let shouldShow = pendingShouldShow {
            pendingShouldShow = nil
            shouldShow ? actions.showCalculator() : actions.hideCalculator()
        } else {
            actions.toggleVisibility()
        }
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
