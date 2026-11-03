census: `:316` added with the `fits` primitive, VERIFIED against CPython (131 PORTED / 0 BROKEN / 4 MISSING)

`symbolic.py:316` -- `x*-1 < c  ->  -c < x  if fits(x, -c.vmin)` -- was blocked on a PRIMITIVE, not a
line, and the primitive is `symbolic.py:32`:

    def fits(x:UOp, v:PyConst) -> bool: return x.dtype not in dtypes.sints or x.dtype.min <= v <= x.dtype.max

It is called TWELVE times in that file and the port had no spelling of it at all (`rg 'def .*fits'`
answered only `ci_fits`, the i32 LANE test in `exec_alu`, which is a different question). It is now
`fits(+dt, +v: I64)`: `S.Dt.min`/`S.Dt.max` carry the bound's MAGNITUDE and answer `None` past 32
bits, where the I64 carries its own range and the half-test is vacuous rather than false.

**TWO THINGS THE PROBE PINNED, AND NEITHER IS OBVIOUS FROM THE SOURCE:**

  1. `-c` IS NOT A FOLDED CONSTANT. CPython 316 answers `CMPLT(CAST(MUL(3,-1), i32), x)` for
     `x*-1 < 3` -- it MINTS the multiplication and lets the comparison's promotion cast it. A port
     that mints `CONST(-3)` answers a DIFFERENT GRAPH that typechecks.
  2. THE GUARD IS THE RULE. For `c == dtype.min` the negation leaves the dtype and the rewrite is
     wrong; `fits(x, -c.vmin)` is what refuses it.

VERIFIED, BOTH SIDES, via `.agents/slop/sym92/probe-316.bend` and `probe-316.py` (the CPython half
runs the VENDORED tinygrad at HEAD through its own `symbolic.sym`, so the two renders answer one
question):

    x*-1 < 3            port `(cmplt (mul c3 n1) x)`    CPython `CMPLT(CAST(MUL(3,-1)), x)`   AGREE
    x*-1 < -1           port `(cmplt (mul n1 n1) x)`    CPython `CMPLT(CAST(MUL(-1,-1)), x)`  AGREE
    x*-1 < int32.min    port `bf` (CONST False)         CPython `CONST(False)`               AGREE

The third is the one that matters: it is the case the guard exists for, and BOTH SIDES DECLINE the
rule and fold through the range instead. A guard that never refuses is a label, and this one refuses.

TWO BUGS OF MY OWN, BOTH FOUND BY THE PROBE AND NOT BY THE COMPILER: `p_const` takes the NODE and I
passed it a child index, so the pattern's second half was false and the rule was dead on arrival
(`direct_316c=norewrite`, `pat_316c=False`); and a minting tag must be in `MINT_TAGS` or
`sym_dispatch_f` never calls the mint lane at all, so the rule fired when called directly and never
through the table. **A RULE THAT COMPILES AND A RULE THAT FIRES ARE TWO DIFFERENT MEASUREMENTS.**

STATE: **131 PORTED, 0 BROKEN, 4 MISSING** of 135 rows. `symrules-gate` 0 problems;
`symclosure-gate`'s four structural rows green (129 rows, 129 distinct tags, mint 98 == MINT_TAGS 98).

REMAINING, all four walls and each named: `divandmod.py:103` (`UOp.simplify`+`gcd`+`divide_exact`,
`usum` cycle), `:450`/`:451` (`simplify_valid`'s `# late import!`), `:476` (STORE with where/invalid).
