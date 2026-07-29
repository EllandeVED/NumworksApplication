# Agent prompt: fix NumWorks ↔ Epsilon integration after a failed CI compile
#
# Paste this whole file into Cursor (or another coding agent) in the NumWorks
# repo when `.github/workflows/epsilon-watch.yml` reports a failure.
#
# Replace placeholders:
#   {{EPSILON_REF}}   — failing Epsilon tag/commit
#   {{LOG_EXCERPT}}   — tail of the CI build log

You are fixing the NumWorks macOS app’s Epsilon simulator integration.

## Goal
Make Epsilon `{{EPSILON_REF}}` prepare + compile as `libepsilon.a` and link into the NumWorks app again.

## How this project integrates Epsilon (do not reinvent)
1. `NumWorks/Scripts/prepare-epsilon.sh <ref>`
   - fetches `numworks/epsilon` into `NumWorks/Vendor/EpsilonSource` (gitignored)
   - runs `NumWorks/Scripts/adapt-epsilon.py` (NOT brittle `.patch` files)
2. `NumWorks/Scripts/build-epsilon-lib.sh`
   - `make PLATFORM=simulator TARGET=macos … libepsilon.a`
   - writes `NumWorks/Vendor/EpsilonSource/output/libepsilon.a`
3. Xcode target `EpsilonLib` invokes that script; the app links the `.a`

Old line-exact patches in `NumWorks/Patches/legacy/` are historical only. Prefer fixing **`adapt-epsilon.py`** so future Epsilon versions keep working.

## What adapt-epsilon.py must guarantee
- `ion/src/simulator/**/window.mm` (macOS):
  - `#import "EpsilonBridge.h"`
  - in `didInit(SDL_Window *)`: after the `NSWindow *` assignment, call
    `[EpsilonBridge registerCalculatorWindow:…]` and `setAlphaValue:0.0`
  - soften / clear `setFrameAutosaveName` and prefer `setRestorable:NO`
  - `willShutdown` unregisters the bridge
- `ion/src/simulator/shared/events.cpp`:
  - include `NumWorksSimulatorActive.h`
  - in `waitForInterruptingEvent`, use a long poll delay (~500 ms) when
    `!NumWorksSimulatorIsActive()`, else ~10 ms
- `ion/src/simulator/shared/window.cpp`:
  - include `NumWorksSimulatorActive.h`
  - in `refresh()`, return early (keep dirty flag) when inactive — no present
- `build/targets.simulator.macos.mak` (or similar):
  - marked block `# >>> NUMWORKS_INTEGRATION` … `# <<< NUMWORKS_INTEGRATION`
  - with `NUMWORKS_INTEGRATION_DIR`, `-Dmain=epsilon_main` on simulator `main.cpp`,
    and a `libepsilon.a` libtool rule over `$(epsilon_src)`

Headers live in `NumWorks/Integration/` (passed via `NUMWORKS_INTEGRATION_DIR`),
including `EpsilonBridge.h` and `NumWorksSimulatorActive.h`.

## Reproduce locally
```bash
cd <repo-root>
./NumWorks/Scripts/prepare-epsilon.sh {{EPSILON_REF}}
ARCHS="$(uname -m)" ./NumWorks/Scripts/build-epsilon-lib.sh
# Optional full app:
xcodebuild -project NumWorks.xcodeproj -scheme NumWorks -configuration Debug build
```

## CI failure excerpt
```
{{LOG_EXCERPT}}
```

## Required outcome
1. Identify the root cause from the log (adapt miss vs makefile vs compile error).
2. Patch `adapt-epsilon.py` and/or minimal NumWorks glue — avoid one-off edits only inside `Vendor/EpsilonSource` (that tree is regenerated).
3. Re-run prepare + `build-epsilon-lib.sh` until it succeeds.
4. Summarize what broke in upstream Epsilon and how the adapter was generalized.
5. If a full app link fails after libepsilon succeeds, fix the Xcode/link side next.

Do not change Sparkle release machinery unless the failure is clearly unrelated to Epsilon.
