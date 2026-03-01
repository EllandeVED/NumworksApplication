//
//  NumworksApplicationTests.swift
//  NumworksApplicationTests
//

import Foundation
import Testing
@testable import NumWorks

// MARK: - SemVer

struct SemVerTests {

    @Test func initValidThreePart() throws {
        let v = SemVer("1.2.3")
        #expect(v != nil)
        #expect(v?.major == 1)
        #expect(v?.minor == 2)
        #expect(v?.patch == 3)
        #expect(v?.string == "1.2.3")
    }

    @Test func initOnePartBecomesMinorPatchZero() {
        let v = SemVer("1")
        #expect(v != nil)
        #expect(v?.string == "1.0.0")
        #expect(v?.major == 1 && v?.minor == 0 && v?.patch == 0)
    }

    @Test func initTwoPartsBecomesPatchZero() {
        let v = SemVer("1.6")
        #expect(v != nil)
        #expect(v?.string == "1.6.0")
        #expect(v?.major == 1 && v?.minor == 6 && v?.patch == 0)
    }

    @Test func initRejectsNonNumeric() {
        #expect(SemVer("a.b.c") == nil)
    }

    @Test func initRejectsEmptyString() {
        #expect(SemVer("") == nil)
    }

    @Test func initRejectsMoreThanThreeParts() {
        #expect(SemVer("1.2.3.4") == nil)
    }

    @Test func comparisonOrdering() {
        let a = SemVer("1.2.3")!
        let b = SemVer("2.0.0")!
        let c = SemVer("1.2.4")!
        #expect(a < b)
        #expect(a < c)
        #expect(c < b)
        #expect(a == SemVer("1.2.3")!)
    }
}

// MARK: - EpsilonUpdateChecker (version extraction and check, no network)

struct EpsilonUpdateCheckerTests {

    @Test func extractVersionFromThreePartFilename() {
        let s = EpsilonUpdateChecker.extractVersionString(from: "numworks-graphing-emulator-25.2.2.zip")
        #expect(s == "25.2.2")
    }

    @Test func extractVersionFromTwoPartFilename() {
        let s = EpsilonUpdateChecker.extractVersionString(from: "26.1.zip")
        #expect(s == "26.1.0")
    }

    @Test func extractVersionFromURL() {
        let url = URL(string: "https://cdn.numworks.com/simulator-26.2.0.zip")!
        let s = EpsilonUpdateChecker.extractVersionString(from: url)
        #expect(s == "26.2.0")
    }

    @Test func extractVersionReturnsNilForNoVersion() {
        #expect(EpsilonUpdateChecker.extractVersionString(from: "readme.txt") == nil)
        #expect(EpsilonUpdateChecker.extractVersionString(from: "archive.zip") == nil)
    }

    @Test func checkNeedsUpdateWhenRemoteNewer() throws {
        let url = URL(string: "https://cdn.numworks.com/numworks-26.2.0.zip")!
        let report = try EpsilonUpdateChecker.check(remoteURL: url, currentVersionString: "26.1.0")
        #expect(report.needsUpdate == true)
        #expect(report.remoteVersion.string == "26.2.0")
        #expect(report.currentVersion.string == "26.1.0")
    }

    @Test func checkNoUpdateWhenCurrentSameOrNewer() throws {
        let url = URL(string: "https://cdn.numworks.com/numworks-26.1.0.zip")!
        let reportSame = try EpsilonUpdateChecker.check(remoteURL: url, currentVersionString: "26.1.0")
        #expect(reportSame.needsUpdate == false)

        let reportNewer = try EpsilonUpdateChecker.check(remoteURL: url, currentVersionString: "26.2.0")
        #expect(reportNewer.needsUpdate == false)
    }

    
    @Test func checkThrowsInvalidCurrentVersion() {
        let url = URL(string: "https://cdn.numworks.com/numworks-26.1.0.zip")!
        #expect(throws: EpsilonUpdateChecker.Error.self) {
            try EpsilonUpdateChecker.check(remoteURL: url, currentVersionString: "bad")
        }
    }

    @Test func checkThrowsCouldNotExtractRemoteVersionForURLWithoutVersion() {
        let url = URL(string: "https://cdn.numworks.com/archive.zip")!
        #expect(throws: EpsilonUpdateChecker.Error.self) {
            try EpsilonUpdateChecker.check(remoteURL: url, currentVersionString: "26.1.0")
        }
    }

    @Test func simulateEpsilonUpdateAvailable() throws {
        let url = URL(string: "https://cdn.numworks.com/simulator-26.2.0.zip")!
        let report = try EpsilonUpdateChecker.check(remoteURL: url, currentVersionString: "26.1.0")
        #expect(report.needsUpdate == true)
        #expect(report.remoteVersion.string == "26.2.0")
    }

    @Test func simulateEpsilonNoUpdateAvailable() throws {
        let url = URL(string: "https://cdn.numworks.com/simulator-26.1.0.zip")!
        let reportSame = try EpsilonUpdateChecker.check(remoteURL: url, currentVersionString: "26.1.0")
        #expect(reportSame.needsUpdate == false)
        let reportNewer = try EpsilonUpdateChecker.check(remoteURL: url, currentVersionString: "26.2.0")
        #expect(reportNewer.needsUpdate == false)
    }
}

// MARK: - AppUpdateChecker (simulation, no network)

struct AppUpdateCheckerSimulationTests {

    @Test func simulateAppUpdateAvailable() throws {
        let report = try AppUpdateChecker.reportForTesting(currentVersion: "1.0.0", latestVersion: "1.1.0")
        #expect(report.needsUpdate == true)
        #expect(report.currentVersion.string == "1.0.0")
        #expect(report.latestVersion.string == "1.1.0")
    }

    @Test func simulateAppNoUpdateAvailable() throws {
        let reportSame = try AppUpdateChecker.reportForTesting(currentVersion: "1.1.0", latestVersion: "1.1.0")
        #expect(reportSame.needsUpdate == false)
        let reportNewer = try AppUpdateChecker.reportForTesting(currentVersion: "1.2.0", latestVersion: "1.1.0")
        #expect(reportNewer.needsUpdate == false)
    }

    @Test func simulateAppUpdateAvailableWithVTag() throws {
        let report = try AppUpdateChecker.reportForTesting(currentVersion: "1.0.0", latestVersion: "1.1.0", latestTag: "v1.1.0")
        #expect(report.needsUpdate == true)
        #expect(report.latestTag == "v1.1.0")
    }
}
