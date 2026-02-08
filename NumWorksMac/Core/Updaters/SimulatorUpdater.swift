import Foundation
import AppKit
import SwiftUI
import Combine

@MainActor
final class SimulatorUpdater: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = SimulatorUpdater()

    enum Phase: Equatable {
        case idle
        case prompt
        case downloading
        case readyToInstall
        case installing
        case restartCountdown
    }

    @Published var isPresented = false
    @Published var phase: Phase = .idle

    @Published var fromVersion: String = EpsilonVersions.bundledSimulator
    @Published var toVersion: String = ""

    @Published var progress: Double = 0
    @Published var progressText: String = ""

    @Published var headline: String = "Update Available"
    @Published var message: String = "A new version of the NumWorks system is available."

    @Published var isRequired: Bool = false

    @Published var restartSecondsRemaining: Int = 0

    private var restartTimer: AnyCancellable?

    private var remoteURL: URL?
    private var stagedZipURL: URL?

    private var panel: NSPanel?

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
    }

    func presentUpdate(remoteURL: URL, remoteVersion: String) {
        print("[SimulatorUpdater] presentUpdate remoteVersion=\(remoteVersion) url=\(remoteURL)")
        isRequired = false
        headline = "Update Available"
        message = "A new version of the NumWorks system is available."
        restartTimer?.cancel()
        restartTimer = nil
        restartSecondsRemaining = 0
        self.remoteURL = remoteURL
        self.fromVersion = currentInstalledVersion
        self.toVersion = remoteVersion
        setProgress(0)
        self.phase = .prompt
        self.isPresented = true
        showPanel()
    }

    func presentRequiredDownload(remoteURL: URL, remoteVersion: String) {
        print("[SimulatorUpdater] presentRequiredDownload remoteVersion=\(remoteVersion) url=\(remoteURL)")
        isRequired = true
        headline = "NumWorks framework needed"
        message = "NumWorks framework needed to run app."
        restartTimer?.cancel()
        restartTimer = nil
        restartSecondsRemaining = 0
        self.remoteURL = remoteURL
        self.fromVersion = currentInstalledVersion
        self.toVersion = remoteVersion
        setProgress(0)
        self.phase = .prompt
        self.isPresented = true
        showPanel()
    }

    func dismiss() {
        print("[SimulatorUpdater] dismiss")
        if isRequired { return }
        closePanel()
        restartTimer?.cancel()
        restartTimer = nil
        restartSecondsRemaining = 0
        isRequired = false
        isPresented = false
        phase = .idle
        progress = 0
        progressText = ""
        remoteURL = nil
        stagedZipURL = nil
    }

    func startDownload() {
        print("[SimulatorUpdater] startDownload")
        guard let url = remoteURL else { return }
        print("[SimulatorUpdater] downloading \(url)")
        setProgress(0)
        phase = .downloading

        let task = session.downloadTask(with: url)
        task.resume()
    }

    func install() {
        print("[SimulatorUpdater] install")
        isRequired = false
        guard let zip = stagedZipURL else { return }
        print("[SimulatorUpdater] installing from staged zip: \(zip.path)")
        phase = .installing
        progressText = "Installing…"

        do {
            let fm = FileManager.default
            let currentDir = simulatorCurrentDir
            let stagingDir = simulatorStagingDir

            if fm.fileExists(atPath: stagingDir.path) {
                try? fm.removeItem(at: stagingDir)
            }
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            try unzip(zipFile: zip, to: stagingDir)

            // swap
            if fm.fileExists(atPath: currentDir.path) {
                try? fm.removeItem(at: currentDir)
            }
            try fm.moveItem(at: stagingDir, to: currentDir)
            try ensureSimulatorEntryHTML(in: currentDir)

            setInstalledVersion(toVersion)
            print("[SimulatorUpdater] installed version set to \(toVersion)")

            // cleanup staged artifacts
            try? fm.removeItem(at: zip)
            stagedZipURL = nil

            beginRestartCountdown(seconds: 2)
        } catch {
            progressText = "Install failed"
            phase = .readyToInstall
            print("[SimulatorUpdater] install failed: \(error)")
        }
    }

    func restartNow() {
        print("[SimulatorUpdater] restartNow")
        restartTimer?.cancel()
        restartTimer = nil
        restartApp()
    }

    // Helper to clamp and set progress and text
    private func setProgress(_ value: Double) {
        let v = max(0, min(1, value))
        progress = v
        let pct = Int((v * 100).rounded())
        progressText = "\(min(pct, 100))%"
    }

    private func beginRestartCountdown(seconds: Int) {
        print("[SimulatorUpdater] beginRestartCountdown \(seconds)s")

        headline = "Restart Required"
        message = "You must now restart the app."
        progressText = ""
        phase = .restartCountdown

        panel?.title = "Restart Required"

        restartTimer?.cancel()
        restartSecondsRemaining = seconds

        restartTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.restartSecondsRemaining > 0 {
                    self.restartSecondsRemaining -= 1
                }
                if self.restartSecondsRemaining <= 0 {
                    self.restartNow()
                }
            }
    }

    nonisolated private static func appSupportDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let id = Bundle.main.bundleIdentifier ?? "NumworksApplication"
        return base.appendingPathComponent(id, isDirectory: true)
    }

    nonisolated private static func simulatorRootDir() -> URL {
        appSupportDir().appendingPathComponent("Simulator", isDirectory: true)
    }

    nonisolated private static func simulatorZipStageURL() -> URL {
        simulatorRootDir().appendingPathComponent("staged.zip", isDirectory: false)
    }

    nonisolated static func isInstalledSimulatorPresent() -> Bool {
        // 1) Installed simulator (Application Support/.../Simulator/current)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let id = Bundle.main.bundleIdentifier ?? "NumworksApplication"
        let currentDir = base
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("Simulator", isDirectory: true)
            .appendingPathComponent("current", isDirectory: true)

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: currentDir.path, isDirectory: &isDir), isDir.boolValue {
            if let items = try? FileManager.default.contentsOfDirectory(atPath: currentDir.path), !items.isEmpty {
                return true
            }
        }

        // 2) Bundled default simulator (Resources/DefaultSimulator/numworks-simulator.html)
        if Bundle.main.url(forResource: "numworks-simulator", withExtension: "html", subdirectory: "DefaultSimulator") != nil {
            return true
        }

        return false
    }

    // Added per update prompting fixes and cleanup
    nonisolated static func installedSimulatorVersionString() -> String {
        UserDefaults.standard.string(forKey: "installedSimulatorVersion") ?? EpsilonVersions.bundledSimulator
    }

    nonisolated static func hasInstalledSimulatorInAppSupport() -> Bool {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let id = Bundle.main.bundleIdentifier ?? "NumworksApplication"
        let currentDir = base
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("Simulator", isDirectory: true)
            .appendingPathComponent("current", isDirectory: true)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: currentDir.path, isDirectory: &isDir), isDir.boolValue else { return false }
        if let items = try? FileManager.default.contentsOfDirectory(atPath: currentDir.path) {
            return !items.isEmpty
        }
        return false
    }

    nonisolated static func clearInstalledSimulatorVersionIfUsingBundled() {
        if !hasInstalledSimulatorInAppSupport() {
            UserDefaults.standard.removeObject(forKey: "installedSimulatorVersion")
        }
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let raw = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let clamped = max(0, min(1, raw))
        let pct = Int((clamped * 100).rounded(.down))

        Task { @MainActor in
            let updater = SimulatorUpdater.shared
            updater.progress = clamped
            updater.progressText = "\(min(pct, 100))%"
            if totalBytesWritten >= totalBytesExpectedToWrite {
                updater.progress = 1
                updater.progressText = "100%"
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        print("[SimulatorUpdater] download finished, staging zip")

        let fm = FileManager.default
        let zip = Self.simulatorZipStageURL()

        do {
            if fm.fileExists(atPath: zip.path) {
                try? fm.removeItem(at: zip)
            }
            try fm.createDirectory(at: zip.deletingLastPathComponent(), withIntermediateDirectories: true)

            // Move immediately while the temp file still exists.
            do {
                try fm.moveItem(at: location, to: zip)
            } catch {
                try fm.copyItem(at: location, to: zip)
            }

            print("[SimulatorUpdater] staged zip at \(zip.path)")

            Task { @MainActor in
                let updater = SimulatorUpdater.shared
                updater.stagedZipURL = zip
                updater.progress = 1
                updater.progressText = "100%"
                updater.phase = .readyToInstall
            }
        } catch {
            print("[SimulatorUpdater] staging failed: \(error)")
            Task { @MainActor in
                let updater = SimulatorUpdater.shared
                updater.progressText = "Download failed"
                updater.phase = .prompt
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }

        Task { @MainActor in
            let updater = SimulatorUpdater.shared
            if updater.phase == .readyToInstall || updater.stagedZipURL != nil {
                print("[SimulatorUpdater] download completion error ignored (already staged): \(error)")
                return
            }
            updater.progressText = "Download failed"
            updater.phase = .prompt
            print("[SimulatorUpdater] download error: \(error)")
        }
    }

    // MARK: - Paths + versions

    private var currentInstalledVersion: String {
        UserDefaults.standard.string(forKey: "installedSimulatorVersion") ?? EpsilonVersions.bundledSimulator
    }

    private func setInstalledVersion(_ v: String) {
        UserDefaults.standard.set(v, forKey: "installedSimulatorVersion")
    }

    private var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let id = Bundle.main.bundleIdentifier ?? "NumworksApplication"
        return base.appendingPathComponent(id, isDirectory: true)
    }

    private var simulatorRootDir: URL {
        appSupportDir.appendingPathComponent("Simulator", isDirectory: true)
    }

    private var simulatorCurrentDir: URL {
        simulatorRootDir.appendingPathComponent("current", isDirectory: true)
    }

    private var simulatorStagingDir: URL {
        simulatorRootDir.appendingPathComponent("staging", isDirectory: true)
    }

    private var simulatorZipStageURL: URL {
        simulatorRootDir.appendingPathComponent("staged.zip", isDirectory: false)
    }

    // MARK: - Install helpers

    private func ensureSimulatorEntryHTML(in currentDir: URL) throws {
        let fm = FileManager.default
        let desired = currentDir.appendingPathComponent("numworks-simulator.html", isDirectory: false)
        if fm.fileExists(atPath: desired.path) { return }

        let index = currentDir.appendingPathComponent("index.html", isDirectory: false)
        if fm.fileExists(atPath: index.path) {
            try? fm.removeItem(at: desired)
            try fm.moveItem(at: index, to: desired)
            return
        }

        let items = (try? fm.contentsOfDirectory(at: currentDir, includingPropertiesForKeys: nil)) ?? []
        if let firstHTML = items.first(where: { $0.pathExtension.lowercased() == "html" }) {
            try? fm.removeItem(at: desired)
            try fm.moveItem(at: firstHTML, to: desired)
        }
    }

    private func unzip(zipFile: URL, to dest: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zipFile.path, dest.path]
        try p.run()
        p.waitUntilExit()
    }

    private func restartApp() {
        let appURL = Bundle.main.bundleURL
        let appPath = appURL.path
        let pid = ProcessInfo.processInfo.processIdentifier

        let escapedPath = appPath.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "(while /bin/kill -0 \(pid) >/dev/null 2>&1; do /bin/sleep 0.1; done; /usr/bin/open \"\(escapedPath)\") &"

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()

        NSApp.terminate(nil)
    }

    private func showPanel() {
        print("[SimulatorUpdater] showPanel")
        NSApp.activate(ignoringOtherApps: true)

        if let panel {
            print("[SimulatorUpdater] reusing existing panel")
            panel.makeKeyAndOrderFront(nil)
            panel.center()
            return
        }

        print("[SimulatorUpdater] creating panel")
        let host = NSHostingController(rootView: SimulatorUpdateSheet())

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        p.title = "Epsilon Simulator Update"
        p.isFloatingPanel = true
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.center()
        p.contentViewController = host
        p.makeKeyAndOrderFront(nil)

        panel = p
    }

    private func closePanel() {
        print("[SimulatorUpdater] closePanel")
        panel?.orderOut(nil)
        panel = nil
    }
}
