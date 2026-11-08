import Foundation
import Testing
@testable import NumWorks

@MainActor
@Suite(.serialized)
struct TelemetryTests {

    private func makeSuite() -> UserDefaults {
        let name = "NumWorksTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    @Test func firstLaunchVersionIsStoredOnlyAfterFlush() async {
        let prefs = Preferences(defaults: makeSuite())
        #expect(prefs.telemetryFirstLaunchVersion == nil)
        Telemetry.flushOverride = {
            #expect(prefs.telemetryFirstLaunchVersion == nil)
        }
        defer { Telemetry.resetDeliveryStateForTesting() }

        await Telemetry.deliverPendingFirstLaunchForTesting(
            preferences: prefs,
            version: "2.0.15 (20)")

        #expect(prefs.telemetryFirstLaunchVersion == "2.0.15 (20)")
    }
}
