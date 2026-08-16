import AppKit
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

    /// Application icon from the asset catalog (cached).
    static let applicationIcon: NSImage = {
        if let icon = NSImage(named: NSImage.Name("AppIcon")), icon.isValid, icon.size != .zero {
            return icon
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        return NSApp.applicationIconImage
    }()

    /// 96×96 raster used in Settings/About so SwiftUI does not keep the 1024pt asset uncompressed.
    static let aboutIcon: NSImage = applicationIcon.numworks_rasterized(to: 96)

    private static func info(_ key: String) -> String {
        Bundle.main.infoDictionary?[key] as? String ?? "?"
    }
}

extension NSImage {
    fileprivate func numworks_rasterized(to side: CGFloat) -> NSImage {
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        image.unlockFocus()
        return image
    }
}
