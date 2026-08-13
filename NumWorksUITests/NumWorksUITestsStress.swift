//
//  NumWorksUITestsStress.swift
//  NumWorksUITests
//

import XCTest

/// Opt-in stress (`NUMWORKS_UI_STRESS=1`). Skipped by default so Test doesn’t stall.
final class NumWorksUITestsStress: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(
            !NumWorksUITestSupport.stressEnabled,
            "Set NUMWORKS_UI_STRESS=1 to run UI stress tests.")
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if let app {
            NumWorksUITestSupport.terminate(app)
        }
        app = nil
    }

    @MainActor
    func testWindowStyleToggleStress() throws {
        try NumWorksUITestSupport.launch(
            app, extraArguments: ["--settings-tab=window"])
        let settings = NumWorksUITestSupport.settingsWindow(in: app)
        XCTAssertTrue(settings.exists)

        for _ in 0..<10 {
            if settings.radioButtons["Native"].exists {
                settings.radioButtons["Native"].click()
            }
            if settings.radioButtons["Toolbar"].exists {
                settings.radioButtons["Toolbar"].click()
            }
        }
        XCTAssertNotEqual(app.state, .notRunning)
    }

    @MainActor
    func testSettingsOpenCloseStress() throws {
        try NumWorksUITestSupport.launch(app)
        let settings = NumWorksUITestSupport.settingsWindow(in: app)

        for _ in 0..<10 {
            if settings.exists {
                settings.buttons[XCUIIdentifierCloseWindow].click()
            }
            app.typeKey(",", modifierFlags: .command)
            _ = settings.waitForExistence(timeout: 3)
        }
        XCTAssertNotEqual(app.state, .notRunning)
    }
}
