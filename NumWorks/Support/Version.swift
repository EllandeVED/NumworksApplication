import Foundation

/// Version information displayed in Settings (Advanced and About).
enum AppInfo {

    /// Marketing version, e.g. "1.0" (CFBundleShortVersionString).
    static var bundleVersion: String {
        info("CFBundleShortVersionString")
    }

    /// Build number, e.g. "1" (CFBundleVersion).
    static var bundleBuild: String {
        info("CFBundleVersion")
    }

    /// Combined display string, e.g. "1.0 (1)".
    static var appVersion: String {
        "\(bundleVersion) (\(bundleBuild))"
    }

    /// Reported by the Epsilon library linked into this process.
    static var epsilonVersion: String {
        EpsilonBridge.epsilonVersionString()
    }

    /// Approximated by the executable's modification date; there is no
    /// build-time stamp in the bundle.
    static var buildDate: String? {
        guard let executable = Bundle.main.executableURL,
              let date = (try? executable.resourceValues(
                  forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func info(_ key: String) -> String {
        Bundle.main.infoDictionary?[key] as? String ?? "?"
    }
}
