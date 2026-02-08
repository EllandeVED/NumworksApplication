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

    // Parses NumWorks' official download page, finds all simulator zip URLs, and returns the highest version.
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

        let pattern = #"https:\/\/cdn\.numworks\.com\/[A-Za-z0-9_-]+\/numworks-simulator-(\d+\.\d+\.\d+)\.zip"#
        let r = try NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = r.matches(in: html, range: range)
        guard !matches.isEmpty else {
            throw Error.couldNotExtractRemoteURL
        }

        var best: (url: URL, ver: SemVer)?

        for m in matches {
            guard let urlRange = Range(m.range(at: 0), in: html) else { continue }
            let urlString = String(html[urlRange])
            guard let url = URL(string: urlString) else { continue }

            guard let verRange = Range(m.range(at: 1), in: html) else { continue }
            let verString = String(html[verRange])
            guard let ver = SemVer(verString) else { continue }

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

    static func extractVersionString(from filename: String) -> String? {
        let pattern = #"(\d+)\.(\d+)\.(\d+)"#
        guard let r = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let m = r.firstMatch(in: filename, range: range) else { return nil }
        guard let rr = Range(m.range(at: 0), in: filename) else { return nil }
        return String(filename[rr])
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
