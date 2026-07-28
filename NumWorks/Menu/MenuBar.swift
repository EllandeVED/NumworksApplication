import AppKit

/// Additions to the main menu that SDL creates during startup.
@MainActor
enum MenuBar {

    /// Inserts a standard "Settings…" (Command-comma) item into the
    /// application menu. Must run after SDL has built the main menu, i.e.
    /// once the Epsilon window is available. Safe to call more than once.
    static func installSettingsItem(target: AnyObject, action: Selector) {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }
        guard !appMenu.items.contains(where: { $0.action == action }) else { return }

        let item = NSMenuItem(title: "Settings…", action: action, keyEquivalent: ",")
        item.target = target

        // SDL's app menu starts with "About <app>" followed by a separator;
        // place Settings after them, in the conventional position.
        let index = min(2, appMenu.items.count)
        appMenu.insertItem(item, at: index)
        appMenu.insertItem(.separator(), at: index + 1)
    }
}
