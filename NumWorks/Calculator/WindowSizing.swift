import AppKit

/// Sizing rules for the calculator window.
///
/// Epsilon's SDL window is created with a content size of 458x888 points and
/// an AppKit content aspect-ratio constraint (set by Epsilon itself in
/// window.mm). All calculations here operate on the *content* size, which is
/// independent of the title bar / toolbar height, so the aspect ratio of the
/// calculator never depends on which chrome style is active.
enum WindowSizing {

    /// Epsilon's "perfect" content size (ion/src/simulator/shared/window.h).
    static let defaultContentSize = NSSize(width: 458, height: 888)

    /// Half the perfect size; below this the calculator becomes unusable.
    static let minimumContentSize = NSSize(width: 229, height: 444)

    static var aspectRatio: CGFloat {
        defaultContentSize.width / defaultContentSize.height
    }

    /// Maximum content size derived from the visible frame of the given
    /// screen, preserving the aspect ratio. Not hard-coded so large displays
    /// can use their full height.
    static func maximumContentSize(for screen: NSScreen?) -> NSSize {
        guard let screen else {
            return NSSize(width: defaultContentSize.width * 4,
                          height: defaultContentSize.height * 4)
        }
        let visible = screen.visibleFrame
        // The title bar takes some of the visible height; keep a small margin.
        let availableHeight = visible.height - 40
        let height = max(availableHeight, minimumContentSize.height)
        return NSSize(width: height * aspectRatio, height: height)
    }

    /// Applies min/max content constraints to the window. The aspect-ratio
    /// constraint itself is owned by Epsilon and left untouched.
    static func applyConstraints(to window: NSWindow) {
        window.contentMinSize = minimumContentSize
        window.contentMaxSize = maximumContentSize(for: window.screen ?? NSScreen.main)
    }

    // MARK: - Frame persistence helpers

    static func encode(frame: NSRect) -> String {
        NSStringFromRect(frame)
    }

    static func decode(frameString: String) -> NSRect? {
        let rect = NSRectFromString(frameString)
        return rect.isEmpty ? nil : rect
    }

    /// True when at least part of the frame's title bar region is on a
    /// connected display, i.e. the user can grab and move the window.
    static func isFrameReachable(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(frame)
        }
    }

    /// Builds the frame to restore at attach time from the saved frame and
    /// the remember-position/-size preferences, falling back to a centred
    /// default frame. `window` provides screen context and chrome metrics.
    static func restorationFrame(
        savedFrame: NSRect?,
        rememberPosition: Bool,
        rememberSize: Bool,
        window: NSWindow
    ) -> NSRect {
        let defaultFrame = centeredFrame(
            contentSize: defaultContentSize, window: window)

        guard let savedFrame, isFrameReachable(savedFrame) else {
            return defaultFrame
        }

        var frame = defaultFrame
        if rememberSize {
            frame.size = clampedSize(savedFrame.size, window: window)
        }
        if rememberPosition {
            frame.origin = savedFrame.origin
        } else {
            // Centre the possibly-resized frame.
            frame.origin = centeredOrigin(for: frame.size, window: window)
        }
        // A remembered origin combined with a different size could push the
        // window off-screen; re-centre in that case.
        if !isFrameReachable(frame) {
            frame.origin = centeredOrigin(for: frame.size, window: window)
        }
        return frame
    }

    static func centeredFrame(contentSize: NSSize, window: NSWindow) -> NSRect {
        let frameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)).size
        return NSRect(origin: centeredOrigin(for: frameSize, window: window),
                      size: frameSize)
    }

    private static func clampedSize(_ size: NSSize, window: NSWindow) -> NSSize {
        let minFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
        let maxContent = maximumContentSize(for: window.screen ?? NSScreen.main)
        let maxFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: maxContent)).size
        let height = min(max(size.height, minFrame.height), maxFrame.height)
        // Width follows from the aspect ratio of the content; approximate by
        // scaling proportionally, AppKit's aspect constraint corrects the rest.
        let scale = height / size.height
        return NSSize(width: size.width * scale, height: height)
    }

    private static func centeredOrigin(for frameSize: NSSize, window: NSWindow) -> NSPoint {
        let screen = window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return .zero }
        return NSPoint(
            x: visible.midX - frameSize.width / 2,
            y: visible.midY - frameSize.height / 2)
    }
}
