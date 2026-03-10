import Foundation

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

    static func currentSimulatorDirectory() throws -> URL {
        try simulatorDirectory().appendingPathComponent("current", isDirectory: true)
    }

    // MARK: - Simulator entry HTML helpers

    static func simulatorHTMLURL(version: String) throws -> URL {
        try currentSimulatorDirectory().appendingPathComponent("numworks-simulator-\(version).html", isDirectory: false)
    }

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
