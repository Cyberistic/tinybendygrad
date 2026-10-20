js-lane: the four float-conversion defects, and the injectivity they cost

dtype.js was the odd lane out on EVERY row of the f16 subnormal class: the C lane
and CPython's own codec agree on all 2200 of them, and the JS lane agreed on none.
Four defects, each with a one-line fix that the C lane and dtype.bend already spell:

  1. half_to_f32's subnormal arm used a FIXED `m << 14`, which assumes the 10-bit
     mantissa is already normalised.  It is not: the exponent is the position of
     the mantissa's leading bit (dtype.c:175) and the fraction is shifted left by
     `23 - k` to put it there (dtype.c:176).  The fixed shift collapsed the 1023
     positive half subnormals onto 512 distinct f32 patterns -- 511 collisions, m=1
     and m=513 sharing one -- where the correct rule maps them onto 1023.
  2. f16_bits' subnormal SHIFT COUNT was `27 - ue` where the C writes `14 - exp`
     (dtype.c:153): thirteen bits too wide, and `>>>` takes its count mod 32, so
     ue = -5 shifted by ZERO.
  3. f16_bits' subnormal arm had no ROUND-HALF-TO-EVEN on the dropped bits, which
     dtype.c:155-157 and dtype.bend:648 both have.
  4. dtype_bf16 rounded a non-finite instead of handing it back untouched, which is
     what dtype.py:230 does, so a NaN's payload and its sign survive
     (dtype.c:205, dtype.bend:609).

MEASURED 2026-10-20 with .venv/bin/python:

  gates/subnormal-flush-gate.py    js-vs-oracle 2200/2200 -> 0/2200, c-vs-oracle
                                   0/2200, js-vs-c 2200/2200 -> 0/2200, PASS
  gates/js-lane-census.py --quick   DISAGREE 1194/8328 -> 0/8328, PASS
  gates/float-injectivity-gate.py   distinct f32 patterns over the 1023 positive
                                   half subnormals 512 -> 1023, and disagreements
                                   against the oracle 0 -> 0

The new gate is the injectivity measurement, and it carries three arms: a plant that
gives the fixed shift back (distinct 1023 -> 512, disagreements 0 -> 2046), a control
that re-spells the same line (nothing moves), and a plant that takes the leading bit
one lower (the map stays a map, the values do not).  The census's own arms for the
four defects now REFUSE, because their anchor IS the defect; that refusal is the
fix landing, and this gate is what keeps the class falsifiable.

SUBSTRATE: the digest moves, because tinybendygrad/ is inside SUBSTRATE_WALKS.

  8c377cb28e25d5e77fd3f224fa3038e0cb49a9eba88eb8c3215d1c8b87a0e2eb  dtype.js at HEAD
  d6ac65388e8962998319126c33a9a4c00da3a1b765da58244a730cec309cb380  this edit

The corpus run of 2026-10-20T14:34:07Z measured 8dc8b786..., which is neither, so
it was already stale before this edit and is NOT re-run here.
