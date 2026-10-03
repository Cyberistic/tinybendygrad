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

## Files

  * `dd-divE-probe.py` — CALLS `DD.f2f_clamp` for the eight targets at both `fr`, so the
    `c7` ambiguity is a measurement rather than an argument.
  * `dd-divE-probe.bend` — calls the port's `f2f_clamp_max` for the same eight.
  * `dd-divE-math.py` — the two formulas side by side, to name which factor is wrong.
  * `dd-divE-check.py` — the checker. **`dd-cmp.py` cannot see this gap**: it compares
    `keys = [k for k in port if k in ora]`, so a row absent from the port lane is never
    compared and eight missing fixtures read exactly like eight passing ones.
  * `dd-divE-run.sh` — run-health guard; see the note on empty cone walks.