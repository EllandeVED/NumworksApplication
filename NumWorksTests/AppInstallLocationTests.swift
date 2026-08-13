//
//  AppInstallLocationTests.swift
//  NumWorksTests
//

import Testing
@testable import NumWorks

struct AppInstallLocationTests {

    private let apps = [
        "/Applications",
        "/Users/test/Applications",
    ]

    @Test func installedWhenDirectlyInApplications() {
        #expect(
            AppInstallLocation.isInstalled(
                bundlePath: "/Applications/NumWorks.app",
                applicationDirectoryPaths: apps))
    }

    @Test func installedWhenNestedUnderApplications() {
        #expect(
            AppInstallLocation.isInstalled(
                bundlePath: "/Users/test/Applications/Utils/NumWorks.app",
                applicationDirectoryPaths: apps))
    }

    @Test func installedWhenPathContainsApplicationsComponent() {
        // DerivedData / odd layouts sometimes still include Applications.
        #expect(
            AppInstallLocation.isInstalled(
                bundlePath: "/Volumes/Apps/Applications/NumWorks.app",
                applicationDirectoryPaths: ["/Applications"]))
    }

    @Test func notInstalledInDerivedData() {
        #expect(
            AppInstallLocation.isInstalled(
                bundlePath:
                    "/Users/test/Library/Developer/Xcode/DerivedData/NumWorks/Build/Products/Debug/NumWorks.app",
                applicationDirectoryPaths: apps)
            == false)
    }

    @Test func notInstalledInDownloads() {
        #expect(
            AppInstallLocation.isInstalled(
                bundlePath: "/Users/test/Downloads/NumWorks.app",
                applicationDirectoryPaths: apps)
            == false)
    }

    @Test func emptyApplicationDirsStillHonorsApplicationsComponent() {
        #expect(
            AppInstallLocation.isInstalled(
                bundlePath: "/Applications/NumWorks.app",
                applicationDirectoryPaths: [])
        )
        #expect(
            AppInstallLocation.isInstalled(
                bundlePath: "/tmp/NumWorks.app",
                applicationDirectoryPaths: [])
            == false)
    }
}
