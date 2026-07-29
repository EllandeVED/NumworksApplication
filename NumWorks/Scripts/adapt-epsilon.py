#!/usr/bin/env python3
"""
Adapt a checked-out Epsilon tree for NumWorks integration.

Unlike line-exact .patch files, this script looks for stable structural
markers (function names, makefile variables) and injects small hooks so
minor upstream churn still works.

Idempotent: safe to run repeatedly on the same tree.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

MARKER_BEGIN = "# >>> NUMWORKS_INTEGRATION"
MARKER_END = "# <<< NUMWORKS_INTEGRATION"

BRIDGE_IMPORT = '#import "EpsilonBridge.h"'


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def info(msg: str) -> None:
    print(f"adapt-epsilon: {msg}")


def find_macos_window_mm(root: Path) -> Path:
    candidates = [
        root / "ion/src/simulator/macos/window.mm",
        root / "ion/src/simulator/mac/window.mm",
    ]
    for path in candidates:
        if path.is_file():
            return path
    sim = root / "ion/src/simulator"
    found = list(sim.rglob("window.mm")) if sim.is_dir() else []
    macosish = [p for p in found if "mac" in str(p).lower()]
    if macosish:
        return macosish[0]
    if found:
        return found[0]
    die("could not find ion/src/simulator/**/window.mm")


def ensure_bridge_import(text: str) -> str:
    if "EpsilonBridge.h" in text:
        return text
    if "#import <Cocoa/Cocoa.h>" in text:
        return text.replace(
            "#import <Cocoa/Cocoa.h>",
            "#import <Cocoa/Cocoa.h>\n" + BRIDGE_IMPORT,
            1,
        )
    matches = list(re.finditer(r"^#\s*(import|include)\b.*$", text, flags=re.M))
    if not matches:
        die("window.mm has no #import/#include to anchor EpsilonBridge.h")
    last = matches[-1]
    insert_at = last.end()
    return text[:insert_at] + "\n" + BRIDGE_IMPORT + text[insert_at:]


def extract_function_body(text: str, signature_re: str) -> tuple[int, int, int, re.Match[str]] | None:
    """Return (sig_start, body_start, body_end_inclusive_brace, match) or None."""
    pattern = re.compile(signature_re, re.S)
    m = pattern.search(text)
    if not m:
        return None
    sig_start = m.start()
    body_start = m.end()
    depth = 1
    i = body_start
    while i < len(text) and depth:
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        i += 1
    # i points past the closing brace
    return sig_start, body_start, i - 1, m


def adapt_did_init_body(body: str) -> str:
    if "EpsilonBridge registerCalculatorWindow" in body:
        # Still soften autosave on re-run.
        pass
    else:
        assign = re.search(
            r"NSWindow\s*\*\s*(\w+)\s*=\s*[^;]+;",
            body,
        )
        if not assign:
            die("didInit has no NSWindow * assignment to hook")
        var = assign.group(1)
        snippet = (
            f"\n  // NumWorks: observe the SDL NSWindow."
            f"\n  [EpsilonBridge registerCalculatorWindow:{var}];"
            f"\n  [{var} setAlphaValue:0.0];"
        )
        insert_at = assign.end()
        body = body[:insert_at] + snippet + body[insert_at:]

    # Soften any frame autosave name; NumWorks owns placement.
    body = re.sub(
        r"\[(\w+)\s+setFrameAutosaveName\s*:\s*@\"[^\"]*\"\s*\]",
        r'[\1 setFrameAutosaveName:@""]',
        body,
    )

    autosave = re.search(
        r"\[(\w+)\s+setFrameAutosaveName\s*:\s*@\"\"\s*\];",
        body,
    )
    if autosave and "setRestorable" not in body:
        var = autosave.group(1)
        body = (
            body[: autosave.end()]
            + f"\n  [{var} setRestorable:NO];"
            + body[autosave.end() :]
        )

    return body


def rewrite_did_init(text: str) -> str:
    found = extract_function_body(
        text,
        r"void\s+didInit\s*\(\s*SDL_Window\s*\*?\s*\w*\s*\)\s*\{",
    )
    if not found:
        die("could not find void didInit(SDL_Window …) in window.mm")
    _, body_start, body_end, _ = found
    body = text[body_start:body_end]
    new_body = adapt_did_init_body(body)
    return text[:body_start] + new_body + text[body_end:]


def rewrite_will_shutdown(text: str) -> str:
    found = extract_function_body(
        text,
        r"void\s+willShutdown\s*\(\s*SDL_Window\s*\*?\s*(\w*)\s*\)\s*\{",
    )
    if not found:
        die("could not find void willShutdown(SDL_Window …) in window.mm")
    sig_start, body_start, body_end, match = found
    param = match.group(1) or "window"
    # Keep the original signature text through '{'
    sig = text[sig_start:body_start]
    # Normalize signature to always name the parameter.
    sig = re.sub(
        r"void\s+willShutdown\s*\(\s*SDL_Window\s*\*?\s*\w*\s*\)\s*\{",
        f"void willShutdown(SDL_Window * {param}) {{",
        sig,
        count=1,
    )
    new_body = f"""
  // NumWorks: release the bridge when the simulator tears the window down.
  if ({param} != nullptr) {{
    NSWindow * nswindow = reinterpret_cast<SDL_WindowData *>({param}->driverdata)->nswindow;
    [EpsilonBridge unregisterCalculatorWindow:nswindow];
  }}
"""
    return text[:sig_start] + sig + new_body + text[body_end:]


def adapt_window_mm(root: Path) -> None:
    path = find_macos_window_mm(root)
    info(f"adapting {path.relative_to(root)}")
    original = path.read_text()
    text = ensure_bridge_import(original)
    text = rewrite_did_init(text)
    text = rewrite_will_shutdown(text)
    if text != original:
        path.write_text(text)
        info("window.mm updated")
    else:
        info("window.mm already adapted")


def find_macos_simulator_mak(root: Path) -> Path:
    candidates = [
        root / "build/targets.simulator.macos.mak",
        root / "build/targets.simulator.mac.mak",
    ]
    for path in candidates:
        if path.is_file():
            return path
    build = root / "build"
    found = list(build.glob("targets.simulator*mac*.mak")) if build.is_dir() else []
    if found:
        return found[0]
    die("could not find build/targets.simulator.macos.mak (or similar)")


def find_simulator_main_cpp(root: Path) -> list[str]:
    sim = root / "ion/src/simulator"
    if not sim.is_dir():
        return ["ion/src/simulator/shared/main.cpp"]
    mains = sorted(
        str(p.relative_to(root))
        for p in sim.rglob("main.cpp")
        if "external" not in p.parts
    )
    return mains or ["ion/src/simulator/shared/main.cpp"]


def makefile_fragment(main_paths: list[str]) -> str:
    main_rules = "\n".join(
        f"$(call object_for,{path}): SFLAGS += -Dmain=epsilon_main"
        for path in main_paths
    )
    return f"""{MARKER_BEGIN}
# NumWorks macOS shell integration (generated by adapt-epsilon.py).
# Builds the simulator as libepsilon.a; the shell calls epsilon_main().
ifdef NUMWORKS_INTEGRATION_DIR
SFLAGS += -I$(NUMWORKS_INTEGRATION_DIR)
{main_rules}

.PHONY: libepsilon.a
libepsilon.a: $(BUILD_DIR)/libepsilon.a

$(BUILD_DIR)/libepsilon.a: $(call flavored_object_for,$(epsilon_src),)
	$(call rule_label,LIBTOOL)
	$(Q) rm -f $@
	$(Q) xcrun libtool -static -no_warning_for_no_symbols -o $@ $^
endif
{MARKER_END}
"""


def upsert_makefile_block(text: str, block: str) -> str:
    if MARKER_BEGIN in text and MARKER_END in text:
        return re.sub(
            re.escape(MARKER_BEGIN) + r".*?" + re.escape(MARKER_END),
            block.strip(),
            text,
            count=1,
            flags=re.S,
        )
    # Drop older hand-patched block without markers (best effort).
    text = re.sub(
        r"\n# NumWorks macOS shell integration\..*?^endif\s*\n",
        "\n",
        text,
        count=1,
        flags=re.S | re.M,
    )
    if not text.endswith("\n"):
        text += "\n"
    return text + "\n" + block


def adapt_makefile(root: Path) -> None:
    path = find_macos_simulator_mak(root)
    info(f"adapting {path.relative_to(root)}")
    mains = find_simulator_main_cpp(root)
    info("main.cpp candidates: " + ", ".join(mains))
    original = path.read_text()
    text = upsert_makefile_block(original, makefile_fragment(mains))
    if text != original:
        path.write_text(text)
        info("makefile updated")
    else:
        info("makefile already adapted")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "epsilon_root",
        nargs="?",
        default=None,
        help="Path to Epsilon checkout (default: ../Vendor/EpsilonSource)",
    )
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    default_root = script_dir.parent / "Vendor" / "EpsilonSource"
    root = Path(args.epsilon_root) if args.epsilon_root else default_root
    root = root.resolve()

    if not root.is_dir():
        die(f"Epsilon root not found: {root}")
    if not (root / "ion").is_dir():
        die(f"does not look like an Epsilon tree (no ion/): {root}")

    adapt_window_mm(root)
    adapt_makefile(root)
    info("done")


if __name__ == "__main__":
    main()
