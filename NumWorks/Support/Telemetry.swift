import Foundation
import Aptabase
import os

/// The SDK owns ordinary event delivery. The durable outbox alone owns
/// first_launch and second_launch, once per version/build and build mode.
@MainActor
enum Telemetry {
    private static let appKey = "A-EU-3390120695"
    private static weak var preferences: Preferences?
    private static var didInitialize = false
    private static var didTrackAppStarted = false
    private static var didUseCalculator = false
    private static var outbox: TelemetryOutbox?
    private static var transition: Task<Void, Never>?
    private static var revision = 0

    private static var identity: TelemetryMilestoneIdentity {
        TelemetryMilestoneIdentity(version: AppInfo.bundleVersion,
                                   build: AppInfo.bundleBuild, mode: .current)
    }

    static func start(preferences: Preferences) {
        guard !UITesting.isEnabled else { return }
        self.preferences = preferences
        if outbox == nil, let store = TelemetryFileStore.applicationStore() {
            outbox = TelemetryOutbox(store: store, sender: AptabaseMilestoneSender(),
                onAccepted: { accepted in
                    await MainActor.run {
                        guard accepted.milestone == .firstLaunch,
                              accepted.mode == .release, accepted == Self.identity,
                              let preferences = Self.preferences,
                              preferences.telemetryEnabled else { return }
                        preferences.telemetryFirstLaunchVersion = accepted.displayVersion
                    }
                })
        }
        applyPreferenceChange()
    }

    static func applyPreferenceChange() {
        guard !UITesting.isEnabled, let preferences else { return }
        revision += 1
        let token = revision
        let enabled = preferences.telemetryEnabled
        let consent = preferences.telemetryConsentGeneration
        // This fence is synchronous, before any task/queue clearing can yield.
        if !enabled, didInitialize { Aptabase.shared.pauseTracking() }
        let previous = transition
        transition = Task { @MainActor in
            // These transitions await enqueue/clear operations, never HTTP.
            await previous?.value
            if !enabled {
                if didInitialize { await Aptabase.shared.discardQueuedEvents() }
                await outbox?.configure(enabled: false, consentGeneration: consent)
                return
            }
            guard token == revision, preferences.telemetryEnabled else { return }
            ensureInitialized()
            await Aptabase.shared.resumeTracking()
            guard token == revision, preferences.telemetryEnabled else {
                Aptabase.shared.pauseTracking()
                return
            }

            await outbox?.configure(enabled: true, consentGeneration: consent)
            if let legacy = preferences.telemetryFirstLaunchVersion,
               identity.mode == .release, let value = parseLegacy(legacy) {
                await outbox?.importLegacySkip(value)
            }

            if !didTrackAppStarted {
                await Aptabase.shared.trackEvent("app_started")
                didTrackAppStarted = true
                Task { await Aptabase.shared.flush() }
            }
            guard token == revision, preferences.telemetryEnabled else { return }
            guard let event = Aptabase.shared.prepareEvent("first_launch", with: [
                "version": AppInfo.bundleVersion, "build": AppInfo.bundleBuild
            ]) else { return }
            let record = PendingTelemetryMilestone(
                id: UUID(), identity: identity, consentGeneration: consent,
                event: event, nextAttemptAt: Date())
            await outbox?.enqueue(record)
            if didUseCalculator,
               let secondEvent = Aptabase.shared.prepareEvent("second_launch", with: [
                   "version": AppInfo.bundleVersion, "build": AppInfo.bundleBuild
               ]) {
                let second = PendingTelemetryMilestone(
                    id: UUID(), identity: identity.forMilestone(.secondLaunch),
                    consentGeneration: consent, event: secondEvent, nextAttemptAt: Date())
                await outbox?.recordLaunch(session: TelemetryLaunchSession.current.id, secondLaunch: second)
            }
        }
    }

    /// Explicit calculator open or input, never a background/login start alone.
    /// Multiple opens in this process still describe a single qualifying run.
    static func noteCalculatorUsed() {
        guard !UITesting.isEnabled, !didUseCalculator else { return }
        didUseCalculator = true
        applyPreferenceChange()
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

    static func trackUserDisabled() { track("telemetry_disabled") }
    static func trackUserEnabled() { track("telemetry_enabled") }

    /// AppMover may exit immediately after this returns. No network wait.
    static func prepareForTermination() async {
        guard !UITesting.isEnabled else { return }
        await transition?.value
        await outbox?.prepareForTermination()
        if didInitialize { Aptabase.shared.pauseTracking() }
    }

    private static var isEnabled: Bool {
        !UITesting.isEnabled && (preferences?.telemetryEnabled ?? false)
    }

    private static func ensureInitialized() {
        guard !didInitialize else { return }
        Aptabase.shared.initialize(appKey: appKey)
        didInitialize = true
    }

    private static func parseLegacy(_ value: String) -> TelemetryMilestoneIdentity? {
        guard let open = value.lastIndex(of: "("), value.hasSuffix(")") else { return nil }
        let version = value[..<open].trimmingCharacters(in: .whitespaces)
        let build = String(value[value.index(after: open)..<value.index(before: value.endIndex)])
        guard !version.isEmpty, !build.isEmpty else { return nil }
        return TelemetryMilestoneIdentity(version: version, build: build, mode: .release)
    }
}
