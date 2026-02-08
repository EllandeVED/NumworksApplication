import Foundation

/// Resolves which simulator HTML to load.
///
/// Behavior:
/// - If an installed simulator exists in Application Support (Simulator/current/numworks-simulator.html), load that.
/// - Otherwise, load the bundled DefaultSimulator directly from the app bundle.
///
/// The bundled default is never copied into Application Support.
final class SimulatorRuntime {

    enum RuntimeError: Error {
        case bundledHTMLNotFound
    }

    /// Returns the URL that WKWebView should load.
    func urlToLoad() throws -> URL {
        if let installed = installedSimulatorHTMLURL(), FileManager.default.fileExists(atPath: installed.path) {
            return installed
        }

        guard let bundled = bundledDefaultHTMLURL() else {
            throw RuntimeError.bundledHTMLNotFound
        }
        return bundled
    }

    // MARK: - Installed simulator

    private func installedSimulatorHTMLURL() -> URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else { return nil }

        let id = Bundle.main.bundleIdentifier ?? "NumworksApplication"
        let currentDir = base
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("Simulator", isDirectory: true)
            .appendingPathComponent("current", isDirectory: true)

        return currentDir.appendingPathComponent("numworks-simulator.html", isDirectory: false)
    }

    // MARK: - Bundled default

    private func bundledDefaultHTMLURL() -> URL? {
        Bundle.main.url(forResource: "numworks-simulator", withExtension: "html", subdirectory: "DefaultSimulator")
            ?? Bundle.main.url(forResource: "numworks-simulator", withExtension: "html")
    }
}
