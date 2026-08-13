import Foundation

/// Pure path rules for “is this bundle in an Applications folder?”.
/// Kept separate from `Bundle` so unit tests can feed fixture paths.
enum AppInstallLocation {

    /// Returns true when `bundlePath` lives under any Applications directory,
    /// or any path component is exactly `Applications`.
    static func isInstalled(
        bundlePath: String,
        applicationDirectoryPaths: [String]
    ) -> Bool {
        let parent = (bundlePath as NSString).deletingLastPathComponent
        for dir in applicationDirectoryPaths {
            let path = dir
            if parent == path || parent.hasPrefix(path + "/") {
                return true
            }
        }
        return bundlePath.split(separator: "/").contains("Applications")
    }
}
