#!/usr/bin/env python3
"""Keep the declared LIVE numbers live, by LOCATION PIN.

Each pin is `(file, line, regex-with-capture, counts.py key)`: the surface line
MUST still carry the value `counts.py` computes today.  If the line MOVED the
regex misses -> FAIL (moved); if it still holds an old value -> FAIL (stale).
Dated readings elsewhere in the file are untouched: this asserts only the pins.

This is the `checks/disagree-gate.py` `(path, must_contain, why)` shape
`citeresolve` recommended, with the number optional.

Verdicts (gates/gatekit.py:59): PASS=0 FAIL=1 REFUSED=3 SKIP=4 DEAD=5.
REFUSED when counts.py cannot run.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

# (file, line, regex whose group(1) is the asserted value, counts.py claim key)
PIN = [
    ("AGENTS.md", 96, r"len\(differ\.declared\(\)\)`?\s*=\s*\*\*([0-9]+)\*\*", "differ.declared()"),
    ("AGENTS.md", 131, r"measured[^:]*:\s*([0-9]+)\s*`?\.py`?", "gates/*.py"),
    ("AGENTS.md", 140, r"\*\*([0-9]+)\s+are present", "TOOLS.md present"),
    ("AGENTS.md", 141, r"\*\*([0-9]+)\s+are gone", "TOOLS.md gone"),
    ("AGENTS.md", 141, r"\*\*([0-9]+)\s+of those under", "TOOLS.md gone under slop"),
    (".agents/TODO.md", 11, r"([0-9]+) unexcused remain", "no-txt HARD"),
]


def values() -> dict[str, str] | None:
    cp = subprocess.run([os.path.join(ROOT, ".venv/bin/python"), ".agents/slop/citeresolve/counts.py"],
                        cwd=ROOT, capture_output=True, text=True)
    if cp.returncode != 0:
        return None
    out = {}
    for ln in cp.stdout.splitlines()[1:]:
        f = ln.split("\t")
        if len(f) == 3:
            m = re.match(r"(\d+)", f[2])
            out[f[0]] = m.group(1) if m else f[2]
    return out


def main() -> int:
    vals = values()
    if vals is None:
        print("REFUSED: counts.py could not run", file=sys.stderr)
        return 3
    cache: dict[str, list[str]] = {}
    fails = 0
    for rel, ln, rx, key in PIN:
        want = vals.get(key)
        if want is None:
            print(f"REFUSED: no rule in counts.py for {key!r}", file=sys.stderr)
            return 3
        if rel not in cache:
            cache[rel] = open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace").read().splitlines()
        lines = cache[rel]
        if not (1 <= ln <= len(lines)):
            print(f"FAIL {rel}:{ln} {key}: file shrank; pin out of range", file=sys.stderr)
            fails += 1
            continue
        m = re.search(rx, lines[ln - 1])
        if not m:
            print(f"FAIL {rel}:{ln} {key}: pin no longer matches (line moved?)", file=sys.stderr)
            fails += 1
        elif m.group(1) != want:
            print(f"FAIL {rel}:{ln} {key}: asserts {m.group(1)}, counts.py says {want}", file=sys.stderr)
            fails += 1
    print(f"# pins={len(PIN)} fails={fails}", file=sys.stderr)
    print("PASS" if fails == 0 else "FAIL", file=sys.stderr)
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
