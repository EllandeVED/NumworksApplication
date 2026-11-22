#!/usr/bin/env bash
set -euo pipefail

# Runs the actual milestone state machine and the vendored SDK against fake
# transports. No GUI app, live Aptabase traffic, or user preferences are used.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEST_DIR="${PROJECT_DIR}/build/telemetry-tests"
HARNESS_DIR="${TEST_DIR}/harness"

mkdir -p "${HARNESS_DIR}/Sources/NumWorks" "${HARNESS_DIR}/Tests/NumWorksTests"
cp "${PROJECT_DIR}/NumWorks/Support/TelemetryDelivery.swift" \
   "${PROJECT_DIR}/NumWorks/Support/TelemetryOutbox.swift" \
   "${HARNESS_DIR}/Sources/NumWorks/"
cp "${PROJECT_DIR}/NumWorksTests/TelemetryTests.swift" \
   "${HARNESS_DIR}/Tests/NumWorksTests/"

cat > "${HARNESS_DIR}/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TelemetryRegressionTests",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../../Packages/Aptabase")],
    targets: [
        .target(name: "NumWorks", dependencies: [
            .product(name: "Aptabase", package: "Aptabase")
        ]),
        .testTarget(name: "NumWorksTests", dependencies: [
            "NumWorks", .product(name: "Aptabase", package: "Aptabase")
        ])
    ])
SWIFT

export CLANG_MODULE_CACHE_PATH="${TEST_DIR}/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${CLANG_MODULE_CACHE_PATH}"

run_suite() {
    local manifest="$1"
    local scratch="$2"
    # Disable SwiftPM's nested manifest sandbox so this also works in a
    # sandboxed executor; the executor's own filesystem restrictions still apply.
    swift test --package-path "${manifest}" --scratch-path "${scratch}" \
        --cache-path "${TEST_DIR}/cache" --config-path "${TEST_DIR}/config" \
        --security-path "${TEST_DIR}/security" --manifest-cache local --disable-sandbox
}

run_suite "${PROJECT_DIR}/Packages/Aptabase" "${TEST_DIR}/sdk"
run_suite "${HARNESS_DIR}" "${TEST_DIR}/core"
