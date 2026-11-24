import AppKit
import Testing
@testable import NumWorks

@MainActor
struct StatusItemInteractionTests {
    @Test func slowButtonHideKeepsReopenSuppressedUntilTheActionFinishes() {
        let name = "NumWorksTests.statusItem.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "launchAtLoginConfigured")
        defaults.set(false, forKey: "showMenuBarIcon")
        let preferences = Preferences(defaults: defaults)

        var hideCount = 0
        var showCount = 0
        var shouldHide = true
        var suppressedDuringHide = false
        weak var weakController: StatusItemController?
        let controller = StatusItemController(preferences: preferences, actions: .init(
            togglePin: {},
            showCalculator: { showCount += 1 },
            hideCalculator: {
                hideCount += 1
                // AppKit can take longer than the old 450 ms guard to order out.
                Thread.sleep(forTimeInterval: 0.5)
                suppressedDuringHide = weakController?.isEventFromStatusItem(nil) == true
            },
            openSettings: {},
            quit: {},
            isPinned: { false },
            shouldHideOnToggle: { shouldHide }))
        weakController = controller

        #expect(!controller.isEventFromStatusItem(nil))
        controller.handleStatusItemEvent(.leftMouseDown)
        // Clicking the status item may change activation before mouse-up.
        shouldHide = false
        controller.handleStatusItemEvent(.leftMouseUp)
        #expect(hideCount == 1)
        #expect(showCount == 0)
        #expect(suppressedDuringHide)
        // Reopen delivery just after orderOut returns also belongs to this click.
        #expect(controller.isEventFromStatusItem(nil))

        Thread.sleep(forTimeInterval: 0.5)
        #expect(!controller.isEventFromStatusItem(nil))
    }
}
