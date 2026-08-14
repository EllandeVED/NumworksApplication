import AppKit

/// In Native style, fades the traffic lights until the pointer is near them.
/// Toolbar style always shows them at full opacity.
///
/// Uses an `NSTrackingArea` on the calculator window instead of a local
/// `mouseMoved` monitor. A mouseMoved monitor forces high-frequency mouse
/// events for the whole app (including Settings scrolling) and shows up as
/// elevated energy impact.
final class NativeTrafficLightsController: NSResponder {

    private weak var trackedWindow: NSWindow?
    private weak var trackingView: NSView?
    private var trackingArea: NSTrackingArea?
    private var hoverEnabled = false
    /// Top-leading hit zone (window coordinates, origin bottom-left).
    private let hoverSize = NSSize(width: 110, height: 52)

    func apply(hoverUntilPointerNearby: Bool, to window: NSWindow) {
        trackedWindow = window
        hoverEnabled = hoverUntilPointerNearby

        if hoverUntilPointerNearby {
            installTracking(on: window)
            setAlpha(pointerIsInHoverZone(of: window) ? 1 : 0, in: window)
        } else {
            removeTracking()
            setAlpha(1, in: window)
        }
    }

    /// Drop the tracking area while the calculator is ordered out.
    func pause() {
        removeTracking()
    }

    func invalidate() {
        removeTracking()
        if let trackedWindow {
            setAlpha(1, in: trackedWindow)
        }
        trackedWindow = nil
        hoverEnabled = false
    }

    // MARK: - Tracking

    private func installTracking(on window: NSWindow) {
        guard let view = window.standardWindowButton(.closeButton)?.superview
                ?? window.contentView else { return }
        if trackingView === view, trackingArea != nil { return }
        removeTracking()
        let area = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeInKeyWindow,
                .inVisibleRect,
            ],
            owner: self,
            userInfo: nil)
        view.addTrackingArea(area)
        trackingView = view
        trackingArea = area
    }

    private func removeTracking() {
        if let trackingArea, let trackingView {
            trackingView.removeTrackingArea(trackingArea)
        }
        trackingArea = nil
        trackingView = nil
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover()
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover()
    }

    override func mouseExited(with event: NSEvent) {
        guard let trackedWindow else { return }
        setAlpha(0, in: trackedWindow)
    }

    private func updateHover() {
        guard hoverEnabled, let trackedWindow, trackedWindow.isKeyWindow else { return }
        setAlpha(pointerIsInHoverZone(of: trackedWindow) ? 1 : 0, in: trackedWindow)
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
