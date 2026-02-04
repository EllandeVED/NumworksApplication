import AppKit
import WebKit

final class WindowManagement {
    private(set) var isAlwaysOnTop = false

    private var baseSize: CGSize?
    private weak var webView: WKWebView?

    private var minContentSize: NSSize = NSSize(width: 360, height: 640)

    private lazy var delegateProxy = DelegateProxy(self)

    private lazy var window: NSWindow = {
        let w = CalculatorWindow.make(self)
        w.delegate = delegateProxy
        applyWindowFlags(w)
        return w
    }()

    func showCalculatorWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideCalculatorWindow() {
        window.orderOut(nil)
    }

    func toggleCalculatorWindow() {
        window.isVisible ? hideCalculatorWindow() : showCalculatorWindow()
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        isAlwaysOnTop = enabled
        applyWindowFlags(window)
    }

    func attachWebView(_ webView: WKWebView) {
        self.webView = webView
    }

    func setBaseSize(_ size: CGSize) {
        baseSize = size
        window.contentAspectRatio = size

        let minW: CGFloat = 120 //Minimum window size
        let minH = minW * size.height / size.width
        minContentSize = NSSize(width: minW, height: minH)

        window.contentMinSize = minContentSize
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minContentSize)).size

        let r = window.contentLayoutRect
        let w = max(minW, r.width)
        window.setContentSize(NSSize(width: w, height: w * size.height / size.width))
    }

    private func applyWindowFlags(_ window: NSWindow) {
        window.level = isAlwaysOnTop ? .floating : .normal
    }

    private final class DelegateProxy: NSObject, NSWindowDelegate {
        private unowned let wm: WindowManagement
        init(_ wm: WindowManagement) { self.wm = wm }
        func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
            let minFrame = sender.frameRect(forContentRect: NSRect(origin: .zero, size: wm.minContentSize)).size
            return NSSize(width: max(frameSize.width, minFrame.width), height: max(frameSize.height, minFrame.height))
        }
    }
}
