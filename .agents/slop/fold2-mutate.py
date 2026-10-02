#!/usr/bin/env python
# fold2-mutate.py -- the mutation harness for `uop/fold.bend`'s `bit_length` and DTYPE
# LIMIT unit.
#
# TWO RULES FROM agent-core.md SHAPE THIS FILE:
#   * IT DIFFS WHOLE `name=value` LINES, NOT ROW NAMES. A name-comparing harness
#     reported 0 for all 30 mutations in one unit and 0 for all 68 in another.
#   * A `0` IS REPORTED AS A REQUEST FOR A FIXTURE, A THEOREM, OR AN UNFIXABLE -- never
#     closed with a row that encodes the equivalence as a check.
#
# It reads the work file, applies ONE textual edit, rebuilds, reruns, and diffs against a
# baseline captured from the SAME file in the SAME state. The baseline is captured here
# rather than trusted, because agent-core records a unit where a concurrent agent's mtime
# moved mid-baseline and made a row appear to move on every mutation.
import subprocess
import sys
import os
import time

WORK = 'tinybendygrad/uop/fold2_work.bend'
BEND = './bin/bend'
# The dtype oracle reads a CLEAN `git archive HEAD tinygrad` snapshot, because another
# agent edits `tinygrad/uop/ops.py` and a half-synchronised tree breaks the import.
TG_TREE = os.environ.get('TG_TREE', '.')

# (label, old, new, what it is testing)
MUT = [
  # ---- bit_length: the ladder ----
  ("BL1", "def mm.bl32.p16(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 65536), U32.shrn(x, 16n), x)",
   "def mm.bl32.p16(+x: U32) -> U32: Bool.pick(U32, U32.is_gt(x, 65536), U32.shrn(x, 16n), x)",
   "the top threshold `>=` vs `>`: 65536 is a boundary only the `>=` gets right"),
  ("BL2", "def mm.bl32.p8(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 256), U32.shrn(x, 8n), x)",
   "def mm.bl32.p8(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 128), U32.shrn(x, 8n), x)",
   "threshold off by a factor of two: 2**8 is 256, not 128"),
  ("BL3", "def mm.bl32.tail(+e: U32) -> U32: Bool.pick(U32, U32.is_zero(e), 0, 1)",
   "def mm.bl32.tail(+e: U32) -> U32: Bool.pick(U32, U32.is_zero(e), 1, 1)",
   "the ZERO case: `bit_length(0) == 0`, and a tail that always adds 1 answers 1"),
  ("BL4", "Bool.pick(U32, U32.is_zero(hi), mm.bl32(lo), U32.add(32, mm.bl32(hi)))",
   "Bool.pick(U32, U32.is_zero(lo), mm.bl32(lo), U32.add(32, mm.bl32(hi)))",
   "the 64-bit pick tested on `lo` instead of `hi`: the two disagree only at the value 0"),
  ("BL5", "def mm.bl32.b16(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 65536), 16, 0)",
   "def mm.bl32.b16(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 65536), 15, 0)",
   "the 16 the top stage ADDS, which must match the 16 it SHIFTS by"),
  # ---- the mask ----
  ("MK1", "def mm.mask.lo(+k: U32) -> U32:\n  U32.shrn(4294967295, Nat.sub(32n, U32.to_nat(k)))",
   "def mm.mask.lo(+k: U32) -> U32:\n  U32.shrn(4294967295, Nat.sub(31n, U32.to_nat(k)))",
   "the low word is all ones shifted by (32 - k); an off-by-one gives 2**k+1 - 1"),
  ("MK2", "def mm.mask.hi(+k: U32) -> U32:\n  U32.shrn(4294967295, Nat.sub(64n, U32.to_nat(k)))",
   "def mm.mask.hi(+k: U32) -> U32:\n  U32.shrn(4294967295, Nat.sub(63n, U32.to_nat(k)))",
   "the high word's width is 64, not 63"),
  ("MK3", "Bool.pick(U32, U32.is_zero(hi), mm.bl32(lo), U32.add(32, mm.bl32(hi)))",
   "Bool.pick(U32, U32.is_zero(hi), mm.bl32(lo), U32.add(31, mm.bl32(hi)))",
   "the 32 the high-word branch adds, which is the WIDTH OF THE HIGH WORD"),
  # ---- the dtype limits ----
  ("DT1", "def bnd_int(+top: Bool, +sgn: Bool, +bits: U32) -> Bnd:\n  Bool.pick(Bnd, U32.is_gt(bits, 64), bnd_flt(top),",
   "def bnd_int(+top: Bool, +sgn: Bool, +bits: U32) -> Bnd:\n  Bool.pick(Bnd, U32.is_gt(bits, 65), bnd_flt(top),",
   "the WIDTH GUARD, off by one: 65 admits a 65-bit width whose mask is not saturating"),
  ("DT2", "Bool.pick(Bnd, top, Bool.pick(Bnd, sgn, bnd.smax(bits), bnd.umax(bits)),\n      Bool.pick(Bnd, sgn, bnd.smag(bits), bnd_zero()))",
   "Bool.pick(Bnd, top, Bool.pick(Bnd, sgn, bnd.umax(bits), bnd.smax(bits)),\n      Bool.pick(Bnd, sgn, bnd_zero(), bnd.smag(bits)))",
   "signed and unsigned SWAPPED: `int8` and `uint8` must not exchange their limits"),
  ("DT3", "def bnd.smax(+bits: U32) -> Bnd: BndInt{False{}, mm.mask64(U32.sub(bits, 1))}",
   "def bnd.smax(+bits: U32) -> Bnd: BndInt{False{}, mm.mask64(bits)}",
   "a signed max is 2**(bits-1) - 1, so the mask is one bit NARROWER than the width"),
  ("DT4", "case S.Dt{7, 64, S.CSint{}, _}: bnd_int(top, True{}, 64)",
   "case S.Dt{7, 64, S.CSint{}, _}: bnd_int(top, False{}, 64)",
   "int64 read as UNSIGNED -- the pair that makes the two-word answer look plausible"),
  ("DT5", "case S.Dt{10, 8, S.CFloat{}, \"float8_e4m3\"}: bnd_fmax(top, 448n)",
   "case S.Dt{10, 8, S.CFloat{}, \"float8_e4m3\"}: bnd_fmax(top, 240n)",
   "the fp8 maxima are 448 / 240 / 57344 and swapping two of them is invisible by eye"),
  ("DT6", "case S.Dt{11, 8, S.CFloat{}, \"float8_e5m2fnuz\"}: bnd_fmax(top, 57344n)",
   "case S.Dt{11, 8, S.CFloat{}, \"float8_e5m2fnuz\"}: bnd_fmax(top, 32768n)",
   "57344 = 1.75 * 2**15, so 32768 is the nearest power of two and is exactly the mistake "
   "an arithmetic derivation would make instead of reading the table"),
  ("DT7", "Bool.pick(Bnd, top, bnd_f(F32.from_nat(m)), bnd_f(F32.neg(F32.from_nat(m))))",
   "Bool.pick(Bnd, top, bnd_f(F32.from_nat(m)), bnd_f(F32.from_nat(0n)))",
   "a float dtype's minimum is `-self.max` and not 0; a bound that is too HIGH is not sound"),
  ("DT8", "case S.Dt{0, 800, S.CWeakInt{}, _}: bnd_int(top, True{}, 800)",
   "case S.Dt{0, 800, S.CWeakInt{}, _}: bnd_int(top, True{}, 64)",
   "weakint's 800-bit width narrowed to 64, which is exactly what makes the guard unnecessary"),
  ("DT9", "def bnd_bool(+top: Bool) -> Bnd:\n  bnd_i(False{}, Bool.pick(H.I64, top, H.i64_of_hi_lo(0, 1), H.i64_of_hi_lo(0, 0)))",
   "def bnd_bool(+top: Bool) -> Bnd:\n  bnd_i(False{}, Bool.pick(H.I64, top, H.i64_of_hi_lo(0, 0), H.i64_of_hi_lo(0, 1)))",
   "`bool`/`void` answer False/True, so min is 0 and max is 1 -- NOT the reverse"),
  ("DT10", "case S.Dt{0, 1, S.CBool{}, _}: bnd_bool(top)\n    case S.Dt{0, 0, S.CVoid{}, _}: bnd_bool(top)",
   "case S.Dt{0, 1, S.CBool{}, _}: bnd_int(top, True{}, 1)\n    case S.Dt{0, 0, S.CVoid{}, _}: bnd_bool(top)",
   "`bool` read as a 1-BIT SIGNED integer, whose minimum is -1 -- the wrong-over-"
   "approximation trap in the other direction"),
  ("DT11", "case S.Dt{12, 16, S.CFloat{}, _}: bnd_flt(top)",
   "case S.Dt{12, 16, S.CFloat{}, _}: bnd_fmax(top, 65504n)",
   "float16's max is `inf`, not 65504: the biggest FINITE half is the classic wrong answer"),
]


def run(extra=()):
  r = subprocess.run([BEND, WORK, *extra], capture_output=True, text=True)
  return r.stdout, (r.stdout + r.stderr).splitlines()[0] if (r.stdout + r.stderr).splitlines() else '<no output>'


def rows():
  return dict(l.split(' ', 1) for l in run()[0].splitlines() if ' ' in l)


def cp_rows():
  env = dict(os.environ, TG_TREE=TG_TREE)
  bl = subprocess.run([sys.executable, '.agents/slop/mm-bl-gate.py'], capture_output=True, text=True, env=env).stdout
  dt = subprocess.run([sys.executable, '.agents/slop/mm-dt-gate.py'], capture_output=True, text=True, env=env).stdout
  return dict(l.split(' ', 1) for l in (bl + dt).splitlines() if ' ' in l)


def main():
  src = open(WORK).read()
  snapshot = src
  base_bend, base_cp = rows(), cp_rows()
  base_check = run(('--check-only',))[1]
  if not base_bend:
    print("BASELINE IS EMPTY -- restoring the snapshot and refusing to run")
    open(WORK, 'w').write(snapshot)
    return 1
  print(f"baseline: {len(base_bend)} bend rows, {len(base_cp)} CPython rows, {base_check!r}")
  # Only THIS unit's 58 rows have a CPython oracle here. The other 88 are the 99
  # committed rows, which diff against their own oracles (fold-mvt-oracle.py, the fold
  # harness) and are simply compared BETWEEN RUNS -- which is all a mutation needs.
  mine = {k: v for k, v in base_bend.items() if k.startswith('bl_')}
  if mine != base_cp:
    bad = {k: (mine.get(k), base_cp.get(k)) for k in base_cp if mine.get(k) != base_cp.get(k)}
    print(f"  BASELINE DISAGREES on {len(bad)}: {list(bad)[:4]}")
    for k, v in list(bad.items())[:6]:
      print(f"    {k}: bend={v[0]!r} cp={v[1]!r}")
    return 1
  print(f"  baseline clean: all {len(mine)} of this unit's rows agree with CPython; "
        f"{len(base_bend) - len(mine)} committed rows carried\n")

  moved_total = 0
  for label, old, new, why in MUT:
    if src.count(old) != 1:
      print(f"{label:5s} SKIP -- pattern occurs {src.count(old)}x, not 1")
      continue
    open(WORK, 'w').write(src.replace(old, new))
    time.sleep(0.2)
    got = rows()
    chk = run(('--check-only',))[1]
    moved = sorted(k for k in base_bend if got.get(k) != base_bend[k])
    lost = sorted(k for k in base_bend if k not in got)
    chk_note = "" if chk == base_check else f" [{chk!r}]"
    moved_total += len(moved)
    print(f"{label:5s} moved {len(moved):3d}{chk_note}  {' '.join(moved[:8])}{' ...' if len(moved) > 8 else ''}")
    print(f"      {why}")
    open(WORK, 'w').write(src)
    time.sleep(0.2)

  # settle and confirm the file is byte-identical to where it started
  if rows() != base_bend:
    diff = [k for k in base_bend if rows().get(k) != base_bend[k]]
    print(f"  DID NOT SETTLE: {diff[:6]}")
    return 1
  print(f"\nfile restored byte-identical; {moved_total} row-moves over {len(MUT)} mutations")
  return 0


if __name__ == '__main__':
  sys.exit(main())
