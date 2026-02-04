import SwiftUI
import WebKit

struct CalculatorView: View {
    let wm: WindowManagement

    var body: some View {
        CalculatorWebView(
            onReady: { wm.attachWebView($0) },
            onBaseSize: { wm.setBaseSize($0) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    CalculatorView(wm: WindowManagement())
}
