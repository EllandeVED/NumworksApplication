import AppKit

/// Visual style of the calculator window.
enum WindowStyle: String, CaseIterable, Identifiable {
    /// Transparent title bar overlaying the calculator (Epsilon’s original
    /// look). Traffic lights sit on the calculator artwork; no title text.
    case native
    /// Opaque standard title bar with the custom pin/settings accessory.
    case toolbar
    /// Placeholder — falls back to `.native` when applied.
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

    var usesAccessoryToolbar: Bool { self == .toolbar }

    /// Configures title-bar chrome. The accessory toolbar is managed by
    /// CalculatorToolbarController separately.
    func applyChrome(to window: NSWindow) {
        switch self {
        case .native, .minimal:
            window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = ""
        case .toolbar:
            window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
            window.styleMask.remove(.fullSizeContentView)
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.title = "NumWorks"
        }
    }
}
