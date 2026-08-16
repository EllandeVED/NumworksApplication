import AppKit

/// In Native style, fades the traffic lights until the pointer is near them.
/// Toolbar style always shows them at full opacity.
///
/// Uses a local event monitor (not an `NSTrackingArea` on the SDL view).
/// Tracking areas on Epsilon’s window have hung the main thread after the
/// app resigns key — the wait cursor then appears over the calculator and
/// the menu-bar extra.
@MainActor
final class NativeTrafficLightsController {

    private weak var window: NSWindow?
    private var mouseMonitor: Any?
    private var hoverEnabled = false
    /// Top-leading hit zone (window coordinates, origin bottom-left).
    private let hoverSize = NSSize(width: 110, height: 52)

    func apply(hoverUntilPointerNearby: Bool, to window: NSWindow) {
        self.window = window
        hoverEnabled = hoverUntilPointerNearby

        if hoverUntilPointerNearby {
            setAlpha(pointerIsInHoverZone(of: window) ? 1 : 0, in: window)
            startMonitorIfNeeded()
        } else {
            stopMonitor()
            setAlpha(1, in: window)
        }
    }

    func pause() {
        stopMonitor()
    }

    func invalidate() {
        stopMonitor()
        if let window {
            setAlpha(1, in: window)
        }
        window = nil
        hoverEnabled = false
    }

    // MARK: - Private

    private func startMonitorIfNeeded() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .mouseEntered, .mouseExited]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.updateForMouseEvent(event)
            }
            return event
        }
    }

    private func stopMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    private func updateForMouseEvent(_ event: NSEvent) {
        guard hoverEnabled, let window else { return }
        // Only the calculator window; ignore Settings / status-item traffic.
        guard event.window === window || window.isKeyWindow else { return }
        let target = event.window ?? window
        guard target === window else {
            setAlpha(0, in: window)
            return
        }
        setAlpha(pointerIsInHoverZone(of: window) ? 1 : 0, in: window)
    }

    private func pointerIsInHoverZone(of window: NSWindow) -> Bool {
        let loc = window.mouseLocationOutsideOfEventStream
        let zone = NSRect(
            x: 0,
            y: window.frame.height - hoverSize.height,
            width: hoverSize.width,
            height: hoverSize.height)
        return zone.contains(loc)
    }

    private func setAlpha(_ alpha: CGFloat, in window: NSWindow) {
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            if abs(button.alphaValue - alpha) > 0.01 {
                button.alphaValue = alpha
            }
        }
    }
}
