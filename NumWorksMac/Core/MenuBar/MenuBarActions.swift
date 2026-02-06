

import Foundation

final class MenuBarActions: ObservableObject {
    @Published private(set) var isPinned: Bool = false
    @Published private(set) var isShown: Bool = false

    private let wm: WindowManagement

    init(wm: WindowManagement) {
        self.wm = wm
        self.isPinned = wm.isPinned
        self.isShown = wm.isShownForUI

        NotificationCenter.default.addObserver(self, selector: #selector(onWMChanged), name: .windowManagementDidChange, object: wm)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func toggleShown() { wm.toggleShown() }
    func togglePinned() { wm.togglePinned() }
    func setPinned(_ enabled: Bool) { wm.setPinned(enabled) }

    @objc private func onWMChanged() {
        isPinned = wm.isPinned
        isShown = wm.isShownForUI
    }
}
