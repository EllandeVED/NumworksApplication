import Foundation
import WebKit

enum WebInjection {
    static let css = """
    :root {
      --nwZoom: 1.18;
      --nwBezelYOffset: 2.1%;
      --nwScreenZoom: 1.04;
      --nwGlobalYOffset: 3.6%;
    }
    html, body {
      margin: 0 !important;
      padding: 0 !important;
      overflow: hidden !important;
      background: transparent !important;
      width: 100% !important;
      height: 100% !important;
    }

    body {
      margin: 0 !important;
      padding: 0 !important;
      overflow: hidden !important;
    }

    .calculator-container {
      width: 100vw !important;
      height: 100vh !important;
      will-change: transform !important;
      transform: translate3d(0, var(--nwGlobalYOffset), 0) scale(var(--nwZoom)) !important;
      transform-origin: center center !important;
      contain: layout paint !important;
    }

    .calculator-container picture {
      display: block !important;
      margin: 0 !important;
      padding: 0 !important;
      width: 100% !important;
      height: 100% !important;
      overflow: hidden !important;
      transform: translateY(var(--nwBezelYOffset)) !important;
    }

    .calculator-container img {
      display: block !important;
      margin: 0 !important;
      padding: 0 !important;
      width: 100% !important;
      height: 100% !important;
      object-fit: cover !important;
      backface-visibility: hidden !important;
      will-change: transform !important;
      transform: translate3d(0, var(--nwBezelYOffset), 0) !important;
    }

    .calculator canvas {
      transform-origin: center center !important;
      transform: scale(var(--nwScreenZoom)) !important;
      will-change: transform !important;
    }

    .actions { display: none !important; }
    .col-fullscreen { display: none !important; }
    """

    static func scripts() -> [WKUserScript] {
        let cssJS = String(data: try! JSONEncoder().encode(css), encoding: .utf8)!
        let js = """
        (function() {
          var css = \(cssJS);
          var style = document.createElement('style');
          style.textContent = css;
          document.head.appendChild(style);

          window.__setCalculatorZoom = function(z) {
            document.documentElement.style.setProperty('--nwZoom', z);
          };

          window.__setCalculatorScreenZoom = function(z) {
            document.documentElement.style.setProperty('--nwScreenZoom', z);
          };

          var sent = false;

          function send(w, h) {
            if (sent) return;
            if (!w || !h) return;
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nwSize) {
              sent = true;
              window.webkit.messageHandlers.nwSize.postMessage({ w: w, h: h });
            }
          }

          function reportSize() {
            var img = document.querySelector('.calculator-container picture img');
            if (!img) {
              var pic = document.querySelector('.calculator-container picture');
              img = pic ? pic.querySelector('img') : null;
            }
            if (img) {
              function sendRect() {
                send(img.naturalWidth, img.naturalHeight);
              }
              if (img.complete) {
                sendRect();
              } else {
                img.addEventListener('load', sendRect, { once: true });
              }
              return;
            }

            var el = document.querySelector('.calculator-container');
            if (!el) return;
            var r = el.getBoundingClientRect();
            send(r.width, r.height);
          }

          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', reportSize);
          } else {
            reportSize();
          }
        })();
        """

        return [WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)]
    }
}
