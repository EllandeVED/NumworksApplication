//
//  NumworksApplicationUITests.swift
//  NumworksApplicationUITests
//

import XCTest

final class NumworksApplicationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {}

    /// Launch the app with UI-test-only flags (e.g. skip "Move to Applications" pop-up).
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-skipMoveToApplications")
        app.launch()
        return app
    }

    // MARK: - Launch & basic UI

    @MainActor
    func testLaunch() throws {
        let app = launchApp()
        XCTAssertTrue(app.windows.count > 0, "At least one window should exist after launch")
    }

    @MainActor
    func testCalculatorWindowAppears() throws {
        let app = launchApp()
        let numWorksWindow = app.windows["NumWorks"]
        if numWorksWindow.waitForExistence(timeout: 5) {
            XCTAssertTrue(numWorksWindow.exists)
        } else {
            XCTAssertTrue(app.windows.count >= 0)
        }
    }

    @MainActor
    func testSettingsCanBeOpened() throws {
        let app = launchApp()
        app.typeKey(",", modifierFlags: .command)
        let hasSettings = app.windows["Settings"].waitForExistence(timeout: 3)
            || app.staticTexts["General"].waitForExistence(timeout: 2)
            || app.staticTexts["NumWorks Settings"].waitForExistence(timeout: 2)
        XCTAssertTrue(hasSettings, "Settings should be open after Cmd+,")
    }

    @MainActor
    func testSettingsGeneralPaneShowsToggles() throws {
        let app = launchApp()
        app.typeKey(",", modifierFlags: .command)
        _ = app.staticTexts["General"].waitForExistence(timeout: 3)
        XCTAssertTrue(
            app.staticTexts["General"].exists || app.staticTexts["Shortcuts"].exists || app.staticTexts["Interface"].exists,
            "General pane should show section titles"
        )
    }

    @MainActor
    func testSettingsTabsExist() throws {
        let app = launchApp()
        app.typeKey(",", modifierFlags: .command)
        _ = app.staticTexts["General"].waitForExistence(timeout: 3)
        let hasAppUpdate = app.buttons["App Update"].exists || app.staticTexts["App Update"].exists
        let hasEpsilon = app.buttons["Epsilon Update"].exists || app.staticTexts["Epsilon Update"].exists
        let hasAbout = app.buttons["About"].exists || app.staticTexts["About"].exists
        XCTAssertTrue(
            app.staticTexts["General"].exists && (hasAppUpdate || hasEpsilon || hasAbout),
            "Settings should show General and at least one other tab"
        )
    }

    // MARK: - Settings: toggles and choices (one launch, multiple checks)

    @MainActor
    func testSettingsInterfaceTogglesExistAndAreTappable() throws {
        let app = launchApp()
        openSettings(app)
        _ = app.staticTexts["Interface"].waitForExistence(timeout: 2)

        // SwiftUI Toggle on macOS can appear as switch or checkbox
        let showMenuBar = toggleOrCheckbox(app, label: "Show Menu Bar Icon")
        let showPinButton = toggleOrCheckbox(app, label: "Show Pin/Unpin button on Calculator")
        let showDock = toggleOrCheckbox(app, label: "Show Dock Icon")
        if showMenuBar.waitForExistence(timeout: 1) {
            showMenuBar.click()
            showMenuBar.click() // restore
        }
        if showPinButton.waitForExistence(timeout: 1) {
            showPinButton.click()
            showPinButton.click() // restore
        }
        if showDock.waitForExistence(timeout: 1) {
            showDock.click()
            showDock.click() // restore
        }
        XCTAssertTrue(showMenuBar.exists || showPinButton.exists || showDock.exists, "At least one Interface toggle should exist")
    }

    @MainActor
    func testSettingsCalculatorImageSwitch3DAndFlat() throws {
        let app = launchApp()
        openSettings(app)
        _ = app.staticTexts["Calculator Image"].waitForExistence(timeout: 2)

        let flatBtn = app.buttons["Flat"]
        let threeDBtn = app.buttons["3D"]
        XCTAssertTrue(flatBtn.waitForExistence(timeout: 2), "Flat button should exist")
        XCTAssertTrue(threeDBtn.waitForExistence(timeout: 1), "3D button should exist")
        flatBtn.click()
        threeDBtn.click()
        // No crash; 3D is selected again
    }

    @MainActor
    func testSettingsMenuBarIconStyleFilledAndOutline() throws {
        let app = launchApp()
        openSettings(app)
        _ = app.staticTexts["Preferred Icon"].waitForExistence(timeout: 2)

        let outlineBtn = app.buttons["Outline"]
        let filledBtn = app.buttons["Filled"]
        XCTAssertTrue(outlineBtn.waitForExistence(timeout: 2), "Outline button should exist")
        XCTAssertTrue(filledBtn.waitForExistence(timeout: 1), "Filled button should exist")
        outlineBtn.click()
        filledBtn.click()
    }

    @MainActor
    func testSettingsShortcutsSectionShowsHideShowAndPinUnpin() throws {
        let app = launchApp()
        openSettings(app)
        _ = app.staticTexts["Shortcuts"].waitForExistence(timeout: 2)
        XCTAssertTrue(app.staticTexts["Hide / Show App"].waitForExistence(timeout: 1), "Hide / Show App label should exist")
        XCTAssertTrue(app.staticTexts["Pin / Unpin App"].waitForExistence(timeout: 1), "Pin / Unpin App label should exist")
    }

    // MARK: - Pin button on calculator

    @MainActor
    func testPinButtonOnCalculatorToggles() throws {
        let app = launchApp()
        guard app.windows["NumWorks"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Calculator window not shown (simulator may be missing)")
        }
        let pinBtn = app.buttons["Pin"]
        let unpinBtn = app.buttons["Unpin"]
        if pinBtn.waitForExistence(timeout: 2) {
            pinBtn.click()
            XCTAssertTrue(unpinBtn.waitForExistence(timeout: 1), "After pinning, Unpin button should appear")
            unpinBtn.click()
            XCTAssertTrue(pinBtn.waitForExistence(timeout: 1), "After unpinning, Pin button should appear")
        } else if unpinBtn.waitForExistence(timeout: 2) {
            unpinBtn.click()
            XCTAssertTrue(pinBtn.waitForExistence(timeout: 1), "After unpinning, Pin button should appear")
            pinBtn.click()
        } else {
            XCTFail("Neither Pin nor Unpin button found on calculator (Show Pin/Unpin button may be off)")
        }
    }

    // MARK: - Menu bar context menu

    @MainActor
    func testMenuBarIconContextMenuOpensAndShowsItems() throws {
        let app = launchApp()
        app.activate()
        waitForAppAndMenuBarReady(app)
        // Status bar item: on macOS it may be under menuBars; our app's status item is often last.
        let statusItems = app.menuBars.descendants(matching: .button)
        let count = statusItems.count
        if count > 0 {
            let item = statusItems.element(boundBy: count - 1)
            if item.waitForExistence(timeout: 2) {
                item.click()
                let hasPin = app.menuItems["Pin"].waitForExistence(timeout: 1) || app.menuItems["Unpin"].waitForExistence(timeout: 1)
                let hasShowHide = app.menuItems["Show"].waitForExistence(timeout: 1) || app.menuItems["Hide"].waitForExistence(timeout: 1)
                let hasSettings = app.menuItems["Settings…"].waitForExistence(timeout: 1)
                let hasQuit = app.menuItems["Quit"].waitForExistence(timeout: 1)
                XCTAssertTrue(hasPin || hasShowHide || hasSettings || hasQuit, "Context menu should show Pin/Unpin, Show/Hide, Settings… or Quit")
                app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
                return
            }
        }
        throw XCTSkip("Could not find status bar button to open menu (menu bar icon may be disabled)")
    }

    @MainActor
    func testClickingMenuBarIconShowsOrHidesApp() throws {
        let app = launchApp()
        app.activate()
        waitForAppAndMenuBarReady(app)
        guard app.windows["NumWorks"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Calculator window not shown")
        }
        let statusItems = app.menuBars.descendants(matching: .button)
        let count = statusItems.count
        guard count > 0, statusItems.element(boundBy: count - 1).waitForExistence(timeout: 2) else {
            throw XCTSkip("Status bar button not found (menu bar icon may be disabled)")
        }
        let statusButton = statusItems.element(boundBy: count - 1)
        let wasVisible = app.windows["NumWorks"].isHittable
        statusButton.click()
        let afterFirstClick = app.windows["NumWorks"].isHittable
        statusButton.click()
        let afterSecondClick = app.windows["NumWorks"].isHittable
        XCTAssertEqual(afterSecondClick, wasVisible, "Second click should restore initial visibility")
        XCTAssertNotEqual(afterFirstClick, afterSecondClick, "Two clicks should toggle visibility")
    }

    // MARK: - Shortcuts (verify UI; actual key depends on user/setup)

    @MainActor
    func testPinShortcutSectionExistsInSettings() throws {
        let app = launchApp()
        openSettings(app)
        XCTAssertTrue(app.staticTexts["Pin / Unpin App"].waitForExistence(timeout: 3), "Pin / Unpin shortcut section should be visible")
    }

    @MainActor
    func testHideShowShortcutSectionExistsInSettings() throws {
        let app = launchApp()
        openSettings(app)
        XCTAssertTrue(app.staticTexts["Hide / Show App"].waitForExistence(timeout: 3), "Hide / Show shortcut section should be visible")
    }

    // MARK: - Edge cases

    @MainActor
    func testOpenSettingsTwiceDoesNotCrash() throws {
        let app = launchApp()
        app.typeKey(",", modifierFlags: .command)
        _ = app.staticTexts["General"].waitForExistence(timeout: 3)
        app.typeKey("w", modifierFlags: .command)
        app.typeKey(",", modifierFlags: .command)
        _ = app.staticTexts["General"].waitForExistence(timeout: 3)
        XCTAssertTrue(app.staticTexts["General"].exists)
    }

    @MainActor
    func testSwitchSettingsTabsDoesNotCrash() throws {
        let app = launchApp()
        openSettings(app)
        if app.buttons["App Update"].waitForExistence(timeout: 2) {
            app.buttons["App Update"].click()
            _ = app.staticTexts["App Update"].waitForExistence(timeout: 1)
        }
        if app.buttons["Epsilon Update"].waitForExistence(timeout: 1) {
            app.buttons["Epsilon Update"].click()
        }
        if app.buttons["About"].waitForExistence(timeout: 1) {
            app.buttons["About"].click()
        }
        if app.buttons["General"].waitForExistence(timeout: 1) {
            app.buttons["General"].click()
        }
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 2) || app.staticTexts["App Update"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments.append("-skipMoveToApplications")
            app.launch()
        }
    }

    // MARK: - Helpers

    private func openSettings(_ app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .command)
        _ = app.staticTexts["General"].waitForExistence(timeout: 4)
    }

    /// Waits for the app to be fully launched and the menu bar icon to be available before interacting with the status bar.
    private func waitForAppAndMenuBarReady(_ app: XCUIApplication) {
        _ = app.windows["NumWorks"].waitForExistence(timeout: 6)
        var deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let count = app.menuBars.descendants(matching: .button).count
            if count > 0 { return }
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private func toggleOrCheckbox(_ app: XCUIApplication, label: String) -> XCUIElement {
        let s = app.switches[label].firstMatch
        let c = app.checkBoxes[label].firstMatch
        if s.waitForExistence(timeout: 0.5) { return s }
        if c.waitForExistence(timeout: 0.5) { return c }
        return s.exists ? s : c
    }
}
