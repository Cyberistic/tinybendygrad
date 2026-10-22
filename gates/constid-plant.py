#!/usr/bin/env python3
"""constid-plant.py -- THE PLANT for the CONST-IDENTITY claim, on COPIES.

    .venv/bin/python gates/constid-plant.py

A GATE THAT CANNOT GO RED IS A LABEL, not a gate -- `checks/differ.py`'s own plant 3 says so,
and it measures it by perturbing a thing and watching the verdict move.  This file is that
measurement for `gates/constid-gate.py`, and it answers ONE question:

    WHICH COMPARATOR MATCHES UPSTREAM's HASH TABLE IN BOTH NAN CELLS?

**AND THE FIRST VERSION OF THIS PLANT WAS WRONG, AND THE PLANT IS WHY IT IS NOW RIGHT.**
It planted the IEEE comparator and predicted it would MERGE two different nan payloads --
2 keys -> 1.  **MEASURED: IT DID NOT.**  IEEE equality already says two different nan
payloads are DIFFERENT, so the count stayed at 2 and the plant FAILED on its own
prediction.  The comparator that merges them is not IEEE -- it is UPSTREAM's `__eq__`, which
special-cases nan as equal, and THAT is arm B below.

**THE THREE COMPARATORS, AND WHAT EACH ONE DOES TO THE TWO NAN CELLS.**  Upstream's hash
table is the thing to match, and `ConstFloat.__hash__` is `hash(self.bits)`, so upstream
interns the SAME payload twice as ONE key and two DIFFERENT payloads as TWO keys:

| comparator | same payload twice (upstream: 1 key) | two different payloads (upstream: 2 keys) |
| --- | --- | --- |
| BITWISE (the port's) | 1 -- MATCHES | 2 -- MATCHES |
| IEEE (arm A) | **2 -- SPLITS what upstream merges** | 2 -- matches |
| upstream's `__eq__` (arm B) | 1 -- matches | **1 -- MERGES, a collision upstream does not have** |

**⇒ THE PORT's BITWISE COMPARATOR IS THE ONLY ONE OF THE THREE THAT MATCHES UPSTREAM's
HASH TABLE IN BOTH CELLS, AND NEITHER ALTERNATIVE IS A FIX.**  Arm A would re-mint an
identical node; arm B would merge two constants upstream keeps apart.

THE MERGE'S COUNT (`merge_keys`, `merge_keys_int`) DOES NOT MOVE UNDER EITHER ARM, because
the merge is not the comparator's doing -- it is the WIDTH (upstream carries 64 bits of a
double in `ConstFloat.bits`, the port carries 32 bits of an f32).  **A PLANT THAT MOVED
EVERY COUNT WOULD HAVE PROVED NOTHING ABOUT WHICH DEFECT IT IS.**

EVERYTHING HAPPENS ON A COPY.  The port's `tinybendygrad/` tree is COPIED into a temporary
directory and the mutation is applied THERE, because a `.bend` file imports its neighbours
RELATIVE TO ITS OWN PATH: a copy of ONE file anywhere else cannot resolve them and answers
"the substrate did not warm" -- a REFUSED exit for the wrong reason, and a harness that
reports "the mutation was found" because the file did not compile has learned nothing.

THE BEND LOCK IS HELD FOR EVERY `bend` RUN, through `checks/bendlock.sh`, which is the tree's
own lock and refuses to steal a live owner's.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PASS, FAIL, REFUSED = 0, 1, 3

# THE MUTATIONS, AND THEY ARE THE COMPARATOR.  The text is the port's own, read out of
# `tinybendygrad/uop/ops.bend`, and the plant REFUSES if it is not there -- a mutation that
# does not apply is not reported as zero.
OLD = "    case CFloat{g}: U32.is_eq(F32.bits(f), F32.bits(g))"

# ARM A -- IEEE.  `F32.is_eq` is IEEE, and IEEE says a nan is not equal to itself.
IEEE = "    case CFloat{g}: F32.is_eq(f, g)"

# ARM B -- UPSTREAM's `__eq__`, spelled out: two nans are equal, and everything else is
# IEEE.  `H.f32_is_nan` is the port's own nan test (`helpers.bend:913`: the exponent field
# all ones AND the mantissa non-zero), and `ops.bend:167` already imports `H`.  THE `+` ON
# THE BINDER IS LOAD-BEARING: `g` is used TWICE, and Bend's linear types REFUSE a binder
# consumed more than once -- MEASURED, the first attempt said
# "expected : g / observed : g (consumed more than once)".
NANAWARE = ("    case CFloat{+g}: Bool.or(Bool.and(H.f32_is_nan(f), H.f32_is_nan(g)), "
            "F32.is_eq(f, g))")

# WHAT THE PLANT EXPECTS TO SEE, IN THE C LANE.  `bin/bend <file> -o <bin>` builds a native
# binary, which is the C lane -- the one that KEEPS a nan payload, and therefore the one in
# which the comparator is the thing that decides the count.
#
# UPSTREAM'S HASH TABLE, WHICH IS WHAT THE PORT'S COMPARATOR HAS TO MATCH, IN BOTH NAN
# CELLS: the same payload twice is ONE entry, and two different payloads are TWO entries
# (`ConstFloat.__hash__` is `hash(self.bits)`).
CONTROL = {"split_keys_distinct": "2", "split_keys_same": "1",
           "merge_keys": "1", "merge_keys_int": "1"}
# ARM A: IEEE says a nan is not equal to itself, so the SAME payload twice SPLITS -- a
# constant upstream interns as ONE node becomes TWO.
ARM_A = {"split_keys_distinct": "2", "split_keys_same": "2",
         "merge_keys": "1", "merge_keys_int": "1"}
# ARM B: upstream's `__eq__` says two nans are EQUAL, so two DIFFERENT payloads MERGE --
# a hash collision upstream's own hash table does not have.
ARM_B = {"split_keys_distinct": "1", "split_keys_same": "1",
         "merge_keys": "1", "merge_keys_int": "1"}


def bend(root: Path, driver: Path, out: Path | None = None, lock: Path | None = None):
    """`bend` UNDER THE TREE'S LOCK, and the ROWS it printed.

    THE LOCK SCRIPT IS TAKEN AS A STABLE COPY, ONCE, AND THE LOCK DIRECTORY IS STILL THE
    TREE'S SHARED ONE.  MEASURED 2026-10-22: `checks/bendlock.sh` was EDITED IN FLIGHT by
    another unit (mtime 10:35) while this plant's shell was READING it, and a shell reads a
    script INCREMENTALLY BY BYTE OFFSET -- so it resumed mid-line and executed the wrong
    bytes: `checks/bendlock.sh: line 102: st.: command not found`, and the plant REFUSED
    (3) for a reason that had NOTHING TO DO WITH THE SUBSTRATE.  **A REFUSAL CAUSED BY
    ANOTHER UNIT'S EDIT IS A REFUSAL, NOT A MEASUREMENT, AND IT MUST NOT BE RECORDED AS
    ONE.**  The copy is the same mechanism and the same lock directory; only the FILE the
    shell reads is pinned.
    """
    argv = [str(root / "bin" / "bend"), str(driver)]
    if out is not None:
        argv += ["-o", str(out)]
    cmd = [str(lock or (root / "checks" / "bendlock.sh")), "--"] + argv
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
        # THE STABLE LOCK SCRIPT, taken ONCE, so an in-flight edit of the tree's copy cannot
        # corrupt a shell's incremental read of it.  The LOCK DIRECTORY is the tree's shared
        # one -- this copy serialises against the other units exactly as the original does.
        lock = scratch / "bendlock.sh"
        shutil.copy(ROOT / "checks" / "bendlock.sh", lock)
        lock.chmod(0o755)
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
        rows, err = bend(ROOT, driver, scratch / "control.bin", lock)
        if rows is None:
            print(f"== REFUSED, NOT A VERDICT: the unmutated copy did not build: {err}",
                  file=sys.stderr)
            return REFUSED
        check("1: the UNMUTATED copy answers the CONTROL counts", rows, CONTROL, bad)

        # 2 -- ARM A: THE IEEE COMPARATOR.  It says a nan is not equal to ITSELF, so the
        # SAME payload twice SPLITS: a constant upstream interns as ONE node becomes TWO.
        ops.write_text(pristine.replace(OLD, IEEE, 1))
        rows, err = bend(ROOT, driver, scratch / "arm-a.bin", lock)
        if rows is None:
            print(f"== REFUSED, NOT A VERDICT: arm A did not build: {err}", file=sys.stderr)
            ops.write_text(pristine)
            return REFUSED
        check("2: ARM A -- the IEEE comparator SPLITS a constant upstream interns as ONE "
              "(split_keys_same 1 -> 2)", rows, ARM_A, bad)
        ops.write_text(pristine)

        # 3 -- ARM B: UPSTREAM's `__eq__`, which says two nans are EQUAL.  It MERGES two
        # DIFFERENT nan payloads -- a hash collision upstream's own hash table does not have,
        # because upstream's `__hash__` is `hash(self.bits)`.
        ops.write_text(pristine.replace(OLD, NANAWARE, 1))
        rows, err = bend(ROOT, driver, scratch / "arm-b.bin", lock)
        if rows is None:
            print(f"== REFUSED, NOT A VERDICT: arm B did not build: {err}", file=sys.stderr)
            ops.write_text(pristine)
            return REFUSED
        check("3: ARM B -- upstream's `__eq__` MERGES two different nan payloads "
              "(split_keys_distinct 2 -> 1), a hash collision upstream does not have",
              rows, ARM_B, bad)
        ops.write_text(pristine)

        # 4 -- THE LIVE TREE, so a copy that is special cannot be the only thing that passed.
        rows, err = bend(ROOT, ROOT / "gates" / "constid.bend", scratch / "live.bin", lock)
        if rows is None:
            print(f"== REFUSED, NOT A VERDICT: the live tree did not build: {err}", file=sys.stderr)
            return REFUSED
        check("4: the LIVE tree answers the CONTROL counts too", rows, CONTROL, bad)

    if bad:
        print(f"constid-plant: FAILED -- {bad}")
        return FAIL
    print("constid-plant: 4 of 4 -- the port's BITWISE `eq_const.CFloat` is the ONLY one of the "
          "three that matches upstream's hash table in BOTH nan cells: IEEE SPLITS a constant "
          "upstream interns as one (the same nan payload twice becomes two nodes), and "
          "upstream's own `__eq__` MERGES two different nan payloads upstream's hash table "
          "keeps apart (a collision upstream does not have). The MERGE's count does not move "
          "under either arm, because the merge is the WIDTH and not the comparator")
    return PASS


if __name__ == "__main__":
    sys.exit(main())
