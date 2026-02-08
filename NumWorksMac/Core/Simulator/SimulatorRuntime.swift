import Foundation

/// Resolves which simulator HTML to load.
///
/// Notes:
/// - The app does not ship with any bundled simulator.
/// - A simulator is considered valid only if `EpsilonVersions` can detect a versioned
///   `numworks-simulator-X.Y.Z.html` file in Application Support.
final class SimulatorRuntime {

    enum RuntimeError: Error {
        case noValidSimulatorInstalled
    }

    /// Returns the URL that WKWebView should load.
    func urlToLoad() throws -> URL {
        guard let url = EpsilonVersions.bestSimulatorHTMLURL() else {
            throw RuntimeError.noValidSimulatorInstalled
        }
        return url
    }
}
