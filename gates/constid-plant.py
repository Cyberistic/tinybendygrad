#!/usr/bin/env python3
"""constid-plant.py -- THE PLANT for the CONST-IDENTITY claim, on COPIES.

    .venv/bin/python gates/constid-plant.py

A GATE THAT CANNOT GO RED IS A LABEL, not a gate -- `checks/differ.py`'s own plant 3 says so,
and it measures it by perturbing a thing and watching the verdict move.  This file is that
measurement for `gates/constid-gate.py`, and it answers ONE question:

    WOULD AN IEEE COMPARATOR BE A FIX, OR A NEW HASH COLLISION?

THE ARM.  Upstream's `ConstFloat.__hash__` is `hash(self.bits)` (`dtype.py:21`), so upstream's
OWN hash table keeps two nans with different payloads apart -- MEASURED, two entries in one
dict, while upstream's `__eq__` says the two are EQUAL.  The port's `eq_const.CFloat`
compares the BITS, so it agrees with upstream's hash table.  This plant plants the IEEE
comparator and shows the port's COUNT OF DISTINCT CONSTANTS MOVE: 2 keys become 1, and one
key is a collision upstream does not have.  **THE ARM THAT MATTERS: A CONST THAT UPSTREAM
KEEPS APART MUST NOT BE ONE IN THE PORT -- PLANT IT AND SHOW THE COUNT MOVE.**

THE SECOND MEASUREMENT IS THE ONE THAT NAMES THE MERGE'S CAUSE.  Under the same plant
`merge_keys` does NOT MOVE: it stays 1, because the merge is not the comparator's doing, it
is the WIDTH (upstream carries 64 bits of a double in `ConstFloat.bits`, the port carries 32
bits of an f32).  **A PLANT THAT MOVED EVERY COUNT WOULD HAVE PROVED NOTHING ABOUT WHICH
DEFECT IT IS.**

EVERYTHING HAPPENS ON A COPY.  The port's `tinybendygrad/` tree is COPIED into a temporary
directory and the mutation is applied THERE, because a `.bend` file imports its neighbours
RELATIVE TO ITS OWN PATH: a copy of ONE file anywhere else cannot resolve them and answers
"the substrate did not warm" -- a REFUSED exit for the wrong reason, and a harness that
reports "the mutation was found" because the file did not compile has learned nothing.

THE BEND LOCK IS HELD FOR EVERY `bend` RUN, through `checks/bendlock.sh`, which is the tree's
own lock and refuses to steal a live owner's.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PASS, FAIL, REFUSED = 0, 1, 3

# THE MUTATION, AND IT IS THE COMPARATOR.  The text is the port's own, read out of
# `tinybendygrad/uop/ops.bend`, and the plant REFUSES if it is not there -- a mutation that
# does not apply is not reported as zero.
OLD = "    case CFloat{g}: U32.is_eq(F32.bits(f), F32.bits(g))"
NEW = "    case CFloat{g}: F32.is_eq(f, g)"

# WHAT THE PLANT EXPECTS TO SEE, IN THE C LANE.  `bin/bend <file> -o <bin>` builds a native
# binary, which is the C lane -- the one that KEEPS a nan payload, and therefore the one in
# which the comparator is the thing that decides the count.
CONTROL = {"split_keys_distinct": "2", "merge_keys": "1", "merge_keys_int": "1"}
PLANTED = {"split_keys_distinct": "1", "merge_keys": "1", "merge_keys_int": "1"}


def bend(root: Path, driver: Path, out: Path | None = None):
    """`bend` UNDER THE TREE'S LOCK, and the ROWS it printed."""
    argv = [str(root / "bin" / "bend"), str(driver)]
    if out is not None:
        argv += ["-o", str(out)]
    cmd = [str(root / "checks" / "bendlock.sh"), "--"] + argv
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        return None, (r.stderr or r.stdout or f"rc={r.returncode}").strip()[:300]
    if out is not None:
        run = subprocess.run([str(out)], capture_output=True, text=True)
        if run.returncode != 0:
            return None, (run.stderr or run.stdout or f"rc={run.returncode}").strip()[:300]
        text = run.stdout
    else:
        text = r.stdout
    rows = dict(l.split("=", 1) for l in text.splitlines() if "=" in l)
    return rows, None


def check(name, got, want, bad):
    if got is None:
        print(f"  FAIL  {name}: the lane did not run")
        bad.append(name)
        return
    moved = {k: (want[k], got.get(k)) for k in want if got.get(k) != want[k]}
    if moved:
        print(f"  FAIL  {name}: {moved}")
        bad.append(name)
    else:
        print(f"  PASS  {name}")


def main() -> int:
    bad = []
    with tempfile.TemporaryDirectory() as td:
        scratch = Path(td)
        shutil.copytree(ROOT / "tinybendygrad", scratch / "tinybendygrad")
        (scratch / "gates").mkdir()
        shutil.copy(HERE / "constid.bend", scratch / "gates" / "constid.bend")
        driver = scratch / "gates" / "constid.bend"
        ops = scratch / "tinybendygrad" / "uop" / "ops.bend"
        pristine = ops.read_text()
        if OLD not in pristine:
            print("== REFUSED, NOT A VERDICT: the mutation DID NOT APPLY, the old text is not in "
                  "the file. NOT REPORTED AS 0.", file=sys.stderr)
            return REFUSED

        # 1 -- THE CONTROL.  The UNMUTATED copy must answer what the live tree answers, or
        # the measurement below would be about the copy rather than about the plant.
        rows, err = bend(ROOT, driver, scratch / "control.bin")
        if rows is None:
            print(f"== REFUSED, NOT A VERDICT: the unmutated copy did not build: {err}",
                  file=sys.stderr)
            return REFUSED
        check("1: the UNMUTATED copy answers the CONTROL counts", rows, CONTROL, bad)

        # 2 -- THE PLANT.  The IEEE comparator: a const upstream keeps apart becomes ONE in
        # the port, and the count of distinct constants MOVES.
        ops.write_text(pristine.replace(OLD, NEW, 1))
        rows, err = bend(ROOT, driver, scratch / "planted.bin")
        if rows is None:
            print(f"== REFUSED, NOT A VERDICT: the planted copy did not build: {err}",
                  file=sys.stderr)
            ops.write_text(pristine)
            return REFUSED
        check("2: the PLANTED comparator makes the port's COUNT OF DISTINCT CONSTANTS MOVE "
              "(2 keys -> 1, a collision upstream does not have) and leaves the MERGE's count "
              "where it was (the merge is the WIDTH, not the comparator)", rows, PLANTED, bad)
        ops.write_text(pristine)

        # 3 -- THE LIVE TREE, so a copy that is special cannot be the only thing that passed.
        rows, err = bend(ROOT, ROOT / "gates" / "constid.bend", scratch / "live.bin")
        if rows is None:
            print(f"== REFUSED, NOT A VERDICT: the live tree did not build: {err}", file=sys.stderr)
            return REFUSED
        check("3: the LIVE tree answers the CONTROL counts too", rows, CONTROL, bad)

    if bad:
        print(f"constid-plant: FAILED -- {bad}")
        return FAIL
    print("constid-plant: 3 of 3 -- the port's bitwise `eq_const.CFloat` is RIGHT, an IEEE "
          "comparator would create a hash collision upstream does not have, and the MERGE is "
          "the WIDTH (upstream carries 64 bits of a double, the port carries 32 bits of an f32)")
    return PASS


if __name__ == "__main__":
    sys.exit(main())
