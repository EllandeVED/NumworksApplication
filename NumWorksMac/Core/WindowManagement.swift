import AppKit
import WebKit
import Foundation

extension Notification.Name {
    static let windowManagementDidChange = Notification.Name("windowManagementDidChange")
}

final class WindowManagement {
    private(set) var isPinned = false
    private var appUpdateObserver: NSObjectProtocol?
    private var lastFrame: NSRect?

    var minContentWidth: CGFloat = 260
    var isShownForUI: Bool { window.isVisible && window.isKeyWindow }
    var nsWindow: NSWindow { window }
    var isVisibleForUser: Bool { window.isVisible && window.occlusionState.contains(.visible) }

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

    init() {
        appUpdateObserver = NotificationCenter.default.addObserver(
            forName: .requestAppUpdateUI,
            object: nil,
            queue: .main
        ) { n in
            print("[WindowManagement] received requestAppUpdateUI")
            guard let u = n.userInfo else { return }
            guard let url = u["latestURL"] as? URL else { return }
            let tag = (u["latestTag"] as? String) ?? ""
            Task { @MainActor in
                AppUpdater.shared.presentUpdate(remoteURL: url, remoteVersion: tag)
            }
        }
        isPinned = Preferences.shared.isPinned
    }

    deinit {
        if let o = appUpdateObserver {
            NotificationCenter.default.removeObserver(o)
        }
    }

    func toggleShown() {
        isShown ? hide() : show()
    }

    func show() {
        restoreWindowFrameIfAny()
        applyWindowFlags(window)

        window.windowController?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if isPinned {
            window.orderFrontRegardless()
        }

        NotificationCenter.default.post(name: .windowManagementDidChange, object: self)
    }

    func hide() {
        window.orderOut(nil)
        NotificationCenter.default.post(name: .windowManagementDidChange, object: self)
    }

    func setPinned(_ enabled: Bool) {
        isPinned = enabled
        if window.isVisible {
            applyWindowFlags(window)
            if enabled {
                window.orderFrontRegardless()
            }
        }
        NotificationCenter.default.post(name: .windowManagementDidChange, object: self)
    }

    func togglePinned() {
        Preferences.shared.isPinned.toggle()
        setPinned(Preferences.shared.isPinned)
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
        window.hidesOnDeactivate = false
        window.collectionBehavior.insert(.moveToActiveSpace)
    }

    private func restoreWindowFrameIfAny() {
        if let f = lastFrame {
            window.setFrame(f, display: true)
        }
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
