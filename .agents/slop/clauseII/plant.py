#!/usr/bin/env python3
"""Plant: drive `retention-check.py`'s clause II on synthetic generators and assert it REFUSES.

A clause that cannot go red is a comment. This drives the real `clause_ii` (imported by path, not
re-implemented) over four generators whose ONLY difference is the shape the clause measures, so the
verdict is attributable to the shape and to nothing else.
"""
import contextlib
import importlib.util
import io
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location("_rc", ROOT / "gates" / "retention-check.py")
rc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc)

TARGET = HERE / "plantdir"
TARGET.mkdir(exist_ok=True)

# (name, source-or-None, expected token, expected red)
CASES = [
    ("ok", "class G:\n"
           "    def run(self):\n"
           "        self.tmp.unlink()\n"
           "        try:\n"
           "            pass\n"
           "        finally:\n"
           "            self._settle(0)\n"
           "        return 0\n", "OK", 0),
    ("false", "class G:\n"
              "    def run(self):\n"
              "        self.tmp.unlink()\n"
              "        return 0\n", "FALSE", 1),
    ("unmeasured", "def run(out):\n"
                   "    return 0\n", "UNMEASURED", 1),   # differ's shape: no `class` at all
    ("missing", None, "MISSING", 1),
]

bad = 0
for name, source, token, want_red in CASES:
    gen = HERE / f"plant-{name}.py"
    gen.write_text(source) if source is not None else gen.unlink(missing_ok=True)
    o = rc.Output("graphcmp", str(TARGET.relative_to(ROOT)), str(gen.relative_to(ROOT)), {"*"}, None)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        red = rc.clause_ii([o])
    line = next((ln for ln in buf.getvalue().splitlines() if ln.startswith("II ")), "")
    ok = red == want_red and f"II {token}" in line
    bad += not ok
    print(f"[{'PASS' if ok else 'FAIL'}] {name:<11} red={red} want={want_red}  {line}")

print(f"\nPLANT: {'GREEN' if not bad else 'RED'}  ({len(CASES) - bad}/{len(CASES)} cases as expected)")
sys.exit(1 if bad else 0)
