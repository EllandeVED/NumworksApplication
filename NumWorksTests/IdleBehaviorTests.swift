import Foundation
import Testing
@testable import NumWorks

struct IdleBehaviorTests {
    private let checkedAt = Date(timeIntervalSince1970: 1_000_000)

    @Test func missingAndFutureDates() {
        #expect(UpdateCheckAge.nextRefresh(for: nil, after: checkedAt) == nil)
        #expect(UpdateCheckAge.label(for: nil, now: checkedAt) == "N.A.")
        let future = checkedAt.addingTimeInterval(10)
        #expect(UpdateCheckAge.nextRefresh(for: future, after: checkedAt) == future)
        #expect(UpdateCheckAge.label(for: future, now: checkedAt) == "N.A.")
        #expect(UpdateCheckAge.accessibilityLabel(for: nil, now: checkedAt)
                == "Never checked for updates")
    }

    @Test func schedulesExactlyWhenEachExistingLabelChanges() {
        let cases: [(TimeInterval, TimeInterval, String, String)] = [
            (0.2, 1, "Checked 0s ago", "Checked 1s ago"),
            (59.9, 60, "Checked 59s ago", "Checked 1 min ago"),
            (60, 120, "Checked 1 min ago", "Checked 2 min ago"),
            (3599.9, 3600, "Checked 59 min ago", "Checked 1 hour ago"),
            (3600, 7200, "Checked 1 hour ago", "Checked 2 hours ago"),
            (86399.9, 86400, "Checked 23 hours ago", "Checked 1 day ago"),
            (86400, 172800, "Checked 1 day ago", "Checked 2 days ago"),
            (30 * 86400 - 0.1, 30 * 86400, "Checked 29 days ago", "Checked 1 month ago"),
            (30 * 86400, 60 * 86400, "Checked 1 month ago", "Checked 2 months ago"),
            (360 * 86400 - 0.1, 360 * 86400, "Checked 11 months ago", "Checked 1 year ago"),
            (360 * 86400, 720 * 86400, "Checked 1 year ago", "Checked 2 years ago")
        ]
        for (elapsed, boundary, before, after) in cases {
            let now = checkedAt.addingTimeInterval(elapsed)
            let next = checkedAt.addingTimeInterval(boundary)
            #expect(UpdateCheckAge.nextRefresh(for: checkedAt, after: now) == next)
            #expect(UpdateCheckAge.label(for: checkedAt, now: now) == before)
            #expect(UpdateCheckAge.label(for: checkedAt, now: next) == after)
            #expect(UpdateCheckAge.label(for: checkedAt, now: next.addingTimeInterval(-0.01)) == before)
            #expect(UpdateCheckAge.accessibilityLabel(for: checkedAt, now: next) == after)
        }
    }
}
