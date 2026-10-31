import Foundation
import Aptabase

/// Thin Aptabase wrapper. Anonymous only: no identity, few events.
///
/// People on a given release: Aptabase count of `first_launch` for that app
/// version (SDK attaches version automatically). Fires once per install per
/// `AppInfo.appVersion`, so each update is a new first launch — not once ever,
/// and not every cold start. Prefer that over `app_started` (launches).
@MainActor
enum Telemetry {
    private static let appKey = "A-EU-3390120695"

    private static var didInitialize = false
    private static weak var preferences: Preferences?
    /// Avoids a second `app_started` if Settings re-enables telemetry in the same run.
    private static var didTrackAppStartedThisRun = false

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

        if !didTrackAppStartedThisRun {
            track("app_started")
            didTrackAppStartedThisRun = true
        }

        // Once per marketing+build string; Sparkle updates bump this and count again.
        let version = AppInfo.appVersion
        if preferences.telemetryFirstLaunchVersion != version {
            track("first_launch", ["version": AppInfo.bundleVersion, "build": AppInfo.bundleBuild])
            preferences.telemetryFirstLaunchVersion = version
        }
    }
}
