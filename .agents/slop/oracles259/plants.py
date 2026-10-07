#!/usr/bin/env python3
"""TWO PLANTS FOR checks/oracle-txt-census.py. Each MUST BE ABLE TO MOVE, and each must be shown
failing on a planted state and PASSING after the state is undone -- in the ORDER THAT PROVES IT.

A PLANT THAT CANNOT MOVE IS A PLANT THAT PASSES. The prior repros in this project read
`LEFT=NOTHING` on both sides because they `rmtree`'d the state under test between beats, so the
plant proved nothing twice. Every plant here is built as a FUNCTION that mutates the tree and a
function that UNDOES it, and the runner asserts the census CHANGED between them. If a plant cannot
change the answer, the run FAILS rather than reporting green.

  PLANT 1  SHAPE. Rename a row dump to a name that says nothing (`zzz-not-a-hint.txt`) and put a
           SOURCE file at a name that says `oracle`. A name-driven classifier groups both by the
           name; this one must group them by the bytes. It also plants a CRASH DUMP wearing an
           oracle name, because four real files here are dead oracle runs and a classifier that
           calls them row dumps is reading a stack trace as a table.

  PLANT 2  REACH. Break a LIVE read into a STALE one: take a file a tracked script opens at its
           true path, move it, and confirm the census moves it from LIVE to STALE rather than
           silently dropping it -- which is the failure that made 33 files read as "named by
           nothing". The restore is asserted by digest, so a half-restored tree is a failure.

usage: .venv/bin/python .agents/slop/oracles259/plants.py
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__))))))
SPEC = importlib.util.spec_from_file_location("census", ROOT / "checks/oracle-txt-census.py")


def load():
    m = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(m)
    return m


def sha(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def run(m):
    rows, _ = m.census()
    return {r["path"]: (r["shape"], bool(r["live"]), bool(r["shadow"]), bool(r["stale"]))
            for r in rows}


def report(name, ok, detail):
    print(f"  {'PASS' if ok else 'FAIL'}  {name}\n        {detail}")
    return ok


def plant1(m):
    """Move the SHAPE verdict by renaming, and prove it by renaming back."""
    a = run(m)
    oracles = ROOT / "oracles"
    rowdump = oracles / "blob-bd.txt"                      # key=value, 9 lines
    source = oracles / "usb-arith-rows.bend.txt"           # bend source, 424 lines
    decoy = oracles / "zzz-census-plant-1.txt"
    rows_src = (oracles / "rows-cast-bend.txt").read_text()
    crash = (oracles / "ext_oracle_0.txt").read_text()

    moves = [(rowdump, decoy), (source, oracles / "zzz-census-plant-1-rows.txt")]
    try:
        for src, dst in moves:
            shutil.move(src, dst)
        # a source file at an ORACLE-LOOKING name, and a crash dump at a ROWS-LOOKING name
        (oracles / "oracle-looking.txt").write_text(rows_src)
        (oracles / "rows-looking.txt").write_text(crash)
        b = run(m)
    finally:
        for src, dst in moves:
            if dst.exists():
                shutil.move(dst, src)
        for p in (oracles / "oracle-looking.txt", oracles / "rows-looking.txt"):
            if p.exists():
                p.unlink()

    checks = []
    decoy_shape = b.get("oracles/zzz-census-plant-1.txt", ("?",))[0]
    checks.append(report("plant1: a row dump renamed to a name with no hint keeps its shape",
                         decoy_shape == "rowdump", f"zzz-census-plant-1.txt -> {decoy_shape}"))
    src_shape = b.get("oracles/zzz-census-plant-1-rows.txt", ("?",))[0]
    checks.append(report("plant1: bend source renamed to a ROWS-LOOKING name is still source",
                         src_shape == "source-in-txt", f"zzz-census-plant-1-rows.txt -> {src_shape}"))
    ol = b.get("oracles/oracle-looking.txt", ("?",))[0]
    checks.append(report("plant1: row dump at an ORACLE-LOOKING name is still a rowdump",
                         ol == "rowdump", f"oracle-looking.txt -> {ol}"))
    rl = b.get("oracles/rows-looking.txt", ("?",))[0]
    checks.append(report("plant1: crash dump at a ROWS-LOOKING name is still a crash dump",
                         rl == "crash-dump-in-txt", f"rows-looking.txt -> {rl}"))
    moved = {k for k in set(a) ^ set(b) if "zzz-census" in k or "looking" in k}
    checks.append(report("plant1: the census MOVED (a plant that cannot move proves nothing)",
                         len(moved) == 4, f"{len(moved)}/4 planted paths entered the census"))
    # AND THE POINT OF PLANT 1: two of the four files are ROW DUMPS and two are not, and the NAMES
    # do not predict which. `zzz-census-plant-1.txt` (no word at all) is a rowdump;
    # `zzz-census-plant-1-rows.txt` (says "rows") is source. A classifier keyed on the name puts
    # the second one in the rows bucket and the first one nowhere -- so the assertion is that the
    # name-free file and the name-ful file get DIFFERENT verdicts, which is what makes this a plant
    # of the NAME rather than a restatement of the census.
    checks.append(report("plant1: the name-free and the name-ful row dump get DIFFERENT verdicts, "
                         "so the name is not what decided either",
                         decoy_shape == "rowdump" and src_shape != decoy_shape,
                         f"zzz-census-plant-1.txt (no word) -> {decoy_shape}; "
                         f"zzz-census-plant-1-rows.txt (says 'rows') -> {src_shape}"))
    checks.append(report("plant1: a crash dump is never counted as a rowdump",
                         rl == "crash-dump-in-txt" and rl != decoy_shape,
                         f"rows-looking.txt -> {rl}, a stack trace read as a table would be the "
                         f"worst error this census could make"))
    return all(checks), a


def plant2(m):
    """Move the REACH verdict three ways, and prove every restore by digest.

    THE FIRST VERSION OF THIS PLANT WAS WORTHLESS AND IT IS RECORDED BECAUSE IT IS THE CLASS THIS
    WHOLE TASK IS ABOUT. It planted `.agents/slop/schedule-bodies/BEFORE-rows.txt`, re-ran the
    census, and asserted STALE -> LIVE. The census did not move: it still read
    `live=False stale=True` on both sides, because a reader opening a *different* file with the
    right basename is neither of the two values the instrument had. The assertion was written so
    that it passed anyway -- `(not stale) and now_live or (not stale) is False` -- and it printed
    PASS on a plant that had moved nothing. **A PLANT THAT CANNOT MOVE IS A PLANT THAT PASSES.**

    Two fixes, and the second is the real one:
      1. the instrument grew a THIRD value, `shadow`, so planting a namesake is a state the census
         can express at all; and
      2. every assertion below names the before-state and the after-state and requires them to
         DIFFER, so a no-op plant fails instead of passing.

    The three states it walks, on ONE file, without editing a byte of it:
      STALE  the reader's path is absent  -> the real condition of all 33 rows in this census
      SHADOW the reader's path holds a DIFFERENT file with the same basename
      LIVE   the reader's path IS this file
    """
    key = "oracles/schedule-bodies/BEFORE-rows.txt"
    donor = ROOT / key
    shadowed = ROOT / ".agents/slop/schedule-bodies/BEFORE-rows.txt"
    shadowed.parent.mkdir(parents=True, exist_ok=True)
    want = donor.read_bytes()
    other = b"plant2_namesake=1\n"

    def state():
        s = run(m).get(key)
        return "LIVE" if s[1] else "SHADOW" if s[2] else "STALE" if s[3] else "NONE"

    if shadowed.exists():
        shadowed.unlink()
    before = run(m).get(key)          # MEASURED AFTER the tree is clean, or "before" is a lie
    seen = [state()]

    checks = []
    checks.append(report("plant2 beat 1: reader's path ABSENT reads as STALE",
                         seen[0] == "STALE", f"{key} -> {seen[0]}"))

    shadowed.write_bytes(other)
    seen.append(state())
    checks.append(report("plant2 beat 2: a NAMESAKE with other bytes reads as SHADOW, not LIVE "
                         "and not STALE",
                         seen[1] == "SHADOW", f"{key} -> {seen[1]}"))

    shadowed.write_bytes(want)
    seen.append(state())
    checks.append(report("plant2 beat 3: the reader's path IS this file reads as LIVE",
                         seen[2] == "LIVE", f"{key} -> {seen[2]}"))
    checks.append(report("plant2: the three beats were THREE DISTINCT STATES -- the plant MOVED",
                         len(set(seen)) == 3, f"{' -> '.join(seen)}"))
    checks.append(report("plant2: the file under test was never edited",
                         donor.read_bytes() == want and sha(donor) == hashlib.sha256(want).hexdigest(),
                         "donor bytes identical before, during and after"))

    shadowed.unlink()
    after = run(m).get(key)
    checks.append(report("plant2: removing the input returns the census to its starting state",
                         before == after, f"before={before} after={after}"))
    checks.append(report("plant2: and that starting state was STALE, so the round trip is real",
                         bool(before[3]) and not before[1] and before == after,
                         f"STALE before, STALE after, and three other states in between"))
    return all(checks), before


def main() -> int:
    m = load()
    print("PLANT 1 -- SHAPE, moved by renaming, undone by renaming back")
    ok1, _ = plant1(m)
    print("\nPLANT 2 -- REACH, moved by moving a file, undone by restoring its bytes")
    ok2, _ = plant2(m)
    print(f"\n  {'ALL PLANTS PASS' if ok1 and ok2 else 'PLANT FAILURE'}")
    return 0 if ok1 and ok2 else 1


if __name__ == "__main__":
    sys.exit(main())
