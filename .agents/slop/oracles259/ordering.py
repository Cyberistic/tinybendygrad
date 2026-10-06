#!/usr/bin/env python3
"""The ORDERING CONSTRAINT, measured rather than argued.

Claim: renaming `oracles/X.txt` to `oracles/X.rows` DESTROYS the evidence that `X` was a broken
gate input, because the stale-rooted read is found by joining on the BASENAME the reader wrote --
and a rename changes the basename. The rename does not fix the gate and does not report it either.
It launders a broken read into a file that looks unreferenced.

This is the only ordering constraint that actually binds these 259, and it is NOT the pin rule:
MEASURED, zero pins in the tree reference any `oracles/` path (the sha256 pin files name only
`runs/graphcmp/D/*`), so a rename here cannot retire a pin. The hazard is the opposite one -- the
rename retires the FINDING.

usage: .venv/bin/python .agents/slop/oracles259/ordering.py
"""
import importlib.util
import os
import pathlib
import shutil
import sys

ROOT = pathlib.Path(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__))))))
spec = importlib.util.spec_from_file_location("census", ROOT / "checks/oracle-txt-census.py")
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)


def counts():
    rows, _ = C.census()
    return (len(rows), sum(1 for r in rows if r["stale"]), sum(1 for r in rows if r["live"]))


def main():
    a = counts()
    print(f"  BEFORE   files={a[0]}  stale={a[1]}  live={a[2]}")

    # Rename the four files of the ONE gate whose reads are all stale, in the group's own extension.
    pairs = [(ROOT / "oracles/BEFORE-rows.txt", ROOT / "oracles/BEFORE-rows.rows"),
             (ROOT / "oracles/schedule-bodies/BEFORE-rows.txt",
              ROOT / "oracles/schedule-bodies/BEFORE-rows.rows"),
             (ROOT / "oracles/sb-oracle.txt", ROOT / "oracles/sb-oracle.rows"),
             (ROOT / "oracles/schedule-bodies/sb-oracle.txt",
              ROOT / "oracles/schedule-bodies/sb-oracle.rows")]
    try:
        for src, dst in pairs:
            shutil.move(src, dst)
        b = counts()
        print(f"  RENAMED  files={b[0]}  stale={b[1]}  live={b[2]}")
        print(f"\n  stale rows LOST to the rename: {a[1] - b[1]}   "
              f"files removed from the census: {a[0] - b[0]}")
        print("  The gate is NOT fixed by this -- `checks/sb-gate.sh` still opens")
        print("  `.agents/slop/schedule-bodies/BEFORE-rows.txt`, which is still absent. The rename")
        print("  only stopped the census from being able to NAME the file the gate is missing.")
    finally:
        for src, dst in pairs:
            if dst.exists():
                shutil.move(dst, src)

    c = counts()
    ok = c == a
    print(f"\n  {'RESTORED' if ok else 'RESTORE FAILED'}: files={c[0]} stale={c[1]} live={c[2]}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
