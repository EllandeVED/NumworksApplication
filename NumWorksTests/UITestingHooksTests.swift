//
//  UITestingHooksTests.swift
//  NumWorksTests
//

import Testing
@testable import NumWorks

struct UITestingHooksTests {

    @Test func settingsTabRawValuesCoverAllCases() {
        for tab in ["general", "window", "shortcuts", "advanced", "about"] {
            #expect(SettingsTab(rawValue: tab) != nil)
        }
        #expect(SettingsTab(rawValue: "bogus") == nil)
    }

    @Test func menuBarIconStylesHaveDistinctAssets() {
        #expect(MenuBarIconStyle.outline.imageName != MenuBarIconStyle.filled.imageName)
        #expect(MenuBarIconStyle.outline.displayName == "Outline")
        #expect(MenuBarIconStyle.filled.displayName == "Filled")
    }

    @Test func appMoverOfferCapIsTwo() {
        #expect(Preferences.appMoverOffersPerVersion == 2)
    }
}
