# FP8FIX — the C lane of `runtime/dtype.c`, and what it found

Unit: `.agents/slop/fp8fix/`. Rule prefix `FX-`. **Nothing committed.** The C compiler
is `cc`; the Bend compiler is **2.0.34** but `bend -o` emits nothing today (§BELOW).
I own `tinybendygrad/runtime/dtype.c`; **three code lines changed, 36 comment lines
added, no `CID` guard touched** (the CID-sweep unit had not landed here).

## THE INSTRUMENT, AND WHY IT IS A NEW ONE

The 1,228-row gate in `.agents/slop/dtypeb/` runs the **Bend** port. It reaches
`runtime/dtype.c` only through a seam, and two files agreeing proves nothing
(AGENTS.md: "Agreement between a port and a hand-typed oracle is not corroboration").
So this measures the C lane directly: `build.py` compiles the **live** `dtype.c` into
two executables and `gate.py` drives them.

| file | what it is |
|---|---|
| `context.h` | the C context this instrument declares itself |
| `harness.c` / `harness_i64.c` | the two drivers, `F`/`D` and `I` |
| `build.py` | compiles the live `dtype.c`; `--deficit` measures the gap |
| `gate.py` | fixtures, the oracle, the differ, the sweep, `--predict` |
| `plants.py` | every plant and disarm as a text edit, and BASE's reverse-edit |
| `oracle.txt` | **82,978 expectations, every one CALLED from `tinygrad`, 0 typed** |
| `gate.txt`, `sweep.txt` | the two logs |

**BELOW: `bend -o` is dead for `.c` files right now.** `substrate-check.sh:134` builds
its `cc` context from `bend -o .agents/slop/guardfix/probe-c.bend`, and that emits
nothing:

```
./bin/bend .agents/slop/guardfix/probe-c.bend -o gen.c  ->  rc 1, no gen.c
expected : Nat / observed : U32 / Location: fp16_flat / dtype.bend:687
```

`dtype.bend` is another unit's LIVE file, so **`substrate-check.sh` prints
`NO INSTRUMENT` for every `.c` file in the tree at this moment.** Reported; not worked
around by editing their file. `context.h` supplies the seven names the two PURE halves
need — smaller than the 190-error deficit `substrate-check.sh:97` measures for
`cc -fsyntax-only dtype.c` alone — and **`cc` corrected me twice**: `ctr_take` and
`io_tup` take `Env` **by value**, not by pointer.

**STATED BLIND SPOTS.** (1) `context.h`'s tuple shim is mine, so this does **not** test
the tuple ABI; it tests the **arithmetic**. (2) A `.c` file here is not a translation
unit (`substrate-check.sh:101`), so `Term`/`Env` are declared by me, not by bend.

## THREE ROW FAMILIES, REPORTED APART AND NEVER SUMMED

| family | what | rows |
|---|---|---|
| **E** encode | `float_to_fp8`, 20,463 patterns × 4 formats | 81,852 |
| **D** decode | `fp8_to_float`, **all 256 codes** × 4 formats | 1,024 |
| **I** i64 | 17 named `(a,b)` × 6 defs; 97 CPython-verified, 5 `TOTALISE` | 102 |
| **S** sweep | **EXHAUSTIVE** over each format's subnormal window, both signs | **234,881,032** |

The five `TOTALISE` rows are `b == 0`, where CPython **raises** `ZeroDivisionError`.
There is no oracle answer, so the expectation is `dtype.c`'s own written zero branch,
the rows are labelled `TOTALISE`, and they are never counted as passes.
`.agents/slop/dtypeb/gen_i64.py:65-72` labels three of the five; five is the same fact
counted completely.

## THE PREDICTIONS, PRINTED BY `gate.py --predict` BEFORE ANY PLANT RAN

| mutation | predicted | moved | out-of-mechanism | verdict |
|---|---|---|---|---|
| **A-plant** ovf threshold `V → V+1` | 31 E | **27 E** | **0** | bound, 4 static (e4m3) |
| **A-plant-ge** `>` → `>=` | 8 E | **0 E** | **0** | **blind spot, reason below** |
| **A-disarm** old table + `absx >= ovf-1` | 0 | **0** | — | disarm holds |
| **C-plant** subnormal scale ×2 | 40 D | **40 D** | **0** | **EXACT** |
| **C-disarm** `ldexpf(1-bias)` → `1.0f/(1u<<(bias-1))` | 0 | **0** | — | disarm holds |
| **D-plant** swap the e4m3 NaN arms | 1 D | **1 D** | **0** | **EXACT** |
| **D-disarm** `0x7FC00000u` → `f32_rewrap(NAN)` | 0 | **0** | — | disarm holds |
| **B-plant** 3-rung ladder, `exp == -3` → `sh 1` | 403 E | **213 E** | **0** | bound, 190 static |

**`OUT-OF-MECHANISM 0` on every plant is the assertion that can fail**, and it caught
three of my own errors: an off-by-one in A-plant's derived set (`{V,V+1}` for `{V+1,
V+2}`), D-plant's derived set naming `d255` — the row the plant **repairs** — and
B-plant's unmasked exponent field, which reads the sign bit on a negative pattern.

**Why a subset assertion and not `moved == derived` everywhere** (AGENTS.md:137 asks
for equality): for C and D the mechanism **determines** the answer and equality is
reported, exact. For the ovf and ladder plants the mechanism only says which patterns
are **candidates** — whether saturating and rounding agree at a pattern is a fact about
the port, not the oracle, and a derived set claiming otherwise **cannot fail**.

## THE RESULTS

| | rows | expected | present | **BEFORE mismatch** | **AFTER mismatch** |
|---|---|---|---|---|---|
| E encode | 81,852 | 81,852 | 81,852 | **15** | **0** |
| D decode | 1,024 | 1,024 | 1,024 | **41** | **0** |
| I i64 | 102 | 102 | 102 | **0** | **0** (5 `TOTALISE`, never passes) |
| S sweep | 234,881,032 | — | — | **0** | **0** |

**`MOVED FIX → BASE : 56 rows = E 15 + D 41 + I 0`** — one lane per defect, never a sum.

`BASE` is reconstructed by reverse-applying this unit's edits and **proven** by md5
(`plants.py:BASE_CODE_MD5`); the comment delta is 41 lines, all `//`.

## THE FOUR FINDINGS

**1. `dtype.c:40` — the dropped `-1`. FIXED, the assigned defect.**
`fp8_ovf` restated dtype.py's three `-1` thresholds as the f32 patterns of the values
themselves, and `>` then excluded the boundary. 15 E rows.
`E[fp8e5m2][thr47700000+0]` answers **124** where CPython says **123**;
`E[fp8e4m3fnuz][thr43780000+0]` answers **128** where CPython says **127**.
Fixed by storing the **last f32 magnitude dtype.py still rounds normally**:
`{ 0x43E80000, 0x476FFFFF, 0x4377FFFF, 0x476FFFFF }`.

**2. THERE IS NO SECOND DEFECT IN `dtype.c`.** The 3-rung ladder is in
`.agents/slop/dtypeb/dtype.patched.bend`, which `DTYPEB.md:127-130` records as
**already caught and fixed in that unit's own tree** — a file I must not touch.
`dtype.c:77` computes `sh = 1 - exp`: not a ladder, and not three rungs.
**The S sweep is exhaustive over the ladder's entire domain — every f32 pattern with
`denorm ≤ absx ≤ min_norm`, four formats, both signs, 234,881,032 of them — and it
reports 0 mismatches on BASE and on FIX.** All four rungs are correct where they are
reachable. `B-plant` is kept because the window being four wide is a fact about
upstream worth a row, and the plant measures it.

**3. `dtype.c:107` — EVERY fp8 SUBNORMAL DECODES TO HALF ITS VALUE. FIXED, found here.**
`(1.0f / (1u << bias))` is `2**-bias`; `dtype.py:279` says `2 ** (1 - bias)`. **40 D
rows.** `D[fp8e4m3][d1]` answers `3a800000` = `-2**-10` where CPython says
`3b000000` = `-2**-9`.

**4. `dtype.c:104` — e4m3's NaN is signed and upstream's is not. FIXED, found here.**
`dtype.py:278` returns a bare `math.nan`; `dtype.c:104` returned
`sgn ? 0xFFC00000 : 0x7FC00000`. **1 D row**: `D[fp8e4m3][d255]` answered `ffc00000`
where CPython says `7fc00000`.

**3 and 4 are why the 1,228 rows never saw either: that gate is `float_to_fp8` end to
end and `fp8_to_float` was not in it at all.** `DTYPEB.md:160` records `Dt.fp8_to` as
still red — the decode path is written, compiles, and is **unreached**.

## IS "THREE OF FOUR THRESHOLDS" UPSTREAM'S RULE?

**Yes, by design, and the gate covers all four — so there is no gap in the gate.**
`dtype.py:238-241` writes `-1` on `fp8e5m2`, `fp8e4m3fnuz`, `fp8e5m2fnuz` and not on
`fp8e4m3`, because the comparison is `absx > ovf_threshold` and **an f64 ULP below the
value means "include the value itself"**. The `-1` is load-bearing: dropping it loses
exactly one f32 pattern per affected format. `fp8e4m3` is the fourth case and it **is**
swept, at `thr43e80000±6`. Measured directly, and the answer to the brief's question is
that the `-1` is upstream's rule while the C's **restatement** of it was the defect.

## THE LADDER IS FOUR WIDE BECAUSE `absx > denorm` COMPARES A WHOLE MAGNITUDE

| kind | `denorm` | its own exp field | `exp` there | `sh` | rungs |
|---|---|---|---|---|---|
| e4m3 | `0x3A800000` | 117 | −3 | **4** | 4 |
| e5m2 | `0x37000000` | 110 | −2 | 3 | 3 |
| e4m3fnuz | `0x3A000000` | 116 | −3 | **4** | 4 |
| e5m2fnuz | `0x36800000` | 109 | −2 | 3 | 3 |

**`denorm`'s own exponent field is inside the window whenever its mantissa is nonzero**,
which is what makes `sh = 4` reachable — and e5m2 is three rungs **in upstream too**, so
the width is **upstream's shape and not an artefact of the f32 restatement.**

## THE A-PLANT-GE BLIND SPOT, WITH ITS REASON

`absx >= fp8_ovf[kind]` moved **0** of 8 predicted rows. Reason, measured not argued:
**at every format's own threshold the saturating answer and the rounding answer are the
same code**, so the arm is idempotent there. `A-plant` says the same from the other side
— of 31 candidate patterns, the 4 e4m3 ones are exactly the ones that do not move. The
arm is still needed *above* the threshold: `thr47700000+1` moves under `A-plant`. **A
zero with a proof is a theorem; a zero without one is a request for a fixture.**

## THE FIXTURE TRAP, AND TWO OF MY OWN INSTRUMENT BUGS

`gen_fp8.py:35` builds its threshold sweep from `dtype.c`'s `OVF`, i.e. **the bug is
transcribed into the fixture**; it catches this defect only because `t-1,t,t+1,t+2`
happens to include `t`. **A fixture swept around the port's own constant tests the
port's constant.** `gate.py` sweeps `t-6..t+6` around **every threshold in the file and
both restatements of it**, which is why `thr476fffff+0` exists at all (+208 rows).

Both of my own bugs **moved rows** and neither was a defect in `dtype.c`:

1. `fx_pairs[64]` against 306 tuples — silent overflow at request 24 = `I 3 m7_m4`,
   printing `cdiv(-7,-4) = 0` where the answer is `1`. Now 4096.
2. `%u` against `%08x` in the drivers: **1,024 decode rows and 62 i64 rows** read as
   MISMATCH. Row space, not arithmetic.

Also fixed in the fixture: `sub_k%d_ef%d` row names carried a kind index into rows
evaluated for **all four** kinds, so `E[fp8e4m3][sub_k2_ef117_…]` read as a
contradiction. **A row name that can be read as false is a defect in the fixture.**

## WHAT REMAINS, WITH `file:line`

**`runtime/dtype.js` CARRIES FINDINGS 1 AND 4, VERIFIED, AND IS NOT MINE.**

| file:line | finding |
|---|---|
| `runtime/dtype.js:37-38` | the same `ovf` restatement, `{…, 0x47700000, 0x43780000, 0x47700000}` |
| `runtime/dtype.js:68` | `absx > ovf`, so **the identical dropped `-1`, identical wrong answers** |
| `runtime/dtype.js:97` | `return sgn ? 0xffc00000 : 0x7fc00000` — **e4m3's NaN is signed here too** |
| `runtime/dtype.js:101` | **`Math.pow(2, 1 - bias)` is CORRECT** — finding 3 is C-only |

`dtype.js` is on my DO-NOT-TOUCH list and I did not touch it. `agent-core.md:183-186`
warns specifically against "fixing `dtype.js` to match `dtype.c`", because the missing
thing is the ABI and not the code — so this is a report, not a patch, and it is the same
report in two files.

## REPRODUCE

```sh
sh .agents/slop/fp8fix/run.sh gate     # 82,978-row gate, ten trees      ~1 min
sh .agents/slop/fp8fix/run.sh sweep    # 234,881,032-pattern sweep       ~12 min
python3 .agents/slop/fp8fix/gate.py --predict   # the predictions, alone
```