import AppKit
import WebKit
import Foundation

extension Notification.Name {
    static let windowManagementDidChange = Notification.Name("windowManagementDidChange")
}

final class WindowManagement {
    private(set) var isPinned = false
    private var lastFrame: NSRect?
    
    var minContentWidth: CGFloat = 260
    var isShownForUI: Bool { window.isVisible && window.isKeyWindow }

    private var isShown: Bool {
        window.isVisible && window.isKeyWindow
    }

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

    func toggleShown() {
        isShown ? hide() : show()
    }

    func show() {
        if let f = lastFrame {
            window.setFrame(f, display: true)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        applyWindowFlags(window)
        NotificationCenter.default.post(name: .windowManagementDidChange, object: self)
    }

    func hide() {
        lastFrame = window.frame
        window.orderOut(nil)
        NotificationCenter.default.post(name: .windowManagementDidChange, object: self)
    }

    func setPinned(_ enabled: Bool) {
        isPinned = enabled
        if window.isVisible {
            applyWindowFlags(window)
        }
        NotificationCenter.default.post(name: .windowManagementDidChange, object: self)
    }

    func togglePinned() {
        setPinned(!isPinned)
    }

    func attachWebView(_ webView: WKWebView) {
        self.webView = webView
    }

    func setBaseSize(_ size: CGSize) {
        baseSize = size
        window.contentAspectRatio = size

        let minW = minContentWidth
        let minH = minW * size.height / size.width
        minContentSize = NSSize(width: minW, height: minH)

        window.contentMinSize = minContentSize
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minContentSize)).size

        let r = window.contentLayoutRect
        let w = max(minW, r.width)
        window.setContentSize(NSSize(width: w, height: w * size.height / size.width))
    }

    private func applyWindowFlags(_ window: NSWindow) {
        window.level = isPinned ? .floating : .normal
        window.collectionBehavior.insert(.moveToActiveSpace)
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
