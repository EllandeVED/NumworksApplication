//
//  PreferencesTests.swift
//  NumWorksTests
//

import Foundation
import Testing
@testable import NumWorks

@MainActor
struct PreferencesTests {

    private func makeSuite() -> UserDefaults {
        let name = "NumWorksTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    @Test func defaultsMatchDocumentedValues() {
        let prefs = Preferences(defaults: makeSuite())
        #expect(prefs.alwaysOnTop == false)
        #expect(prefs.showPinButton == true)
        #expect(prefs.showSettingsButton == true)
        #expect(prefs.shortcutsEnabled == true)
        #expect(prefs.showDockIcon == true)
        #expect(prefs.showMenuBarIcon == true)
        #expect(prefs.menuBarIconStyle == .filled)
        #expect(prefs.windowStyle == .toolbar)
        #expect(prefs.launchWindowVisible == false)
        #expect(prefs.moveWindowToCurrentSpaceWhenShown == true)
        #expect(prefs.savedWindowFrame == nil)
    }

    @Test func preferenceRoundTripsPersist() {
        let defaults = makeSuite()
        let prefs = Preferences(defaults: defaults)

        prefs.alwaysOnTop = true
        prefs.showPinButton = false
        prefs.showSettingsButton = false
        prefs.shortcutsEnabled = false
        prefs.showDockIcon = false
        prefs.showMenuBarIcon = false
        prefs.menuBarIconStyle = .outline
        prefs.windowStyle = .native
        prefs.launchWindowVisible = true
        prefs.moveWindowToCurrentSpaceWhenShown = false
        prefs.savedWindowFrame = "{{10, 20}, {300, 600}}"

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.alwaysOnTop == true)
        #expect(reloaded.showPinButton == false)
        #expect(reloaded.showSettingsButton == false)
        #expect(reloaded.shortcutsEnabled == false)
        #expect(reloaded.showDockIcon == false)
        #expect(reloaded.showMenuBarIcon == false)
        #expect(reloaded.menuBarIconStyle == .outline)
        #expect(reloaded.windowStyle == .native)
        #expect(reloaded.launchWindowVisible == true)
        #expect(reloaded.moveWindowToCurrentSpaceWhenShown == false)
        #expect(reloaded.savedWindowFrame == "{{10, 20}, {300, 600}}")
    }

    @Test func unavailableWindowStyleFallsBackToToolbar() {
        let defaults = makeSuite()
        defaults.set(WindowStyle.minimal.rawValue, forKey: "windowStyle")
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.windowStyle == .toolbar)
    }

    @Test func resetToDefaultsRestoresUIPrefsButKeepsFrameAndAppMover() {
        let defaults = makeSuite()
        let prefs = Preferences(defaults: defaults)
        prefs.appMoverVersionProvider = { "9.9 (99)" }

        prefs.alwaysOnTop = true
        prefs.showPinButton = false
        prefs.windowStyle = .native
        prefs.launchWindowVisible = true
        prefs.savedWindowFrame = "{{1, 1}, {400, 800}}"
        prefs.synchronizeAppMoverOffers(withVersion: "9.9 (99)")
        prefs.recordAppMoverOfferShown()
        prefs.recordAppMoverOfferShown()

        prefs.resetToDefaults()

        #expect(prefs.alwaysOnTop == false)
        #expect(prefs.showPinButton == true)
        #expect(prefs.windowStyle == .toolbar)
        #expect(prefs.launchWindowVisible == false)
        // Frame + AppMover counters are intentionally not part of reset.
        #expect(prefs.savedWindowFrame == "{{1, 1}, {400, 800}}")
        #expect(defaults.string(forKey: "appMoverOfferVersion") == "9.9 (99)")
        #expect(defaults.integer(forKey: "appMoverOfferCount") == 2)
    }

    @Test func appMoverOffersTwicePerVersionThenStops() {
        let defaults = makeSuite()
        let prefs = Preferences(defaults: defaults)
        prefs.appMoverVersionProvider = { "1.0 (1)" }

        #expect(prefs.shouldOfferAppMover == true)
        prefs.recordAppMoverOfferShown()
        #expect(defaults.integer(forKey: "appMoverOfferCount") == 1)
        #expect(prefs.shouldOfferAppMover == true)

        prefs.recordAppMoverOfferShown()
        #expect(defaults.integer(forKey: "appMoverOfferCount") == 2)
        #expect(prefs.shouldOfferAppMover == false)
    }

    @Test func appMoverCounterResetsWhenVersionChanges() {
        let defaults = makeSuite()
        let prefs = Preferences(defaults: defaults)
        prefs.appMoverVersionProvider = { "1.0 (1)" }

        prefs.recordAppMoverOfferShown()
        prefs.recordAppMoverOfferShown()
        #expect(defaults.integer(forKey: "appMoverOfferCount") == 2)

        prefs.appMoverVersionProvider = { "1.0 (2)" }
        #expect(prefs.shouldOfferAppMover == true)
        #expect(defaults.integer(forKey: "appMoverOfferCount") == 0)
        #expect(defaults.string(forKey: "appMoverOfferVersion") == "1.0 (2)")
    }

    @Test func rapidPreferenceTogglesRemainConsistent() {
        let prefs = Preferences(defaults: makeSuite())
        for i in 0..<200 {
            prefs.alwaysOnTop = i.isMultiple(of: 2)
            prefs.showMenuBarIcon = !prefs.alwaysOnTop
            prefs.launchWindowVisible.toggle()
        }
        #expect(prefs.alwaysOnTop == false)
        #expect(prefs.showMenuBarIcon == true)
    }
}
