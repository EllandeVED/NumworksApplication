import AppKit

/// Visual style of the calculator window.
enum WindowStyle: String, CaseIterable, Identifiable {
    /// Standard macOS title bar, no custom accessory toolbar.
    case native
    /// Standard title bar plus the custom titlebar accessory with pin and
    /// settings buttons. Default mode.
    case toolbar
    /// Placeholder: a borderless window that remains movable, resizable and
    /// recoverable needs a dedicated implementation, so this option is
    /// disabled in the UI for now and falls back to `.native` when applied.
    case minimal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .native: return "Native"
        case .toolbar: return "Toolbar"
        case .minimal: return "Minimal"
        }
    }

    var isAvailable: Bool { self != .minimal }

    /// Whether the custom titlebar accessory should be attached in this style.
    var usesAccessoryToolbar: Bool { self == .toolbar }

    /// Applies the style's window chrome. The accessory toolbar itself is
    /// managed by CalculatorToolbarController; this only configures the
    /// title bar. Upstream Epsilon uses a transparent, full-size-content
    /// title bar; both of our styles use a standard opaque title bar so the
    /// toolbar never overlaps the calculator content, and so the SDL content
    /// view keeps its exact aspect-ratio-constrained size.
    func applyChrome(to window: NSWindow) {
        window.styleMask.remove(.fullSizeContentView)
        window.titlebarAppearsTransparent = false
        window.title = "NumWorks"
        window.titleVisibility = .visible
    }
}
