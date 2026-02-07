import SwiftUI

@main
struct NumWorksMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .defaultSize(width: 520, height: 420)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}
