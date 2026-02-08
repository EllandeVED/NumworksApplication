import Foundation

/// Centralized paths for the offline NumWorks simulator assets.
///
/// Notes:
/// - The app does not ship with any bundled simulator.
/// - Downloaded simulator assets live in Application Support/<bundle-id>/Simulator/current
/// - Versioning and selection logic live in `EpsilonVersions`.

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

    // MARK: - Simulator entry HTML helpers

    /// Build the expected simulator HTML URL for a given normalized version string (NN.NN.NN).
    static func simulatorHTMLURL(version: String) throws -> URL {
        try currentSimulatorDirectory().appendingPathComponent("numworks-simulator-\(version).html", isDirectory: false)
    }

    /// List all HTML files directly in the current simulator directory.
    /// Selection/parsing logic is handled elsewhere.
    static func simulatorHTMLCandidates() -> [URL] {
        do {
            let dir = try currentSimulatorDirectory()
            let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            return items.filter { $0.pathExtension.lowercased() == "html" }
        } catch {
            return []
        }
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
