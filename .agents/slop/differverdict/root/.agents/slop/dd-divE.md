# dd-divE — the eight `c{i}` fixtures, closed 7/8 and made visible on the 8th

`.agents/slop/dd-oracle.py` prints `c{i}=F(<f32 bits>)` for the eight `CLAMP_DTS`
(`dd-oracle.py:456-457`), which is `f2f_clamp`'s `mx` constant — `tinygrad/codegen/
decomp/dtype.py:131`. The port printed **none** of them, for weeks, unowned.

## What the port actually had

Not an unimplemented spec. `dd_lab.node` at `dtype.bend:1734` is the float-CONST
renderer and it emits exactly the oracle's format:

    case O.APy{O.CFloat{f}}: String.concat(["F(", U32.show(F32.bits(f)), ")"])

and `dd_cval` at 1713-1723 is the integer one. `C(mag)` and `C(hi:lo)` are real and
present. The gap was that **nothing in the gate ever reached a float const**, so the
float half of `dtype.py` — `f2f`, `f2f_clamp`, `rne`, `reindex`, `l2i_define`, the
three pattern tables — contributes 0 of 252 oracle-only rows. All 164 printed rows are
`l2i` + `unpack32`.

## Two real bugs, both in `f2f_clamp_max.put` (dtype.bend:1165-1177)

`dtype.py:129-130` is **two predicates, not one**:

    if dt in dtypes.fp8_fnuz: max_exp, max_man = (1 << e) - 1, (1 << m) - 1
    else: max_exp, max_man = ((1 << e) - 1, (1 << m) - 2) if dt == dtypes.fp8e4m3 else ((1 << e) - 2, (1 << m) - 1)

  * `max_exp` is `(1 << e) - 1` for fnuz-and-e4m3. The port used `Bool.pick(..., ocp, 0, 2)`,
    subtracting **0** on that branch.
  * `max_man` is `(1 << m) - 2` for `fp8e4m3` **alone**. The port used `ocp` again, so both
    fnuz layouts got `- 2` instead of `- 1`.

All seven reachable values were wrong; `c6` was off by one ulp (`0x7F7FFFFE` vs `0x7F7FFFFF`)
and the two errors cancelled on the fnuz dtypes, which is why nothing noticed.

## The eighth, and why the ORACLE is the under-determined side

`mx` is `val.const_like(...)`, so its value depends on `fr` too. Called, in
`dd-divE-probe.py`:

    f2f_clamp(f32_val, float64) -> mx = inf     -> F(2139095040)
    f2f_clamp(f64_val, float64) -> mx = 1.8e308 -> F(ovf)   (outside f32, struct raises)

`c0..c6` are the same number under both `fr`, which is why the row is well posed for seven of
the eight. For `c7` the oracle's row is a function of `dt` alone and has no single answer; the
fresh run prints `F(ovf)`, the saved baseline prints `F(2139095040)`, and **both are correct
CPython output** — for different `fr`. That is the one disagreement between the fresh oracle
and `.agents/slop/dd-oracle.txt`, not a hand-typed constant.

`dd-oracle.py`'s `clamp_mx` drops `const_like`, which is a reimplementation of
`dtype.py:128-131` in a file whose header says "nothing here is a reimplementation of it".

The port now prints `c7=refused:unported`, so the name exists in both lanes with different
values: one disagreement, counted, instead of eight absences, uncounted.

## Evidence, before and after

Three independent methods agree on the same seven numbers, and the gate rows were proven to
fail before the fix and pass after it:

  * `.agents/slop/dd-divE-probe.bend` calls the port's own `f2f_clamp_max` and prints the
    gate's exact `F(...)` strings. **2.3 seconds**, against a 4.5-7 minute gate run.
  * `.agents/slop/dd-divE-math.py` evaluates both formulas in Python and attributes the
    difference per factor.
  * `.agents/slop/dd-divE-prefix-bug.txt` is a real gate run of a COPY of the tree with the
    two factor lines reverted. It is a HEALTHY run (`worse-than-known-good sig/k=0`) and it
    reports **7 of 8 c-rows FAIL**.

| row | before (bug present) | after (fixed) | CPython, called |
|---|---|---|---|
| c0 fp8e4m3 | F(1149239296) | F(1138753536) | F(1138753536) = 448.0 |
| c1 fp8e4m3fnuz | F(1140850688) | F(1131413504) | F(1131413504) = 240.0 |
| c2 fp8e5m2 | F(1195376640) | F(1197473792) | F(1197473792) = 57344.0 |
| c3 fp8e5m2fnuz | F(1207959552) | F(1197473792) | F(1197473792) = 57344.0 |
| c4 f16 | F(1199554560) | F(1199562752) | F(1199562752) = 65504.0 |
| c5 bf16 | F(2138963968) | F(2139029504) | F(2139029504) = 2^127*(1+127/128) |
| c6 f32 | F(2139095038) | F(2139095039) | F(2139095039) = 0x7F7FFFFF |
| c7 f64 | refused:unported | refused:unported | `F(ovf)` / `F(2139095040)`, see above |

Note `c2` and `c3` are the SAME number in CPython (57344.0 by two different routes: OCP's
`(1<<e)-2` exponent with bias 15, fnuz's `(1<<e)-1` with bias 16) and the port had them
2.28x apart. That pair is the fixture; nothing else in the file separates `fp8e5m2` from
`fp8e5m2fnuz`.

## Row-count delta

    gate rows      164 -> 172   (+8, the c{i} rows)
    names shared with the oracle   164 -> 172   of 416  (39.4% -> 41.3%)
    c-rows agreeing with CPython      0 ->   7
    c-rows disagreeing on purpose     0 ->   1   (c7, named, not absent)

## Files

  * `dd-divE-probe.py` — CALLS `DD.f2f_clamp` for the eight targets at both `fr`, so the
    `c7` ambiguity is a measurement rather than an argument.
  * `dd-divE-probe.bend` — calls the port's `f2f_clamp_max` for the same eight.
  * `dd-divE-math.py` — the two formulas side by side, to name which factor is wrong.
  * `dd-divE-check.py` — the checker. **`dd-cmp.py` cannot see this gap**: it compares
    `keys = [k for k in port if k in ora]`, so a row absent from the port lane is never
    compared and eight missing fixtures read exactly like eight passing ones.
  * `dd-divE-run.sh` — run-health guard; self-tested `ok: healthy run on attempt 1`.
  * `dd-divE-prefix-bug.txt` — the FAIL-BEFORE capture (bug reverted in a copy of the tree).
  * `dd-divE-after.txt` / `dd-divE-rows-degraded.txt` — the PASS-AFTER capture and a
    stack-overflowed run of the same code, kept because the pair is the evidence that a
    degraded run is indistinguishable from a passing one by row count alone.