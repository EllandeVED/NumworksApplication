import Foundation
import Aptabase

/// Thin Aptabase wrapper. Anonymous only: no identity, few events.
///
/// People on a given release: Aptabase count of `first_launch` for that app
/// version (SDK attaches version automatically). Fires once per install per
/// `AppInfo.appVersion`, so each update is a new first launch — not once ever,
/// and not every cold start. Prefer that over `app_started` (launches).
///
/// `telemetryFirstLaunchVersion` is written only after a flush. Aptabase keeps
/// events in memory and the release SDK sends them on a 60s timer (or on
/// `willTerminate`). Saving the version at `track()` time made a short first
/// run, including AppMover's `exit(0)`, skip the event forever.
@MainActor
enum Telemetry {
    private static let appKey = "A-EU-3390120695"
    /// `trackEvent` enqueues on an unstructured task. Flushing immediately can
    /// run before that task, see an empty queue, and we would then store the
    /// version for an event that is still unsent.
    private static let enqueueGraceNanoseconds: UInt64 = 100_000_000
    /// Cap so Move to Applications cannot stall forever on a hung request.
    private static let terminationFlushTimeoutNanoseconds: UInt64 = 3_000_000_000

    private static var didInitialize = false
    private static weak var preferences: Preferences?
    /// Avoids a second `app_started` if Settings re-enables telemetry in the same run.
    private static var didTrackAppStartedThisRun = false
    /// Version whose `first_launch` is queued but not yet flushed.
    private static var pendingFirstLaunchVersion: String?
    private static var flushTask: Task<Void, Never>?
#if DEBUG
    /// Tests replace the network flush. Production leaves this nil.
    static var flushOverride: (@MainActor () async -> Void)?
#endif

    /// Call once early on the main thread (before Epsilon takes over).
    static func start(preferences: Preferences) {
        guard !UITesting.isEnabled else { return }
        self.preferences = preferences
        guard preferences.telemetryEnabled else { return }
        ensureInitialized()
        trackLaunchEvents()
    }

    /// Re-evaluate after the Settings toggle changes.
    static func applyPreferenceChange() {
        guard !UITesting.isEnabled, let preferences else { return }
        guard preferences.telemetryEnabled else { return }
        ensureInitialized()
        trackLaunchEvents()
    }

    static func track(_ name: String, _ props: [String: Value] = [:]) {
        guard isEnabled else { return }
        ensureInitialized()
        Aptabase.shared.trackEvent(name, with: props)
    }

    static func trackError(_ error: Error, fatal: Bool = false) {
        guard isEnabled else { return }
        ensureInitialized()
        Aptabase.shared.trackError(error, fatal: fatal)
    }

    /// Settings toggle only. Call while telemetry is still on, then set the pref off.
    static func trackUserDisabled() {
        track("telemetry_disabled")
    }

    /// Settings toggle only. Call after the pref is on again.
    static func trackUserEnabled() {
        track("telemetry_enabled")
    }

    /// Send queued events before a path that ends in `exit` (AppMover).
    /// `exit` does not post `willTerminate`, so Aptabase's own quit flush never runs.
    static func flushBeforeTermination() async {
        guard !UITesting.isEnabled else { return }
        let delivery = Task { @MainActor in
            await completePendingDelivery(retryFailures: true)
        }
        let timeoutNanoseconds = Self.terminationFlushTimeoutNanoseconds
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await delivery.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private static var isEnabled: Bool {
        !UITesting.isEnabled && (preferences?.telemetryEnabled ?? false)
    }

    private static func ensureInitialized() {
        guard !didInitialize else { return }
        Aptabase.shared.initialize(appKey: appKey)
        didInitialize = true
    }

    private static func trackLaunchEvents() {
        guard let preferences else { return }

        var needsDelivery = false
        if !didTrackAppStartedThisRun {
            track("app_started")
            didTrackAppStartedThisRun = true
            needsDelivery = true
        }

        // Once per marketing+build string. The version is stored in
        // `commitPendingFirstLaunch` after the flush, not here.
        let version = AppInfo.appVersion
        if preferences.telemetryFirstLaunchVersion != version,
           pendingFirstLaunchVersion != version {
            track("first_launch", ["version": AppInfo.bundleVersion, "build": AppInfo.bundleBuild])
            pendingFirstLaunchVersion = version
            needsDelivery = true
        }

        if needsDelivery {
            scheduleDelivery()
        }
    }

    private static func scheduleDelivery() {
        let previous = flushTask
        flushTask = Task { @MainActor in
            await previous?.value
            guard await sendQueuedEvents() else { return }
            commitPendingFirstLaunch()
        }
    }

    /// Waits for the launch flush, which stores the version only after its send.
    /// A failed send sits back on Aptabase's in-memory queue, so the exit path
    /// flushes once more before the process dies.
    private static func completePendingDelivery(retryFailures: Bool) async {
        await flushTask?.value
        guard retryFailures, didInitialize, !Task.isCancelled else { return }
        await Aptabase.shared.flush()
        commitPendingFirstLaunch()
    }

    /// Yields so Aptabase's enqueue task can run, then flushes.
    /// Returns false when this attempt was cancelled or the SDK is not up.
    private static func sendQueuedEvents() async -> Bool {
#if DEBUG
        if let flushOverride {
            await flushOverride()
            return !Task.isCancelled
        }
#endif
        await Task.yield()
        try? await Task.sleep(nanoseconds: enqueueGraceNanoseconds)
        guard didInitialize, !Task.isCancelled else { return false }
        await Aptabase.shared.flush()
        return true
    }

    private static func commitPendingFirstLaunch() {
        guard let preferences, let version = pendingFirstLaunchVersion else { return }
        preferences.telemetryFirstLaunchVersion = version
        pendingFirstLaunchVersion = nil
    }

#if DEBUG
    /// Drives the flush-then-store path without starting Aptabase.
    static func deliverPendingFirstLaunchForTesting(
        preferences: Preferences,
        version: String
    ) async {
        self.preferences = preferences
        pendingFirstLaunchVersion = version
        guard await sendQueuedEvents() else { return }
        commitPendingFirstLaunch()
    }

    static func resetDeliveryStateForTesting() {
        flushOverride = nil
        pendingFirstLaunchVersion = nil
        flushTask?.cancel()
        flushTask = nil
        preferences = nil
    }
#endif
}
