import AppKit

/// Sizing rules for the calculator window.
///
/// Epsilon's SDL window is created with a content size of 458x888 points and
/// an AppKit content aspect-ratio constraint (set by Epsilon itself in
/// window.mm). All calculations here operate on the *content* size, which is
/// independent of the title bar / toolbar height, so the aspect ratio of the
/// calculator never depends on which chrome style is active.
enum WindowSizing {

    /// Content size matching the calculator artwork aspect (background.jpg is
    /// 1005×1975). Slightly taller than Epsilon’s historical 458×888 “perfect”
    /// size so the body isn’t cropped at the top/bottom.
    static let defaultContentSize = NSSize(width: 458, height: 900)

    /// Half the default size; below this the calculator becomes unusable.
    static let minimumContentSize = NSSize(width: 229, height: 450)

    /// width / height
    static var aspectRatio: CGFloat {
        defaultContentSize.width / defaultContentSize.height
    }

    static func contentSize(forWidth width: CGFloat) -> NSSize {
        let w = max(width, minimumContentSize.width)
        return NSSize(width: w, height: w / aspectRatio)
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
        let availableHeight = visible.height - 40
        let height = max(availableHeight, minimumContentSize.height)
        return NSSize(width: height * aspectRatio, height: height)
    }

    /// Applies min/max content constraints to the window. The aspect-ratio
    /// constraint itself is owned by Epsilon and left untouched.
    static func applyConstraints(to window: NSWindow) {
        window.contentAspectRatio = defaultContentSize
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
        // Interpret the saved frame size as a frame, convert to content, then
        // force the calculator aspect so a stale chrome-dependent frame can’t
        // keep the window cropped.
        let content = window.contentRect(forFrameRect: NSRect(origin: .zero, size: size)).size
        let corrected = contentSize(forWidth: content.width)
        let minContent = minimumContentSize
        let maxContent = maximumContentSize(for: window.screen ?? NSScreen.main)
        let width = min(max(corrected.width, minContent.width), maxContent.width)
        return window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize(forWidth: width))).size
    }

    private static func centeredOrigin(for frameSize: NSSize, window: NSWindow) -> NSPoint {
        let screen = window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return .zero }
        return NSPoint(
            x: visible.midX - frameSize.width / 2,
            y: visible.midY - frameSize.height / 2)
    }
}
