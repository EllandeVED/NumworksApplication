import AppKit
import Combine

/// Actions the toolbar can trigger. Provided by AppController so the toolbar
/// stays free of window-management logic.
struct ToolbarActions {
    let togglePin: () -> Void
    let openSettings: () -> Void
}

/// Owns an AppKit titlebar accessory (no SwiftUI / ViewBridge).
///
/// Pure AppKit avoids the RemoteViewService cancellations that crashed the
/// app when the calculator was shown and hidden from the status item.
@MainActor
final class CalculatorToolbarController: NSObject {

    private var accessory: NSTitlebarAccessoryViewController?
    private var pinButton: NSButton?
    private var settingsButton: NSButton?
    private var stack: NSStackView?
    private var actions: ToolbarActions?
    private weak var preferences: Preferences?
    private var cancellables = Set<AnyCancellable>()

    var isAttached: Bool { accessory != nil }

    func attach(to window: NSWindow, preferences: Preferences, actions: ToolbarActions) {
        self.preferences = preferences
        self.actions = actions
        observePreferences(preferences)

        if accessory == nil {
            let pin = makeIconButton(
                toolTip: "Pin",
                accessibilityLabel: "Pin calculator",
                action: #selector(pinClicked(_:)))
            let settings = makeIconButton(
                toolTip: "Open NumWorks settings",
                accessibilityLabel: "Open settings",
                action: #selector(settingsClicked(_:)))
            settings.image = NSImage(
                systemSymbolName: "gearshape",
                accessibilityDescription: "Settings")

            let stack = NSStackView(views: [pin, settings])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 2
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 6)
            stack.setHuggingPriority(.required, for: .horizontal)
            stack.translatesAutoresizingMaskIntoConstraints = false

            let container = NSView(frame: NSRect(x: 0, y: 0, width: 64, height: 28))
            container.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                container.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
                container.heightAnchor.constraint(equalToConstant: 28),
            ])

            let accessory = NSTitlebarAccessoryViewController()
            accessory.view = container
            accessory.layoutAttribute = .trailing
            window.addTitlebarAccessoryViewController(accessory)

            self.accessory = accessory
            self.pinButton = pin
            self.settingsButton = settings
            self.stack = stack
        }

        // Keep the accessory installed across style flips; only hide it in Native.
        accessory?.isHidden = false
        refresh()
    }

    /// Hides without removing — avoids title-bar rebuild jank when flipping styles.
    func setVisible(_ visible: Bool) {
        accessory?.isHidden = !visible
    }

    func detach(from window: NSWindow) {
        cancellables.removeAll()
        if let accessory,
           let index = window.titlebarAccessoryViewControllers.firstIndex(of: accessory) {
            window.removeTitlebarAccessoryViewController(at: index)
        }
        accessory = nil
        pinButton = nil
        settingsButton = nil
        stack = nil
        actions = nil
        preferences = nil
    }

    func refresh() {
        guard let preferences, let stack else { return }

        pinButton?.isHidden = !preferences.showPinButton
        settingsButton?.isHidden = !preferences.showSettingsButton

        let pinned = preferences.alwaysOnTop
        pinButton?.image = NSImage(
            systemSymbolName: pinned ? "pin.fill" : "pin",
            accessibilityDescription: pinned ? "Unpin" : "Pin")
        pinButton?.toolTip = pinned
            ? "Unpin: stop keeping the calculator above other windows"
            : "Pin: keep the calculator above other windows"
        pinButton?.setAccessibilityLabel(
            pinned ? "Unpin calculator" : "Pin calculator")
        pinButton?.setAccessibilityIdentifier(
            pinned ? "Unpin calculator" : "Pin calculator")
        pinButton?.contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor

        // Keep stack width tight when buttons are hidden.
        stack.needsLayout = true
        accessory?.view.needsLayout = true
    }

    private func observePreferences(_ preferences: Preferences) {
        cancellables.removeAll()
        preferences.$alwaysOnTop
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        preferences.$showPinButton
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        preferences.$showSettingsButton
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func makeIconButton(
        toolTip: String,
        accessibilityLabel: String,
        action: Selector
    ) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 22))
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.toolTip = toolTip
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityIdentifier(accessibilityLabel)
        button.target = self
        button.action = action
        button.refusesFirstResponder = true
        return button
    }

    @objc private func pinClicked(_ sender: Any?) {
        actions?.togglePin()
    }

    @objc private func settingsClicked(_ sender: Any?) {
        actions?.openSettings()
    }
}
