//
//  OnLaunch.swift
//  NumworksApplication
//
//  Created by van Egmond Dascon on 07/02/2026.
//

@preconcurrency import Foundation

enum OnLaunch {
    static func ensureAppSupportExists() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let id = Bundle.main.bundleIdentifier ?? "NumworksApplication"
        let root = base.appendingPathComponent(id, isDirectory: true)
        let simulator = root.appendingPathComponent("Simulator", isDirectory: true)

        if !fm.fileExists(atPath: root.path) {
            print("[OnLaunch] app support missing → creating \(root.path)")
        }

        do {
            try fm.createDirectory(at: simulator, withIntermediateDirectories: true)
        } catch {
            print("[OnLaunch] failed to create app support dirs: \(error)")
        }
    }

    static func hasInstalledSimulator() -> Bool {
        EpsilonVersions.currentSimulatorVersionString() != "00.00.00"
    }

    static func requestRequiredSimulatorUpdater() {
        print("[OnLaunch] requestRequiredSimulatorUpdater")
        Task { @MainActor in
            do {
                let remoteURL = try await EpsilonUpdateChecker.fetchLatestRemoteURL()
                let v = EpsilonUpdateChecker.extractVersionString(from: remoteURL) ?? ""
                NotificationCenter.default.post(
                    name: .requestEpsilonUpdateUI,
                    object: nil,
                    userInfo: [
                        "remoteURL": remoteURL,
                        "remoteVersion": v,
                        "required": true
                    ]
                )
            } catch {
                print("[OnLaunch] failed to resolve simulator download URL: \(error)")
            }
        }
    }

    
    static func run() {
        print("[OnLaunch] run()")
        Task { await runAsync() }
    }

    @MainActor
    private static func runAsync() async {
        print("[OnLaunch] runAsync() begin")
        print("[OnLaunch] maybeMoveToApplications")
        await maybeMoveToApplications()
        print("[OnLaunch] maybeMoveToApplications done")

        print("[OnLaunch] ensureAppSupportExists")
        ensureAppSupportExists()
        print("[OnLaunch] ensureAppSupportExists done")

        // Removed simulator missing gate here (moved to AppController)

        // 2) Run checkers
        var appNeedsUpdate = false
        var appLatestURL: URL?
        var appLatestTag: String?

        do {
            print("[OnLaunch] checking app update")
            let report = try await AppUpdateChecker.checkLatestRelease()
            appNeedsUpdate = report.needsUpdate
            print("[OnLaunch] app update check needsUpdate=\(report.needsUpdate) tag=\(report.latestTag)")
            appLatestURL = report.latestHTMLURL
            appLatestTag = report.latestTag
        } catch {
            print("[OnLaunch] app update check failed: \(error)")
            // ignore
        }

        var epsilonNeedsUpdate = false
        var epsilonRemoteURL: URL?
        var epsilonRemoteVersion: String?

        do {
            print("[OnLaunch] checking epsilon update")

            let current = EpsilonVersions.currentSimulatorVersionString()
            let report = try await EpsilonUpdateChecker.checkLatest(currentVersionString: current)

            epsilonNeedsUpdate = report.needsUpdate
            print("[OnLaunch] epsilon update check needsUpdate=\(report.needsUpdate) remote=\(report.remoteVersion.string) current=\(report.currentVersion.string)")

            if report.needsUpdate {
                epsilonRemoteURL = report.remoteURL
                epsilonRemoteVersion = report.remoteVersion.string
            } else {
                print("[OnLaunch] epsilon up to date")
            }
        } catch {
            print("[OnLaunch] epsilon update check failed: \(error)")
            // ignore
        }

        guard appNeedsUpdate || epsilonNeedsUpdate else {
            print("[OnLaunch] no updates")
            return
        }

        // 3) Let the app finish loading and settle
        print("[OnLaunch] updates found → waiting 10s")
        try? await Task.sleep(nanoseconds: 10_000_000_000)

        // 4) Order: App update first, then Epsilon update
        if appNeedsUpdate {
            print("[OnLaunch] requesting AppUpdate UI")
            NotificationCenter.default.post(
                name: .requestAppUpdateUI,
                object: nil,
                userInfo: [
                    "latestURL": appLatestURL as Any,
                    "latestTag": appLatestTag as Any
                ]
            )

            if epsilonNeedsUpdate {
                print("[OnLaunch] waiting for appUpdateFlowDidFinish")
                await waitForNotification(.appUpdateFlowDidFinish)
                print("[OnLaunch] appUpdateFlowDidFinish received")
            }
        }

        if epsilonNeedsUpdate, let epsilonRemoteURL, let epsilonRemoteVersion {
            print("[OnLaunch] requesting EpsilonUpdate UI")
            NotificationCenter.default.post(
                name: .requestEpsilonUpdateUI,
                object: nil,
                userInfo: [
                    "remoteURL": epsilonRemoteURL,
                    "remoteVersion": epsilonRemoteVersion
                ]
            )
        }
    }

    @MainActor
    private static func waitForNotification(_ name: Notification.Name) async {
        var it = NotificationCenter.default.notifications(named: name).makeAsyncIterator()
        _ = await it.next()
    }

    @MainActor
    private static func maybeMoveToApplications() async {
        AppMover.moveIfNecessary()
    }
}

extension Notification.Name {
    static let calculatorDidLoad = Notification.Name("calculatorDidLoad")
    static let requestAppUpdateUI = Notification.Name("requestAppUpdateUI")
    static let requestEpsilonUpdateUI = Notification.Name("requestEpsilonUpdateUI")
    static let appUpdateFlowDidFinish = Notification.Name("appUpdateFlowDidFinish")
}
