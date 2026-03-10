import Foundation

enum EpsilonVersions {

    struct SimulatorVersion: Comparable {
        let major: Int
        let minor: Int
        let patch: Int

        var normalizedString: String {
            "\(String(format: "%02d", major)).\(String(format: "%02d", minor)).\(String(format: "%02d", patch))"
        }

        static func < (lhs: SimulatorVersion, rhs: SimulatorVersion) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            return lhs.patch < rhs.patch
        }
    }

    static func currentSimulatorVersionString() -> String {
        bestDetectedSimulator()?.version.normalizedString ?? "00.00.00"
    }

    static func bestSimulatorHTMLURL() -> URL? {
        bestDetectedSimulator()?.url
    }

    // MARK: - Detection

    private static func bestDetectedSimulator() -> (version: SimulatorVersion, url: URL)? {
        let candidates = SimulatorPaths.simulatorHTMLCandidates()
        var best: (SimulatorVersion, URL)? = nil

        for url in candidates {
            guard let v = parseSimulatorVersion(from: url.lastPathComponent) else { continue }
            if let currentBest = best {
                if v > currentBest.0 { best = (v, url) }
            } else {
                best = (v, url)
            }
        }

        return best.map { (version: $0.0, url: $0.1) }
    }

    private static func parseSimulatorVersion(from filename: String) -> SimulatorVersion? {
        let prefix = "numworks-simulator-"
        let suffix = ".html"
        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else { return nil }

        let start = filename.index(filename.startIndex, offsetBy: prefix.count)
        let end = filename.index(filename.endIndex, offsetBy: -suffix.count)
        let core = String(filename[start..<end])

        let parts = core.split(separator: ".")
        guard parts.count == 3 else { return nil }
        guard let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }

        return SimulatorVersion(major: major, minor: minor, patch: patch)
    }
}
