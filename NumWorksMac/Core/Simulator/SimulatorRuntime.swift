import Foundation

final class SimulatorRuntime {

    enum RuntimeError: Error {
        case noValidSimulatorInstalled
    }

    func urlToLoad() throws -> URL {
        guard let url = EpsilonVersions.bestSimulatorHTMLURL() else {
            throw RuntimeError.noValidSimulatorInstalled
        }
        return url
    }
}
