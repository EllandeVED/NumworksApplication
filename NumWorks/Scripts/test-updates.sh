#!/usr/bin/env bash
set -euo pipefail

# Tests the production schedule, prompt state, relaunch arguments, and Sparkle
# user-driver callback. Uses isolated preferences and no network or app moves.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEST_DIR="${PROJECT_DIR}/build/update-tests"
HARNESS_DIR="${TEST_DIR}/harness"
SPARKLE_XCFRAMEWORK="${SPARKLE_XCFRAMEWORK:-${PROJECT_DIR}/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework}"

if [[ ! -d "${SPARKLE_XCFRAMEWORK}" ]]; then
    echo "Set SPARKLE_XCFRAMEWORK to the resolved Sparkle.xcframework, or resolve Xcode package dependencies first." >&2
    exit 1
fi

mkdir -p "${HARNESS_DIR}/Sources/NumWorks" "${HARNESS_DIR}/Tests/NumWorksTests"
ln -sfn "${SPARKLE_XCFRAMEWORK}" "${HARNESS_DIR}/Sparkle.xcframework"
cp "${PROJECT_DIR}/NumWorks/Updates/UpdatePolicy.swift" \
   "${PROJECT_DIR}/NumWorks/Updates/MoveRequiredUpdateDriver.swift" \
   "${PROJECT_DIR}/NumWorks/AppMover/AppInstallLocation.swift" \
   "${PROJECT_DIR}/NumWorks/AppMover/Extensions.swift" \
   "${PROJECT_DIR}/NumWorks/Support/TelemetryDelivery.swift" \
   "${HARNESS_DIR}/Sources/NumWorks/"
cp "${PROJECT_DIR}/NumWorksTests/UpdateTests.swift" \
   "${PROJECT_DIR}/NumWorksTests/AppInstallLocationTests.swift" \
   "${HARNESS_DIR}/Tests/NumWorksTests/"

cat > "${HARNESS_DIR}/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "UpdateRegressionTests",
    platforms: [.macOS("15.5")],
    dependencies: [.package(path: "../../../Packages/Aptabase")],
    targets: [
        .binaryTarget(name: "Sparkle", path: "Sparkle.xcframework"),
        .target(name: "NumWorks", dependencies: [
            "Sparkle", .product(name: "Aptabase", package: "Aptabase")
        ]),
        .testTarget(name: "NumWorksTests", dependencies: ["NumWorks", "Sparkle"])
    ])
SWIFT

export CLANG_MODULE_CACHE_PATH="${TEST_DIR}/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${CLANG_MODULE_CACHE_PATH}"
swift test --package-path "${HARNESS_DIR}" --scratch-path "${TEST_DIR}/core" \
    --cache-path "${TEST_DIR}/cache" --config-path "${TEST_DIR}/config" \
    --security-path "${TEST_DIR}/security" --manifest-cache local --disable-sandbox
