#!/usr/bin/env python3
"""Measure the BLIND SPOT of `substrate.discover()`'s suffix filter, on a scratch copy.

THE QUESTION: `discover()` walks by `os.walk` but keeps only `endswith(POP_SUFFIXES)`. What does
that filter COST when a non-source stray is present in the population?

THE METHOD: a scratch copy of the live `tinybendygrad/` with the four historical
`ops.staged-blob-*` strays restored from git. Then count, for each rule:
  OLD (suffix filter)  vs  NEW (every file under the root).
No `bend` is invoked; `discover()` is a pure walk and this script re-derives BOTH rules locally so
it can be run before and after the edit.

Writes `.agents/slop/substratepop/discover.rows` (names, one per line, prefixed by rule+tree).
"""
from __future__ import annotations

import importlib.util
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
POP_SUFFIXES = (".bend", ".c", ".js", ".mjs")
LIVE = REPO / "tinybendygrad"
HERE = Path(__file__).resolve().parent
SCRATCH = HERE / "tree" / "tinybendygrad"
STAGED = {
    "tinybendygrad/uop/ops.staged-blob-64022": "07cb5a85a",
    "tinybendygrad/uop/ops.staged-blob-97648": "07cb5a85a",
    "tinybendygrad/uop/ops.staged-blob-36145": "07cb5a85a",
    "tinybendygrad/uop/ops.staged-blob-66397": "07cb5a85a",
}


def old_rule(root: Path) -> list[str]:
    """THE RULE AS WRITTEN BEFORE THE FIX: suffix filter at discovery time."""
    out: list[str] = []
    for d, dirs, fs in os.walk(root):
        dirs.sort()
        out += [os.path.join(d, f) for f in sorted(fs) if f.endswith(POP_SUFFIXES)]
    return out


def module_discover(root: Path) -> list[str]:
    """THE RULE AS LOADED FROM `checks/substrate.py` -- so the measurement exercises the REAL
    code, not a copy of it. Import is side-effect-free here: the ORACLE_PIN check, `os.chdir` and
    the runs live behind `main()`/`run()`."""
    spec = importlib.util.spec_from_file_location(
        "substrate_probe", REPO / "checks" / "substrate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.discover(str(root))


def stage() -> None:
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    SCRATCH.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(LIVE, SCRATCH)
    # A scratch copy needs the empties too, and `copytree` has them.
    for rel, rev in STAGED.items():
        blob = subprocess.run(["git", "show", f"{rev}:{rel}"], cwd=REPO,
                              capture_output=True, check=True).stdout
        dest = SCRATCH / rel[len("tinybendygrad/"):]
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(blob)


def report(label: str, root: Path, rows: list[str]) -> tuple[int, int]:
    old = old_rule(root)
    new = module_discover(root)
    staged_here = [p for p in new if "staged" in p]
    print(f"{label}:  files={len(new)}  old_rule={len(old)}  delta={len(new) - len(old)}")
    for p in sorted(staged_here):
        print(f"    SEEN only by new rule: {os.path.relpath(p, root)}")
    rows.append(f"# {label} root={root} new={len(new)} old={len(old)} "
                f"delta={len(new) - len(old)}")
    for p in sorted(set(new) - set(old)):
        rows.append(f"NEW-ONLY\t{os.path.relpath(p, root)}")
    for p in sorted(set(old) - set(new)):
        rows.append(f"OLD-ONLY\t{os.path.relpath(p, root)}")
    return len(new), len(old)


def main() -> int:
    if os.environ.get("SUBSTRATEPOP_SKIP_STAGE") != "1":
        stage()
    rows: list[str] = []
    print("=== LIVE tree (no strays: the filter has nothing to hide) ===")
    report("live", LIVE, rows)
    print("\n=== SCRATCH tree (four ops.staged-blob-* restored from git) ===")
    report("scratch", SCRATCH, rows)
    (HERE / "discover.rows").write_text("\n".join(rows) + "\n")
    print(f"\nwrote {HERE / 'discover.rows'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
