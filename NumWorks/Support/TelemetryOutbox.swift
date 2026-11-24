import Foundation
import Aptabase
import os

/// Owns milestone retries; SDK polling never queues these records.
/// Working state may include an accepted event whose acknowledgement still needs
/// a disk write. That state is retained on write failure, never rolled back into
/// another HTTP submission. A crash before the write remains an at-least-once limit.
actor TelemetryOutbox {
    private let store: any TelemetryPersisting
    private let sender: any TelemetrySending
    private let clock: any TelemetryClock
    private let automaticRetry: Bool
    private let onAccepted: @Sendable (TelemetryMilestoneIdentity) async -> Void
    private let logger = Logger(subsystem: "com.ellandeved.NumWorks", category: "Telemetry")

    private var state: TelemetryOutboxSnapshot?
    private var staged: [TelemetryMilestoneIdentity: PendingTelemetryMilestone] = [:]
    private var stagedLaunches: [TelemetryQualifyingLaunch] = []
    private var legacySkips: Set<TelemetryMilestoneIdentity> = []
    private var acceptedAwaitingPersistence: [PendingTelemetryMilestone] = []
    private var dirty = false
    private var enabled = false
    private var consentGeneration = 0
    private var lifecycle = 0
    private var processing = false
    private var terminated = false
    private var request: Task<EventDeliveryResult, Never>?
    private var wake: Task<Void, Never>?
    private var wakeID: UUID?
    private var storageAttempts = 0
    private var storageRetryAt: Date?
    private(set) var lastStorageError: String?

    init(store: any TelemetryPersisting, sender: any TelemetrySending,
         clock: any TelemetryClock = SystemTelemetryClock(), automaticRetry: Bool = true,
         onAccepted: @escaping @Sendable (TelemetryMilestoneIdentity) async -> Void = { _ in }) {
        self.store = store
        self.sender = sender
        self.clock = clock
        self.automaticRetry = automaticRetry
        self.onAccepted = onAccepted
    }

    func configure(enabled: Bool, consentGeneration: Int) {
        if self.enabled == enabled, self.consentGeneration == consentGeneration, !terminated {
            schedule(at: clock.now())
            return
        }
        lifecycle += 1
        request?.cancel()
        request = nil
        wake?.cancel()
        wake = nil
        wakeID = nil
        processing = false
        terminated = false
        self.enabled = enabled
        self.consentGeneration = consentGeneration
        if !enabled {
            staged.removeAll()
            stagedLaunches.removeAll()
            acceptedAwaitingPersistence.removeAll()
        }
        reconcileConsent()
        schedule(at: clock.now())
    }

    func enqueue(_ record: PendingTelemetryMilestone) {
        guard enabled, !terminated, record.consentGeneration == consentGeneration,
              record.event.eventName == record.identity.milestone.rawValue else { return }
        if state?.acknowledged.contains(where: { $0.identity == record.identity }) == true { return }
        if state?.pending.contains(where: { $0.identity == record.identity }) == true { return }
        if staged[record.identity] == nil { staged[record.identity] = record }
        schedule(at: clock.now())
    }

    /// Called once a user opens/uses the calculator. The process token survives
    /// AppMover, so a relocation or repeated window opens cannot become a second run.
    func recordLaunch(session: UUID, secondLaunch record: PendingTelemetryMilestone) {
        guard enabled, !terminated, record.consentGeneration == consentGeneration,
              record.identity.milestone == .secondLaunch,
              record.event.eventName == TelemetryMilestone.secondLaunch.rawValue else { return }
        if state?.acknowledged.contains(where: { $0.identity == record.identity }) == true { return }
        if state?.pending.contains(where: { $0.identity == record.identity }) == true { return }
        let first = record.identity.forMilestone(.firstLaunch)
        if state?.launches.contains(where: {
            $0.identity == first && ($0.firstSession == session || $0.secondSession != nil)
        }) == true { return }
        if !stagedLaunches.contains(where: { $0.session == session && $0.secondLaunch.identity == record.identity }) {
            stagedLaunches.append(TelemetryQualifyingLaunch(session: session, secondLaunch: record))
        }
        schedule(at: clock.now())
    }

    func importLegacySkip(_ identity: TelemetryMilestoneIdentity) {
        guard identity.mode == .release, identity.milestone == .firstLaunch else { return }
        legacySkips.insert(identity)
        schedule(at: clock.now())
    }

    /// Never awaits a network task. All normal submissions were checkpointed
    /// before HTTP; any not-yet-started staged intent gets one disk-only attempt.
    func prepareForTermination() {
        terminated = true
        lifecycle += 1
        request?.cancel()
        request = nil
        wake?.cancel()
        wake = nil
        wakeID = nil
        processing = false
        _ = prepareStorage()
    }

    func snapshotForTesting() -> TelemetryOutboxSnapshot? { state }
    func hasRequestForTesting() -> Bool { request != nil }

    /// Public within the module so tests can drive the real state machine with
    /// automatic scheduling disabled, without sleeps or real analytics traffic.
    func processDue() async {
        guard !terminated, !processing else { return }
        processing = true
        let token = lifecycle
        wake?.cancel()
        wake = nil
        wakeID = nil
        defer {
            if token == lifecycle {
                processing = false
                request = nil
                scheduleNext()
            }
        }

        while token == lifecycle, !terminated {
            guard prepareStorage() else { return }
            let callbacks = acceptedAwaitingPersistence
            acceptedAwaitingPersistence.removeAll()
            for record in callbacks where enabled && record.consentGeneration == consentGeneration {
                await onAccepted(record.identity)
                guard token == lifecycle else { return }
            }
            guard enabled else { return }
            guard let record = sendableRecords().first(where: { $0.nextAttemptAt <= clock.now() }) else { return }

            let task = Task { [sender] in await sender.send(record.event) }
            request = task
            let result = await task.value
            guard token == lifecycle, enabled,
                  record.consentGeneration == consentGeneration else { return }
            request = nil
            guard let index = state?.pending.firstIndex(where: { $0.id == record.id }) else { continue }

            switch result {
            case .accepted(let status) where (200..<300).contains(status):
                state?.acknowledged.append(TelemetryAcknowledgement(
                    identity: record.identity, recordID: record.id, kind: .accepted))
                state?.pending.remove(at: index)
                acceptedAwaitingPersistence.append(record)
                dirty = true

            case .rejected(let status, _):
                state?.pending[index].attempts += 1
                state?.pending[index].rejected = true
                state?.pending[index].lastHTTPStatus = status
                state?.pending[index].nextAttemptAt = clock.now().addingTimeInterval(24 * 60 * 60)
                dirty = true

            case .retryableFailure(let status, let retryAfter):
                reschedule(index: index, status: status, retryAfter: retryAfter)

            case .cancelled, .accepted:
                // Cancellation is not acceptance, even if the caller itself
                // was not cancelled (for example, a transport cancellation).
                reschedule(index: index, status: nil, retryAfter: nil)
            }
        }
    }

    private func reschedule(index: Int, status: Int?, retryAfter: TimeInterval?) {
        guard state != nil else { return }
        state!.pending[index].attempts += 1
        state!.pending[index].lastHTTPStatus = status
        let delay = Self.backoff(attempt: state!.pending[index].attempts, retryAfter: retryAfter)
        state!.pending[index].nextAttemptAt = clock.now().addingTimeInterval(delay)
        dirty = true
    }

    private func prepareStorage() -> Bool {
        if let retry = storageRetryAt, retry > clock.now() { return false }
        do {
            if state == nil {
                var loaded = try store.load()
                // Rejections may retry only on a later process launch, after 24h.
                for index in loaded.pending.indices
                    where loaded.pending[index].rejected && loaded.pending[index].nextAttemptAt <= clock.now() {
                    loaded.pending[index].rejected = false
                    dirty = true
                }
                state = loaded
            }
            reconcileConsent()
            guard var candidate = state else { return false }
            let complete = Set(candidate.acknowledged.map(\.identity))
            let before = candidate.pending.count
            candidate.pending.removeAll { complete.contains($0.identity) }
            if candidate.pending.count != before { dirty = true }
            for identity in legacySkips where !complete.contains(identity) {
                candidate.acknowledged.append(TelemetryAcknowledgement(
                    identity: identity, recordID: nil, kind: .legacySkip))
                candidate.pending.removeAll { $0.identity == identity }
                dirty = true
            }
            legacySkips.removeAll()
            for record in staged.values {
                if !candidate.acknowledged.contains(where: { $0.identity == record.identity }),
                   !candidate.pending.contains(where: { $0.identity == record.identity }),
                   enabled, record.consentGeneration == consentGeneration {
                    candidate.pending.append(record)
                    dirty = true
                }
            }
            staged.removeAll()
            for launch in stagedLaunches {
                let record = launch.secondLaunch
                guard enabled, record.consentGeneration == consentGeneration,
                      !candidate.acknowledged.contains(where: { $0.identity == record.identity }),
                      !candidate.pending.contains(where: { $0.identity == record.identity }) else { continue }
                let first = record.identity.forMilestone(.firstLaunch)
                if let index = candidate.launches.firstIndex(where: { $0.identity == first }) {
                    guard candidate.launches[index].firstSession != launch.session,
                          candidate.launches[index].secondSession == nil else { continue }
                    candidate.launches[index].secondSession = launch.session
                    candidate.pending.append(record)
                } else {
                    // Old files have no qualifying-session history. Establish a
                    // baseline rather than inventing a retrospective second use.
                    candidate.launches.append(TelemetryLaunchHistory(
                        identity: first, consentGeneration: consentGeneration,
                        firstSession: launch.session, secondSession: nil))
                }
                dirty = true
            }
            stagedLaunches.removeAll()
            candidate.pending.sort { $0.event.timestamp < $1.event.timestamp }
            state = candidate
            if dirty {
                try store.save(candidate)
                dirty = false
            }
            storageAttempts = 0
            storageRetryAt = nil
            lastStorageError = nil
            return true
        } catch {
            // Keep the loaded/working state, including any accepted event.
            // If load failed, state stays nil: no empty overwrite or HTTP.
            storageAttempts += 1
            storageRetryAt = clock.now().addingTimeInterval(Self.backoff(attempt: storageAttempts))
            lastStorageError = String(describing: error)
            logger.error("Telemetry storage operation failed; delivery is paused until retry.")
            return false
        }
    }

    private func reconcileConsent() {
        guard state != nil else { return }
        let before = state!.pending.count
        let launchesBefore = state!.launches.count
        let allowed = enabled
        let currentConsent = consentGeneration
        state!.pending.removeAll { !allowed || $0.consentGeneration != currentConsent }
        state!.launches.removeAll { !allowed || $0.consentGeneration != currentConsent }
        if state!.pending.count != before || state!.launches.count != launchesBefore { dirty = true }
    }

    private func sendableRecords() -> [PendingTelemetryMilestone] {
        guard let state else { return [] }
        let completed = Set(state.acknowledged.map(\.identity))
        return state.pending.filter {
            !$0.rejected && $0.consentGeneration == consentGeneration
                && ($0.identity.milestone == .firstLaunch
                    || completed.contains($0.identity.forMilestone(.firstLaunch)))
        }
    }

    private func scheduleNext() {
        guard automaticRetry, !terminated else { return }
        if state == nil || dirty || !staged.isEmpty || !stagedLaunches.isEmpty || !legacySkips.isEmpty {
            schedule(at: storageRetryAt ?? clock.now())
        } else if enabled,
                  let date = sendableRecords().map(\.nextAttemptAt).min() {
            schedule(at: date)
        }
    }

    private func schedule(at date: Date) {
        guard automaticRetry, !terminated, !processing else { return }
        wake?.cancel()
        let id = UUID()
        wakeID = id
        wake = Task { [weak self, clock] in
            do { try await clock.sleep(until: date) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.wakeAndProcess(id)
        }
    }

    private func wakeAndProcess(_ id: UUID) async {
        guard wakeID == id, !Task.isCancelled else { return }
        wake = nil
        wakeID = nil
        await processDue()
    }

    static func backoff(attempt: Int, retryAfter: TimeInterval? = nil) -> TimeInterval {
        let local = min(900, 2 * pow(2, Double(min(max(attempt - 1, 0), 9))))
        guard let server = retryAfter, server.isFinite, server >= 0 else { return local }
        // Retry-After is a server minimum, not subject to the local backoff cap.
        return max(local, server)
    }
}
