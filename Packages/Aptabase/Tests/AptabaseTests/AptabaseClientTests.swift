import XCTest
@testable import Aptabase

private enum ClientTestError: Error { case failed }

private actor DeliverySession: URLSessionProtocol {
    let delivered: XCTestExpectation
    private var events: [[String: Any]] = []
    private var attempts = 0

    init(delivered: XCTestExpectation) { self.delivered = delivered }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        attempts += 1
        if attempts == 1 {
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }
        events += try JSONSerialization.jsonObject(with: request.httpBody!) as! [[String: Any]]
        delivered.fulfill()
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func eventNames() -> [String] { events.compactMap { $0["eventName"] as? String } }
}

private actor RecordingSession: URLSessionProtocol {
    let received: XCTestExpectation
    private(set) var bodies: [[String: Any]] = []

    init(received: XCTestExpectation) { self.received = received }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        bodies.append(try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any])
        received.fulfill()
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!)
    }
}

private actor ScheduledDeliverySession: URLSessionProtocol {
    private(set) var attempts = 0
    private(set) var names: [String] = []
    private var failuresRemaining: Int

    init(failures: Int = 0) { failuresRemaining = failures }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        attempts += 1
        await Task.yield()
        let status: Int
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            status = 500
        } else {
            status = 200
            let json = try JSONSerialization.jsonObject(with: request.httpBody!)
            if let events = json as? [[String: Any]] {
                names += events.compactMap { $0["eventName"] as? String }
            }
        }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!)
    }
}

final class AptabaseClientTests: XCTestCase {
    private let env = EnvironmentInfo(isDebug: true, osName: "macOS", osVersion: "14.0", appVersion: "1.0", deviceModel: "Mac")

    @MainActor private func waitUntil(_ condition: @escaping () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    @MainActor func testIdleClientHasNoFlushTimer() async {
        let session = ScheduledDeliverySession()
        let client = AptabaseClient(appKey: "A-DEV-000", baseUrl: "https://test.invalid", env: env,
                                   options: InitOptions(flushInterval: 0.02), session: session)
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(client.isFlushScheduled)
        let attempts = await session.attempts
        XCTAssertEqual(attempts, 0)
        client.startPolling() // App activation must not start an empty repeating timer.
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(client.isFlushScheduled)
    }

    @MainActor func testSuccessfulQueueStopsAndNewEventRestartsScheduling() async {
        let session = ScheduledDeliverySession()
        let client = AptabaseClient(appKey: "A-DEV-000", baseUrl: "https://test.invalid", env: env,
                                   options: InitOptions(flushInterval: 0.02), session: session)
        defer { client.pauseTracking() }
        await client.trackEvent("first")
        let first = await waitUntil { await session.names == ["first"] }
        XCTAssertTrue(first)
        let idle = await waitUntil { !client.isFlushScheduled }
        XCTAssertTrue(idle)
        let attempts = await session.attempts
        try? await Task.sleep(nanoseconds: 60_000_000)
        let stillIdleAttempts = await session.attempts
        XCTAssertEqual(attempts, stillIdleAttempts)
        await client.trackEvent("second")
        let second = await waitUntil { await session.names == ["first", "second"] }
        XCTAssertTrue(second)
        let idleAgain = await waitUntil { !client.isFlushScheduled }
        XCTAssertTrue(idleAgain)
    }

    @MainActor func testRetryKeepsSchedulingOnlyUntilSuccess() async {
        let session = ScheduledDeliverySession(failures: 2)
        let client = AptabaseClient(appKey: "A-DEV-000", baseUrl: "https://test.invalid", env: env,
                                   options: InitOptions(flushInterval: 0.02), session: session)
        defer { client.pauseTracking() }
        await client.trackEvent("retry")
        let delivered = await waitUntil { await session.names == ["retry"] }
        XCTAssertTrue(delivered)
        let idle = await waitUntil { !client.isFlushScheduled }
        XCTAssertTrue(idle)
        let attempts = await session.attempts
        XCTAssertEqual(attempts, 3)
    }

    @MainActor func testManualFlushCancelsLongDeadline() async {
        let session = ScheduledDeliverySession()
        let client = AptabaseClient(appKey: "A-DEV-000", baseUrl: "https://test.invalid", env: env,
                                   options: InitOptions(flushInterval: 3600), session: session)
        defer { client.pauseTracking() }
        await client.trackEvent("manual")
        let scheduled = await waitUntil { client.isFlushScheduled }
        XCTAssertTrue(scheduled)
        await client.flush()
        let idle = await waitUntil { !client.isFlushScheduled }
        XCTAssertTrue(idle)
        let names = await session.names
        XCTAssertEqual(names, ["manual"])
    }

    @MainActor func testPauseCancelsAndResumeSchedulesOnlyNewWork() async {
        let session = ScheduledDeliverySession()
        let client = AptabaseClient(appKey: "A-DEV-000", baseUrl: "https://test.invalid", env: env,
                                   options: InitOptions(flushInterval: 3600), session: session)
        await client.trackEvent("old_consent")
        let scheduled = await waitUntil { client.isFlushScheduled }
        XCTAssertTrue(scheduled)
        client.pauseTracking()
        XCTAssertFalse(client.isFlushScheduled)
        await client.trackEvent("paused")
        client.startPolling()
        XCTAssertFalse(client.isFlushScheduled)
        await client.resumeTracking()
        await client.trackEvent("new_consent")
        await client.flush()
        let names = await session.names
        XCTAssertEqual(names, ["new_consent"])
        client.pauseTracking()
    }

    @MainActor func testConcurrentEnqueueAndFlushCannotCancelNewWork() async {
        let session = ScheduledDeliverySession()
        let client = AptabaseClient(appKey: "A-DEV-000", baseUrl: "https://test.invalid", env: env,
                                   options: InitOptions(flushInterval: 0.02), session: session)
        defer { client.pauseTracking() }
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<80 {
                group.addTask { await client.trackEvent("event_\(i)") }
                if i % 3 == 0 { group.addTask { await client.flush() } }
            }
        }
        let delivered = await waitUntil { await session.names.count == 80 }
        XCTAssertTrue(delivered)
        let names = await session.names
        XCTAssertEqual(Set(names), Set((0..<80).map { "event_\($0)" }))
        XCTAssertEqual(names.count, 80)
        let idle = await waitUntil { !client.isFlushScheduled }
        XCTAssertTrue(idle)
    }

    @MainActor func testFailedImmediateErrorGetsScheduledRetry() async {
        let session = ScheduledDeliverySession(failures: 1)
        let client = AptabaseClient(appKey: "A-DEV-000", baseUrl: "https://test.invalid", env: env,
                                   options: InitOptions(flushInterval: 0.02), session: session)
        defer { client.pauseTracking() }
        await client.trackError(ClientTestError.failed, fatal: false, stackTrace: "test")
        let retried = await waitUntil { await session.attempts == 2 }
        XCTAssertTrue(retried)
        let idle = await waitUntil { !client.isFlushScheduled }
        XCTAssertTrue(idle)
    }

    @MainActor func testInitializationRetriesWithoutActivationNotification() async {
        let delivered = expectation(description: "Timer retries an event without app activation or manual flush")
        let session = DeliverySession(delivered: delivered)
        let client = AptabaseClient(appKey: "A-DEV-000", baseUrl: "http://localhost:3000", env: env,
                                    options: InitOptions(flushInterval: 0.05), session: session)
        defer { client.stopPolling() }
        await client.trackEvent("finder_operation")
        await fulfillment(of: [delivered], timeout: 2)
        let names = await session.eventNames()
        XCTAssertEqual(names, ["finder_operation"])
    }

    @MainActor func testTrackErrorSendsImmediatelyWithCallerStack() async throws {
        let received = expectation(description: "Error report is sent without waiting for the flush timer")
        let session = RecordingSession(received: received)
        let client = AptabaseClient(appKey: "A-DEV-000", baseUrl: "http://localhost:3000", env: env,
                                    options: InitOptions(flushInterval: 3600), session: session)
        defer { client.stopPolling() }

        // the synchronous entry point used by Aptabase.shared.trackError
        let trackError: (any Error, Bool) -> Void = client.trackError
        trackError(ClientTestError.failed, false)

        await fulfillment(of: [received], timeout: 2)
        let bodies = await session.bodies
        let body = try XCTUnwrap(bodies.first)
        XCTAssertEqual(body["errorType"] as? String, "ClientTestError")
        XCTAssertEqual(body["errorMessage"] as? String, "ClientTestError: failed")
        XCTAssertEqual(body["kind"] as? String, "handled")

        let stack = try XCTUnwrap(body["stackTrace"] as? String)
        let firstFrame = stack.split(separator: "\n").first.map(String.init) ?? ""
        XCTAssertTrue(firstFrame.contains("testTrackErrorSendsImmediatelyWithCallerStack"), "first frame should be the caller, got: \(firstFrame)")
        XCTAssertFalse(stack.contains("$s8Aptabase0A6ClientC10trackError"), "SDK frames should be stripped")
    }
}
