//
//  WindowStyleTests.swift
//  NumWorksTests
//

import Testing
@testable import NumWorks

struct WindowStyleTests {

    @Test func availabilityFlags() {
        #expect(WindowStyle.native.isAvailable)
        #expect(WindowStyle.toolbar.isAvailable)
        #expect(WindowStyle.minimal.isAvailable == false)
    }

    @Test func accessoryToolbarOnlyForToolbarStyle() {
        #expect(WindowStyle.toolbar.usesAccessoryToolbar)
        #expect(WindowStyle.native.usesAccessoryToolbar == false)
        #expect(WindowStyle.minimal.usesAccessoryToolbar == false)
    }

    @Test func displayNamesAreStable() {
        #expect(WindowStyle.native.displayName == "Native")
        #expect(WindowStyle.toolbar.displayName == "Toolbar")
        #expect(WindowStyle.minimal.displayName == "Minimal")
    }

    @Test func rawValuesRoundTrip() {
        for style in WindowStyle.allCases {
            #expect(WindowStyle(rawValue: style.rawValue) == style)
        }
    }
}
