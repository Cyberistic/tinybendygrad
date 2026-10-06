#!/usr/bin/env python3
"""PLANT AND DISARM for the bf16 guard.

THE ASYMMETRY THIS UNIT EXISTS TO SETTLE, stated before the numbers so the
numbers cannot be read the way the reporter wants:

  dtype.py:230 `if not math.isfinite(x): return x` says the guard's content is
  PASS-THROUGH -- `x` back untouched. So:
    * the CORRECT guard passes non-finite through   -> bf16_run == dtype.py
    * the INVERTED guard rounds non-finite         -> bf16_run == the old defect
    * SATURATION would be a THIRD answer, neither upstream's nor the old defect.
  A "plant" that merely removes the guard reproduces the PRE-EXISTING defect and
  therefore CANNOT move rows -- and that is the correct, expected result for a
  removal. Treating it as a disarm that "should" move rows would be the error
  JSFP8 warns about in the other direction.

THE ROWS THAT MUST MOVE, and why each one is named rather than discovered:
  * Any f32 pattern whose exponent field is all ones and whose low 16 bits are
    NOT zero. Rounding such a pattern carries into the exponent/mantissa, so the
    unguarded line rewrites it; the guard returns it. 16776960 of them, measured.
  * A bf16-REPRESENTABLE non-finite pattern (low 16 bits zero, e.g. 0x7FC00000,
    0x7F800000) must move NOTHING: adding 0x7FFF to a zero low half cannot carry,
    so the unguarded line already agrees with upstream there. That is a THEOREM
    about the arithmetic and it is why the bf16 code space shows 0 both before
    and after -- an unarmed gate and an armed gate agree on all 65536 bf16 codes.
    It is also exactly why the reported defect was invisible to a gate over the
    bf16 input space.
"""
import os, re, shutil, subprocess, sys, hashlib, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
LIVE = os.path.join(ROOT, "tinybendygrad", "runtime", "dtype.c")
sys.path.insert(0, HERE)
import gate

GUARD = "  if ((x & 0x7F800000u) == 0x7F800000u) return (Term)(intptr_t)x;\n"


def md5(b):
    return hashlib.md5(b).hexdigest()


FAMILIES = ("B", "N", "X")


def tree_rows(families=FAMILIES):
    """Rows from the FORMAT, never from dtype.c.

    `F` (the whole 16.7M f32 non-finite space) is NOT here and the reason is
    cost, stated so it is not mistaken for coverage: the row pipe costs ~10 s per
    drive, and four mutations x two row sets makes that minutes. `F` IS settled
    exhaustively, by bf16_gate.c's `census` mode, which walks all 2^32 in C in
    2.3 s -- 0 wrong after the fix, 16776960 before it. What `X` adds is the
    ability to move a FINITE row, which is the only way to catch an INVERTED
    guard: see gate.py's f32_rounding_rows for why the bf16 code space is blind
    to polarity."""
    src = {"B": gate.bf16_rows, "N": gate.nonfinite_rows,
           "X": gate.f32_rounding_rows, "F": gate.f32_nonfinite_rows}
    rows = []
    for f in families:
        rows += list(src[f]())
    assert len({n for n, _ in rows}) == len(rows), "row names must be unique"
    return rows


def build_variant(src, tag):
    """dtype.c is #included, so the only thing a variant needs is the mutated
    copy on the include path. The build is the FIRST thing this project has
    learned to distrust (bend -o is not a build), so it is `cc`, and it ASSERTS
    the binary exists rather than trusting cc's exit status."""


def build_variant(src, tag):
    """dtype.c is #included, so the only thing a variant needs is the mutated
    copy on the include path. The build is the FIRST thing this project has
    learned to distrust (bend -o is not a build), so it is `cc` and it asserts
    the binary exists."""
    d = tempfile.mkdtemp(prefix=f"bf16-{tag}-")
    dt = os.path.join(d, "dtype.c")
    open(dt, "w").write(src)
    exe = os.path.join(d, "bf16")
    r = subprocess.run(
        ["cc", "-O2", "-I", HERE, "-I", d, "-o", exe,
         os.path.join(HERE, "bf16_gate.c"), "-lm"], capture_output=True, text=True)
    if r.returncode != 0:
        shutil.rmtree(d)
        raise RuntimeError(f"BUILD FAILED {tag}: {r.stderr[-400:]}")
    assert os.path.exists(exe), f"cc reported success but wrote no binary ({tag})"
    return d, exe


def invert(src):
    """PLANT-inverted: the guard taken on the FINITE patterns instead."""
    assert src.count(GUARD) == 1
    return src.replace(
        GUARD,
        "  if ((x & 0x7F800000u) != 0x7F800000u) return (Term)(intptr_t)x;\n")


def remove(src):
    """DISARM-removed: the guard deleted -- the pre-existing defect."""
    assert src.count(GUARD) == 1
    return src.replace(GUARD, "")


def saturate(src):
    """PLANT-saturated: non-finite becomes a signed infinity. Upstream does NOT
    do this (dtype.py:230 returns x), so every non-finite row must move."""
    assert src.count(GUARD) == 1
    return src.replace(
        GUARD,
        "  if ((x & 0x7F800000u) == 0x7F800000u)\n"
        "    return (Term)(intptr_t)((x & 0x80000000u) | 0x7F800000u);\n")


def quieten(src):
    """DISARM-quieten: keep the guard but force the quiet bit, which is what a
    CPU float boundary does to a signalling NaN. dtype.py returns x UNCHANGED, so
    this must move the sNaN rows and no others. THE DISARM THAT COULD HAVE MOVED
    126 ROWS IF IT HAD BEEN WRITTEN AS A NO-OP -- it is a real mutation, not a
    removal, so "moved 0" here would have been a red flag rather than a pass."""
    assert src.count(GUARD) == 1
    return src.replace(
        GUARD,
        "  if ((x & 0x7F800000u) == 0x7F800000u)\n"
        "    return (Term)(intptr_t)((x & 0x7FFFFFFFu) == 0 ? x : x | 0x00400000u);\n")


def measure(exe, rows):
    """`moved` compares WHOLE name=value lines (agent-core.md:181: a
    name-comparing harness reported 0 for 30 mutations in one unit and 0 for 68 in
    another)."""
    got = gate.drive(rows, exe)
    mm = [(n, p) for n, p in rows if got[n] != gate.spec(p)]
    return got, mm


def main():
    exe = gate.build()
    print(f"LIVE dtype.c md5 {gate.md5(LIVE)}")

    for fams in (("B", "N"), ("X",), FAMILIES):
        rows = tree_rows(fams)
        base, mm = measure(exe, rows)
        tag = "+".join(fams)
        print(f"\n=== families {tag}: rows={len(rows)} "
              f"BASE MISMATCH={len(mm)} ===")
        for name, fn, why in (
                ("PLANT-inverted", invert, "guard polarity flipped"),
                ("PLANT-saturated", saturate, "pass-through replaced by inf"),
                ("DISARM-removed", remove,
                 "guard deleted: reproduces the pre-existing defect"),
                ("DISARM-quieten", quieten,
                 "guard kept, quiet bit forced on the sNaNs"),
        ):
            src = open(LIVE).read()
            try:
                dd, ex = build_variant(fn(src), name)
                v = gate.drive(rows, ex)
            except Exception as e:
                print(f"{name:18s} {e}")
                continue
            finally:
                shutil.rmtree(dd, ignore_errors=True)
            moved = [n for n, _ in rows if base[n] != v[n]]
            mmv = [n for n, p in rows if v[n] != gate.spec(p)]
            print(f"{name:18s} rows={len(rows):9d} moved={len(moved):9d} "
                  f"mismatch={len(mmv):9d}  ({why})")
            if moved and len(moved) <= 6:
                print("   " + " ".join(moved))


if __name__ == "__main__":
    main()