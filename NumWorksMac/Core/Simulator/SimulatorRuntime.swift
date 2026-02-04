import Foundation

/// Responsible for ensuring the simulator HTML exists in Application Support and returning a loadable URL.
///
/// This intentionally keeps all knowledge about the bundled seed file here.
final class SimulatorRuntime {

    enum RuntimeError: Error {
        case bundledHTMLNotFound
    }

    /// Returns the URL that WKWebView should load.
    /// If the HTML is missing in Application Support, copies the bundled default there first.
    func urlToLoad() throws -> URL {
        try SimulatorPaths.ensureDirectoriesExist()

        let target = try SimulatorPaths.currentHTMLURL()
        if FileManager.default.fileExists(atPath: target.path) {
            return target
        }

        try installBundledDefaultIfNeeded(to: target)
        return target
    }

    // MARK: - Install bundled seed

    private func installBundledDefaultIfNeeded(to targetURL: URL) throws {
        guard let bundled = bundledDefaultHTMLURL() else {
            throw RuntimeError.bundledHTMLNotFound
        }

        let fm = FileManager.default
        // Ensure parent directory exists.
        try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Copy bundled file into Application Support.
        // (We expect it not to exist yet, but handle the case defensively.)
        if fm.fileExists(atPath: targetURL.path) {
            return
        }
        try fm.copyItem(at: bundled, to: targetURL)
    }

    private func bundledDefaultHTMLURL() -> URL? {
        return Bundle.main.url(forResource: "numworks-simulator", withExtension: "html", subdirectory: "DefaultSimulator")
            ?? Bundle.main.url(forResource: "numworks-simulator", withExtension: "html")
    }
}
