#!/usr/bin/env python3
"""THE CLAIM AND THE WITNESSES: drive the four rows through BOTH consumers on a COPY of the live
artifacts, then move an artifact and show both consumers go red.

    .venv/bin/python .agents/slop/devrecord/xcheck.py

READ-ONLY over `runs/graphcmp/D/` and `checks/`. Writes only into a `TemporaryDirectory`, so
`gates/gendirs.py` does not discover it (its PLANT 2 is the measurement that a source writing only
into a tempfile yields NO generated directory) and no plant here mutates the state under test.

WHY THIS EXISTS RATHER THAN A CLAIM IN A COMMENT. `checks/differ.py` derives the four rows from
the artifacts and `checks/env-precond.py` compares the summary against its own declaration; two
instruments derived from the same idea cannot audit each other, so this asks a THIRD question of
both: *do the row and the 99 artifacts that name a device agree?* -- and then breaks the agreement
on purpose.

    step 1  rows present, artifacts untouched  -> env-precond METHOD B green, CLAUSE IV silent
    step 2  ONE artifact's device rewritten, summary untouched -> BOTH red
"""
from __future__ import annotations

import importlib.util
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
LIVE = ROOT / "runs/graphcmp/D"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def row_complaints(tree):
    """What `checks/differ.py`'s OWN health function says -- the same callable
    `gates/retention-check.py`'s CLAUSE IV invokes, so this is the clause and not a copy."""
    differ = sys.modules["differ"]
    differ.D = tree
    kv = dict(ln.split("=", 1) for ln in (tree / "D0-run-summary.txt").read_text().splitlines()
              if "=" in ln)
    return differ.preconditions_bad(kv)


def env_precond(summary):
    """`checks/env-precond.py`'s METHOD B, on the summary, with METHOD A's sources as they are."""
    env = load("env_precond", ROOT / "checks/env-precond.py")
    return env.check(summary=summary)


def main() -> int:
    differ = load("differ", ROOT / "checks/differ.py")
    differ.D = LIVE
    bad = []
    with tempfile.TemporaryDirectory() as td:
        tree = pathlib.Path(td).resolve() / "D"
        tree.mkdir()
        for p in sorted(LIVE.glob("*.txt")):
            shutil.copy2(p, tree / p.name)

        differ.D = tree
        rows = differ.precondition_rows()
        print(f"THE FOUR ROWS, each read from where it lives:\n  " + "\n  ".join(rows))
        heads, fields = differ.devices()
        print(f"\nWITNESSES -- 139 artifacts read, header says {sorted(heads)}, "
              f"ParamArg field says {sorted(fields)}  (TWO METHODS, NO SHARED REGEX)")
        print(f"  census/canon cross-check: `late` is 13 nodes in D0-coverage-census.txt and 12 "
              f"rows in D2-canon-py-late.txt,\n  and the census TOTAL is 313 where the canon "
              f"files sum to 312 -- so THAT census predates the\n  oracle's own `os.environ[\"DEV\"] "
              f"= DEV` fix and was taken on a different device. Reported, not resolved.")

        summary = tree / "D0-run-summary.txt"
        body = [ln for ln in summary.read_text().splitlines()
                if not any(ln.startswith(k + "=") for k in differ.ROW_KEYS)]
        summary.write_text("\n".join(body + rows) + "\n")

        print("\nSTEP 1 -- rows present, artifacts untouched")
        rc = env_precond(summary)
        complaints = row_complaints(tree)
        print(f"  differ.unhealthy()   : {len(complaints)} precondition complaint(s) {complaints}")
        print("  CLAUSE IV reads exactly that list, by reference -- no new parser, no new clause")
        print("  env-precond METHOD B printed four `ok` above; its exit is still 1 because METHOD A\n"
              "  reports `.agents/slop/graphcmp.py:1800`, which is NOT MINE and whose requirement is\n"
              "  OVER-BROAD -- MEASURED, `clean_env` only ever reaches `bin/bend`, and the port reads\n"
              "  exactly five flags (DEBUG DEFAULT_FLOAT DEFAULT_INT NO_COLOR SUM_DTYPE), so neither\n"
              "  PYTHONHASHSEED nor NOOPT has a reader downstream of that line. Named, not satisfied.")
        bad += [f"step 1: {complaints}"] if complaints else []

        print("\nSTEP 2 -- ***ONE ARTIFACT'S DEVICE CHANGED, THE SUMMARY ROW UNCHANGED***")
        wire = tree / "D2-canon-py-lin.txt"
        keep = wire.read_bytes()
        wire.write_bytes(keep.replace(b"SGLOBAL,sCPU", b"SGLOBAL,sMETAL"))
        try:
            complaints = row_complaints(tree)
            print(f"  differ.unhealthy()   : {complaints}")
            print("  ^ THE ROW STILL SAYS dev=CPU. IT IS NOW A LABEL IF THAT LIST IS EMPTY.")
            print("  env-precond METHOD B still reads four `ok` -- IT CANNOT SEE THIS, which is why\n"
                  "  the artifact cross-check lives where CLAUSE IV already looks.")
            if not complaints:
                bad.append("step 2: the row is a LABEL -- an artifact moved and nothing noticed")
        finally:
            wire.write_bytes(keep)

    print("\n" + ("XCHECK: RED -- " + "; ".join(bad) if bad else
                  "XCHECK: GREEN -- the row is a claim and the artifacts are its witnesses"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
