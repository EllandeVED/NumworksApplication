import SwiftUI
import WebKit

struct CalculatorWebView: NSViewRepresentable {
    var onReady: (WKWebView) -> Void = { _ in }
    var onBaseSize: (CGSize) -> Void = { _ in }

    private let runtime = SimulatorRuntime()

    func makeCoordinator() -> Coordinator { Coordinator(onReady: onReady, onBaseSize: onBaseSize) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if !Preferences.shared.webInjectionDisabled {
            WebInjection.scripts().forEach { config.userContentController.addUserScript($0) }
        }
        config.userContentController.add(context.coordinator, name: "nwSize")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator

        do {
            let url = try runtime.urlToLoad()
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } catch {
            print("[CalculatorWebView] no valid simulator to load: \(error)")
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let onReady: (WKWebView) -> Void
        private let onBaseSize: (CGSize) -> Void
        private var didSendSize = false

        init(onReady: @escaping (WKWebView) -> Void, onBaseSize: @escaping (CGSize) -> Void) {
            self.onReady = onReady
            self.onBaseSize = onBaseSize
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onReady(webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "nwSize", !didSendSize else { return }
            guard let d = message.body as? [String: Any] else { return }
            guard let w = d["w"] as? Double, let h = d["h"] as? Double else { return }
            didSendSize = true
            onBaseSize(CGSize(width: w, height: h))
        }
    }
}

#Preview {
    CalculatorWebView()
}
