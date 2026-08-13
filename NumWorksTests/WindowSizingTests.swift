//
//  WindowSizingTests.swift
//  NumWorksTests
//

import AppKit
import Testing
@testable import NumWorks

@MainActor
struct WindowSizingTests {

    @Test func aspectRatioMatchesDefaultContent() {
        let expected = WindowSizing.defaultContentSize.width
            / WindowSizing.defaultContentSize.height
        #expect(WindowSizing.aspectRatio == expected)
        #expect(WindowSizing.aspectRatio > 0)
        #expect(WindowSizing.aspectRatio < 1)
    }

    @Test func contentSizePreservesAspectAndRespectsMinimum() {
        let sized = WindowSizing.contentSize(forWidth: 458)
        #expect(abs(sized.width / sized.height - WindowSizing.aspectRatio) < 0.0001)

        let belowMin = WindowSizing.contentSize(forWidth: 10)
        #expect(belowMin.width == WindowSizing.minimumContentSize.width)
        #expect(abs(belowMin.height - WindowSizing.minimumContentSize.height) < 0.5)
    }

    @Test func maximumContentSizeUsesScreenHeightWhenAvailable() {
        let withoutScreen = WindowSizing.maximumContentSize(for: nil)
        #expect(withoutScreen.width == WindowSizing.defaultContentSize.width * 4)

        guard let screen = NSScreen.main else { return }
        let maxSize = WindowSizing.maximumContentSize(for: screen)
        #expect(maxSize.height >= WindowSizing.minimumContentSize.height)
        #expect(abs(maxSize.width / maxSize.height - WindowSizing.aspectRatio) < 0.0001)
        #expect(maxSize.height <= screen.visibleFrame.height)
    }

    @Test func encodeDecodeRoundTrip() {
        let rect = NSRect(x: 12.5, y: 34, width: 458, height: 900)
        let encoded = WindowSizing.encode(frame: rect)
        let decoded = WindowSizing.decode(frameString: encoded)
        #expect(decoded == rect)
    }

    @Test func decodeRejectsEmptyRect() {
        #expect(WindowSizing.decode(frameString: "{{0, 0}, {0, 0}}") == nil)
        #expect(WindowSizing.decode(frameString: "") == nil)
    }

    @Test func unreachableFrameIsDetected() {
        let farAway = NSRect(x: -100_000, y: -100_000, width: 400, height: 800)
        #expect(WindowSizing.isFrameReachable(farAway) == false)

        if let screen = NSScreen.main {
            let onScreen = screen.visibleFrame.insetBy(dx: 40, dy: 40)
            #expect(WindowSizing.isFrameReachable(onScreen) == true)
        }
    }

    /// Creating a live NSWindow while the TEST_HOST runs Epsilon/SDL can terminate
    /// the process, so restorationFrame is covered indirectly via encode/decode +
    /// reachability above (and UI tests for attach behaviour).

    @Test func stressManyContentWidthsStayAboveMinimum() {
        for width in stride(from: 1.0, through: 2_000.0, by: 17) {
            let size = WindowSizing.contentSize(forWidth: width)
            #expect(size.width >= WindowSizing.minimumContentSize.width)
            #expect(size.height >= WindowSizing.minimumContentSize.height - 0.5)
        }
    }
}
