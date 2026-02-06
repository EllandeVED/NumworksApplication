import Foundation
import CoreGraphics

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private init() {}

    @Published var menuBarIconStyle: MenuBarIconStyle = .filled
    @Published var menuBarIconSize: CGFloat = 20

    @Published var isMenuBarIconEnabled: Bool = true
    @Published var isPinned: Bool = false
    @Published var isAppVisible: Bool = true
}
