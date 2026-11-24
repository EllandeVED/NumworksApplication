import Foundation
import XCTest
@testable import Aptabase

private actor MilestoneHTTPProbe: URLSessionProtocol {
    var codes: [Int]
    private(set) var requests: [URLRequest] = []
    init(_ codes: [Int] = [200]) { self.codes = codes }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let status = codes.isEmpty ? 200 : codes.removeFirst()
        return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: status == 429 ? ["Retry-After": "7200"] : [:])!)
    }
    func events() throws -> [[String: String]] {
        try requests.flatMap { request in
            let items = try JSONSerialization.jsonObject(with: request.httpBody!) as! [[String: Any]]
            return items.map { ["name": $0["eventName"] as? String ?? "", "session": $0["sessionId"] as? String ?? ""] }
        }
    }
}

private actor DelayedHTTPProbe: URLSessionProtocol {
    private var response: CheckedContinuation<(Data, URLResponse), Error>?
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var count = 0
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        count += 1; waiting.forEach { $0.resume() }; waiting.removeAll()
        if count > 1 {
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
        }
        return try await withCheckedThrowingContinuation { response = $0 }
    }
    func waitForRequest() async {
        if count > 0 { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func fail() { response?.resume(throwing: URLError(.notConnectedToInternet)); response = nil }
}

final class MilestoneDeliveryTests: XCTestCase {
    private let env = EnvironmentInfo(isDebug: true, osName: "macOS", osVersion: "15.5",
        appVersion: "2.0.17", appBuildNumber: "22", deviceModel: "unit-test")

    @MainActor func testPreparedDeliveryReportsHTTPAcceptanceWithoutDoubleQueueing() async throws {
        let session = MilestoneHTTPProbe([500, 200, 200])
        let client = AptabaseClient(appKey: "A-DEV-000", baseUrl: "https://unit.test", env: env,
            options: InitOptions(flushInterval: 3600), session: session)
        defer { client.stopPolling() }
        let event = try XCTUnwrap(client.prepareEvent("first_launch", with: ["build": .string("22")]))
        let failed = await client.sendPreparedEvent(event)
        XCTAssertEqual(failed, .retryableFailure(statusCode: 500, retryAfter: nil))
        let accepted = await client.sendPreparedEvent(event)
        XCTAssertEqual(accepted, .accepted(statusCode: 200))
        await client.flush()
        let count = await session.requests.count
        XCTAssertEqual(count, 2)
        await client.trackEvent("app_started")
        await client.flush()
        let events = try await session.events()
        XCTAssertEqual(events.map { $0["name"]! }, ["first_launch", "first_launch", "app_started"])
        XCTAssertEqual(Set(events.map { $0["session"]! }), [event.sessionId])
        XCTAssertEqual(event.systemProps.appVersion, "2.0.17")
    }

    @MainActor func test429And403AreNotAcknowledgements() async throws {
        let session = MilestoneHTTPProbe([429, 403])
        let client = AptabaseClient(appKey: "A-DEV-000", baseUrl: "https://unit.test", env: env,
            options: InitOptions(flushInterval: 3600), session: session)
        defer { client.stopPolling() }
        let event = try XCTUnwrap(client.prepareEvent("first_launch"))
        let throttled = await client.sendPreparedEvent(event)
        XCTAssertEqual(throttled, .retryableFailure(statusCode: 429, retryAfter: 7200))
        let rejected = await client.sendPreparedEvent(event)
        XCTAssertEqual(rejected, .rejected(statusCode: 403, diagnostic: "HTTP 403"))
    }

    @MainActor func testOptOutFencesDeferredEnqueuesErrorsAndActivationPolling() async throws {
        let session = MilestoneHTTPProbe()
        let client = AptabaseClient(appKey: "A-DEV-000", baseUrl: "https://unit.test", env: env,
            options: InitOptions(flushInterval: 3600), session: session)
        defer { client.stopPolling() }
        let enqueue: (String, [String: AnyCodableValue]) -> Void = client.trackEvent
        enqueue("queued_before_opt_out", [:])
        client.pauseTracking()
        await client.discardQueuedEvents()
        client.startPolling()
        await client.trackError(URLError(.badURL))
        await client.flush()
        let disabledCount = await session.requests.count
        XCTAssertEqual(disabledCount, 0)
        await client.resumeTracking()
        await client.flush()
        await client.trackEvent("enabled_again")
        await client.flush()
        let events = try await session.events()
        XCTAssertEqual(events.map { $0["name"]! }, ["enabled_again"])
    }

    @MainActor func testAnOldFailedFlushCannotRequeueDiscardedEvents() async {
        let session = DelayedHTTPProbe()
        let client = AptabaseClient(appKey: "A-DEV-000", baseUrl: "https://unit.test", env: env,
            options: InitOptions(flushInterval: 3600), session: session)
        defer { client.stopPolling() }
        await client.trackEvent("old_event")
        let flushing = Task { await client.flush() }
        await session.waitForRequest()
        client.pauseTracking()
        await client.discardQueuedEvents()
        await session.fail()
        await flushing.value
        await client.resumeTracking()
        await client.flush()
        let count = await session.count
        XCTAssertEqual(count, 1)
    }

    func testRetryAfterRejectsNonFiniteNumbersAndHonoursHTTPDates() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(EventDelivery.parseRetryAfter("Thu, 01 Jan 1970 02:00:00 GMT", now: now), 7200)
        XCTAssertEqual(EventDelivery.parseRetryAfter("7200", now: now), 7200)
        for text in ["NaN", "inf", "-1", "invalid"] {
            XCTAssertNil(EventDelivery.parseRetryAfter(text, now: now))
        }
    }
}
