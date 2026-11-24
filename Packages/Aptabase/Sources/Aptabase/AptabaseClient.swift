import Foundation

class AptabaseClient {
    private static let sdkVersion = "aptabase-swift@0.4.0"
    private static let sessionTimeout: TimeInterval = 60 * 60
    private let sessionLock = NSLock()
    private var sessionId = newSessionId()
    private var lastTouched = Date()
    private var flushTimer: Timer?
    // Scheduler fields and flushTimer are accessed only through onMain.
    private var pollingEnabled = false
    private var schedulingRevision: UInt64 = 0
    private var flushCadenceStart = ProcessInfo.processInfo.systemUptime
    private let eventDispatcher: EventDispatcher
    private let errorDispatcher: ErrorDispatcher
    private let env: EnvironmentInfo
    private let flushInterval: Double
    private let tracking = TrackingState()

    init(appKey: String, baseUrl: String, env: EnvironmentInfo, options: InitOptions?,
         session: URLSessionProtocol = URLSession.shared) {
        flushInterval = options?.flushInterval ?? (env.isDebug ? 2 : 60)
        self.env = env
        let transport = TrackingSession(underlying: session, state: tracking)
        eventDispatcher = EventDispatcher(appKey: appKey, baseUrl: baseUrl, env: env, session: transport)
        errorDispatcher = ErrorDispatcher(appKey: appKey, baseUrl: baseUrl, env: env, session: transport)
        startPolling()
    }

    public func trackEvent(_ name: String, with props: [String: AnyCodableValue] = [:]) {
        guard let epoch = tracking.currentEpoch() else { return }
        Task {
            guard self.tracking.accepts(epoch) else { return }
            let event = self.makeEvent(name, props: props)
            await self.eventDispatcher.enqueueIfCurrent(event, tracking: self.tracking, epoch: epoch)
            if self.tracking.accepts(epoch) { self.requestFlush() }
        }
    }

    public func trackEvent(_ name: String, with props: [String: AnyCodableValue] = [:]) async {
        guard let epoch = tracking.currentEpoch() else { return }
        let event = makeEvent(name, props: props)
        await eventDispatcher.enqueueIfCurrent(event, tracking: tracking, epoch: epoch)
        if tracking.accepts(epoch) { requestFlush() }
    }

    public func trackError(_ error: any Error, fatal: Bool = false) {
        guard let epoch = tracking.currentEpoch() else { return }
        let stack = ErrorReport.captureStackTrace()
        Task {
            await self.trackError(error, fatal: fatal, stackTrace: stack, epoch: epoch)
        }
    }

    public func trackError(_ error: any Error, fatal: Bool = false, stackTrace: String? = nil) async {
        guard let epoch = tracking.currentEpoch() else { return }
        await trackError(error, fatal: fatal, stackTrace: stackTrace, epoch: epoch)
    }

    private func trackError(_ error: any Error, fatal: Bool, stackTrace: String?, epoch: UInt64) async {
        guard tracking.accepts(epoch) else { return }
        let session = sessionLock.withLock { currentSessionLocked() }
        let report = ErrorReport.build(error, fatal: fatal, sessionId: session,
            sdkVersion: Self.sdkVersion, env: env, stackTrace: stackTrace)
        await errorDispatcher.enqueueIfCurrent(report, tracking: tracking, epoch: epoch)
        guard tracking.accepts(epoch) else { return }
        await errorDispatcher.flush()
        reconcileFlushSchedule()
    }

    public func prepareEvent(_ name: String, with props: [String: AnyCodableValue] = [:]) -> PreparedEvent? {
        guard tracking.currentEpoch() != nil else { return nil }
        return PreparedEvent(event: makeEvent(name, props: props))
    }

    public func sendPreparedEvent(_ event: PreparedEvent) async -> EventDeliveryResult {
        guard tracking.currentEpoch() != nil else { return .cancelled }
        return await eventDispatcher.sendPrepared(event)
    }

    public func pauseTracking() {
        tracking.pause()
        stopPolling(flushOutstanding: false)
    }

    public func resumeTracking() async {
        let revision = tracking.revision()
        await discardQueuedEvents()
        guard tracking.resume(ifRevision: revision) else { return }
        startPolling()
    }

    public func discardQueuedEvents() async {
        await eventDispatcher.discardQueuedItems()
        await errorDispatcher.discardQueuedItems()
        reconcileFlushSchedule()
    }

    public func startPolling() {
        onMain { [weak self] in
            guard let self, self.tracking.currentEpoch() != nil else { return }
            self.pollingEnabled = true
            self.schedulingRevision &+= 1
            self.flushCadenceStart = ProcessInfo.processInfo.systemUptime
            self.flushTimer?.invalidate()
            self.flushTimer = nil
            self.reconcileFlushSchedule()
        }
    }

    public func stopPolling() { stopPolling(flushOutstanding: true) }

    private func stopPolling(flushOutstanding: Bool) {
        onMain { [weak self] in
            guard let self else { return }
            self.pollingEnabled = false
            self.schedulingRevision &+= 1
            self.flushTimer?.invalidate()
            self.flushTimer = nil
        }
        if flushOutstanding, tracking.currentEpoch() != nil {
            Task { await self.flush() }
        }
    }

    public func flush() async {
        guard tracking.currentEpoch() != nil else { return }
        await eventDispatcher.flush()
        await errorDispatcher.flush()
        reconcileFlushSchedule()
    }

    deinit { flushTimer?.invalidate() }

    @MainActor var isFlushScheduled: Bool { flushTimer != nil }

    /// Enqueue completion schedules the next existing cadence boundary. Further
    /// events share that deadline; an empty queue has no periodic tasks.
    private func requestFlush() {
        onMain { [weak self] in
            guard let self else { return }
            self.schedulingRevision &+= 1
            self.scheduleOneShotIfNeeded()
        }
    }

    private func scheduleOneShotIfNeeded() {
        guard pollingEnabled, tracking.currentEpoch() != nil, flushTimer == nil else { return }
        // Keep the old repeating timer's cadence even across empty periods.
        // Starting a fresh full interval per event would postpone delivery near
        // quit. Uptime avoids turning a wall-clock change into a long delay.
        let interval = max(flushInterval, 0.001)
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - flushCadenceStart)
        let delay = interval - elapsed.truncatingRemainder(dividingBy: interval)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.flushTimer = nil
            self.schedulingRevision &+= 1
            guard self.pollingEnabled, self.tracking.currentEpoch() != nil else { return }
            Task { await self.flush() }
        }
        timer.tolerance = min(delay * 0.1, 1)
        flushTimer = timer
        RunLoop.main.add(timer, forMode: .default)
    }

    private func reconcileFlushSchedule() {
        onMain { [weak self] in
            guard let self else { return }
            let revision = self.schedulingRevision
            Task { [self] in
                let eventsPending = await self.eventDispatcher.hasQueuedItems()
                let errorsPending = await self.errorDispatcher.hasQueuedItems()
                self.onMain { [weak self] in
                    guard let self, self.schedulingRevision == revision else { return }
                    // A stale empty snapshot must never cancel a newer enqueue.
                    if eventsPending || errorsPending {
                        self.scheduleOneShotIfNeeded()
                    } else {
                        self.flushTimer?.invalidate()
                        self.flushTimer = nil
                    }
                }
            }
        }
    }

    private func makeEvent(_ name: String, props: [String: AnyCodableValue]) -> Event {
        sessionLock.withLock {
            Event(timestamp: Date(), sessionId: currentSessionLocked(), eventName: name,
                systemProps: Event.SystemProps(isDebug: env.isDebug, locale: env.locale,
                    osName: env.osName, osVersion: env.osVersion, appVersion: env.appVersion,
                    appBuildNumber: env.appBuildNumber, sdkVersion: Self.sdkVersion,
                    deviceModel: env.deviceModel), props: props)
        }
    }

    private func currentSessionLocked() -> String {
        let now = Date()
        if now.timeIntervalSince(lastTouched) > Self.sessionTimeout { sessionId = Self.newSessionId() }
        lastTouched = now
        return sessionId
    }

    private static func newSessionId() -> String {
        String(UInt64(Date().timeIntervalSince1970) * 100_000_000 + UInt64.random(in: 0...99_999_999))
    }

    private func onMain(_ operation: @escaping @Sendable () -> Void) {
        if Thread.isMainThread { operation() }
        else { DispatchQueue.main.async(execute: operation) }
    }

}
