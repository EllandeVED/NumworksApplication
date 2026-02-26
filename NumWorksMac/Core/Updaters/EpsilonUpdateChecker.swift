import Foundation

struct EpsilonUpdateChecker {
    struct Report: Sendable {
        let currentVersion: SemVer
        let remoteVersion: SemVer
        let needsUpdate: Bool
        let remoteURL: URL
    }

    enum Error: Swift.Error {
        case invalidCurrentVersion(String)
        case invalidResponse
        case couldNotExtractRemoteURL
        case couldNotExtractRemoteVersion(URL)
    }

    static func check(remoteURL: URL, currentVersionString: String) throws -> Report {
        guard let current = SemVer(currentVersionString) else {
            throw Error.invalidCurrentVersion(currentVersionString)
        }
        guard let remoteString = extractVersionString(from: remoteURL),
              let remote = SemVer(remoteString) else {
            throw Error.couldNotExtractRemoteVersion(remoteURL)
        }

        return .init(
            currentVersion: current,
            remoteVersion: remote,
            needsUpdate: remote > current,
            remoteURL: remoteURL
        )
    }

    // Parses NumWorks' download page for cdn.numworks.com zip URLs (e.g. numworks-simulator-*.zip or numworks-graphing-emulator-*.zip).
    // Picks the URL whose filename contains the highest X.Y.Z version.
    static func fetchLatestRemoteURL() async throws -> URL {
        let page = URL(string: "https://www.numworks.com/simulator/download/")!
        var req = URLRequest(url: page)
        req.httpMethod = "GET"
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        req.setValue("NumworksApplication", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw Error.invalidResponse
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw Error.invalidResponse
        }

        // Match any cdn.numworks.com ... .zip URL (e.g. .../numworks-graphing-emulator-25.2.2.zip or .../26.1.zip).
        let urlPattern = #"https://cdn\.numworks\.com/[^"'\s<>]+\.zip"#
        let urlRegex = try NSRegularExpression(pattern: urlPattern)
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let urlMatches = urlRegex.matches(in: html, range: range)

        var best: (url: URL, ver: SemVer)?

        for m in urlMatches {
            guard let urlRange = Range(m.range(at: 0), in: html) else { continue }
            let urlString = String(html[urlRange])
            guard let url = URL(string: urlString) else { continue }
            guard let ver = parseVersionFromFilename(url.lastPathComponent) else { continue }

            if let currentBest = best {
                if ver > currentBest.ver { best = (url, ver) }
            } else {
                best = (url, ver)
            }
        }

        guard let best else {
            throw Error.couldNotExtractRemoteURL
        }

        return best.url
    }

    static func checkLatest(currentVersionString: String) async throws -> Report {
        let remoteURL = try await fetchLatestRemoteURL()
        return try check(remoteURL: remoteURL, currentVersionString: currentVersionString)
    }

    static func extractVersionString(from url: URL) -> String? {
        extractVersionString(from: url.lastPathComponent)
    }

    /// Extracts a version string (X.Y or X.Y.Z) from a filename and normalizes to X.Y.Z for SemVer.
    static func extractVersionString(from filename: String) -> String? {
        parseVersionFromFilename(filename)?.string
    }

    /// Parses X.Y or X.Y.Z from a filename (e.g. "26.1.zip" or "numworks-simulator-25.2.2.zip"). Returns nil if no valid version.
    private static func parseVersionFromFilename(_ filename: String) -> SemVer? {
        // Prefer X.Y.Z then X.Y (treat as X.Y.0).
        let threePart = #"(\d+)\.(\d+)\.(\d+)"#
        // X.Y only when not part of X.Y.Z (e.g. 26.1 in "26.1.zip" yes; 26.1 in "26.1.2.zip" no)
        let twoPart = #"(\d+)\.(\d+)(?=\.zip|[^.\d]|$)"#
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        if let r3 = try? NSRegularExpression(pattern: threePart),
           let m3 = r3.firstMatch(in: filename, range: range),
           let rr = Range(m3.range(at: 0), in: filename) {
            let s = String(filename[rr])
            return SemVer(s)
        }
        if let r2 = try? NSRegularExpression(pattern: twoPart),
           let m2 = r2.firstMatch(in: filename, range: range),
           let r0 = Range(m2.range(at: 0), in: filename),
           let r1 = Range(m2.range(at: 1), in: filename),
           let r2g = Range(m2.range(at: 2), in: filename) {
            let major = Int(filename[r1]) ?? 0
            let minor = Int(filename[r2g]) ?? 0
            return SemVer("\(major).\(minor).0")
        }
        return nil
    }
}

struct SemVer: Comparable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ s: String) {
        let parts = s.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        (major, minor, patch) = (parts[0], parts[1], parts[2])
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    var string: String { "\(major).\(minor).\(patch)" }
}
