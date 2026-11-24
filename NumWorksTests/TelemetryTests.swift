import Foundation
import Testing
import Aptabase
@testable import NumWorks

@Suite(.serialized)
struct TelemetryTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(version: String = "2.0.17", build: String = "22",
                        mode: TelemetryBuildMode = .release, generation: Int = 0,
                        timestamp: Date? = nil, session: String = "original-session",
                        milestone: TelemetryMilestone = .firstLaunch)
        -> PendingTelemetryMilestone {
        let date = timestamp ?? base
        let identity = TelemetryMilestoneIdentity(version: version, build: build, mode: mode, milestone: milestone)
        let event = Event(timestamp: date, sessionId: session, eventName: milestone.rawValue,
            systemProps: Event.SystemProps(isDebug: mode == .debug, locale: "en", osName: "macOS",
                osVersion: "15.5", appVersion: version, appBuildNumber: build,
                sdkVersion: "aptabase-swift@0.4.0", deviceModel: "unit-test"),
            props: ["version": .string(version), "build": .string(build)])
        return PendingTelemetryMilestone(id: UUID(), identity: identity, consentGeneration: generation,
                                         event: PreparedEvent(event: event), nextAttemptAt: date)
    }

    private func box(_ store: TestTelemetryStore, _ sender: any TelemetrySending,
                     _ clock: TestTelemetryClock,
                     onAccepted: @escaping @Sendable (TelemetryMilestoneIdentity) async -> Void = { _ in })
        -> TelemetryOutbox {
        TelemetryOutbox(store: store, sender: sender, clock: clock, automaticRetry: false,
                        onAccepted: onAccepted)
    }

    @Test func automaticSchedulingRetriesWithoutManualFlushes() async throws {
        let store = TestTelemetryStore()
        let sender = ScriptedMilestoneSender([
            .retryableFailure(statusCode: 500, retryAfter: nil), .accepted(statusCode: 200)])
        let clock = AdvancingTelemetryClock(base)
        let outbox = TelemetryOutbox(store: store, sender: sender, clock: clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(record())
        for _ in 0..<400 {
            if store.saved.acknowledged.count == 1 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        await outbox.prepareForTermination()
        #expect(await sender.events.count == 2)
        #expect(store.saved.acknowledged.count == 1)
        #expect(clock.now() >= base.addingTimeInterval(2))
    }

    @Test func successfulMilestoneIsAcknowledgedOnce() async {
        let store = TestTelemetryStore(), sender = ScriptedMilestoneSender()
        let clock = TestTelemetryClock(base)
        let outbox = box(store, sender, clock)
        let event = record()
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(event)
        await outbox.processDue()
        #expect(await sender.events.count == 1)
        #expect(store.saved.pending.isEmpty)
        #expect(store.saved.acknowledged.first?.recordID == event.id)
        #expect(store.saved.acknowledged.first?.kind == .accepted)
        await outbox.enqueue(record())
        await outbox.processDue()
        #expect(await sender.events.count == 1)

        let second = box(store, sender, clock)
        await second.configure(enabled: true, consentGeneration: 0)
        await second.enqueue(record())
        await second.processDue()
        #expect(await sender.events.count == 1)
    }

    @Test func checkpointBeforeHTTPIsDurableAcrossRelaunch() async {
        let store = TestTelemetryStore(), sender = ScriptedMilestoneSender()
        let clock = TestTelemetryClock(base), event = record()
        let first = box(store, sender, clock)
        await first.configure(enabled: true, consentGeneration: 0)
        await first.enqueue(event)
        await first.prepareForTermination()
        #expect(await sender.events.isEmpty)
        #expect(store.saved.pending.first?.id == event.id)

        let second = box(store, sender, clock)
        await second.configure(enabled: true, consentGeneration: 0)
        await second.enqueue(record())
        await second.processDue()
        #expect(await sender.events.count == 1)
        #expect(store.saved.acknowledged.first?.recordID == event.id)
    }

    @Test func offlineThenRelaunchRetainsOriginalPayload() async {
        let store = TestTelemetryStore()
        let failed = ScriptedMilestoneSender([.retryableFailure(statusCode: nil, retryAfter: nil)])
        let clock = TestTelemetryClock(base), event = record()
        let first = box(store, failed, clock)
        await first.configure(enabled: true, consentGeneration: 0)
        await first.enqueue(event)
        await first.processDue()
        #expect(store.saved.acknowledged.isEmpty)
        #expect(store.saved.pending.first?.id == event.id)
        await first.prepareForTermination()

        clock.advance(2)
        let sender = ScriptedMilestoneSender()
        let second = box(store, sender, clock)
        await second.configure(enabled: true, consentGeneration: 0)
        await second.enqueue(record(timestamp: clock.now(), session: "new-session"))
        await second.processDue()
        #expect(await sender.events.first == event.event)
        #expect(store.saved.acknowledged.first?.recordID == event.id)
    }

    @Test func http500HasNoAcknowledgementUntilLaterAcceptance() async {
        let store = TestTelemetryStore()
        let sender = ScriptedMilestoneSender([
            EventDelivery.interpret(statusCode: 500, error: nil, retryAfterHeader: nil),
            .accepted(statusCode: 200)])
        let clock = TestTelemetryClock(base), outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(record())
        await outbox.processDue()
        #expect(store.saved.acknowledged.isEmpty)
        #expect(store.saved.pending.first?.lastHTTPStatus == 500)
        await outbox.processDue()
        #expect(await sender.events.count == 1)
        clock.advance(2)
        await outbox.processDue()
        #expect(await sender.events.count == 2)
        #expect(store.saved.acknowledged.count == 1)
    }

    @Test func retryAfterIsAnUncappedServerMinimum() async {
        let store = TestTelemetryStore()
        let sender = ScriptedMilestoneSender([
            EventDelivery.interpret(statusCode: 429, error: nil, retryAfterHeader: "7200", now: base),
            .accepted(statusCode: 200)])
        let clock = TestTelemetryClock(base), outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(record())
        await outbox.processDue()
        #expect(store.saved.pending.first?.nextAttemptAt == base.addingTimeInterval(7200))
        clock.advance(7199)
        await outbox.processDue()
        #expect(await sender.events.count == 1)
        clock.advance(1)
        await outbox.processDue()
        #expect(await sender.events.count == 2)
    }

    @Test func invalidRetryAfterFallsBackToBoundedLocalDelay() {
        #expect(TelemetryOutbox.backoff(attempt: 1, retryAfter: .nan) == 2)
        #expect(TelemetryOutbox.backoff(attempt: 1, retryAfter: .infinity) == 2)
        #expect(TelemetryOutbox.backoff(attempt: 1, retryAfter: -1) == 2)
        #expect(TelemetryOutbox.backoff(attempt: 1000) == 900)
        #expect(TelemetryOutbox.backoff(attempt: 1, retryAfter: 7200) == 7200)
    }

    @Test func rejected403WaitsForLaterLaunchAfter24Hours() async {
        let store = TestTelemetryStore()
        let sender = ScriptedMilestoneSender([.rejected(statusCode: 403, diagnostic: "HTTP 403")])
        let clock = TestTelemetryClock(base), outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(record())
        await outbox.processDue()
        #expect(store.saved.acknowledged.isEmpty)
        #expect(store.saved.pending.first?.rejected == true)
        clock.advance(24 * 60 * 60)
        await outbox.processDue()
        #expect(await sender.events.count == 1)
        await outbox.prepareForTermination()
        let next = box(store, sender, clock)
        await next.configure(enabled: true, consentGeneration: 0)
        await next.processDue()
        #expect(await sender.events.count == 2)
        #expect(store.saved.acknowledged.count == 1)
    }

    @Test func initialPersistenceFailureSendsNothingThenRecovers() async {
        let store = TestTelemetryStore()
        store.failWrites(after: 0)
        let sender = ScriptedMilestoneSender()
        let clock = TestTelemetryClock(base), outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(record())
        await outbox.processDue()
        #expect(await sender.events.isEmpty)
        #expect(await outbox.lastStorageError != nil)
        store.failWrites(after: nil)
        clock.advance(2)
        await outbox.processDue()
        #expect(await sender.events.count == 1)
        #expect(store.saved.acknowledged.count == 1)
    }

    @Test func failedAcknowledgementWriteNeverResendsAcceptedEvent() async {
        let store = TestTelemetryStore()
        store.failWrites(after: 1)
        let sender = ScriptedMilestoneSender(), callbacks = AcceptedIdentities()
        let clock = TestTelemetryClock(base)
        let outbox = box(store, sender, clock, onAccepted: { await callbacks.append($0) })
        let event = record()
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(event)
        await outbox.processDue()
        #expect(await sender.events.count == 1)
        #expect(store.saved.pending.first?.id == event.id)
        #expect(store.saved.acknowledged.isEmpty)
        #expect(await callbacks.values.isEmpty)
        for _ in 0..<5 { await outbox.processDue() }
        #expect(await sender.events.count == 1)
        clock.advance(2)
        await outbox.processDue() // Still a failed disk write, not another HTTP request.
        #expect(await sender.events.count == 1)
        store.failWrites(after: nil)
        clock.advance(4)
        await outbox.processDue()
        #expect(await sender.events.count == 1)
        #expect(store.saved.pending.isEmpty)
        #expect(store.saved.acknowledged.first?.recordID == event.id)
        #expect(await callbacks.values == [event.identity])
    }

    @Test func loadFailureDoesNotOverwriteOrSubmitAssumedEmptyHistory() async {
        let previous = record(version: "2.0.15", build: "20")
        let oldAck = record(version: "2.0.14", build: "19")
        let store = TestTelemetryStore(TelemetryOutboxSnapshot(
            pending: [previous], acknowledged: [TelemetryAcknowledgement(
                identity: oldAck.identity, recordID: oldAck.id, kind: .accepted)]))
        store.failReads(true)
        let sender = ScriptedMilestoneSender()
        let clock = TestTelemetryClock(base), outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(record())
        await outbox.processDue()
        #expect(store.saveCount == 0)
        #expect(await sender.events.isEmpty)
        #expect(await outbox.snapshotForTesting() == nil)
        #expect(store.saved.pending.first?.id == previous.id)
        store.failReads(false)
        clock.advance(2)
        await outbox.processDue()
        #expect(await sender.events.count == 2)
        #expect(store.saved.acknowledged.contains { $0.recordID == oldAck.id })
        #expect(store.saved.acknowledged.contains { $0.recordID == previous.id })
    }

    @Test func fileRoundTripRetainsPayloadAndRestrictivePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TelemetryFileStore(directory: directory)
        #expect(try store.load().pending.isEmpty)
        let event = record(timestamp: base.addingTimeInterval(0.123456))
        try store.save(TelemetryOutboxSnapshot(pending: [event]))
        let loaded = try store.load()
        #expect(loaded.pending.first?.event == event.event)
        #expect(loaded.pending.first?.id == event.id)
        let fm = FileManager.default
        let folderMode = try fm.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        let fileMode = try fm.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? NSNumber
        #expect(folderMode?.intValue == 0o700)
        #expect(fileMode?.intValue == 0o600)
    }

    @Test func corruptFileIsPreservedWithoutNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = TelemetryFileStore(directory: directory), original = Data("broken-json".utf8)
        try original.write(to: store.file)
        let sender = ScriptedMilestoneSender()
        let outbox = TelemetryOutbox(store: store, sender: sender,
            clock: TestTelemetryClock(base), automaticRetry: false)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(record())
        await outbox.processDue()
        #expect(await sender.events.isEmpty)
        #expect(try Data(contentsOf: store.file) == original)
        #expect(await outbox.lastStorageError != nil)
    }

    @Test func pendingReloadWithAcknowledgementDoesNotCrashOrResend() async {
        let event = record()
        let store = TestTelemetryStore(TelemetryOutboxSnapshot(
            pending: [event], acknowledged: [TelemetryAcknowledgement(
                identity: event.identity, recordID: event.id, kind: .accepted)]))
        let sender = ScriptedMilestoneSender(), outbox = box(store, sender, TestTelemetryClock(base))
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.processDue()
        #expect(await sender.events.isEmpty)
        #expect(store.saved.pending.isEmpty)
    }

    @Test func delayedSendAndOverlappingTriggersNeverAckEarly() async {
        let store = TestTelemetryStore(), sender = GatedMilestoneSender()
        let outbox = box(store, sender, TestTelemetryClock(base))
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(record())
        let pumping = Task { await outbox.processDue() }
        await sender.waitForRequest()
        for _ in 0..<10 { await outbox.processDue() }
        #expect(await sender.count == 1)
        #expect(store.saved.acknowledged.isEmpty)
        #expect(await outbox.hasRequestForTesting())
        await sender.complete(.accepted(statusCode: 200))
        await pumping.value
        #expect(store.saved.acknowledged.count == 1)
    }

    @Test func disablingDuringRequestIgnoresLateAcceptance() async {
        let store = TestTelemetryStore(), sender = GatedMilestoneSender()
        let outbox = box(store, sender, TestTelemetryClock(base))
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(record())
        let pumping = Task { await outbox.processDue() }
        await sender.waitForRequest()
        await outbox.configure(enabled: false, consentGeneration: 1)
        await outbox.processDue()
        await sender.complete(.accepted(statusCode: 200))
        await pumping.value
        #expect(store.saved.pending.isEmpty)
        #expect(store.saved.acknowledged.isEmpty)
    }

    @Test func failedOptOutWriteCannotResurrectRecordsAfterReenable() async {
        let old = record()
        let store = TestTelemetryStore(TelemetryOutboxSnapshot(pending: [old]))
        store.failWrites(after: 0)
        let sender = ScriptedMilestoneSender()
        let clock = TestTelemetryClock(base), outbox = box(store, sender, clock)
        await outbox.configure(enabled: false, consentGeneration: 1)
        await outbox.processDue()
        #expect(store.saved.pending.first?.id == old.id)
        store.failWrites(after: nil)
        let fresh = record(generation: 1, session: "after-opt-in")
        let second = box(store, sender, clock)
        await second.configure(enabled: true, consentGeneration: 1)
        await second.enqueue(fresh)
        await second.processDue()
        #expect(await sender.events.count == 1)
        #expect(await sender.events.first?.sessionId == "after-opt-in")
        #expect(store.saved.acknowledged.first?.recordID == fresh.id)
    }

    @Test func terminationReturnsBeforeHangingNetworkAndRetainsPendingRecord() async {
        let store = TestTelemetryStore(), sender = GatedMilestoneSender()
        let outbox = box(store, sender, TestTelemetryClock(base)), event = record()
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(event)
        let pumping = Task { await outbox.processDue() }
        await sender.waitForRequest()
        await outbox.prepareForTermination()
        // The transport is still blocked here: no timeout race or HTTP wait.
        #expect(await sender.count == 1)
        #expect(store.saved.pending.first?.id == event.id)
        await sender.complete(.cancelled)
        await pumping.value
        #expect(store.saved.acknowledged.isEmpty)
    }

    @Test func cancellationWithoutTaskCancellationBacksOff() async {
        let store = TestTelemetryStore()
        let sender = ScriptedMilestoneSender([.cancelled, .accepted(statusCode: 200)])
        let clock = TestTelemetryClock(base), outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(record())
        await outbox.processDue()
        #expect(await sender.events.count == 1)
        #expect(store.saved.acknowledged.isEmpty)
        clock.advance(2)
        await outbox.processDue()
        #expect(await sender.events.count == 2)
        #expect(store.saved.acknowledged.count == 1)
    }

    @Test func debugAndReleaseHaveIndependentMilestones() async {
        let store = TestTelemetryStore(), sender = ScriptedMilestoneSender()
        let clock = TestTelemetryClock(base)
        for mode in [TelemetryBuildMode.debug, .release] {
            let outbox = box(store, sender, clock)
            await outbox.configure(enabled: true, consentGeneration: 0)
            await outbox.enqueue(record(mode: mode))
            await outbox.processDue()
            await outbox.prepareForTermination()
        }
        #expect(await sender.events.count == 2)
        #expect(store.saved.acknowledged.count == 2)
    }

    @Test func legacyMarkerSkipsOnlyThatReleaseVersion() async {
        let store = TestTelemetryStore(), sender = ScriptedMilestoneSender()
        let outbox = box(store, sender, TestTelemetryClock(base))
        let legacy = record(version: "2.0.16", build: "21")
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.importLegacySkip(legacy.identity)
        await outbox.enqueue(legacy)
        await outbox.enqueue(record(version: "2.0.16", build: "21", mode: .debug))
        await outbox.enqueue(record())
        await outbox.processDue()
        #expect(await sender.events.count == 2)
        #expect(store.saved.acknowledged.contains { $0.kind == .legacySkip && $0.identity == legacy.identity })
    }

    @Test func olderPendingBuildKeepsMetadataAfterUpgrade() async {
        let old = record(version: "2.0.16", build: "21")
        let store = TestTelemetryStore(TelemetryOutboxSnapshot(pending: [old]))
        let sender = ScriptedMilestoneSender(), callbacks = AcceptedIdentities()
        let clock = TestTelemetryClock(base.addingTimeInterval(30))
        let outbox = box(store, sender, clock, onAccepted: { await callbacks.append($0) })
        let current = record(timestamp: clock.now())
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(current)
        await outbox.processDue()
        #expect(await sender.events.first == old.event)
        #expect(await callbacks.values == [old.identity, current.identity])
        #expect(store.saved.acknowledged.contains { $0.recordID == old.id })
    }

    private func acceptedFirstSnapshot() -> TelemetryOutboxSnapshot {
        let first = record()
        return TelemetryOutboxSnapshot(acknowledged: [TelemetryAcknowledgement(
            identity: first.identity, recordID: first.id, kind: .accepted)])
    }

    private func firstUserSession(_ store: TestTelemetryStore, _ clock: TestTelemetryClock,
                                  session: UUID = UUID()) async -> UUID {
        let outbox = box(store, ScriptedMilestoneSender(), clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.recordLaunch(session: session, secondLaunch: record(milestone: .secondLaunch))
        await outbox.prepareForTermination()
        return session
    }

    @Test func secondLaunchRequiresTwoDistinctQualifyingSessionsAndNeverRepeats() async {
        let store = TestTelemetryStore(), sender = ScriptedMilestoneSender(), clock = TestTelemetryClock(base)
        let session = UUID()
        let first = box(store, sender, clock)
        await first.configure(enabled: true, consentGeneration: 0)
        await first.enqueue(record())
        for _ in 0..<10 {
            await first.recordLaunch(session: session, secondLaunch: record(milestone: .secondLaunch))
        }
        await first.processDue()
        #expect(await sender.events.map(\.eventName) == ["first_launch"])
        #expect(store.saved.launches.first?.firstSession == session)
        #expect(store.saved.launches.first?.secondSession == nil)
        await first.prepareForTermination()

        let moved = box(store, sender, clock)
        await moved.configure(enabled: true, consentGeneration: 0)
        await moved.recordLaunch(session: session, secondLaunch: record(milestone: .secondLaunch))
        await moved.processDue()
        #expect(await sender.events.count == 1) // AppMover carries the original token.
        await moved.prepareForTermination()

        for _ in 0..<3 {
            let next = box(store, sender, clock)
            await next.configure(enabled: true, consentGeneration: 0)
            await next.enqueue(record())
            await next.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
            await next.processDue()
            await next.prepareForTermination()
        }
        #expect(await sender.events.map(\.eventName) == ["first_launch", "second_launch"])
        #expect(store.saved.acknowledged.count == 2)
    }

    @Test func backgroundStartsWithoutCalculatorUseNeverAdvanceSecondLaunch() async {
        let store = TestTelemetryStore(), sender = ScriptedMilestoneSender(), clock = TestTelemetryClock(base)
        for _ in 0..<4 {
            let outbox = box(store, sender, clock)
            await outbox.configure(enabled: true, consentGeneration: 0)
            await outbox.enqueue(record())
            await outbox.processDue()
            await outbox.prepareForTermination()
        }
        #expect(store.saved.launches.isEmpty)
        #expect(await sender.events.map(\.eventName) == ["first_launch"])
    }

    @Test func secondLaunchIsSavedOnImmediateQuitWithoutWaitingForHTTP() async {
        let store = TestTelemetryStore(acceptedFirstSnapshot()), clock = TestTelemetryClock(base)
        _ = await firstUserSession(store, clock)
        let sender = GatedMilestoneSender(), outbox = box(store, sender, clock)
        let second = record(milestone: .secondLaunch), session = UUID()
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.recordLaunch(session: session, secondLaunch: second)
        await outbox.prepareForTermination()
        #expect(await sender.count == 0)
        #expect(store.saved.pending.first?.id == second.id)
        #expect(store.saved.launches.first?.secondSession == session)
        let resumed = box(store, ScriptedMilestoneSender(), clock)
        await resumed.configure(enabled: true, consentGeneration: 0)
        await resumed.processDue()
        #expect(store.saved.acknowledged.contains { $0.identity.milestone == .secondLaunch })
    }

    @Test func offlineFirstAndSecondLaunchesRecoverInOrderWithOriginalPayloads() async {
        let store = TestTelemetryStore(), clock = TestTelemetryClock(base)
        let firstEvent = record()
        let offline = ScriptedMilestoneSender([.retryableFailure(statusCode: 500, retryAfter: 30)])
        let first = box(store, offline, clock)
        await first.configure(enabled: true, consentGeneration: 0)
        await first.enqueue(firstEvent)
        await first.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await first.processDue()
        await first.prepareForTermination()

        clock.advance(1)
        let secondEvent = record(timestamp: clock.now(), session: "second-session", milestone: .secondLaunch)
        let sender = ScriptedMilestoneSender(), second = box(store, sender, clock)
        await second.configure(enabled: true, consentGeneration: 0)
        await second.recordLaunch(session: UUID(), secondLaunch: secondEvent)
        await second.processDue()
        #expect(await sender.events.isEmpty)
        #expect(store.saved.pending.count == 2)
        clock.advance(29)
        await second.processDue()
        #expect(await sender.events == [firstEvent.event, secondEvent.event])
        #expect(store.saved.pending.isEmpty)
    }

    @Test func secondLaunchOfflineRetryAfterRestartDoesNotCreateAnotherMilestone() async {
        let store = TestTelemetryStore(acceptedFirstSnapshot()), clock = TestTelemetryClock(base)
        _ = await firstUserSession(store, clock)
        let event = record(milestone: .secondLaunch)
        let offline = ScriptedMilestoneSender([.retryableFailure(statusCode: nil, retryAfter: nil)])
        let outbox = box(store, offline, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.recordLaunch(session: UUID(), secondLaunch: event)
        await outbox.processDue()
        await outbox.prepareForTermination()
        #expect(store.saved.pending.first?.id == event.id)
        clock.advance(2)
        let sender = ScriptedMilestoneSender(), resumed = box(store, sender, clock)
        await resumed.configure(enabled: true, consentGeneration: 0)
        await resumed.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await resumed.processDue()
        #expect(await sender.events == [event.event])
        #expect(store.saved.acknowledged.filter { $0.identity.milestone == .secondLaunch }.count == 1)
    }

    @Test func secondLaunch429HonoursTwoHourMinimum() async {
        let store = TestTelemetryStore(acceptedFirstSnapshot()), clock = TestTelemetryClock(base)
        _ = await firstUserSession(store, clock)
        let sender = ScriptedMilestoneSender([
            .retryableFailure(statusCode: 429, retryAfter: 7_200), .accepted(statusCode: 200)])
        let outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await outbox.processDue()
        clock.advance(7_199)
        await outbox.processDue()
        #expect(await sender.events.count == 1)
        #expect(store.saved.pending.first?.nextAttemptAt == base.addingTimeInterval(7_200))
        clock.advance(1)
        await outbox.processDue()
        #expect(await sender.events.count == 2)
        #expect(store.saved.pending.isEmpty)
    }

    @Test func rejectedSecondLaunchWaitsForLaterProcessAfter24Hours() async {
        let store = TestTelemetryStore(acceptedFirstSnapshot()), clock = TestTelemetryClock(base)
        _ = await firstUserSession(store, clock)
        let sender = ScriptedMilestoneSender([.rejected(statusCode: 403, diagnostic: "test")])
        let outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await outbox.processDue()
        clock.advance(86_400)
        await outbox.processDue()
        #expect(await sender.events.count == 1)
        #expect(store.saved.pending.first?.rejected == true)
        await outbox.prepareForTermination()
        let resumed = box(store, sender, clock)
        await resumed.configure(enabled: true, consentGeneration: 0)
        await resumed.processDue()
        #expect(await sender.events.count == 2)
        #expect(store.saved.pending.isEmpty)
    }

    @Test func rejectedFirstLaunchCannotBeOvertakenBySecondLaunch() async {
        let store = TestTelemetryStore(), clock = TestTelemetryClock(base)
        let sender = ScriptedMilestoneSender([.rejected(statusCode: 403, diagnostic: "test")])
        let outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(record())
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await outbox.processDue()
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await outbox.processDue()
        #expect(await sender.events.map(\.eventName) == ["first_launch"])
        #expect(store.saved.pending.count == 2)
        await outbox.prepareForTermination()
        clock.advance(86_400)
        let resumed = box(store, sender, clock)
        await resumed.configure(enabled: true, consentGeneration: 0)
        await resumed.processDue()
        #expect(await sender.events.map(\.eventName) == ["first_launch", "first_launch", "second_launch"])
    }

    @Test func secondLaunchCounterAndEventAreOneCheckpointOnWriteFailure() async {
        let store = TestTelemetryStore(acceptedFirstSnapshot()), clock = TestTelemetryClock(base)
        _ = await firstUserSession(store, clock)
        let before = store.saveCount
        store.failWrites(after: before)
        let sender = ScriptedMilestoneSender(), outbox = box(store, sender, clock)
        let event = record(milestone: .secondLaunch)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.recordLaunch(session: UUID(), secondLaunch: event)
        await outbox.processDue()
        #expect(await sender.events.isEmpty)
        #expect(store.saved.launches.first?.secondSession == nil)
        #expect(store.saved.pending.isEmpty)
        store.failWrites(after: nil)
        clock.advance(2)
        await outbox.processDue()
        #expect(await sender.events == [event.event])
        #expect(store.saved.launches.first?.secondSession != nil)
    }

    @Test func failedSecondLaunchAcknowledgementWriteRetriesDiskOnly() async {
        let store = TestTelemetryStore(acceptedFirstSnapshot()), clock = TestTelemetryClock(base)
        _ = await firstUserSession(store, clock)
        store.failWrites(after: store.saveCount + 1)
        let sender = ScriptedMilestoneSender(), outbox = box(store, sender, clock)
        let event = record(milestone: .secondLaunch)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.recordLaunch(session: UUID(), secondLaunch: event)
        await outbox.processDue()
        #expect(await sender.events.count == 1)
        #expect(store.saved.pending.first?.id == event.id)
        for _ in 0..<8 { await outbox.processDue() }
        clock.advance(2)
        await outbox.processDue()
        #expect(await sender.events.count == 1)
        store.failWrites(after: nil)
        clock.advance(4)
        await outbox.processDue()
        #expect(await sender.events.count == 1)
        #expect(store.saved.pending.isEmpty)
    }

    @Test func readFailurePreservesExistingLaunchHistoryUntilRecovery() async {
        let store = TestTelemetryStore(acceptedFirstSnapshot()), clock = TestTelemetryClock(base)
        let firstSession = await firstUserSession(store, clock)
        let savedWrites = store.saveCount
        store.failReads(true)
        let sender = ScriptedMilestoneSender(), outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await outbox.processDue()
        #expect(store.saveCount == savedWrites)
        #expect(store.saved.launches.first?.firstSession == firstSession)
        #expect(await sender.events.isEmpty)
        store.failReads(false)
        clock.advance(2)
        await outbox.processDue()
        #expect(await sender.events.map(\.eventName) == ["second_launch"])
    }

    @Test func preFeatureJSONMigratesWithoutInventingSecondLaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = TelemetryFileStore(directory: directory)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var legacy = try #require(JSONSerialization.jsonObject(with: encoder.encode(acceptedFirstSnapshot())) as? [String: Any])
        legacy.removeValue(forKey: "launches")
        var acks = try #require(legacy["acknowledged"] as? [[String: Any]])
        var identity = try #require(acks[0]["identity"] as? [String: Any])
        identity.removeValue(forKey: "milestone")
        acks[0]["identity"] = identity
        legacy["acknowledged"] = acks
        try JSONSerialization.data(withJSONObject: legacy).write(to: store.file)
        let migrated = try store.load()
        #expect(migrated.acknowledged.first?.identity.milestone == .firstLaunch)
        #expect(migrated.launches.isEmpty)
        let sender = ScriptedMilestoneSender(), clock = TestTelemetryClock(base)
        let outbox = TelemetryOutbox(store: store, sender: sender, clock: clock, automaticRetry: false)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(record())
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await outbox.processDue()
        #expect(await sender.events.isEmpty)
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await outbox.processDue()
        #expect(await sender.events.map(\.eventName) == ["second_launch"])
    }

    @Test func legacyFirstSkipNeverSuppressesSecondLaunch() async {
        let store = TestTelemetryStore(), sender = ScriptedMilestoneSender(), clock = TestTelemetryClock(base)
        let outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.importLegacySkip(record().identity)
        await outbox.importLegacySkip(record(milestone: .secondLaunch).identity) // Invalid migration request.
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await outbox.processDue()
        #expect(await sender.events.isEmpty)
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await outbox.processDue()
        #expect(await sender.events.map(\.eventName) == ["second_launch"])
    }

    @Test func launchHistoriesAreIndependentForVersionsBuildsAndModes() async {
        let store = TestTelemetryStore(), sender = ScriptedMilestoneSender(), clock = TestTelemetryClock(base)
        let outbox = box(store, sender, clock), session = UUID()
        await outbox.configure(enabled: true, consentGeneration: 0)
        let pairs: [(String, String, TelemetryBuildMode)] = [
            ("2.0.17", "22", .release), ("2.0.17", "22", .debug),
            ("2.0.17", "23", .release), ("2.0.18", "22", .release)]
        for (version, build, mode) in pairs {
            await outbox.enqueue(record(version: version, build: build, mode: mode))
            await outbox.recordLaunch(session: session, secondLaunch: record(
                version: version, build: build, mode: mode, milestone: .secondLaunch))
            await outbox.processDue()
        }
        #expect(await sender.events.count == 4)
        #expect(store.saved.launches.count == 4)
        #expect(store.saved.launches.allSatisfy { $0.secondSession == nil })
        for (version, build, mode) in pairs {
            await outbox.recordLaunch(session: UUID(), secondLaunch: record(
                version: version, build: build, mode: mode, milestone: .secondLaunch))
            await outbox.processDue()
        }
        #expect(await sender.events.filter { $0.eventName == "second_launch" }.count == 4)
    }

    @Test func optingOutDeletesSecondLaunchHistoryAndPendingEvent() async {
        let store = TestTelemetryStore(acceptedFirstSnapshot()), clock = TestTelemetryClock(base)
        _ = await firstUserSession(store, clock)
        let sender = ScriptedMilestoneSender(), outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await outbox.configure(enabled: false, consentGeneration: 1)
        await outbox.processDue()
        #expect(store.saved.launches.isEmpty)
        #expect(store.saved.pending.isEmpty)
        #expect(await sender.events.isEmpty)
        await outbox.configure(enabled: true, consentGeneration: 1)
        let current = UUID()
        await outbox.recordLaunch(session: current, secondLaunch: record(generation: 1, milestone: .secondLaunch))
        await outbox.processDue()
        #expect(await sender.events.isEmpty)
        #expect(store.saved.launches.first?.firstSession == current)
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(generation: 1, milestone: .secondLaunch))
        await outbox.processDue()
        #expect(await sender.events.map(\.eventName) == ["second_launch"])
    }

    @Test func optingOutDuringSecondLaunchRequestIgnoresLateAcceptance() async {
        let store = TestTelemetryStore(acceptedFirstSnapshot()), clock = TestTelemetryClock(base)
        _ = await firstUserSession(store, clock)
        let sender = GatedMilestoneSender(), outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        let pumping = Task { await outbox.processDue() }
        await sender.waitForRequest()
        await outbox.configure(enabled: false, consentGeneration: 1)
        await outbox.processDue()
        await sender.complete(.accepted(statusCode: 200))
        await pumping.value
        #expect(store.saved.launches.isEmpty)
        #expect(!store.saved.acknowledged.contains { $0.identity.milestone == .secondLaunch })
    }

    @Test func failedOptOutWriteDoesNotResurrectSecondLaunchAfterRestart() async {
        let store = TestTelemetryStore(acceptedFirstSnapshot()), clock = TestTelemetryClock(base)
        _ = await firstUserSession(store, clock)
        let old = box(store, ScriptedMilestoneSender(), clock)
        await old.configure(enabled: true, consentGeneration: 0)
        await old.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await old.prepareForTermination()
        #expect(store.saved.pending.count == 1)
        store.failWrites(after: store.saveCount)
        let disabled = box(store, ScriptedMilestoneSender(), clock)
        await disabled.configure(enabled: false, consentGeneration: 1)
        await disabled.processDue()
        store.failWrites(after: nil)
        let sender = ScriptedMilestoneSender(), resumed = box(store, sender, clock)
        await resumed.configure(enabled: true, consentGeneration: 1)
        await resumed.recordLaunch(session: UUID(), secondLaunch: record(generation: 1, milestone: .secondLaunch))
        await resumed.processDue()
        #expect(await sender.events.isEmpty)
        #expect(store.saved.pending.isEmpty)
        #expect(store.saved.launches.first?.consentGeneration == 1)
        #expect(store.saved.launches.first?.secondSession == nil)
    }

    @Test func concurrentDuplicateUseHooksOnlyAdvanceOneSession() async {
        let store = TestTelemetryStore(acceptedFirstSnapshot()), sender = ScriptedMilestoneSender()
        let clock = TestTelemetryClock(base), outbox = box(store, sender, clock)
        let session = UUID(), event = record(milestone: .secondLaunch)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask { await outbox.recordLaunch(session: session, secondLaunch: event) }
            }
        }
        await outbox.processDue()
        #expect(store.saved.launches.count == 1)
        #expect(store.saved.launches.first?.secondSession == nil)
        #expect(await sender.events.isEmpty)
    }

    @Test func relaunchSessionTokenIsLocalValidatedAndReusedOnlyWhenPassed() throws {
        let original = TelemetryLaunchSession(environment: [:])
        let relocated = TelemetryLaunchSession(environment: [TelemetryLaunchSession.environmentKey: original.id.uuidString])
        #expect(relocated.id == original.id)
        #expect(original.relaunchEnvironment == "\(TelemetryLaunchSession.environmentKey)=\(original.id.uuidString)")
        let fallback = UUID()
        #expect(TelemetryLaunchSession(environment: [TelemetryLaunchSession.environmentKey: "invalid"], fallback: fallback).id == fallback)
        #expect(TelemetryLaunchSession(environment: [:], fallback: fallback).id == fallback)
        let json = String(decoding: try JSONEncoder().encode(record(milestone: .secondLaunch).event), as: UTF8.self)
        #expect(!json.contains(original.id.uuidString))
        #expect(!json.contains(TelemetryLaunchSession.environmentKey))
    }

    @Test func anotherAppCopyCannotOverwriteLiveOwnersSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let waiting = TelemetryFileStore(directory: directory)
        do {
            let owner = TelemetryFileStore(directory: directory)
            try owner.save(acceptedFirstSnapshot())
            #expect(throws: (any Error).self) { try waiting.load() }
            #expect(throws: (any Error).self) { try waiting.save(.init()) }
            #expect(try owner.load().acknowledged.count == 1)
        }
        #expect(try waiting.load().acknowledged.count == 1)
    }

    @Test func moverRelaunchPreservesArgumentsWithoutShellExpansion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stub = directory.appendingPathComponent("fake open")
        try Data("#!/bin/sh\nprintf '%s\\0' \"$@\"\n".utf8).write(to: stub)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stub.path)
        let session = TelemetryLaunchSession(environment: [:])
        let path = "/tmp/Applications with spaces/'\";$(printf UNEXPECTED)\nNumWorks.app"
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = session.relaunchArguments(processID: .max, path: path, openExecutable: stub.path)
        process.standardOutput = output
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(bytes.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
            == ["--env", session.relaunchEnvironment, path])
    }

    @Test func completedSecondLaunchRemainsDoneAfterOptOutAndReenable() async {
        let store = TestTelemetryStore(acceptedFirstSnapshot()), clock = TestTelemetryClock(base)
        _ = await firstUserSession(store, clock)
        let sender = ScriptedMilestoneSender(), outbox = box(store, sender, clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await outbox.processDue()
        await outbox.configure(enabled: false, consentGeneration: 1)
        await outbox.processDue()
        await outbox.configure(enabled: true, consentGeneration: 1)
        for _ in 0..<3 {
            await outbox.recordLaunch(session: UUID(), secondLaunch: record(generation: 1, milestone: .secondLaunch))
            await outbox.processDue()
        }
        #expect(await sender.events.map(\.eventName) == ["second_launch"])
        #expect(store.saved.acknowledged.filter { $0.identity.milestone == .secondLaunch }.count == 1)
    }

    @Test func automaticSchedulingUnblocksSecondAfterFirstAcceptance() async throws {
        let store = TestTelemetryStore(), clock = AdvancingTelemetryClock(base)
        let sender = ScriptedMilestoneSender([
            .retryableFailure(statusCode: 500, retryAfter: 60), .accepted(statusCode: 200), .accepted(statusCode: 200)])
        let outbox = TelemetryOutbox(store: store, sender: sender, clock: clock)
        await outbox.configure(enabled: true, consentGeneration: 0)
        await outbox.enqueue(record())
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        await outbox.recordLaunch(session: UUID(), secondLaunch: record(milestone: .secondLaunch))
        for _ in 0..<400 {
            if store.saved.acknowledged.count == 2 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        await outbox.prepareForTermination()
        #expect(await sender.events.map(\.eventName) == ["first_launch", "first_launch", "second_launch"])
        #expect(clock.now() >= base.addingTimeInterval(60))
    }
}

private enum TestTelemetryError: Error { case read, write }

private final class TestTelemetryStore: TelemetryPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TelemetryOutboxSnapshot
    private var readFailure = false
    private var maximumWrites: Int?
    private var writes = 0
    init(_ value: TelemetryOutboxSnapshot = .init()) { self.value = value }
    var saved: TelemetryOutboxSnapshot { lock.withLock { value } }
    var saveCount: Int { lock.withLock { writes } }
    func failReads(_ value: Bool) { lock.withLock { readFailure = value } }
    func failWrites(after value: Int?) { lock.withLock { maximumWrites = value } }
    func load() throws -> TelemetryOutboxSnapshot {
        try lock.withLock {
            if readFailure { throw TestTelemetryError.read }
            return value
        }
    }
    func save(_ snapshot: TelemetryOutboxSnapshot) throws {
        try lock.withLock {
            writes += 1
            if let maximumWrites, writes > maximumWrites { throw TestTelemetryError.write }
            value = snapshot
        }
    }
}

private final class TestTelemetryClock: TelemetryClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ date: Date) { value = date }
    func now() -> Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
    func sleep(until date: Date) async throws { throw CancellationError() }
}

private actor ScriptedMilestoneSender: TelemetrySending {
    private var results: [EventDeliveryResult]
    private(set) var events: [PreparedEvent] = []
    init(_ results: [EventDeliveryResult] = []) { self.results = results }
    func send(_ event: PreparedEvent) async -> EventDeliveryResult {
        events.append(event)
        return results.isEmpty ? .accepted(statusCode: 200) : results.removeFirst()
    }
}

private actor GatedMilestoneSender: TelemetrySending {
    private var response: CheckedContinuation<EventDeliveryResult, Never>?
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var count = 0
    func send(_ event: PreparedEvent) async -> EventDeliveryResult {
        count += 1
        waiting.forEach { $0.resume() }
        waiting.removeAll()
        // Deliberately ignores cancellation to test stale completions.
        return await withCheckedContinuation { response = $0 }
    }
    func waitForRequest() async {
        if count > 0 { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func complete(_ result: EventDeliveryResult) { response?.resume(returning: result); response = nil }
}

private actor AcceptedIdentities {
    private(set) var values: [TelemetryMilestoneIdentity] = []
    func append(_ value: TelemetryMilestoneIdentity) { values.append(value) }
}

private final class AdvancingTelemetryClock: TelemetryClock, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    func now() -> Date { lock.withLock { date } }
    func sleep(until deadline: Date) async throws {
        try Task.checkCancellation()
        lock.withLock { if date < deadline { date = deadline } }
        await Task.yield()
        try Task.checkCancellation()
    }
}
