import AppKit

final class AppController {
    let windowManagement = WindowManagement()
    private var menuBarController: MenuBarController?

    func start() {
        menuBarController = MenuBarController(wm: windowManagement)
        windowManagement.show()
    }
}
