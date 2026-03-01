import Foundation

struct AppUpdateChecker {
    struct Report: Sendable {
        let currentVersion: AppSemVer
        let latestVersion: AppSemVer
        let latestTag: String
        let latestZipURL: URL
        let latestReleaseNotesMarkdown: String
        let needsUpdate: Bool
    }

    enum Error: Swift.Error {
        case invalidCurrentVersion(String)
        case invalidResponse
        case invalidLatestTag(String)
        case missingLatestZipURL
    }

    static func checkLatestRelease(owner: String = "EllandeVED", repo: String = "NumworksApplication") async throws -> Report {
        let currentString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard let current = AppSemVer(currentString) else {
            throw Error.invalidCurrentVersion(currentString)
        }

        let api = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var req = URLRequest(url: api)
        req.httpMethod = "GET"
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("NumworksApplication", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw Error.invalidResponse
        }

        let r = try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
        let tag = r.tag_name
        let notes = r.body ?? ""
        let cleaned = AppSemVer.clean(tag)
        guard let latest = AppSemVer(cleaned) else {
            throw Error.invalidLatestTag(tag)
        }
        guard let zipURL = r.assets
            .compactMap({ URL(string: $0.browser_download_url) })
            .first(where: { $0.pathExtension.lowercased() == "zip" }) else {
            throw Error.missingLatestZipURL
        }

        return .init(
            currentVersion: current,
            latestVersion: latest,
            latestTag: tag,
            latestZipURL: zipURL,
            latestReleaseNotesMarkdown: notes,
            needsUpdate: latest > current
        )
    }

    /// Builds a Report from version strings for testing/simulation (no network).
    static func reportForTesting(currentVersion: String, latestVersion: String, latestTag: String? = nil, zipURL: URL = URL(string: "https://example.com/app.zip")!) throws -> Report {
        guard let current = AppSemVer(currentVersion) else {
            throw Error.invalidCurrentVersion(currentVersion)
        }
        let cleaned = AppSemVer.clean(latestVersion)
        guard let latest = AppSemVer(cleaned) else {
            throw Error.invalidLatestTag(latestVersion)
        }
        return Report(
            currentVersion: current,
            latestVersion: latest,
            latestTag: latestTag ?? "v\(latestVersion)",
            latestZipURL: zipURL,
            latestReleaseNotesMarkdown: "",
            needsUpdate: latest > current
        )
    }

    static func fetchLatestReleaseNotes(owner: String = "EllandeVED", repo: String = "NumworksApplication") async throws -> String {
        let api = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var req = URLRequest(url: api)
        req.httpMethod = "GET"
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("NumworksApplication", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw Error.invalidResponse
        }

        let r = try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
        return r.body ?? ""
    }
}

private struct GitHubLatestRelease: Decodable {
    let tag_name: String
    let body: String?
    let assets: [GitHubReleaseAsset]
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browser_download_url: String
}

struct AppSemVer: Comparable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ s: String) {
        let raw = s.split(separator: ".")
        guard raw.count >= 1 && raw.count <= 3 else { return nil }

        let parts = raw.compactMap { Int($0) }
        guard parts.count == raw.count else { return nil }

        let major = parts[0]
        let minor = parts.count > 1 ? parts[1] : 0
        let patch = parts.count > 2 ? parts[2] : 0
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func clean(_ tag: String) -> String {
        var t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("v") || t.hasPrefix("V") {
            t.removeFirst()
        }
        return t
    }

    static func < (lhs: AppSemVer, rhs: AppSemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    var string: String { "\(major).\(minor).\(patch)" }
}
