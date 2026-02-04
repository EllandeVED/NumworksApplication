

import Foundation

final class AppController {
    let windowManagement = WindowManagement()

    func start() {
        windowManagement.showCalculatorWindow()
    }
}
