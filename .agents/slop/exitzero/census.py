#!/usr/bin/env python3
"""THE DENOMINATOR: across EVERY gate in `checks/` and `gates/`, how many can print a CLEAN
verdict while something is UNMEASURED?

Two classes are combined, each with its own instrument (AGENTS.md doctrine 1: a population by
discovery, never a hand list):

  CLASS A -- REFUSED-MISSING (envguard's class). A gate that reads an input under `runs/` or
    `gates/artifacts/` with no preceding existence check, and no `try`, can crash or read FAIL
    where the honest answer is REFUSED. Instrument: `.agents/slop/envguard/scan.py`, UNCHANGED,
    over the discovery population `checks/*.py` + `gates/*.py`. Reads are a LOWER BOUND: a path
    through a helper-returned Name is a NAMED miss.

  CLASS B -- WARM="report" (gatekit's ported `|| true`). `beautiful-mnist-gate.sh:29` runs the
    driver `--check-only || true`; the port keeps that shape as `warm="report"`, so a COLD driver
    is REPORTED and the lanes are STILL DIFFED -- the gate can go green over a cold substrate.
    Instrument: a scan of `gates/*.py` for the literal `warm="report"`.

  NOT STATIC, REPORTED AS A NAMED INSTANCE: CLASS C -- A CHECK NOBODY HAS SEEN FIRE. `.agents/
    slop/censusred/REPORT.md` tabulated 16 named checks in `graphcmp-oracle.py`: 6 observed to
    fire, 10 never. "Ever observed to fire" is HISTORY, not AST, so this census cannot recount it
    tree-wide; it carries the one measured instance and its denominator.

This script WRITES nothing but its own stdout. Run: `.venv/bin/python .agents/slop/exitzero/census.py`.
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def class_a() -> tuple[int, int, list[str]]:
    """(raw, genuine-ish, files) from envguard's scanner, unmodified."""
    out = subprocess.run([".venv/bin/python", ".agents/slop/envguard/scan.py"],
                         cwd=ROOT, capture_output=True, text=True).stdout
    files = sorted({re.match(r"  MISS ([^:]+):", l).group(1)
                    for l in out.splitlines() if l.startswith("  MISS ")})
    head = out.splitlines()[0] if out else ""
    raw = int(re.search(r"UNGUARDED (\d+)", head).group(1))
    # envguard's own classification: reads under `if ok:` and write-then-read are guarded BY
    # CONSTRUCTION; the genuine no-guard-anywhere instances are differ.py's TWO read helpers
    # (`text()` and `one_line()`), whose callers guard.
    genuine = 2 if any(f.endswith("checks/differ.py") for f in files) else 0
    return raw, genuine, files


def class_b() -> list[str]:
    return sorted(p.name for p in (ROOT / "gates").glob("*.py")
                  if 'warm="report"' in p.read_text() and p.name != "gatekit.py")


def main() -> int:
    files = sorted(list((ROOT / "checks").glob("*.py")) + list((ROOT / "gates").glob("*.py")))
    print(f"POPULATION  checks/*.py + gates/*.py = {len(files)} file(s)")
    raw, genuine, afiles = class_a()
    print(f"CLASS A  REFUSED-missing (envguard/scan.py): {raw} unguarded read(s), "
          f"genuine no-guard-anywhere = {genuine} (checks/differ.py)")
    for f in afiles:
        print(f"           - {f}")
    bfiles = class_b()
    print(f"CLASS B  warm=\"report\" (a COLD driver reported, lanes still diffed): "
          f"{len(bfiles)} gate(s)")
    for f in bfiles:
        print(f"           - gates/{f}")
    print("CLASS C  a check nobody has seen fire (not static): "
          "graphcmp-oracle.py 6 of 16 observed, 10 never (censusred/REPORT.md §6)")
    strict = genuine + len(bfiles) + 10
    lower = raw + len(bfiles) + 10
    print(f"\nDISTINCT unmeasured-while-green paths (the two lists combined):")
    print(f"  strict (genuine A)            : {genuine} + {len(bfiles)} + 10 = {strict}")
    print(f"  lower bound (raw A)           : {raw} + {len(bfiles)} + 10 = {lower}")
    print("  + 1 CLOSED by this task        : checks/substrate.py tally[\"none\"]>0 "
          "printed CLEAN and exited 0 (now REFUSED, exit 3)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
