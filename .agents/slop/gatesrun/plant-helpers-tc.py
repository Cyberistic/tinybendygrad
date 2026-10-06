#!/usr/bin/env python3
"""PLANTS for `helpers-tc-gate.sh` / `helpers-oracle.py`. NO bend run: the port's evidence is
the committed `.bd`, and every plant drives the gate's OWN diff (`:64`) against it.

The change under test is the oracle's `_d` column, fixed to emit CPython's true `str` for
`d_i64min` instead of substituting the port's answer. Three directions:

  GREEN    fixed `.rows`          vs  `.bd`            -> diff rc=0  (the change works)
  PLANT-A  PRE-CHANGE oracle      vs  `.bd`            -> diff rc=1  (the pre-change file FAILS)
  PLANT-B  fixed `.rows`          vs  a BROKEN `.bd`   -> diff rc=1  (a wrong port FAILS)

`diff` is invoked exactly as `helpers-tc-gate.sh:64` invokes it and the verdict is its
return code, never a `wc -l` echo after it.
"""
from __future__ import annotations
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SLOP = ROOT / ".agents" / "slop"
GT = SLOP / "helpers-tc-gate"
ENV = {"DEFAULT_FLOAT": "f16", "DEFAULT_INT": "i64", "NO_COLOR": "1"}
OK = []


def diff(a: Path, b: Path) -> int:
    return subprocess.run(["diff", str(a), str(b)], capture_output=True).returncode


def plant(name, a, b, want):
    got = diff(a, b)
    good = got == want
    OK.append(good)
    print(f"  {'PASS' if good else 'FAIL'}  {name}: diff rc={got} (want {want})")


def main():
    bd = GT.with_suffix(".bd")
    rows = GT.with_suffix(".rows")
    print(f"subjects: {rows.name} {rows.stat().st_size}B, {bd.name} {bd.stat().st_size}B")

    # GREEN -- the fixed oracle's own output, the state the gate now reaches
    plant("GREEN   fixed .rows vs .bd", rows, bd, 0)

    # PLANT A -- the PRE-CHANGE oracle, read out of git (this unit's edit is uncommitted,
    # so HEAD still holds it), run under the gate's env, diffed against the SAME `.bd`.
    pre = subprocess.run(["git", "show", "HEAD:.agents/slop/helpers-oracle.py"],
                         cwd=ROOT, capture_output=True, text=True)
    if pre.returncode != 0:
        print("  FAIL  PLANT A: cannot read the pre-change oracle from git:", pre.stderr)
        OK.append(False)
    else:
        import os
        with tempfile.TemporaryDirectory() as td:
            po = Path(td) / "pre-oracle.py"
            po.write_text(pre.stdout)
            env = {**os.environ, **ENV}
            r = subprocess.run([str(ROOT / ".venv/bin/python"), str(po)],
                               cwd=ROOT, capture_output=True, text=True, env=env)
            pre_rows = Path(td) / "pre.rows"
            pre_rows.write_text(r.stdout)
            print(f"        pre-change oracle rc={r.returncode}, {len(r.stdout.splitlines())} rows")
            plant("PLANT-A pre-change oracle vs .bd", pre_rows, bd, 1)

    # PLANT B -- a BROKEN port lane: one value moved in a copy of `.bd`. The gate must move.
    with tempfile.TemporaryDirectory() as td:
        bad = Path(td) / "broken.bd"
        body = bd.read_text().splitlines()
        body[236] = "d_i64min_d=-9223372036854775807"   # off by one
        bad.write_text("\n".join(body) + "\n")
        plant("PLANT-B broken .bd vs fixed .rows", rows, bad, 1)

    print(f"PLANTS {'GREEN' if all(OK) else 'RED'} ({sum(OK)}/{len(OK)})")
    return 0 if all(OK) else 1


if __name__ == "__main__":
    sys.exit(main())
