import AppKit
import SwiftUI

enum CalculatorWindow {
    static func make(_ wm: WindowManagement) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NumWorks"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: CalculatorView(wm: wm))
        return window
    }
}
