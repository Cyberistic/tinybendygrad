#!/usr/bin/env python3
"""gapcensus-gate.py -- THE TABLE, RE-RUN ON DEMAND, AGAINST A COMMITTED BASELINE.

    .venv/bin/python gates/gapcensus-gate.py            # the table + the diff against pins
    .venv/bin/python gates/gapcensus-gate.py --rows     # rows only
    .venv/bin/python gates/gapcensus-gate.py --plant    # the census made to MOVE, and moved
    .venv/bin/python gates/gapcensus-gate.py --accept   # re-pin, deliberately and by name

NO `bend`. THE CENSUS READS SOURCE, IT DOES NOT RUN THE PORT, so there is no lane to time out
and no 1.4 GB process to collide with. That is also why it is cheap enough to be the thing a
reader re-runs rather than the thing they take on trust.

THE FIVE VERDICTS ARE `gatekit`'s AND NOT LOCAL CONSTANTS, because `gatekit.VERDICT` is the
one table in this tree that assigns meaning to an exit code and a second copy is a second
vocabulary -- the `checks/sb-gate.sh` defect `AGENTS.md` records.

WHAT THE PINS ARE, AND WHY THE TABLE CANNOT GO SILENTLY STALE. `gates/gapcensus-pins.rows`
is a COMMITTED baseline of every row. A run that moves any row is a `FAIL` and NAMES the row
and both values. `--accept` re-pins, and only `--accept` does -- so "the number changed" and
"somebody decided the number should change" are two different events, and neither is silent.
`--plant` then proves the detector works: it perturbs a SOURCE FILE IN A TEMP COPY of the
repo, re-runs, and requires the affected row to MOVE and the gate to go `FAIL`. A gate whose
plant does not move is a gate that measures nothing, which `AGENTS.md` calls `DEAD` and which
this file can therefore detect about itself.

`corpus.*` IS PINNED TOO, AND THAT IS THE POINT OF IT. `corpus.artefacts_OLDER_by` is a
duration that grows by one second per second, so it is EXCLUDED from the comparison and
reported instead: a row that cannot be pinned without failing is a row whose pin would rot
daily, and `AGENTS.md`'s rule about a second number nobody can check applies to pins too.
"""
from __future__ import annotations

import argparse


import shutil

import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import gapcensus  # noqa: E402
from gatekit import DEAD, FAIL, PASS, REFUSED, verdict_of  # noqa: E402

PINS = HERE / "gapcensus-pins.rows"

# A ROW WHOSE VALUE IS A DURATION, so a pin on it fails every second and a pin off it rots.
VOLATILE = ("corpus.artefacts_OLDER_by", "corpus.artifact_newest_mtime")


def read_pins() -> dict[str, str]:
    if not PINS.is_file():
        return {}
    return dict(l.split("=", 1) for l in PINS.read_text().splitlines() if "=" in l)


def compare(got: list[str]) -> tuple[int, list[str]]:
    """The rows that MOVED. `0` rows and no pins is not a pass -- see `main`."""
    pins, now = read_pins(), dict(l.split("=", 1) for l in got if "=" in l)
    moved = [f"{k}: pinned {pins.get(k, 'ABSENT')!r} -> now {now.get(k, 'ABSENT')!r}"
             for k in now if k not in VOLATILE and pins.get(k) != now[k]]
    dropped = [f"{k}: pinned {v!r} is GONE from the census" for k, v in pins.items() if k not in now]
    return (len(moved) + len(dropped)), moved + dropped


def plant() -> int:
    """ONE PLANT AND ONE DISARM, ON A SOURCE FILE, IN A TEMP COPY OF THE REPO. No `bend`, no
    live mutation, no other unit's tree touched.

    THE PLANT deletes `Ops.POW = auto()` from `tinygrad/uop/__init__.py` -- upstream's own
    enum. It MUST move `ops.upstream_declaration_order_members` and
    `ops.order_variant_block_equals_upstream_DECLARATION`, the second because the port's
    variant block still holds `POW` and the two lists are no longer equal.

    THE DISARM is `ops.cpython_members`, which must NOT move: the census's CPython SET comes
    from `.venv/bin/python gates/tn_minimum-oracle.py`, and that interpreter imports the
    INSTALLED tinygrad, not the temp copy. So the plant cannot move it and must not be
    credited with moving it. A plant that claimed three rows and only had two would be the
    `ri_add_*` shape `cstyle_render_census-gate.py` records.

    AND THIS FUNCTION IS WHAT FOUND A REAL DEFECT IN THIS GATE ON ITS FIRST RUN: `UP`/`PORT`
    were bound at import, so reassigning `ROOT` to the temp copy moved nothing, every row
    stayed put, and the plant reported FAILED -- a gate whose plant cannot make it fail.
    """
    with tempfile.TemporaryDirectory() as td:
        copy = Path(td) / "repo"
        copy.mkdir()
        for rel in ("tinygrad/uop/__init__.py", "tinybendygrad/uop/ops.bend",
                    "gates/tn_minimum-oracle.py"):
            (dst := copy / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / rel, dst)
        target = copy / "tinygrad" / "uop" / "__init__.py"
        before = target.read_text()
        # `POW = auto()` AND NOT `Ops.POW = auto()`. The first run of this plant used the
        # qualified spelling and matched line 106 -- a `GroupOp` MEMBERSHIP list -- instead of
        # the enum, so it edited a line the census never reads and every row stood still. A
        # plant that edits the wrong line is indistinguishable from a census that cannot see
        # the right one, which is why the disarm below is not optional.
        edited = before.replace("POW = auto()", "")
        if edited == before:
            print("FAILED: the plant matched nothing -- the pattern is stale", file=sys.stderr)
            return 1
        target.write_text(edited)

        # ONLY THE PERTURBED UNIT IS RE-RUN, AND THAT IS STATED HERE RATHER THAN IMPLIED: a
        # full `rows()` against a three-file temp copy raises `FileNotFoundError` on the units
        # this plant did not touch, which is a plant that measures its own harness.
        lane = (gapcensus.unit_ops,)
        live = dict(l.split("=", 1) for l in gapcensus.rows(lane) if "=" in l)
        was, gapcensus.ROOT = gapcensus.ROOT, copy
        try:
            got = dict(l.split("=", 1) for l in gapcensus.rows(lane) if "=" in l)
        finally:
            gapcensus.ROOT = was
        move = ("ops.upstream_declaration_order_members",
                "ops.order_variant_block_equals_upstream_DECLARATION")
        hold = ("ops.cpython_members", "ops.port_constructors")
        bad = []
        for k in move:
            print(f"  MOVE  {k}: {live[k]}  ->  {got[k]}")
            if got[k] == live[k]:
                bad.append(f"{k} did not move")
        for k in hold:
            print(f"  HOLD  {k}: {live[k]}  ->  {got[k]}")
            if got[k] != live[k]:
                bad.append(f"{k} moved and must not have")
        n = len(move) + len(hold)
        print(f"--plant: {'all ' + str(n) + ' states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
        return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--rows", action="store_true", help="print rows only")
    ap.add_argument("--plant", action="store_true", help="prove the census moves when the tree does")
    ap.add_argument("--accept", action="store_true", help="re-pin the baseline, by name")
    a = ap.parse_args()
    if a.plant:
        return plant()
    got = gapcensus.rows()
    if a.accept:
        # RE-PINNING IS A NAMED ACT, NOT A SIDE EFFECT OF LOOKING. `AGENTS.md` records a
        # message that claimed a deletion its diff did not witness; the same shape is a
        # census that silently accepts its own new numbers because nobody typed anything.
        PINS.write_text("\n".join(got) + "\n")
        print(f"gapcensus-gate: re-pinned {len(got)} rows into {PINS.relative_to(ROOT)} "
              f"({len(VOLATILE)} left unpinned)")
        return PASS
    if a.rows:
        print("\n".join(got))
        return PASS
    if not read_pins():
        print("== REFUSED, NOT A VERDICT: no baseline to compare against. "
              f"Write {PINS.relative_to(ROOT)} with --accept.", file=sys.stderr)
        return REFUSED
    n, moved = compare(got)
    # ZERO ROWS IS `DEAD`, NOT `PASS`. A census whose unit functions all raised would print
    # an empty diff, `moved` would be empty, and the gate would report PASS having compared
    # nothing -- the shape `AGENTS.md` records for `rebase-gate-selftest.py`. `DEAD` is exit
    # 5 in `gatekit.VERDICT`, and `verdict_of` is what prints the word, so this file invents
    # no vocabulary of its own.
    if not got:
        print(f"gapcensus-gate: {verdict_of(DEAD)} -- the census emitted no rows at all")
        return DEAD
    gapcensus.table()
    for k in VOLATILE:
        print(f"   (unpinned, it is a clock) {k}={dict(l.split('=', 1) for l in got if '=' in l)[k]}")
    if moved:
        print(f"\n{n} of {len(got)} rows MOVED since the baseline:")
        for m in moved:
            print(f"  {m}")
        print(f"gapcensus-gate: {verdict_of(FAIL)}")
        return FAIL
    print(f"gapcensus-gate: {verdict_of(PASS)} -- {len(got)} rows, "
          f"{len(VOLATILE)} unpinned by design, 0 moved")
    return PASS


if __name__ == "__main__":
    sys.exit(main())