// swift-tools-version: 5.7
import PackageDescription
// aptabase-swift 0.4.0, a1ee53e99478921cd166c40f59f2e41271032776, with tracked local changes.
let package = Package(name: "Aptabase",
    platforms: [.iOS(.v13), .macCatalyst(.v13), .macOS(.v10_15), .watchOS(.v6), .tvOS(.v13)],
    products: [.library(name: "Aptabase", targets: ["Aptabase"])],
    targets: [
        .target(name: "Aptabase", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "AptabaseTests", dependencies: ["Aptabase"])
    ])
