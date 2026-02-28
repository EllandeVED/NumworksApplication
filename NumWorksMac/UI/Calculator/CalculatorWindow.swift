import AppKit
import SwiftUI

enum CalculatorWindow {
    static func make(_ wm: WindowManagement) -> NSWindow {
        let ratio: CGFloat = {
            guard let img = NSImage(named: "CalculatorImage"), img.size.width > 0, img.size.height > 0 else {
                return 360 / 640
            }
            return img.size.width / img.size.height
        }()
        let width: CGFloat = 420
        let height = width / ratio
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
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
