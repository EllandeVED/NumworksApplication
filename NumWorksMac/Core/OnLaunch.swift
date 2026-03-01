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
                print("[EpsilonUpdateChecker] could not get remote URL: \(error)")
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

        // 2) Run checkers (only if automatic checks are enabled)
        var appNeedsUpdate = false
        var appLatestURL: URL?
        var appLatestTag: String?

        if Preferences.shared.checkForAppUpdatesAutomatically {
            do {
                print("[OnLaunch] checking app update")
                let report = try await AppUpdateChecker.checkLatestRelease()
                appNeedsUpdate = report.needsUpdate
                print("[OnLaunch] app update check needsUpdate=\(report.needsUpdate) tag=\(report.latestTag)")
                appLatestURL = report.latestZipURL
                appLatestTag = report.latestTag
            } catch {
                print("[OnLaunch] app update check failed: \(error)")
            }
        } else {
            print("[OnLaunch] app update check skipped (automatic check disabled)")
        }

        var epsilonNeedsUpdate = false
        var epsilonRemoteURL: URL?
        var epsilonRemoteVersion: String?

        if Preferences.shared.checkForEpsilonUpdatesAutomatically {
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
                print("[EpsilonUpdateChecker] error: \(error)")
            }
        } else {
            print("[OnLaunch] epsilon update check skipped (automatic check disabled)")
        }

        guard appNeedsUpdate || epsilonNeedsUpdate else {
            print("[OnLaunch] no updates")
            return
        }

        // 3) Let the app finish loading and settle
        print("[OnLaunch] updates found → waiting 5s")
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        // 4) Order: App update first, then Epsilon update
        if appNeedsUpdate {
            if let u = appLatestURL, u.pathExtension.lowercased() == "zip" {
                print("[OnLaunch] requesting AppUpdate UI")
                NotificationCenter.default.post(
                    name: .requestAppUpdateUI,
                    object: nil,
                    userInfo: [
                        "latestURL": u,
                        "latestTag": appLatestTag ?? ""
                    ]
                )

                if epsilonNeedsUpdate {
                    print("[OnLaunch] waiting for appUpdateFlowDidFinish")
                    await waitForNotification(.appUpdateFlowDidFinish)
                    print("[OnLaunch] appUpdateFlowDidFinish received")
                }
            } else {
                print("[OnLaunch] app update available but no valid zip URL; skipping UI")
                appNeedsUpdate = false
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
        await withCheckedContinuation { cont in
            let holder = TokenHolder()
            holder.token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                if let t = holder.token { NotificationCenter.default.removeObserver(t) }
                cont.resume()
            }
        }
    }

    @MainActor
    private static func maybeMoveToApplications() async {
        guard !ProcessInfo.processInfo.arguments.contains("-skipMoveToApplications") else { return }
        AppMover.moveIfNecessary()
    }
}

private final class TokenHolder: @unchecked Sendable {
    var token: NSObjectProtocol?
}

extension Notification.Name {
    static let calculatorDidLoad = Notification.Name("calculatorDidLoad")
    static let requestAppUpdateUI = Notification.Name("requestAppUpdateUI")
    static let requestEpsilonUpdateUI = Notification.Name("requestEpsilonUpdateUI")
    static let appUpdateFlowDidFinish = Notification.Name("appUpdateFlowDidFinish")
}
