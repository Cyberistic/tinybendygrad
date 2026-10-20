# FINDINGS -- the four float-conversion defects, and what is next to them

Unit: the four defects in `tinybendygrad/runtime/dtype.js` (commit `636e797cb`).
Every number below was MEASURED with the command named beside it, on the date named in
the report; nothing here is read off a diff.

## 1. THE HALF NaN CLASS: THE C LANE AGREES WITH CPYTHON AND THE JS LANE DOES NOT

`gates/subnormal-flush-gate.py` drives the half SUBNORMALS and the f32->half subnormal
band.  `gates/js-lane-census.py` drives `range(0x402)`.  So the half NaNs -- 0x7c01..
0x7fff and 0xfc01..0xffff -- are driven by NOTHING, and the three lanes spell that class
three ways:

  `dtype.c:172`   `| (m ? 0x400000u : 0u)`      -- the quiet bit only
  `dtype.js:164`  `| (m << 13)`                 -- the whole payload
  `dtype.bend:736`| (m << 13)                   -- the whole payload

MEASURED, `.venv/bin/python .agents/slop/floatfix/measure-nan-class.py`, 2026-10-20:

  half -> f32 : js-vs-oracle 2044/2046 | c-vs-oracle 0/2046 | js-vs-c 2044/2046
      h2f_7c01: oracle=7fc00000 js=7f802000 c=7fc00000
      h2f_7e00: oracle=7fc00000 js=7fc00000 c=7fc00000
      h2f_7fff: oracle=7fc00000 js=7fffe000 c=7fc00000
  f32 -> half : js-vs-oracle 0/128 | c-vs-oracle 0/128 | js-vs-c 0/128

So the C lane is the one that matches CPython's own codec on this class, and the JS lane
and the BEND agree with EACH OTHER and not with the oracle.  `dtype.bend:731-733` calls
the C's quiet-bit-only rule "the same payload loss from the other side", i.e. the BEND
believes the payload survives.  On the class as CPython spells it, it does not.

NOT FIXED HERE, and the reason is not that it is hard: the C and the BEND DISAGREE with
each other, so there is no single spelling already in the tree for the JS to match, and
the brief this unit answered named FOUR defects.  The two lanes' disagreement is
confined to the WHITE-BOX `half_to_f32`; the seam path (`Dt.fp16` = `f16_bits` then
`half_to_f32`) agrees, because `f16_bits` reduces every NaN to the quiet bit first --
`gates/js-lane-census.py --quick` reads 0 disagreements in the `fp16` class.

## 2. THE SIBLING GATE'S "RULE js" DISPLAY ROW IS KEYED ON THE PRE-FIX TEXT

`gates/subnormal-flush-gate.py:355` prints the JS lane's rule by grepping the source for
the literal `103 << 23`.  That literal IS the defect: the correct rule's exponent is
`k + 103`, so no correct spelling of the line contains `103 << 23`.  After the fix the
row prints `RULE js (dtype.js:145): NOT FOUND`.

That row is a PROSE row -- the verdict is the disagreement count, and it is 0/2200 -- but
it is a display row keyed on a literal that is only true of the broken tree, which is
the `checks/no-txt.py` / `artefacts_ok()` shape: a row that cannot find its subject
because the subject moved.

## 3. THE ARMS THAT PLANT THESE FOUR DEFECTS NOW REFUSE, AND THAT IS THE FIX LANDING

`gates/js-lane-census.py` (13 arms) and `gates/subnormal-flush-gate.py` (6 arms) plant a
defect by REPLACING its text in a copy of the lane, and each anchor is the defect
itself: `>>> (27 - ue)`, `((s | (103 << 23) | (m << 14)) >>> 0)`,
`function dtype_bf16(u) {\n  return of32(`.  After the fix those anchors are GONE, so
nine census arms and four flush-gate arms answer `REFUSED` (exit 3) -- "a precondition
was absent" -- which is the tree's own word for the defect no longer being there.

The falsifiability those arms carried is replaced by `gates/float-injectivity-gate.py`,
whose arms are anchored on the FIXED text: `norm-plant` gives the fixed shift back
(distinct 1023 -> 512, disagreements 0 -> 2046), `norm-disarm` re-spells the same line
(nothing moves), and `clz-plant` takes the leading bit one lower (the map stays a map,
the values do not).
