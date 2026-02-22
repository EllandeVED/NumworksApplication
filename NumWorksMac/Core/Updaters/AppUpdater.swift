import Foundation
import AppKit
import Combine
import SwiftUI

@MainActor
final class AppUpdater: ObservableObject {

    static let shared = AppUpdater()

    enum Phase {
        case idle
        case updateAvailable(version: String, url: URL, releaseNotes: String)
        case downloading
        case readyToOpen
        case failed(String)
    }

    @Published var phase: Phase = .idle

    private var panel: NSPanel?
    /// Kept so Retry can run after a failed attempt (phase does not carry URL).
    private var lastUpdateURL: URL?

    private let fileManager = FileManager.default

    func presentUpdate(remoteURL: URL, remoteVersion: String) {
        Task { @MainActor in
            let notes = (try? await AppUpdateChecker.fetchLatestReleaseNotes()) ?? ""
            lastUpdateURL = remoteURL
            phase = .updateAvailable(version: remoteVersion, url: remoteURL, releaseNotes: notes)
            showPanel()
        }
    }

    func dismiss() {
        closePanel()
        phase = .idle
        lastUpdateURL = nil
        NotificationCenter.default.post(name: .appUpdateFlowDidFinish, object: nil)
    }

    func retry() {
        guard let url = lastUpdateURL else { return }
        Task { await downloadAndInstall(remoteURL: url) }
    }

    func downloadAndInstall(remoteURL: URL) async {
        if case .downloading = phase { return }
        phase = .downloading
        lastUpdateURL = remoteURL

        guard let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            phase = .failed("Downloads folder unavailable.")
            return
        }

        let extractDir = downloads.appendingPathComponent("NumWorksUpdate", isDirectory: true)

        do {
            let (tmpURL, response) = try await URLSession.shared.download(from: remoteURL)

            var filename = response.suggestedFilename ?? remoteURL.lastPathComponent
            if filename.isEmpty { filename = "NumWorks.zip" }
            if !filename.lowercased().hasSuffix(".zip") {
                filename += ".zip"
            }

            let zipURL = downloads.appendingPathComponent(filename)

            try? fileManager.removeItem(at: zipURL)
            try fileManager.moveItem(at: tmpURL, to: zipURL)

            try? fileManager.removeItem(at: extractDir)
            try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

            try unzip(zipURL: zipURL, to: extractDir)
            try? fileManager.removeItem(at: zipURL)

            let extractedApp = try findExtractedApp(in: extractDir)
            let targetApp = downloads.appendingPathComponent("NumWorks.app")

            if extractedApp.standardizedFileURL != targetApp.standardizedFileURL {
                try? fileManager.removeItem(at: targetApp)
                try fileManager.moveItem(at: extractedApp, to: targetApp)
            }

            try? fileManager.removeItem(at: extractDir)
            phase = .readyToOpen
        } catch {
            try? fileManager.removeItem(at: extractDir)
            try? fileManager.removeItem(at: downloads.appendingPathComponent("NumWorks.zip"))
            phase = .failed(error.localizedDescription)
        }
    }

    func openDownloadsAndQuit() {
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let targetApp = downloads.appendingPathComponent("NumWorks.app")

        if fileManager.fileExists(atPath: targetApp.path) {
            NSWorkspace.shared.activateFileViewerSelecting([targetApp])
        } else {
            // Fallback: just open Downloads if the app is not found
            NSWorkspace.shared.open(downloads)
        }

        NSApp.terminate(nil)
    }

    /// Finds the first .app bundle under the given directory (e.g. our dedicated extract folder).
    /// Unzip often restores timestamps from the zip, so we do not filter by date.
    private func findExtractedApp(in directory: URL) throws -> URL {
        let fm = fileManager
        let keys: Set<URLResourceKey> = [.isDirectoryKey]

        guard let e = fm.enumerator(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            throw NSError(domain: "AppUpdater", code: 3)
        }

        for case let url as URL in e {
            guard url.pathExtension.lowercased() == "app" else { continue }
            let rv = try? url.resourceValues(forKeys: keys)
            guard rv?.isDirectory == true else { continue }
            return url
        }

        throw NSError(domain: "AppUpdater", code: 4)
    }

    private func unzip(zipURL: URL, to destination: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-o", zipURL.path, "-d", destination.path]
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw NSError(domain: "AppUpdater", code: 1)
        }
    }


    private func showPanel() {
        NSApp.activate(ignoringOtherApps: true)

        if let panel {
            panel.makeKeyAndOrderFront(nil)
            panel.center()
            return
        }

        let host = NSHostingController(rootView: AppUpdateView(updater: self))

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        p.title = "App Update"
        p.isFloatingPanel = true
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.minSize = NSSize(width: 480, height: 360)
        p.center()
        p.contentViewController = host
        p.makeKeyAndOrderFront(nil)

        panel = p
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
    }
}
