import Foundation

/// Centralized paths for the offline NumWorks simulator assets.
///
/// Design goals:
/// - The app ships with a bundled default HTML (Resources/DefaultSimulator/numworks-simulator.html)
/// - On first launch, we copy that file into Application Support so it can be updated/replaced later
/// - The WKWebView always loads from Application Support (not from the read-only app bundle)

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
        // Use a stable folder name that matches the app name.
        return url.appendingPathComponent("NumWorksMac", isDirectory: true)
    }

    // MARK: - Simulator directories

    static func simulatorDirectory() throws -> URL {
        return try appSupportBaseDirectory().appendingPathComponent("simulator", isDirectory: true)
    }

    /// Active simulator version folder.
    static func currentSimulatorDirectory() throws -> URL {
        return try simulatorDirectory().appendingPathComponent("current", isDirectory: true)
    }

    // MARK: - Entry HTML

    /// Where the app should load the simulator HTML from.
    static func currentHTMLURL() throws -> URL {
        return try currentSimulatorDirectory().appendingPathComponent("numworks-simulator.html", isDirectory: false)
    }

    // MARK: - Ensure directories exist

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
