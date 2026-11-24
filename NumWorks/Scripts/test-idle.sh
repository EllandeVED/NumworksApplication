#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEST_DIR="${PROJECT_DIR}/build/idle-optimization-20261123/tests"
HARNESS="${TEST_DIR}/harness"
mkdir -p "${HARNESS}/Sources/NumWorks" "${HARNESS}/Tests/NumWorksTests"

xcrun clang++ -std=c++20 -fobjc-arc -framework AppKit -framework Carbon \
    -I"${PROJECT_DIR}/NumWorks/Integration" \
    "${PROJECT_DIR}/NumWorks/Integration/EpsilonBridge.mm" \
    "${SCRIPT_DIR}/Tests/NativeEventWaitTests.mm" \
    -o "${TEST_DIR}/native-event-wait-tests"
"${TEST_DIR}/native-event-wait-tests"

VENDOR="${PROJECT_DIR}/NumWorks/Vendor/EpsilonSource"
CPP_FLAGS=(-std=c++20 -DION_VARIANT_EPSILON=1 -DION_KEYBOARD_HAS_ALPHA=1
    -DION_KEYBOARD_ROWS=9 -DION_KEYBOARD_COLUMNS=6 -DION_EVENTS_JOURNAL=1
    -DION_SIMULATOR_FILES=0 -DION_SIMULATOR_PERFECT_WIDTH=458 -DION_SIMULATOR_PERFECT_HEIGHT=900
    -I"${PROJECT_DIR}/NumWorks/Integration" -I"${VENDOR}/shared"
    -I"${VENDOR}/shared/ion/include" -I"${VENDOR}/shared/omg/include"
    -I"${VENDOR}/shared/kandinsky/include"
    -I"${VENDOR}/epsilon/output/release/macos/shared"
    -I"${VENDOR}/shared/ion/include/ion/keyboard/epsilon"
    -I"${VENDOR}/shared/ion/src/simulator/external/sdl/include")
INPUT_OBJECTS=()
for source in events events_platform keyboard; do
    object="${TEST_DIR}/${source}.o"
    xcrun clang++ "${CPP_FLAGS[@]}" -c \
        "${VENDOR}/shared/ion/src/simulator/shared/${source}.cpp" -o "${object}"
    INPUT_OBJECTS+=("${object}")
done
xcrun clang++ "${CPP_FLAGS[@]}" -fobjc-arc -Wl,-dead_strip \
    "${PROJECT_DIR}/NumWorks/Integration/EpsilonBridge.mm" \
    "${SCRIPT_DIR}/Tests/EventPipelineTests.mm" "${INPUT_OBJECTS[@]}" \
    "${VENDOR}/epsilon/output/release/macos/arm64/libepsilon.a" \
    -framework AppKit -framework Carbon -framework CoreAudio -framework CoreVideo \
    -framework IOKit -framework ForceFeedback -framework AudioToolbox \
    -framework Metal -framework QuartzCore -o "${TEST_DIR}/event-pipeline-tests"
"${TEST_DIR}/event-pipeline-tests"

cp "${PROJECT_DIR}/NumWorks/Settings/UpdateCheckAge.swift" "${HARNESS}/Sources/NumWorks/"
cp "${PROJECT_DIR}/NumWorksTests/IdleBehaviorTests.swift" "${HARNESS}/Tests/NumWorksTests/"
cat > "${HARNESS}/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "IdleBehaviorTests", targets: [
    .target(name: "NumWorks"),
    .testTarget(name: "NumWorksTests", dependencies: ["NumWorks"])
])
SWIFT
export CLANG_MODULE_CACHE_PATH="${TEST_DIR}/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${CLANG_MODULE_CACHE_PATH}"
swift test --package-path "${HARNESS}" --scratch-path "${TEST_DIR}/swift" \
    --cache-path "${TEST_DIR}/cache" --config-path "${TEST_DIR}/config" \
    --security-path "${TEST_DIR}/security" --manifest-cache local --disable-sandbox
