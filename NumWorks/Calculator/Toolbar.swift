import AppKit
import SwiftUI

/// Actions the toolbar can trigger. Provided by AppController so the toolbar
/// stays free of window-management logic.
struct ToolbarActions {
    let togglePin: () -> Void
    let openSettings: () -> Void
}

/// Owns the NSTitlebarAccessoryViewController hosting the SwiftUI toolbar.
///
/// The accessory is placed at the trailing edge of the standard title bar, so
/// the traffic lights and the centred window title keep their native
/// positions and the calculator content below is never overlapped.
@MainActor
final class CalculatorToolbarController {

    private var accessory: NSTitlebarAccessoryViewController?

    var isAttached: Bool { accessory != nil }

    func attach(to window: NSWindow, preferences: Preferences, actions: ToolbarActions) {
        guard accessory == nil else { return }

        let hostingView = NSHostingView(
            rootView: CalculatorToolbarView(preferences: preferences, actions: actions))
        hostingView.frame.size = hostingView.fittingSize

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = hostingView
        accessory.layoutAttribute = .trailing

        window.addTitlebarAccessoryViewController(accessory)
        self.accessory = accessory
    }

    func detach() {
        accessory?.removeFromParent()
        accessory = nil
    }
}

/// Compact trailing title bar controls: pin (always on top) and settings.
struct CalculatorToolbarView: View {
    @ObservedObject var preferences: Preferences
    let actions: ToolbarActions

    var body: some View {
        HStack(spacing: 4) {
            if preferences.showPinButton {
                ToolbarIconButton(
                    systemImage: preferences.alwaysOnTop ? "pin.fill" : "pin",
                    help: preferences.alwaysOnTop
                        ? "Unpin: stop keeping the calculator above other windows"
                        : "Pin: keep the calculator above other windows",
                    accessibilityLabel: preferences.alwaysOnTop
                        ? "Unpin calculator" : "Pin calculator",
                    isActive: preferences.alwaysOnTop,
                    action: actions.togglePin)
            }
            if preferences.showSettingsButton {
                ToolbarIconButton(
                    systemImage: "gearshape",
                    help: "Open NumWorks settings",
                    accessibilityLabel: "Open settings",
                    isActive: false,
                    action: actions.openSettings)
            }
        }
        .padding(.trailing, 6)
        .frame(height: 28)
    }
}

private struct ToolbarIconButton: View {
    let systemImage: String
    let help: String
    let accessibilityLabel: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }
}
