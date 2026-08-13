import XCTest

/// Shared launch / alert helpers so popups never strand the suite.
///
/// ## Why these tests stay Settings-first
/// Epsilon runs on the main thread (SDL). Accessibility queries against the
/// calculator window often never return, which looks like a “stall”. Settings
/// is a normal AppKit/SwiftUI window and is opened automatically under
/// `--ui-testing` so XCTest has something reliable to wait on.
///
/// macOS also needs Accessibility permission for Xcode / `xcodebuild`.
enum NumWorksUITestSupport {

    /// Hard cap for “app finished attaching”.
    static let readyTimeout: TimeInterval = 12
    /// Hard cap for individual controls.
    static let controlTimeout: TimeInterval = 3

    static var isolationArguments: [String] {
        [
            "--ui-testing",
            "-ApplePersistenceIgnoreState", "YES",
        ]
    }

    static var stressEnabled: Bool {
        ProcessInfo.processInfo.environment["NUMWORKS_UI_STRESS"] == "1"
    }

    /// Launch, wait until Settings exists (attach complete), optionally show calculator.
    static func launch(
        _ app: XCUIApplication,
        extraArguments: [String] = [],
        showCalculator: Bool = false
    ) throws {
        if app.state != .notRunning {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 5)
        }

        var args = isolationArguments
        args.append(contentsOf: extraArguments)
        // Settings is the AX harness; omit only with --no-settings.
        if showCalculator {
            args.append("--show-calculator")
        }
        app.launchArguments = args
        app.launch()

        guard app.wait(for: .runningForeground, timeout: readyTimeout)
            || app.state == .runningBackground
        else {
            throw XCTSkip("NumWorks did not reach a running state (Automation/Accessibility?)")
        }

        dismissBlockingAlertsOnce(in: app)

        let settings = app.windows["NumWorks Settings"]
        let settingsById = app.windows["settings-window"]
        let ready = settings.waitForExistence(timeout: readyTimeout)
            || settingsById.waitForExistence(timeout: 1)
        guard ready else {
            throw XCTSkip(
                "Settings window never appeared — attach stalled or Accessibility blocked. "
                    + "Check System Settings → Privacy & Security → Accessibility for Xcode.")
        }
    }

    static func terminate(_ app: XCUIApplication) {
        guard app.state != .notRunning else { return }
        app.terminate()
        _ = app.wait(for: .notRunning, timeout: 5)
    }

    /// One-shot dismiss — never spin for seconds (AX against SDL can hang).
    static func dismissBlockingAlertsOnce(in app: XCUIApplication) {
        let titles = ["Do Not Move", "Don’t Move", "Don't Move", "Later", "Cancel", "OK"]
        for title in titles {
            let button = app.dialogs.buttons[title]
            if button.exists {
                button.click()
                return
            }
            let alertButton = app.alerts.buttons[title]
            if alertButton.exists {
                alertButton.click()
                return
            }
        }
    }

    static func settingsWindow(in app: XCUIApplication) -> XCUIElement {
        let byTitle = app.windows["NumWorks Settings"]
        if byTitle.exists { return byTitle }
        return app.windows["settings-window"]
    }

    /// SDL calculator — may be missing from Accessibility; callers should XCTSkip.
    static func calculatorWindow(in app: XCUIApplication) -> XCUIElement? {
        let byId = app.windows["calculator-window"]
        if byId.waitForExistence(timeout: controlTimeout) { return byId }
        let byTitle = app.windows["NumWorks"]
        if byTitle.waitForExistence(timeout: 1) { return byTitle }
        return nil
    }

    static func selectSettingsTab(_ name: String, in app: XCUIApplication) {
        let settings = settingsWindow(in: app)
        let candidates: [XCUIElement] = [
            settings.tabs[name],
            settings.radioButtons[name],
            settings.buttons[name],
            settings.staticTexts[name],
        ]
        for element in candidates where element.exists {
            element.click()
            return
        }
    }
}
