# DTYPEB — retiring `tinybendygrad/dtype.bend`'s red laws

Unit: `.agents/slop/dtypeb/`. **Nothing committed, nothing in the live tree.** Compiler
**Bend 2.0.34** via `./bin/bend`. Patched file: `dtypeb/dtype.patched.bend` (871 lines,
was 638). Rule prefix `DTB-`.

## THE COUNT

| | before | after |
|---|---|---|
| `bend tinybendygrad/dtype.bend --check-only` | **14** defs rely on unsafe or foreign code | **6** |
| `import "./runtime/dtype.*"` lines in the file | 20 | 6 |

**Retired 8, remaining 6, and all 6 are one missing primitive.** No law was DELETED:
all fourteen names are still declared once each, checked (`grep -c "^def <n>("` = 1 for
every one, live and patched), so no count here is a law that went missing.

Whole-tree `--check-only` sweep, live vs patched: **the set of red files is byte-identical**
(14 files, `dtype.bend` still among them). Nothing else regressed.

## WHAT EACH RETIREMENT COST

**6 × `Dt.i64_*` — cost: an effect boundary removed, nothing else.** They were
`IO(..)` with no body. The type was never the wall: `H.I64` is `I64{hi: U32, lo: U32}`
(`helpers.bend:1639`) and `helpers.bend` already carries the whole 64-bit ALU
(`i64_divmod`, `i64_add`, `i64_sub`, `i64_bit`, `i64_zero`, `i64_is_neg`,
`i64_is_zero`). They became pure defs. `i64_mul` is **still missing** and
`mixin/dtype.bend:56` is still right about that: upstream's `cmod = x - cdiv(x,y)*y`
is unreachable, so `cdiv`/`cmod` are derived from the multiply-free floor pair. Cost of
that derivation, and it is not free: **`ceildiv` could not be done the upstream way.**
`helpers.py:66-69` is `-((-x)//y)` and `-x` does not exist when `x` is `int64.min`; the
negation route answers `-1` where CPython answers `1` for `ceildiv(int64.min,
int64.min)`. It is now `cdiv + (r != 0 and sign(a) == sign(b))` — `dtype.c:240-242`'s
direct form — and the fixture `min_min` is the row that caught it.

**2 × `Dt.fp8_from`, `float_to_fp8` — cost: one missing arithmetic op, which is
`U32.shln`/`U32.shrn` requiring a `Nat`.** `fp8_encode` (`dtype.c:44-87`) is pure U32
arithmetic on the f32 pattern, so it is expressible — but `U32.shl`/`U32.shr` are ONE-BIT
and the shaper's shift amounts are *computed* (`1 - exp`, `23 - sig`). Measured on 2.0.34:
`U32.shln(a, U32.to_nat(n))` with a runtime `n` **works** (`U32.shln(3, 4n)` = 48), so
`fp8_enc.shl`/`fp8_enc.shr` are two one-line defs and the shaper is writable. `float_to_fp8`
was never arithmetic — it was red only because `Dt.fp8_from` was.

**6 × `Dt.bf16`, `Dt.fp16`, `Dt.fp8_to`, `float_to_bf16`, `float_to_fp16`,
`fp8_to_float` — cost: a dtype the port does not have, and it is ONE primitive.**
Measured on 2.0.34: `F32.bits` exists and is a bitcast (`F32.bits(1.0)` = 1065353216 =
0x3F800000); `F32.from_bits` does **not** exist; and the near miss is not a near miss —
`U32.to_f32` is the NUMERIC conversion (`U32.to_f32(3)` = 3), not a bitcast. Bend can take
a float apart and cannot put one back together. All three seams end in exactly that step
(`dtype.c:156-176`, `160-162`), and the three wrappers have **no arithmetic at all** — they
are red only because of the seams. Six red laws, one missing `def F32.from_bits` in
`base.bend`, which is not this file's.

## THE PURE-FOLD QUESTION, ANSWERED AGAINST THE CALL GRAPH

`UOp._min_max` is a pure fold computed in a Kahn worklist (`mixin/dtype.bend:38-60`), and
a fold cannot run an effect. Two routes exist. **(a)** make the fold effectful — that
changes `fold.bend`'s `Folded`/`Table` from a value to an `IO` value and propagates through
every consumer of the fold; it is `uop/fold.bend`'s call, not this file's. **(b)** remove
the effect from the **leaf**. This file takes (b): **the arithmetic does not move at all and
the fold does not change type.** What moved is the effect boundary, out of the callee and
nowhere. The fold is still pure, and it is still `fold.bend`'s. **No fold was made effectful
to make a gate pass** — there is no `IO` in `mixin/dtype.bend` or `uop/fold.bend` and none
was added.

## PLANT AND DISARM — DISARM FIRST

`gate.txt` is the full log. `run.py` builds four trees and diffs whole `name=value` lines,
never row names.

```
BASE    PASS  rows present 102/102 (i64) + 1228/1228 (fp8) = 1330, mismatch 0
DISARM  PASS  0 rows moved                    <- ran BEFORE the plant
PLANT   --    i64: 6 moved == 6 derived, every one a `cmod` row
               fp8: 236 moved, 0 outside the reachability family
                     fnuz-zero sub-plant: 33 derived == 33 moved
BLIND   --    12 rows moved  (tie-parity probe -- NOT a blind spot, see below)
GATE PASS
```

**The disarms.** `Dt.i64_trunc` from `x` to `H.i64_or(x, H.i64_zero())`, and the fp8 zero
test from `U32.is_le(absx, denorm)` to `Bool.not(U32.is_gt(absx, denorm - 1))`. Both are
the same function by a different expression. **0 rows moved.**

**The plants.** `Dt.i64_cmod.put` drops the `- b` (the remainder keeps the floor's sign).
It moves **6** rows and the harness asserts the moved set **equals** the set derived from the
mutation's own algebra — `sign(a) != sign(b) and floormod(a,b) != 0`, computed from the
oracle — not a transcribed list. The rows that must not move do not: `7_4`, `8_4`, `m8_4`
(same sign or exact), `m7_m4` (same sign), `5_0` (zero divisor), and all five other defs.
The fp8 plant removes C's `& 0xFFu` from the exponent field — **the bug this lane actually
found** — and moves 236 rows, **0 of them outside the derived family** (bit 31 of the
pattern, i.e. a negative f32 literal; that is the only bit `& 0xFF` removes from `pattern
>> 23`). The second fp8 plant gives fnuz a negative zero and moves exactly the 33 rows the
oracle derives: fnuz, CPython answer `0`, sign set.

**The blindness probe** asked whether the fixture set separates round-half-to-even from
round-half-away (`res & 1` → `res & 2`). It moved **12 rows**, so it is covered, and it is
reported as a non-zero rather than as a blind spot.

## THE GATES RAN AGAINST A CALLED ORACLE — YES

Every expectation is produced by **calling** the upstream module in-process; none is
transcribed. `tinygrad/helpers.py` `cdiv`/`cmod`/`ceildiv` and Python's own `//`/`%`;
`tinygrad/dtype.py` `float_to_fp8`. Rows-present vs rows-expected is counted on **every**
run, including the disarmed and planted ones.

| lane | rows | oracle | 3 of them |
|---|---|---|---|
| i64 | 102 | **99 CPython-verified** | `TOTALISE`, never counted as passes |
| fp8 | 1228 | **1228 CPython-verified** | — |

The 3 totalise rows are `b == 0`, where `helpers.py` has no zero guard and Python raises
`ZeroDivisionError`. There is no oracle answer, so the expectation is `runtime/dtype.c`'s
own written zero branch (`dtype.c:191` `q=0, r=a`, `dtype.c:239` `return 0`) and the rows are
labelled `TOTALISE`. They are counted, printed, and never called passes.

Fixtures: 17 named `(a, b)` pairs chosen to separate floor from truncated on every sign,
including both `int64` edges; 215 f32 patterns (every threshold ±1 for all four formats,
every exponent of the whole subnormal window at five mantissas, the tie bit ±1, ±0, ±inf,
±nan, 40 seeded randoms) × 4 formats, plus 122 of them reachable as f32 literals so
`float_to_fp8` is gated end to end through `F32.bits` and `fp8_kind`.

## WHAT THE GATES FOUND

1. **Mine, caught:** the port dropped `dtype.c:48`'s `& 0xFFu` from the exponent field. 236
   rows.
2. **Mine, caught:** the subnormal shift ladder had three rungs; the window is **four**
   exponents wide, because `absx > denorm` compares the whole magnitude, so `denorm`'s own
   exponent field is in the branch whenever its mantissa is nonzero. `exp == -3` was
   answering shift 1 instead of 4. 43 rows.
3. **`runtime/dtype.c`, REPORTED NOT FIXED — it is not this file's.** `dtype.c:40`'s
   `fp8_ovf = {0x43E80000, 0x47700000, 0x43780000, 0x47700000}` restates three of dtype.py's
   thresholds **without their trailing `-1`** (`dtype.py:236-241` writes
   `0x40EE000000000000-1`, `0x406F000000000000-1`, `0x40EE000000000000-1`), and `dtype.c:70`
   compares with `>`. The f32 restatement rounds those one-f64-ULP-low values onto the value
   itself, so the `-1` is lost. Measured: at `absx == 0x47700000` CPython answers **123** for
   `fp8e5m2` and **127** for `fp8e4m3fnuz` (both `max_norm`) and the C's comparison answers
   124 and 128. `dtype.c:19-21`'s claim that the f32 restatement "agree[s] bit for bit on
   every f32 input" is false on that row. The port therefore stores `ovf` as the **last f32
   magnitude dtype.py still rounds normally** (`0x476FFFFF`, `0x476FFFFF`, `0x43E80000`
   order) so the `>` is dtype.py's own `>`.
4. **A stale citation, found in the report that made it:** W64-MILE.md's ADDENDUM says
   `runtime/dtype.c:205-206` reads `f[0], f[1]` and is wrong on 0 of 30 rows. It does not:
   the live `dtype.c:205-209` already takes `Env`+`Term` and uses `ctr_take`. That patch
   landed. Do not act on that item.
5. **A wall that is now half stale:** `mixin/dtype.bend:50-58` records CAST/CDIV/FLOORMOD/
   FLOORMOD/CMOD as "EFFECT SEAMS" that `_min_max` cannot call. After this change div, mod,
   trunc, cdiv, cmod and ceildiv are pure and callable from the fold. **`i64_mul` and a
   64-bit shift are still missing** (`mixin/dtype.bend:56,58`), and those two are the whole
   of what now blocks `UOp._min_max`. Also: all fourteen of these defs have **zero
   executable call sites** outside `dtype.bend` — every hit in the tree is a comment — so
   `mixin/dtype.bend` names a seam it never calls.

## WHAT REMAINS, WITH `file:line`

| def | file:line | why |
|---|---|---|
| `Dt.bf16` | `tinybendygrad/dtype.bend:576` → patched `:836` | ends in `f32_rewrap`; needs `F32.from_bits` |
| `Dt.fp16` | `:580` → `:840` | `fp16_f32` ends in the same bitcast |
| `Dt.fp8_to` | `:588` → `:844` | `fp8_decode` returns an f32 **pattern** (`dtype.c:110`) and the law returns `F32` |
| `float_to_bf16` | `:627` → `:859` | no arithmetic; red only through `Dt.bf16` |
| `float_to_fp16` | `:631` → `:863` | no arithmetic; red only through `Dt.fp16` |
| `fp8_to_float` | `:637` → `:870` | no arithmetic; red only through `Dt.fp8_to` |

The eight retired, for the same citation: `Dt.i64_cdiv` `:604` → `:624`,
`Dt.i64_cmod` `:608` → `:633`, `Dt.i64_trunc` `:592` → `:636`, `Dt.i64_floor_div` `:596` →
`:639`, `Dt.i64_floor_mod` `:600` → `:642`, `Dt.i64_ceildiv` `:612` → `:660`,
`Dt.fp8_from` `:584` → `:808`, `float_to_fp8` `:634` → `:867`.

**The one requirement, in the file that is not mine:** `def F32.from_bits(bits: U32) -> F32`
in `references/bend/bend2/base.bend`. With it, all three bodies are already written in U32 in
`runtime/dtype.c` — `fp16_encode`, `fp16_f32` and `fp8_decode` are pure U32 except for that
one rewrap — and all six laws close. **Until then this file is COLD, and every verdict taken
against it stays INCONCLUSIVE.** That is now a *stated* cause rather than the 14-law wall,
and the count, not zero, is the deliverable.

## WHAT A ZERO WOULD STILL HAVE NEEDED

`--check-only` is not sufficient evidence here, so the deliverable was checked with
`substrate-check.sh`: **COLD** on the bend half (6 laws, as expected), **NAMES CLEAN** on the
names half (2 modules, 328 refs, 328 exact, 0 suffix-only, 0 unresolved, 0 dead imports),
and the file is 871 lines rather than empty. The whole-tree sweep is the third instrument:
`ops_python.bend` — the file that made `ops.bend`'s false green visible — is still red, so the
`O.ParamArg.no_slot` class of failure is not present.

## REPRODUCE

```sh
python3 .agents/slop/dtypeb/patch_dtype.py $TMPDIR/dtbtree   # writes the patched dtype.bend
python3 .agents/slop/dtypeb/run.py                           # base / disarm / plant / blind
```

## FILES

`patch_dtype.py` (assembles head + two tails) · `tail-i64-pure.bend.txt` ·
`tail-fp8-pure.bend.txt` · `gen_i64.py` · `gen_fp8.py` · `run.py` · `gate.txt` ·
`dtype.patched.bend` · `00-stub.md`