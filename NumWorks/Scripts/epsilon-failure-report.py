#!/usr/bin/env python3
"""Pull compiler errors out of CI logs for the GitHub issue and run annotations."""

import re
import sys
from pathlib import Path

ERROR = re.compile(
    r"fatal error:|undefined symbols|\*\* BUILD FAILED \*\*|make: \*\*\* \[|^error: |clang: error:",
    re.I,
)
CLANG = re.compile(r"^(\S+?):(\d+):(?:\d+:)?\s+(?:fatal )?error:\s+(.*)$")


def load(paths: list[Path]) -> str:
    parts = []
    for path in paths:
        if path.is_file() and path.stat().st_size:
            parts.append(path.read_text(errors="replace"))
    return "\n".join(parts)


def excerpt(text: str) -> str:
    lines = text.splitlines()
    hits = [i for i, line in enumerate(lines) if ERROR.search(line)]
    if not hits:
        return "\n".join(lines[-80:])
    start = max(0, hits[0] - 5)
    end = min(len(lines), hits[0] + 25)
    return "\n".join(lines[start:end])


def main() -> None:
    out = Path(sys.argv[1])
    text = load([Path(p) for p in sys.argv[2:]])
    body = excerpt(text).strip() or "(no log captured)"
    out.write_text(body + "\n")

    seen: set[tuple[str, str, str]] = set()
    for line in text.splitlines():
        m = CLANG.search(line.rstrip())
        if not m:
            continue
        key = (m.group(1), m.group(2), m.group(3))
        if key in seen:
            continue
        seen.add(key)
        print(f"::error file={m.group(1)},line={m.group(2)}::{m.group(3)}", file=sys.stderr)
        if len(seen) >= 10:
            break
    if not seen:
        for line in body.splitlines():
            if ERROR.search(line):
                print(f"::error::{line[:900]}", file=sys.stderr)
                break


if __name__ == "__main__":
    main()
