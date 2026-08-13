//
//  NumWorksUITestsLaunchTests.swift
//  NumWorksUITests
//

import XCTest

final class NumWorksUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchScreenshot() throws {
        let app = XCUIApplication()
        defer { NumWorksUITestSupport.terminate(app) }

        try NumWorksUITestSupport.launch(app)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["NUMWORKS_UI_PERF"] != "1",
            "Set NUMWORKS_UI_PERF=1 to run launch performance (slow; relaunches the app).")

        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = NumWorksUITestSupport.isolationArguments
            app.launch()
            _ = app.windows["NumWorks Settings"].waitForExistence(timeout: 12)
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 5)
        }
    }
}
