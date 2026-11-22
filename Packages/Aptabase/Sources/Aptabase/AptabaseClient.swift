import Foundation

class AptabaseClient {
    private static let sdkVersion = "aptabase-swift@0.4.0"
    private static let sessionTimeout: TimeInterval = 60 * 60
    private let sessionLock = NSLock()
    private var sessionId = newSessionId()
    private var lastTouched = Date()
    private var flushTimer: Timer?
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
        }
    }

    public func trackEvent(_ name: String, with props: [String: AnyCodableValue] = [:]) async {
        guard let epoch = tracking.currentEpoch() else { return }
        let event = makeEvent(name, props: props)
        await eventDispatcher.enqueueIfCurrent(event, tracking: tracking, epoch: epoch)
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
    }

    public func startPolling() {
        onMain { [weak self] in
            guard let self, self.tracking.currentEpoch() != nil else { return }
            self.flushTimer?.invalidate()
            self.flushTimer = Timer.scheduledTimer(timeInterval: self.flushInterval, target: self,
                selector: #selector(self.timerFlushSync), userInfo: nil, repeats: true)
        }
    }

    public func stopPolling() { stopPolling(flushOutstanding: true) }

    private func stopPolling(flushOutstanding: Bool) {
        onMain { [weak self] in
            self?.flushTimer?.invalidate()
            self?.flushTimer = nil
        }
        if flushOutstanding, tracking.currentEpoch() != nil {
            Task { await self.flush() }
        }
    }

    public func flush() async {
        guard tracking.currentEpoch() != nil else { return }
        await eventDispatcher.flush()
        await errorDispatcher.flush()
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

    @objc private func timerFlushSync() {
        guard tracking.currentEpoch() != nil else { return }
        Task { await self.flush() }
    }
}
