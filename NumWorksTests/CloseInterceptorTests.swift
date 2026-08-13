//
//  CloseInterceptorTests.swift
//  NumWorksTests
//

import AppKit
import Testing
@testable import NumWorks

/// Avoid constructing NSWindows or calling into the live Epsilon SDL window —
/// the TEST_HOST process is intolerant of that. Behaviour is covered in UI tests
/// (`testCloseButtonHidesCalculatorWithoutTerminating`).
@MainActor
struct CloseInterceptorTests {

    @Test func respondsToWindowShouldClose() {
        let interceptor = CalculatorCloseInterceptor()
        #expect(interceptor.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))))
    }

    @Test func hideCallbackCanBeAssigned() {
        let interceptor = CalculatorCloseInterceptor()
        var called = false
        interceptor.onRequestHide = { called = true }
        interceptor.onRequestHide?()
        #expect(called)
    }
}
