#!/usr/bin/env python3
"""untested-gate.py -- THE 23: IS THE MIDDLE BUCKET A LIST, A FINDING, OR A MISCOUNT?

    .venv/bin/python gates/untested-gate.py            # the verdict
    .venv/bin/python gates/untested-gate.py --rows     # rows only
    .venv/bin/python gates/untested-gate.py --plant    # the instrument, made to move
    .venv/bin/python gates/untested-gate.py --accept   # re-pin, deliberately and by name

NO `bend`. This reads SOURCE. It is cheap enough to be re-run rather than taken on trust.

WHAT IS BEING GATED. `gates/gapcensus.py` publishes
`uop.ported_name_identical_UNEXERCISED=23` and calls it "the most dangerous number in the
table". `untested-census.py` re-derives that 23 out of `gapcensus`'s OWN populations and then
measures each member against a population the census never looked at. This gate pins the
FIVE rows that make the disagreement a measurement rather than an opinion, and -- the part
that matters -- it pins the row that would RETRACT the finding if the tree were fixed.

THE PINNED CLAIM, STATED SO IT CAN BE WRONG:

    `exercised` at `gates/gapcensus.py:293` searches the 62 `.bend` files a gate names in its
    own `bend=`. Of those, ONE is inside `tinybendygrad/`. So a method the port calls on every
    compilation is reported UNEXERCISED because no harness spells its name. 21 of the 23 have
    a call site in the port; 2 (`metadata`, `topovisit`) have none.

If somebody teaches `gapcensus` to search the port, `port_bend_files_searched_by_exercised`
rises to 155 and this gate FAILS, which is correct: the finding would be false.

THE FIVE VERDICTS ARE `gatekit`'s AND NOT LOCAL CONSTANTS -- `gates/gapcensus-gate.py:13-15`
records why a second copy of the table is a second vocabulary.
"""
from __future__ import annotations

import argparse
import importlib.util
import re
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gapcensus  # noqa: E402
from gatekit import DEAD, FAIL, PASS, REFUSED, verdict_of  # noqa: E402

# `untested-census.py` IS LOADED BY PATH, NOT BY `import`. The hyphen is the tree's naming
# convention for a file that is also an executable, and a module whose name is not an
# identifier cannot be imported by name. Doctrine 1's first clause -- a generator's own
# declaration, LOADED BY PATH -- is the same shape, and it means a rename moves this one line
# instead of silently falling back to another `untested` file on `sys.path`.
_uc_spec = importlib.util.spec_from_file_location("untested_census", HERE / "untested-census.py")
uc = importlib.util.module_from_spec(_uc_spec)
_uc_spec.loader.exec_module(uc)

PINS = HERE / "untested-pins.rows"

# THE ROWS THAT ARE A BASELINE RATHER THAN OUTPUT. The 23 per-method rows are NOT pinned:
# 138 rows keyed by a name that changes shape is a second copy of the bucket wearing a `.rows`
# costume. Four rows, and every one of them is a measurement of the INSTRUMENT.
PINNED = (
    "bucket.size",
    "bucket.drivers_searched",
    "bucket.drivers_INSIDE_the_port",
    "bucket.port_bend_files_searched_by_exercised",
)

# `bucket.port_bend_files` IS NOT PINNED, AND THIS IS MEASURED RATHER THAN ASSUMED. It read
# 155 at 04:24:30Z, 156 at 04:28:32Z and 157 at 04:30:01Z -- a unit is porting
# `tinybendygrad/extra/`, `examples/` and `nn/` underneath this session. A pin on a count of
# a tree another unit is writing to is a pin that fails for a reason unrelated to this
# instrument, which is `gapcensus-gate.py:51`'s `VOLATILE` and its stated reason ("a row that
# cannot be pinned without failing is a row whose pin would rot"). THE FINDING SURVIVES
# WITHOUT IT: `drivers_INSIDE_the_port` and `port_bend_files_searched_by_exercised` are both
# stable and both pinned, and "1 of N" is still printed from the unpinned row beside them.
VOLATILE = ("bucket.port_bend_files",)


def read_pins() -> dict[str, str]:
    if not PINS.is_file():
        return {}
    return dict(l.split("=", 1) for l in PINS.read_text().splitlines() if "=" in l)


def got_rows() -> dict[str, str]:
    return dict(l.split("=", 1) for l in uc.rows() if "=" in l)


def plant() -> int:
    """THE PLANT, AND ITS DISARM IS THE FINDING.

    THE MOVE. Pick the middle-bucket method with the MOST call sites OUTSIDE `ops.bend` --
    DERIVED, never named here -- copy the tree into a temp directory, delete every one of its
    call sites there, and require its rows to MOVE. If the rows do not move, this instrument
    is not measuring call sites and every number in it is decoration.

    THE DISARM. The census's own published row MUST NOT MOVE. And that is the whole finding:
    `exercised` decides the middle bucket over test-driver text, so deleting every call site
    of a method the port invokes, in every module of the port, leaves the census reading 23.
    A finding whose disarm is asserted here is a finding that can be wrong; had the census's
    row moved with the call sites, this file would print FAILED and the report would have to
    retract it.

    NO `bend`, NO live mutation, NO other unit's tree touched. ~24 MB, once.
    """
    got = got_rows()
    cands = [(n, int(got[f"bucket.{n}.port_call_sites_outside_ops_bend"])) for n in uc.middle_bucket()
             if int(got[f"bucket.{n}.port_call_sites_outside_ops_bend"]) > 0]
    if not cands:
        print("FAILED: no middle-bucket method has a call site outside ops.bend -- the "
              "finding is already retracted, and the plant has nothing to perturb")
        return 1
    target, outside = sorted(cands, key=lambda kv: (-kv[1], kv[0]))[0]
    print(f"--plant: target `{target}`, DERIVED as the bucket member with the most "
          f"call sites outside ops.bend ({outside}), never named here")

    with tempfile.TemporaryDirectory() as td:
        copy = Path(td) / "repo"
        # EXACTLY WHAT IS READ, AND NO MORE: `ast_methods` needs `tinygrad/uop/ops.py`;
        # `gate_drivers` walks `gates/` and keeps a driver only if the file resolves; the
        # five non-`gates` drivers need their own directories. A plant that copies the repo
        # is a 300 MB plant, and a plant nobody runs is a plant that proves nothing.
        #
        # `tinygrad/` IS COPIED WHOLE, AND THAT IS THE FIRST RUN OF THIS PLANT FIXING A
        # DEFECT IN ITSELF. The first version copied only `tinygrad/uop/ops.py`, so
        # `bucket.<m>.cpython_call_sites` fell 21 -> 0 in the copy and the HOLD fired. The
        # HOLD was measuring the TEMP COPY'S INCOMPLETENESS, not the plant's scope -- which
        # is the shape `gapcensus-gate.py:109-110` names as "a plant that measures its own
        # harness". 33 MB, once, and the HOLD now means what it says.
        for rel in ("tinygrad", "gates", "tinybendygrad", "examples",
                    ".agents/slop/bitcastrow", ".agents/slop/i64shl", ".agents/slop/ishr"):
            src, dst = gapcensus.ROOT / rel, copy / rel
            if src.is_dir():
                shutil.copytree(src, dst, dirs_exist_ok=True,
                                ignore=shutil.ignore_patterns("__pycache__"))
            elif src.is_file():
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
        shutil.copy2(HERE / "gapcensus-pins.rows", copy / "gates" / "gapcensus-pins.rows")

        w = re.compile(r"\b" + re.escape(target) + r"\s*\(")
        decl = re.compile(r"^def\s+UOp\." + re.escape(target) + r"\b")
        killed = 0
        for p in sorted((copy / "tinybendygrad").rglob("*.bend")):
            keep = []
            for line in p.read_text(errors="replace").splitlines(True):
                s = line.strip()
                if not s.startswith("#") and w.search(line) and not decl.match(s):
                    killed += 1
                    continue
                keep.append(line)
            p.write_text("".join(keep))
        print(f"   deleted {killed} call site(s) of `{target}` from the temp copy")
        if not killed:
            print("FAILED: the plant matched nothing -- the call-site pattern is stale")
            return 1

        was, gapcensus.ROOT = gapcensus.ROOT, copy
        try:
            after = got_rows()
            census_after = dict(l.split("=", 1) for l in gapcensus.rows((gapcensus.unit_uop,))
                                if "=" in l)
        finally:
            gapcensus.ROOT = was
        census_live = dict(l.split("=", 1) for l in gapcensus.rows((gapcensus.unit_uop,)) if "=" in l)

    bad = []
    states = 0
    for k in (f"bucket.{target}.port_call_sites",
              f"bucket.{target}.port_call_sites_outside_ops_bend"):
        states += 1
        print(f"  MOVE  {k}: {got[k]}  ->  {after[k]}")
        if after[k] == got[k]:
            bad.append(f"{k} did not move")
    for k in ("bucket.size", f"bucket.{target}.cpython_call_sites"):
        states += 1
        print(f"  HOLD  {k}: {got[k]}  ->  {after[k]}")
        if after[k] != got[k]:
            bad.append(f"{k} moved and must not have")
    key = "uop.ported_name_identical_UNEXERCISED"
    states += 1
    print(f"  HOLD  gapcensus {key}: {census_live[key]}  ->  {census_after[key]}")
    if census_after[key] != census_live[key]:
        bad.append(f"gapcensus {key} MOVED -- the census does see port call sites, and the "
                   f"finding must be RETRACTED")
    else:
        print(f"  DISARM CONFIRMED: deleting {killed} call sites of `{target}` from the port "
              f"left the census reading {census_after[key]}")
    print(f"--plant: {'all ' + str(states) + ' states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--rows", action="store_true", help="print rows only")
    ap.add_argument("--plant", action="store_true", help="prove the instrument moves")
    ap.add_argument("--accept", action="store_true", help="re-pin the baseline, by name")
    a = ap.parse_args()
    if a.plant:
        return plant()
    got = got_rows()
    if a.accept:
        PINS.write_text("\n".join(f"{k}={got[k]}" for k in PINNED) + "\n")
        print(f"untested-gate: re-pinned {len(PINNED)} rows into {PINS.relative_to(gapcensus.ROOT)} "
              f"({len(VOLATILE)} left unpinned: {', '.join(VOLATILE)})")
        return PASS
    if a.rows:
        print("\n".join(f"{k}={v}" for k, v in got.items()))
        return PASS
    if not read_pins():
        print("== REFUSED, NOT A VERDICT: no baseline to compare against. "
              f"Write {PINS.relative_to(gapcensus.ROOT)} with --accept.", file=sys.stderr)
        return REFUSED
    # `DEAD` BEFORE ANY COMPARISON. An instrument whose rows vanished compares nothing and an
    # empty diff is `PASS` -- the shape `AGENTS.md` and `gapcensus-gate.py:160-167` both name.
    if not got:
        print(f"untested-gate: {verdict_of(DEAD)} -- no rows emitted")
        return DEAD
    disagree = uc.check_against_pins()
    uc.table()
    for k in VOLATILE:
        print(f"\n   (unpinned, it is a clock) {k}={got[k]}")
    moved = [f"  {k}: pinned {read_pins().get(k, 'ABSENT')!r} -> now {got[k]!r}"
             for k in PINNED if read_pins().get(k) != got[k]]
    for d in disagree:
        moved.append(f"  untested-census disagrees with gapcensus: {d}")
    if moved:
        print(f"\n{len(moved)} of {len(PINNED)} pinned rows MOVED, or the derivation drifted:")
        print("\n".join(moved))
        print(f"untested-gate: {verdict_of(FAIL)}")
        return FAIL
    zero = [n for n in uc.middle_bucket() if got[f"bucket.{n}.port_call_sites"] == "0"]
    print(f"\nuntested-gate: {verdict_of(PASS)} -- {got['bucket.size']} in the middle bucket; "
          f"{len(zero)} have no call site in the port: {', '.join(zero) if zero else 'NONE'}")
    print("   the middle bucket is DERIVED, and `exercised` searches test-driver text only.")
    return PASS


if __name__ == "__main__":
    sys.exit(main())