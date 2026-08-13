//
//  NumWorksUITests.swift
//  NumWorksUITests
//

import XCTest

/// Lean UI smoke tests. Settings (AppKit) is the harness; calculator AX is optional.
final class NumWorksUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if let app {
            NumWorksUITestSupport.dismissBlockingAlertsOnce(in: app)
            NumWorksUITestSupport.terminate(app)
        }
        app = nil
    }

    @MainActor
    func testLaunchShowsSettingsWithoutAppMover() throws {
        try NumWorksUITestSupport.launch(app)
        let settings = NumWorksUITestSupport.settingsWindow(in: app)
        XCTAssertTrue(settings.exists)
        XCTAssertFalse(app.dialogs["Move to Applications folder"].exists)
        XCTAssertFalse(app.alerts["Move to Applications folder"].exists)
        XCTAssertNotEqual(app.state, .notRunning)
    }

    @MainActor
    func testSettingsTabsSwitch() throws {
        try NumWorksUITestSupport.launch(app, extraArguments: ["--settings-tab=general"])
        let settings = NumWorksUITestSupport.settingsWindow(in: app)
        XCTAssertTrue(settings.exists)

        for tab in ["General", "Window", "Shortcuts", "Advanced", "About"] {
            NumWorksUITestSupport.selectSettingsTab(tab, in: app)
            XCTAssertTrue(settings.exists, "Settings disappeared after \(tab)")
        }
    }

    @MainActor
    func testAboutLicenceSheet() throws {
        try NumWorksUITestSupport.launch(app, extraArguments: ["--settings-tab=about"])
        let settings = NumWorksUITestSupport.settingsWindow(in: app)
        NumWorksUITestSupport.selectSettingsTab("About", in: app)

        let licenceCandidates: [XCUIElement] = [
            settings.buttons["licence-button"],
            settings.buttons["Licence"],
            settings.links["Licence"],
            app.buttons["licence-button"],
            app.buttons["Licence"],
            app.links["Licence"],
        ]
        let licence = licenceCandidates.first { $0.waitForExistence(timeout: 2) }
        guard let licence else {
            throw XCTSkip("Licence control not found in Accessibility tree")
        }
        licence.click()

        let closeCandidates: [XCUIElement] = [
            app.buttons["licence-close-button"],
            app.sheets.buttons["Close"],
            app.dialogs.buttons["Close"],
        ]
        if let close = closeCandidates.first(where: { $0.exists }) {
            close.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
        XCTAssertTrue(settings.exists)
    }

    @MainActor
    func testRestoreDefaultsCancel() throws {
        try NumWorksUITestSupport.launch(app, extraArguments: ["--settings-tab=advanced"])
        let settings = NumWorksUITestSupport.settingsWindow(in: app)
        NumWorksUITestSupport.selectSettingsTab("Advanced", in: app)

        let restoreCandidates: [XCUIElement] = [
            settings.buttons["restore-defaults-button"],
            settings.buttons["Restore Default Settings…"],
            app.buttons["restore-defaults-button"],
            app.buttons["Restore Default Settings…"],
        ]
        let restore = restoreCandidates.first { $0.waitForExistence(timeout: 2) }
        guard let restore else {
            throw XCTSkip("Restore Defaults control not found")
        }
        restore.click()

        // Prefer Escape — multiple "Cancel" buttons can exist in the AX tree.
        let scopedCancel = app.dialogs.buttons["Cancel"].firstMatch
        if scopedCancel.waitForExistence(timeout: 2) {
            scopedCancel.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
        XCTAssertTrue(settings.exists)
        XCTAssertNotEqual(app.state, .notRunning)
    }

    @MainActor
    func testSettingsSurvivesRapidOpenClose() throws {
        try NumWorksUITestSupport.launch(app)
        let settings = NumWorksUITestSupport.settingsWindow(in: app)
        XCTAssertTrue(settings.exists)

        for _ in 0..<4 {
            settings.buttons[XCUIIdentifierCloseWindow].click()
            // Re-open via menu / Cmd+,
            let item = app.menuItems["Settings…"]
            if item.waitForExistence(timeout: 2) {
                item.click()
            } else {
                app.typeKey(",", modifierFlags: .command)
            }
            XCTAssertTrue(
                settings.waitForExistence(timeout: NumWorksUITestSupport.controlTimeout)
                    || NumWorksUITestSupport.settingsWindow(in: app).exists)
        }
        XCTAssertNotEqual(app.state, .notRunning)
    }

    @MainActor
    func testCalculatorWindowOptionalUnderAccessibility() throws {
        try NumWorksUITestSupport.launch(app, showCalculator: true)
        // SDL windows are often invisible to AX — skip instead of hanging.
        guard let calculator = NumWorksUITestSupport.calculatorWindow(in: app) else {
            throw XCTSkip("Calculator window not exposed to Accessibility (expected with SDL)")
        }
        XCTAssertTrue(calculator.exists)
        XCTAssertNotEqual(app.state, .notRunning)
    }
}
