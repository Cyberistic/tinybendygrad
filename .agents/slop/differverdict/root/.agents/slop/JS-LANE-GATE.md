# JS-LANE-GATE — the JS dtype lane executes, and it is RED on 30 of 30 rows

Rule prefix for this unit: **`JSL2-`**. Files: `.agents/slop/jslane2/`.
**Nothing committed. `dtype.js`, `dtype.c`, `dtype.bend`, `helpers.bend` are
byte-unchanged** (verified `git status --porcelain` empty for all four, md5s
recorded). Every mutation ran on a `$TMPDIR` copy.

Reproduce:

```
python3 .agents/slop/jslane2/gen_js_seam.py    # rc 0 -- gate is live, base is RED
python3 .agents/slop/jslane2/gen_f32_seam.py   # rc 1 -- lanes disagree on 3 of 6
```

Outputs: `jslane2/js-lane-gate.txt`, `jslane2/f32-lane-gate.txt`.

---

## 1. Does the JS lane execute? YES. Here is how I know.

Not by reading `main.ts`. Three independent measurements.

**(a) It is a real target.** `bend <f.bend> -o <out>.js` writes `Comp.js_book`
(`references/bend/bend2/main.ts:361`) and every `import "./x.js"` is embedded
**verbatim** (`comp.ts:3385`, `effect_srcs(fl, ".js", …)`).

**(b) `node` hosts it.** `node` is v26.8.1 and runs a plain script here. The
generated `seam.js` contains `dtype.js`'s own text — `grep -c asIntN seam.js`
= 1, `function i64_of(p)` at line 287 — so the JS lane's code is in the binary.

**(c) It ran and it answered.** `node seam.js` printed `SEAM trunc =  : ` on the
identity seam. **The C lane printed `0:7` from the same `.bend`.**

The header of `dtype.js:3-6` claims *"a `.bend` that runs under both lanes
cannot tell which one it got"*. **That is now refuted by measurement, not by
argument: on the shipped tree the two lanes differ on 30 of 30 rows.**

## 2. Rows present vs rows expected

`gen_js_seam.py` reuses `w64mile/gen_seam.py`'s 6 `DEFS`, its 5 `FIXTURES`
(including `int64.min`), its `hi:lo` printing and its oracle — `tinygrad/helpers.py`
**called**, never transcribed. 30 rows, row-for-row comparable.

| arm | rows present / expected | agrees with CPython |
|---|---|---|
| `node` (shipped, the measurement) | **30 / 30** | **0 / 30** |
| `node` (repaired, scratch diagnosis) | 30 / 30 | 30 / 30 |
| `cc` (shipped C, same rows) | 30 / 30 | 30 / 30 |

Rows are emitted as `SEAM <def> #<k> = <v>` so that **absent** and **present and
wrong** cannot print the same thing. The shipped lane prints ` : ` on all 30 —
present, and wrong. Counting them as missing would have reported green.

## 3. WHY the shipped JS lane answers `0` for everything — instrumented

I put `console.error` probes in a **`$TMPDIR` copy** of `dtype.js` and `dtype.c`.
Verbatim output:

```
JS  i64_of got keys=["$","hi","lo"]  p={"$":"tinybendygrad/helpers.I64","hi":0,"lo":7}
JS  pack64 -> {"$":"Tuple","fst":0,"snd":0}
C   fp16_run f[0] = 1069547520      (the BITS of 1.5)
JS  dtype_fp16 x=1.5                (the VALUE 1.5)
```

**Four independent ABI divergences, none declared anywhere.**

| # | divergence | consequence |
|---|---|---|
| 1 | a record crosses to JS **by NAME** (`{hi, lo}`), not positionally. `dtype.js:137` reads `p.fst`/`p.snd`; both are `undefined`, and `undefined >>> 0 === 0`, so **`i64_of` ≡ 0 for every input**. `Dt.i64_trunc` — the identity — is not the identity. | 30 / 30 rows |
| 2 | `pack64` returns `io_tup(...)` = `{"$":"Tuple","fst":…,"snd":…}` where the caller reads `{hi, lo}`, so even the `0n` does not come back. | 30 / 30 rows |
| 3 | an `F32` argument crosses as a **bit pattern in C** and as a **value in node**. `of32(1.5)` then reinterprets the value 1.5 as the pattern 1 = the smallest f32 subnormal. | `fp16(1.5)` is `0` under node, `1.5` under cc |
| 4 | pair ordering is undeclared in both lanes. | not a bug yet; see §5 |

**This refutes `JS-LANE.md`.** That note says `i64_of` "reads the two halves of
one record. That is exactly right." It reads `p.fst`/`p.snd`; the record's fields
are `hi`/`lo`. **The JS lane is not the correct twin — it was the lane nobody ran.**

Also: `dtype.c:212` `pack64` uses the *same* `io_tup`, and C works. So C's
agreement is a third coincidence — `io_tup` and `H.I64` are both 2-field
constructors laid out alike. C is right by layout, not by contract.

## 4. Can `BigInt.asIntN(64, …)` and `(s64)` be made to differ? NO — and it is a THEOREM

**No fixture separates them, because they are the same function.** For every
`h, l` in `[0, 2**32)` both compute the two's-complement signed reading of the
64-bit pattern `h:l`. The gate measures it rather than asserting it: the
`repaired` arm (which uses `asIntN(64, …)`) is **byte-identical to the C lane on
30 / 30 rows**, including `int64.min`.

So the honest answer is *not* "they diverge somewhere I haven't found". The
sign-carrying step is the one part of these two lanes that genuinely agrees.

**But the lane does diverge — one step earlier.** I started to write the disarm
as the tempting `h * 2**32 + l` in ordinary `Number` arithmetic, and **it moved
15 of 30 rows**, so it is a second plant, not a disarm. A double has 53 mantissa
bits, so `hi * 4294967296` is exact only when `hi == 0`, `hi < 2**21`, or `hi`
is a power of two. Every one of the 15 moved rows is attributed, per **operand**,
to exactly the operand with an inexact `hi` half (`gen_js_seam.py` prints that
attribution). The two rows that survive are `hi == 0` and `hi == 2**31`, both
exact — as predicted, not by luck.

**BigInt in `dtype.js` is load-bearing, not stylistic.**

## 5. Plant and disarm — disarm first

| | rows moved | against |
|---|---|---|
| **DISARM** `h * 2n**32n + l`, BigInt, a different expression for the same value | **0 / 30** | `repaired` |
| **PLANT** halves swapped to `lo << 32 \| hi` | **23 / 30** | `repaired` |
| **SECOND PLANT** `h * 2**32 + l` in `Number` arithmetic | **15 / 30** | `repaired` |

The disarm moves 0 and that is the only correct count. **The plant's 7 unmoved
rows are a theorem, checked not assumed**: swapping is invisible exactly when
`hi == lo`, and the gate prints the `hi`/`lo` of each — `0:1`, `0:2`,
`4294967295:4294967295`, `4294967295:4294967294`… all have `hi == lo` in the high
word. `floor_mod(-8,4) = 0` (`0:0`) is the degenerate case.

The gate's own liveness condition is `repaired == CPython` **and** `repaired == C`
**and** plant ≠ 0 **and** disarm == 0. It exits 0 only if all four hold.

## 6. The F32 seams — `gen_f32_seam.py`, 6 rows

| seam | in → out | CPython | node | cc | agree |
|---|---|---|---|---|---|
| `bf16` | U32 → F32 | `1.5` | `1.5` | `1.5` | yes |
| `fp16` | **F32** → F32 | `1.5` | **`0`** | `1.5` | **NO** |
| `fp8_from` | U32 → U32 | `60` | `60` | `60` | yes |
| `fp8_to 0x3C` | U32 → F32 | `1.5` | **`1`** | `1.5` | **NO** |
| `fp8_to 0x7E` | U32 → F32 | `448.0` | `448` | `448` | yes |
| `fp8_to 0x7F` e5m2 | U32 → F32 | `nan` | **`2143289300`** | `nan` | **NO** |

`node` 3/6 against CPython. `cc` 6/6. Rows present 6/6 both lanes.

**A rule I derived and this gate REFUTED.** I predicted "a seam taking `U32`
agrees, a seam whose `F32` crosses disagrees". `fp8_to(U32, U32) -> F32` takes
two `U32` and still disagrees on 2 of 3 rows. What survives is narrower: the two
`U32 → U32` seams agree exactly; `fp16` disagrees for an instrumented reason
(bits vs value); **`fp8_to`'s divergence is measured but NOT localised and is
deliberately not guessed at here.**

One number needed care: `cc` first read 5/6 until I compared as floats, because
`F32.show` prints `448` where CPython prints `448.0`. That is a **format**
difference. A count containing both kinds of miss is a count that means two
things at once.

## 7. What remains

- **Declare the ABI once, in the type system.** Four undeclared conventions, two
  languages, two field-naming regimes. Until `H.I64` crosses by a declared rule,
  the next `i64_of` is a coin flip.
- **`fp8_to`'s JS divergence is unlocalised.** 2 of 3 rows, mechanism unknown.
- **`ceildiv(x, 0)`** answers `0` in both lanes where CPython raises. Still
  counted `diverge`, never `pass`.
- **`dtype.bend` is COLD** (`SOME PROOFS FAIL`, its own 14 seams) per
  `substrate-check.sh`, which prints *"ANY VERDICT TAKEN AGAINST THESE FILES IS
  INCONCLUSIVE"*. `gen_js_seam.py` does **not** gate on bend's verdict — it gates
  on stdout rows, like `rebase-gate.py`. That is deliberate, not an oversight.
- **No gate in this tree runs `node`.** Both gates here are new. Nothing
  prevents the JS lane rotting again silently.

## 8. Rules learned

- **`JSL2-1` — a lane that no gate drives is not "believed correct", it is
  unexamined.** The coordinator's brief inherited "the JS lane is believed
  correct". It agreed with CPython on **0 of 30**.
- **`JSL2-2` — an ABI that lives in two languages with no shared declaration is
  not a binding.** `i64_of` appeared twice, under one `CID`, with one name. The
  JS one was wrong about the *field names*; the C one was wrong about the
  *argument count*. Same tokens, different semantics, in opposite directions.
- **`JSL2-3` — a record crosses an FFI boundary by NAME in one lane and by
  LAYOUT in another, and `a.fst`/`a.snd` is the assumption that hides it.**
  `undefined >>> 0 === 0` is a silent totalisation: the identity seam answers `0`
  and prints a plausible row.
- **`JSL2-4` — "the JS lane is the correct twin" was refuted the moment it ran.**
  `JS-LANE.md` reasoned from tokens (`fst`/`snd`) without an execution. Same
  failure mode as the brief that asserted "the same flat assumption" in JS.
- **`JSL2-5` — a disarm can be a defect in disguise.** `h * 2**32 + l` in
  `Number` arithmetic looked like a re-spelling and moved 15 of 30 rows. **Had I
  asserted it moved 0 and not run it, the gate would have shipped a false
  theorem.** A disarm is only a disarm after it has moved 0 in fact.
- **`JSL2-6` — a derived rule is a hypothesis, and the gate that tests it may
  refute it.** "U32 seams agree, `F32` seams don't" survived 2 rows and died on
  the third. Report the refutation; do not narrow the rule to fit.
- **`JSL2-7` — `F32.show` prints `448`, CPython prints `448.0`.** Normalise
  before counting, or the count silently absorbs format noise.