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

    private let fileManager = FileManager.default

    func presentUpdate(remoteURL: URL, remoteVersion: String) {
        Task { @MainActor in
            let notes = (try? await AppUpdateChecker.fetchLatestReleaseNotes()) ?? ""
            phase = .updateAvailable(version: remoteVersion, url: remoteURL, releaseNotes: notes)
            showPanel()
        }
    }

    func dismiss() {
        closePanel()
        phase = .idle
    }

    func downloadAndInstall(remoteURL: URL) async {
        phase = .downloading

        do {
            let (tmpURL, response) = try await URLSession.shared.download(from: remoteURL)

            let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!

            var filename = response.suggestedFilename ?? remoteURL.lastPathComponent
            if filename.isEmpty { filename = "NumWorks.zip" }
            if filename.lowercased().hasSuffix(".zip") == false {
                filename += ".zip"
            }

            let zipURL = downloads.appendingPathComponent(filename)

            try? fileManager.removeItem(at: zipURL)
            try fileManager.moveItem(at: tmpURL, to: zipURL)

            if zipURL.pathExtension.lowercased() != "zip" {
                throw NSError(domain: "AppUpdater", code: 2)
            }

            let unzipStart = Date()
            try unzip(zipURL: zipURL, to: downloads)
            try? fileManager.removeItem(at: zipURL)

            let extractedApp = try findNewestExtractedApp(in: downloads, since: unzipStart)
            let targetApp = downloads.appendingPathComponent("NumWorks.app")

            if extractedApp.standardizedFileURL != targetApp.standardizedFileURL {
                try? fileManager.removeItem(at: targetApp)
                try fileManager.moveItem(at: extractedApp, to: targetApp)
            } else {
                // If it already extracted as NumWorks.app, make sure it replaces any previous copy.
                // (At this point, targetApp is the extracted app.)
            }

            phase = .readyToOpen
        } catch {
            // Best effort cleanup
            if let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                let fallback = downloads.appendingPathComponent("NumWorks.zip")
                try? fileManager.removeItem(at: fallback)
            }
            phase = .failed(error.localizedDescription)
        }
    }

    func openDownloadsAndQuit() {
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        NSWorkspace.shared.open(downloads)
        NSApp.terminate(nil)
    }

    private func findNewestExtractedApp(in downloads: URL, since: Date) throws -> URL {
        let fm = fileManager
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]

        guard let e = fm.enumerator(at: downloads, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            throw NSError(domain: "AppUpdater", code: 3)
        }

        var bestURL: URL?
        var bestDate: Date = since

        for case let url as URL in e {
            if url.pathExtension.lowercased() != "app" { continue }

            let rv = try? url.resourceValues(forKeys: keys)
            guard rv?.isDirectory == true else { continue }

            let d = rv?.contentModificationDate ?? .distantPast
            if d >= bestDate {
                bestDate = d
                bestURL = url
            }
        }

        if let bestURL { return bestURL }
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
