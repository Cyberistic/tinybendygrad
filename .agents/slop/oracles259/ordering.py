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

THE RENAME IS NOW EXECUTED. 258 of the 259 `oracles/**/*.txt` became their class's extension (see
`.agents/slop/txtexec/REPORT.md`); this script's own four rename pairs were among them. It was the
ONE LIVE reader the census names, so its four `.txt` tokens were repointed to the new `.rows` names:
a reader left naming a moved file is the failure the repoint exists for. It now asserts the four
resolve, instead of moving files that are already named correctly.

usage: .venv/bin/python .agents/slop/oracles259/ordering.py
"""
import importlib.util
import os
import pathlib
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
    # The four files whose read was LIVE, now named at their POST-RENAME paths. Renaming the
    # sources -- which this script used to perform -- has already happened, so the pairs are no
    # longer (src, dst) and the move loop is gone. Naming an old `.txt` here would be exactly the
    # dangling reference the repoint exists to prevent.
    renamed = [ROOT / "oracles/BEFORE-rows.rows",
               ROOT / "oracles/schedule-bodies/BEFORE-rows.rows",
               ROOT / "oracles/sb-oracle.rows",
               ROOT / "oracles/schedule-bodies/sb-oracle.rows"]
    missing = [str(p.relative_to(ROOT)) for p in renamed if not p.exists()]
    files, stale, live = counts()
    print(f"  reader targets that RESOLVE: {len(renamed) - len(missing)}/{len(renamed)}")
    for p in renamed:
        print(f"    {'OK ' if p.exists() else 'MISSING'}  {p.relative_to(ROOT)}")
    print(f"\n  census after the rename: files={files}  stale={stale}  live={live}")
    print("  The gate is NOT fixed by this -- `checks/sb-gate.sh` still opens")
    print("  `.agents/slop/schedule-bodies/BEFORE-rows.txt`, which is still absent.")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
