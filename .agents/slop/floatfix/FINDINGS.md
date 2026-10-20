# FINDINGS -- the four float-conversion defects, and what is next to them

Unit: the four defects in `tinybendygrad/runtime/dtype.js` (commit `636e797cb`), and the
fifth one found beside them (commit `2eda0063e` and the one after it).  Every number
below was MEASURED with the command named beside it; nothing here is read off a diff.

## 0. THE BRIEF'S PREMISE IS FALSE, AND IT MATTERS: `dtype.bend` IS NOT A CORRECT LANE

The brief said "the C version AND the Bend version are correct", and the four fixes
were to be spelled "in C AND in Bend".  **The two disagree, and the C is the one that
agrees with CPython.**  `dtype.bend:711-715` computes the f32 exponent of a half
subnormal as `(31 - U32.log2(m)) + 103`, and bend2's stdlib `U32.log2`
(`references/bend/bend2/base.bend:1544`) is `floor(log2 n)` -- NOT the C's
`__builtin_clz`, which is `31 - floor(log2 n)`.  `dtype.bend:708-710` asserts the
opposite ("`U32.log2` stands in for the C's `__builtin_clz`"), and the brief's own hint
contains the contradiction: it says the Bend's `31 - floor(log2 m)` IS `Math.clz32(m)`,
while the C's `k` is `floor(log2 m)`.

MEASURED, `.venv/bin/python .agents/slop/floatfix/measure-bend-lane.py`, 2026-10-20, on
the bend2 EMITTER's own output for the live `tinybendygrad/dtype.bend`
(`checks/gen/probe.js`):

  BEND half->f32 (fp16_f32, white-box), 2046 half subnormals: 2046 disagree with CPython
      h2f_1: oracle=33800000 bend=43000000     <- 128.0 where the answer is 2**-24
  BEND f32->half (fp16_encode, white-box), 77 band patterns: 0 disagree with CPython
  BEND f32->half (Dt.fp16, THE SEAM), 77 band patterns: 75 disagree with CPython
      seam_33000001: oracle=33800000 bend=43000000
  BEND Dt.fp16 over 64 f32 NaN patterns (both ends of the mantissa): 32 disagree
  BEND half->f32 distinct f32 patterns over the 1023 positive half subnormals: 1023

So the Bend's ENCODE side is right on the subnormal band, its DECODE side is wrong by a
factor of 2**(31 - 2*log2 m) -- 2**31 at m = 1 -- and the Bend's `Dt.fp16` is wrong on 75
of the 77 f32->half subnormal-band patterns.  The Bend's map is INJECTIVE (1023
distinct), so this is a VALUE defect, not the injectivity defect the JS had.  And the
Bend's NaN arm keeps the payload in BOTH directions (`dtype.bend:698-701` on the way in,
`:736` on the way out) where CPython canonicalises: the 32 disagreements above are
exactly the high-mantissa NaNs, the 32 low-mantissa ones agreeing only because
`m >> 13` is 0 there.

THE FIX, MEASURED: `.venv/bin/python .agents/slop/floatfix/measure-bend-fix.py` applies
one token to a COPY of the emitted bundle -- the `31 -` dropped from
`dtype.bend:713` -- and re-measures:

  AS EMITTED                 disagree with CPython 2046/2046 | h2f_1 = 43000000
  WITH THE `31 -` DROPPED    disagree with CPython 0/2046     | h2f_1 = 33800000

**NOT APPLIED**: `tinybendygrad/dtype.bend` is not in this unit's grant, and the brief
says "DO NOT EDIT ANY OTHER `.bend` FILE".  The one-token fix is
`dtype.bend:713`, `U32.sub(31, U32.from_nat(U32.log2(m)))` -> `U32.from_nat(U32.log2(m))`,
and the comment at `dtype.bend:708-710` has to go with it.  A full `bend` RECOMPILE was
not run: the fix was measured on the emitted JS, which is the Bend's own arithmetic with
one token dropped, and not on a fresh compilation of the patched source.

## 1. THE HALF NaN CLASS, AND THE FIFTH DEFECT IT FOUND IN THE JS

`gates/subnormal-flush-gate.py` drives the half SUBNORMALS and the f32->half subnormal
band.  `gates/js-lane-census.py` drives `range(0x402)`.  So the half NaNs -- 0x7c01..
0x7fff and 0xfc01..0xffff -- are driven by NOTHING, and the three lanes spelled that
class three ways: `dtype.c:172` keeps only the quiet bit, `dtype.js` and `dtype.bend:736`
kept the whole payload.

MEASURED, `.venv/bin/python .agents/slop/floatfix/measure-nan-class.py`, 2026-10-20:

  BEFORE the fifth fix:
      half -> f32 : js-vs-oracle 2044/2046 | c-vs-oracle 0/2046 | js-vs-c 2044/2046
          h2f_7c01: oracle=7fc00000 js=7f802000 c=7fc00000
  AFTER the fifth fix:
      half -> f32 : js-vs-oracle 0/2046 | c-vs-oracle 0/2046 | js-vs-c 0/2046
      f32 -> half : js-vs-oracle 0/128 | c-vs-oracle 0/128 | js-vs-c 0/128

CPython's codec CANONICALISES every half NaN to the one f32 NaN per sign, and the C
lane already did that.  The JS lane did not, and the JS's own ENCODE arm already
dropped the payload (it matched the C and CPython there), so the file was inconsistent
with ITSELF about the payload: it dropped it one way and kept it the other.  The fifth
fix is one line -- `dtype.js`'s NaN arm now reads
`((s | 0x7f800000 | (m ? 0x400000 : 0)) >>> 0)`, which is `dtype.c:172` -- and
`gates/float-halfclass-gate.py` now HOLDS the class, with the property the class has:
the map must NOT be injective there, because CPython answers 2 patterns and not 2046.

## 2. THE SIBLING GATE'S "RULE js" DISPLAY ROW IS KEYED ON THE PRE-FIX TEXT

`gates/subnormal-flush-gate.py:355` prints the JS lane's rule by grepping the source for
the literal `103 << 23`.  That literal IS the defect: the correct rule's exponent is
`k + 103`, so no correct spelling of the line contains `103 << 23`.  After the fix the
row prints `RULE js (dtype.js:145): NOT FOUND`.

That row is a PROSE row -- the verdict is the disagreement count, and it is 0/2200 -- but
it is a display row keyed on a literal that is only true of the broken tree, which is
the `artefacts_ok()` shape: a row that cannot find its subject because the subject moved.

## 3. THE ARMS THAT PLANT THESE DEFECTS NOW REFUSE, AND THAT IS THE FIX LANDING

`gates/js-lane-census.py` (13 arms) and `gates/subnormal-flush-gate.py` (6 arms) plant a
defect by REPLACING its text in a copy of the lane, and each anchor is the defect
itself: `>>> (27 - ue)`, `((s | (103 << 23) | (m << 14)) >>> 0)`,
`function dtype_bf16(u) {\n  return of32(`.  After the fix those anchors are GONE, so
nine census arms and four flush-gate arms answer `REFUSED` (exit 3) -- "a precondition
was absent" -- which is the tree's own word for the defect no longer being there.

The falsifiability those arms carried is replaced by `gates/float-halfclass-gate.py`,
whose arms are anchored on the FIXED text: `norm-plant` gives the fixed shift back
(h2s distinct 1023 -> 512 over the positive class, disagreements 0 -> 2046),
`norm-disarm` re-spells the same line (nothing moves), `nan-plant` carries the NaN
payload again (h2n distinct 2 -> 2046, disagreements 0 -> 2044), and `nan-disarm`
re-spells that line (nothing moves).
