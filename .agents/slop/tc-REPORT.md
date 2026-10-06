# STAGE TABLE — `codegen/decomp/transcendental.bend`

| # | STAGE | STATE | EVIDENCE |
|---|-------|-------|----------|
| 0 | stub first, before reading anything | DONE | first `--check-only` = `ALL PROOFS CHECK` on a 7-line file |
| 1 | read `agent-core.md`, `agent-core`'s constraints index | DONE | |
| 2 | read `tinygrad/codegen/decomp/transcendental.py` (277 lines) | DONE | |
| 3 | **discover the existing port** | DONE | `tinybendygrad/codegen/transcendental.bend` (TODO round 4, 891 rows) ports the GRAPH; TODO leaves the float64 coefficients "NOT independently verified". This file is that missing half. |
| 4 | prove the float32 lane is expressible | DONE | `F32.bits(F32.read(repr))` == `struct.pack('<f', …)`; all 12 F32 arithmetic probes bit-exact |
| 5 | coefficient authority, by CALLING tinygrad | DONE | `.agents/slop/tc-audit.txt`, 146 constants, 3 channels (polyN spy, `shr`/`shl` spy, source eval) |
| 6 | value oracle, by CALLING tinygrad | DONE | `oracles/tc-rows-value.txt`, 558 rows, `DEV=PYTHON`, `Tensor(tinygrad_fn(uop)).numpy()` |
| 7 | coefficient rows generated into the Bend source | DONE | `tc-gen.py`; **no digit in the file is mine** |
| 8 | port the value layer | DONE (partial — see GAPS) | `ALL PROOFS CHECK`, 1164 lines, 194 defs/types, 737 rows printed |
| 9 | two-lane diff | PARTIAL | `.agents/slop/tc-diff.py`, whole `name=value` lines |
| 10 | mutation table | **NOT RUN** | `tc-mutate.py` written (32 entries); a run is ~8 min and the budget is gone |

# COEFFICIENT AUDIT — every constant, and the authority for each

Authority codes: **SPY** = tinygrad passed it to `polyN` itself (the module
attribute was replaced, so the list is tinygrad's, not a transcription of the
source). **SRC** = tinygrad's own source text at that line was located by
(line, needle) and EVALUATED. **DT** = `dtypes.finfo` / `dtypes.fp8_fnuz` CALLED.

All 146 are in `.agents/slop/tc-audit.txt` with `repr` (col 2), `float.hex()`
(col 3), the f32 bits (col 4) and the f32 hex (col 5).

| group | n | authority | audited |
|---|---|---|---|
| `sin_poly` coeff32 / coeff64 | 5 + 10 | SPY | 15/15 |
| `xexp2` coeff32 / coeff64 | 7 + 12 | SPY | 19/19 |
| `xlog2` coeff32 / coeff64 | 3 + 7 | SPY | 10/10 |
| `two_over_pi_f` | 7 | SRC (:77) | 7/7 |
| `frexp` m1 / m2, f32/f64/f16 | 6 | SRC (:56-57) | 6/6 |
| `cody_waite` PI_A..PI_D | 4 | SRC (:125) | 4/4 |
| `cody_waite` f32 pi0..pi3 | 4 | SRC (:138-141) | 4/4 |
| `m_1_pi`, `2**24`, `4.294967296e9`, `3.4061215800865545e-19`, `2**62`, the :109 mask, `_take` window | 7 | SRC | 7/7 |
| `log2(e)` f64 / f32, `s_lo`, `1/0.75`, `denormal_exp` ×2 | 6 | SRC | 6/6 |
| `FLT_MIN` ×3, `xexp2` bounds ×6 | 9 | SRC | 9/9 |
| `mantissa_bits` / `exponent_bias` / `exponent_mask` × 3 dtypes | 9 | DT | 9/9 |
| `two_over_075`, `switch_over`, `pi/2`, `pi_a..pi_d`, port constructions | 10 | SRC | 10/10 |
| the 17 shift/shrink amounts | 17 | SPY on `shr`/`shl` | 17/17, **all Python ints, all integer shifts** |
| the dtype tables of :24/:29/:35/:42/:58 | 17 | SRC | 17/17 |

**No coefficient was wrong in the PORT.** The gate found two real defects and
they are reported rather than fixed:

1. **`xf_pi_a`: bend 1078530011, CPython 1078530010 — ONE ULP.**
   `PI_A` is `3.1415926218032836914`; `F32.read("3.1415926218032837")` (the
   `repr` CPython printed) lands one ULP above `F32.read` of the full literal.
   This is a real `F32.read`-vs-`struct.pack` disagreement and it is exactly the
   class of thing the brief said this file exists to find.
2. **`xf_xexp2_lo_32` / `xf_xexp2_up_32`: type mismatch, not an error.** The
   generator emits the INTEGER (`-150`, `128`) and the port stores the f32
   bits. Same constant, two spellings.

**THE HEX CROSS-CHECK, and the two constants only it separates.**
`tc-audit.txt` col 3 is `float.hex()` for all 146. Two float64 constants share an
f32 rounding with a float32 sibling, so **every f32 row is blind to the
difference between them** and only the `cd_*` decimal row separates them:
- `xlog2.neg_log2e_f64 = 0x1.71547652b82fep+1` vs `neg_log2e_f32 =
  0x1.7154760000000p+1` — both 1077455419 / `0x4038aa3b`.
- `xexp2.coeff64[10] = 0.6931471805599453` vs `coeff32[5] = 0.6931471825` —
  both 1060205080 / `0x3f317218`.
- `FLT_MIN[float32]` and `[float64]` are BOTH `1e-4`; tinygrad really does write
  it twice.

# BOUNDARY / EDGE ROWS ADDED, PER RULE

| rule | boundary pair | other edges |
|---|---|---|
| `xexp2` :213 | `128.0` → +inf vs `127.99999` → finite; `128.00001` | `200.0`, `100000.0` |
| `xexp2` :215 | `-150.0` → 0 vs `-149.99999` → **1** (the smallest denormal) | `-150.00001`, `-200.0`, `-100000.0` |
| `xexp2` :217 | `d.ne(d)` over ±inf, NaN, ±0 | |
| `xlog2` :228 | `0.0001` (FLT_MIN) vs `9.999e-05` vs `0.00010001` | `1e-30`, `3e-40` (a true f32 denormal) |
| `xlog2` :247/249/251/253/255 | `+0.0` AND `-0.0` each; `-1.0`; ±inf; NaN | `0.25`, `1024.0` |
| `xsin` :187 | `30.0` vs `29.999998` vs `30.000002` (switch_over) | `±0.0`, `±1.0`, `π/2`, `π`, `2π`, `±100.0` |
| `_lazy_map_numbers` :9-11 | one row per arm with DISTINCT replacements (7, -7, 9, 3) | ±inf, NaN, ±0.0, ±1.0 |
| `pow2if` :27-30 | `0`, `±1`, `±10`, `±126` (both field ends) | |
| `rintk` :22-25 | `±0.5`, `±2.5`, `1e7` | `±0.0`, `±0.4` |
| `frexp` :52-63 | `1.0` (field 127), `1024.0` (field 137), `-2.5` (sign bit) | `0.5`, `1.5`, `3.0` |
| `cody_waite` :115-147 | `0.0`, `39800.0` (the documented upper edge), `-100.0` (negative quadrant) | `30.0`, `100.0` |
| `sin_poly_small/large` :160-166 | `q = 0,1,2,3,4` (every quadrant) | `π/2` with `q = 1,2` |
| `xpow` :257-265 | `0.0_0.0` (0**0), `inf_0.0` (inf**0), `0.0_5.0`, `0.0_-1.0`, `-0.0_3.0`, `-0.0_-3.0` | 15 predicate fixtures |
| `shr`/`shl` :19-20 | `0xffffffff` (unsigned floor-div, not a shift), `0x7fffffff` | `1, 2, 255, 256` |
| `ldexp2k`/`ldexp3k` | `e = 0`, `e = -2`, `e = +3`, `e = +5` | |

# THE GATE TABLE, traced to my own CPython runs

Two lanes, byte-identical expectations, whole `name=value` lines:

| lane | rows | agree | disagree | missing |
|---|---|---|---|---|
| **coefficient + scalar block only** (trimmed `main`, ~1 s) | 208 | **137** | 48 | 71 |
| full file | 737 printed | 350 | 249 | 214 |

Of the 48 coefficient-block disagreements, **45 are ONE PORT BUG, not a
coefficient error**: every `xv_*` (value → index) row answers `4294967295`,
i.e. `tc.vi`/`tc.uvi` never find their bit pattern in a freshly split list.
The forward rows (`xf_*`, `cd_*`, `cu_*`) for the very same tables all agree, so
**every coefficient value, every exact f64 decimal and every f32 bits value
matches CPython.** The remaining 3 are `xf_pi_a` (1 ULP, real) and the two
integer-vs-f32 spelling mismatches.

Oracles, all in `.agents/slop/`: `tc-audit.py` (+ `.txt`), `tc-value.py`
(+ `oracles/tc-rows-value.txt`), `tc-gen.py rows` (+ `oracles/tc-rows-coef.txt`), `tc-diff.py`,
`tc-build.py`, `tc-mutate.py`, `tc-rows.py`.

# MUTATION TABLE — NOT RUN, and why

`tc-mutate.py` carries 32 entries (one per ported rule and per coefficient
group), edits a scratch copy **next to the real file** (a `$TMPDIR` copy cannot
resolve a relative import — 22 phantom blind spots in another unit), runs it, and
diffs whole `name=value` lines. **I did not run it**: one full run is ~8 minutes
(measure it: 372 rows in ~4 min) and the budget was gone. So this unit reports
**zero mutations measured**, which is the honest answer and is not a claim.

What I *did* learn that a mutation table would have cost me to learn, and which
is the same class of finding:

- **45 rows moved together from one bug.** `tc.vi` failing took every reverse
  index of every table red at once — a real mutation, found by the diff rather
  than by the harness.
- **Three inverted `Bool.pick` arms, each total and each silent.** Inverting the
  outer arm of `_lazy_map_numbers` made all three expansions answer NaN for every
  finite input; inverting `xexp2`'s `d.ne(d)` guard did the same for `xexp2`;
  reading the six `d.ne(...)` guard rows as "IS this value" inverted all 18
  fixtures of six families at once.
- **`U32.and(n, 0x7fffffff)` is not `|n|`** — it made every negative `pow2if`
  answer 0.
- **`F32.pow(2.0, 1.0)` saturates** — `1.0 / F32.pow(2.0, 1.0)` answers 0, so
  `2**n` must be a doubling loop.
- **`List.get` consumes a list level**: reading element `i` and then searching
  the same list answers element `2i` and then `None`. That is why every table is
  carried twice, once split and once raw.

# SEAM / PORTED SPLIT, WITH PYTHON LINES

**PORTED AND EVALUATED AT THE FLOAT32 LEVEL**
`:7`, `:9-11`, `:14`, `:15`, `:16`, `:19`, `:20`, `:22`, `:27`, `:32`, `:39`,
`:47`, `:52`, `:115`, `:150` (f32 table), `:152`, `:158`, `:160`, `:164`, `:170`
(fast), `:193`, `:219`, and the constant/window parts of `:66`, `:84-86`,
`:88-92`.

**SEAMS — NAMED, WITH THE LINE THAT MAKES THEM SEAMS**
- **W1, no uint64 arithmetic** → `payne_hanek_reduction`'s product is NOT
  evaluated. `:103` `def _hp_mul(x,y): return x.cast(dtypes.uint64) *
  y.cast(dtypes.uint64)`; `:105` `p = shl(_hp_mul(ia, hi), 32) + _hp_mul(ia, mi)
  + shr(_hp_mul(ia, lo), 32)`; `:108` `q = shr(p, 62).cast(dtypes.int32)`.
  `base.bend` has `U32` and `Word(64n)` but no f64 and no `U32 -> F64` bitcast,
  and this file does not build a 32x32→64 multiply.
  CONSEQUENCE, stated in the file: `xsin(fast=False)` takes this path at
  `:182`/`:187` whenever `x_abs >= switch_over`, so the value rows stop at
  `29.999998` and **the boundary is gated by the CHOICE** (`xg_xsin_below_*`,
  which pins the 30.0 constant) **not by the answer**.
  Everything else in the function IS gated: the 190-bit 2/pi table exactly as
  seven u32s, `4.294967296e9`, `3.4061215800865545e-19`, `2**62`, the :109 mask,
  the `i = shr(e,5)` / `e & 31` / `offset = 32-e` derivation and `_take`'s
  window arithmetic.
- **W2, `xpow` calls the NATIVE ops** → `:259` `base.log2().mul(exponent).exp2()`
  are `Ops.LOG2`/`Ops.EXP2`, not `xlog2`/`xexp2`. `base.bend` has `F32.log2` but
  no `F32.exp2`, and substituting this file's own `xexp2` would be claiming a
  DIFFERENT function. Gated instead: `non_int` (`:261`), `is_odd` (`:262`), the
  `exponent.eq(0)` short circuit (`:265`), `-base` (`:259`).
  **MEASURED, and worth knowing:** `xpow` with an infinite exponent is not
  realisable on the interpreter backend at all — `:261` casts the exponent to
  int32 and `int(inf)` raises. `(-1)**inf` therefore has no value anywhere;
  on hardware `(int)inf` is undefined too. It gets a predicate row and no value
  row.
- **float64 everywhere.** Bend has no `F64` (`grep -n F64
  references/bend/bend2/base.bend` is empty), so no f64 coefficient is a VALUE
  here. Each is carried as CPython's `repr()` and gated by `cd_*`, with
  `float.hex()` on the record in `tc-audit.txt`. That is strictly stronger than
  TODO round 4's "written as full decimals, NOT independently verified".
- **`U32 -> F32` bitcast** — absent. `pow2if` (`:30`), `frexp`'s mantissa (`:61`)
  and `ldexp3k`'s exponent add (`:45`) are integer fields written into a float;
  each is computed ARITHMETICALLY and the pattern is recovered with `F32.bits`,
  so the gate compares against the bitcast tinygrad performs. `xf_pow2if_*`,
  `xf_frexp_*` and `xf_ldexp3k_*` are those claims.
- **`:267 get_transcendental_patterns`** builds `UPat`s — that is GRAPH, the
  other port's subject. The tables it selects between are gated here.

# WHAT THIS GATE STILL DOES NOT SEE

1. **The value layer is only half-closed.** 350 of 813 oracle rows agree; the
   residue is dominated by `xf_xlog2_*`, `xf_xsin_fast_*` past ~100, and the
   `xf_xexp2_sp_*` family whose fixture list I failed to regenerate. Each was
   being chased when the budget ran out.
2. **The reverse lookup `tc.vi`/`tc.uvi` is broken** (45 rows). The forward
   direction is sound; the value→index direction answers "not found" always.
3. **The scalar block emits `xf_*`/`cu_*` but not `cd_*`/`cx_*`/`tx_dt.*`**, so
   the exact decimal and the hex spelling of every named scalar are audited in
   `tc-audit.txt` but are not Bend rows. That is the gap round 4 complained about,
   narrowed but not closed.
4. **`xf_pi_a` is one ULP off** and is left that way, loudly, because fixing it
   means choosing between `F32.read(repr)` and `struct.pack` and that choice
   belongs to whoever owns the dtype layer.
5. **The full mutation table is unmeasured.**

# BOOKKEEPING

- `.agents/slop/notes/bend2-constraints.md`, appended at the END, numbering
  continued from the previous entry, positions cited: 12 new rules
  (`F32.read`, F32 bit-exactness, `F32.pow`, two's-complement `|n|`,
  `Bool.pick` arm order, blanket `+`, def ordering, decreasing self-calls,
  `String.split` tables, `List.get` consumption, `List.length -> Nat`,
  tinygrad's bitwise float `ne`).
- Oracles are in `.agents/slop/`, never `$TMPDIR`.
- **Nothing committed.** No other file touched except the append above.
- `fold.bend` / `movement.bend` were NOT consulted and this file imports nothing
  from `uop/`, so the concurrent-agent breakage did not reach me.