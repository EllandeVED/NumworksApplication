import Foundation

/// Version information displayed in Settings > Advanced.
enum AppInfo {

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// Reported by the Epsilon library linked into this process.
    static var epsilonVersion: String {
        EpsilonBridge.epsilonVersionString()
    }
}
