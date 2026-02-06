import AppKit


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
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    private(set) var iconStyle: MenuBarIconStyle = .outline
    private(set) var iconSize: CGFloat = 18

    init(wm: WindowManagement) {
        self.wm = wm
        self.actions = MenuBarActions(wm: wm)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        iconStyle = Preferences.shared.menuBarIconStyle
        iconSize = Preferences.shared.menuBarIconSize

        if let b = statusItem.button {
            b.target = self
            b.action = #selector(onStatusItemAction)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        applyIcon()
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
        guard let b = statusItem.button else { return }
        let img = NSImage(named: iconStyle.assetName)
        img?.isTemplate = true
        if let img {
            img.size = NSSize(width: iconSize, height: iconSize)
        }
        b.imageScaling = .scaleProportionallyDown
        b.image = img
    }

    @objc private func onStatusItemAction() {
        let isRight = NSApp.currentEvent?.type == .rightMouseUp
        if isRight {
            togglePopover()
        } else {
            actions.toggleShown()
        }
    }

    private func togglePopover() {
        guard let b = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        }
    }
}
