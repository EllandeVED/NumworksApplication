import Foundation

/// Centralized paths for the offline NumWorks simulator assets.
///
/// Design goals:
/// - The app ships with a bundled default HTML (Resources/DefaultSimulator/numworks-simulator.html)
/// - If a newer simulator is downloaded, it lives in Application Support/<bundle-id>/Simulator/current
/// - The app prefers the downloaded simulator when present, otherwise falls back to the bundled default

enum SimulatorPaths {

    // MARK: - App Support base

    static func appSupportBaseDirectory() throws -> URL {
        let fm = FileManager.default
        let url = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let id = Bundle.main.bundleIdentifier ?? "NumworksApplication"
        return url.appendingPathComponent(id, isDirectory: true)
    }

    // MARK: - Simulator directories

    static func simulatorDirectory() throws -> URL {
        try appSupportBaseDirectory().appendingPathComponent("Simulator", isDirectory: true)
    }

    /// Active downloaded simulator version folder.
    static func currentSimulatorDirectory() throws -> URL {
        try simulatorDirectory().appendingPathComponent("current", isDirectory: true)
    }

    // MARK: - Entry HTML

    /// Bundled default simulator HTML inside the app.
    static func bundledHTMLURL() -> URL {
        guard let url = Bundle.main.url(
            forResource: "numworks-simulator",
            withExtension: "html",
            subdirectory: "DefaultSimulator"
        ) else {
            fatalError("Missing bundled DefaultSimulator/numworks-simulator.html")
        }
        return url
    }

    /// Downloaded simulator HTML if present in Application Support.
    static func installedHTMLURLIfPresent() -> URL? {
        do {
            let url = try currentSimulatorDirectory().appendingPathComponent("numworks-simulator.html", isDirectory: false)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            return nil
        } catch {
            return nil
        }
    }

    /// URL the app should load.
    /// Prefer downloaded simulator; fall back to bundled default.
    static func urlToLoad() -> URL {
        installedHTMLURLIfPresent() ?? bundledHTMLURL()
    }

    // MARK: - Ensure directories exist (for updater)

    static func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        let base = try appSupportBaseDirectory()
        let sim = try simulatorDirectory()
        let current = try currentSimulatorDirectory()

        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        try fm.createDirectory(at: sim, withIntermediateDirectories: true)
        try fm.createDirectory(at: current, withIntermediateDirectories: true)
    }
}
