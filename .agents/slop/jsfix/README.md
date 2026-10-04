# jsfix — `runtime/dtype.js` read the wrong fields, in BOTH directions

Rule prefix for this unit: **`JSF-`**. Files: `.agents/slop/jsfix/`.

`runtime/dtype.js` shipped reading `p.fst`/`p.snd` on a record whose Bend fields are
`hi`/`lo`, **and** answering with `io_tup(...)` = `Tuple{fst,snd}` where the caller
reads `{hi, lo}`. Inbound and outbound, two defects, one file. Reproduce:

```
python3 .agents/slop/jsfix/jsfix_gate.py   # rc 0 -- 30 rows x 10 arms, node
python3 .agents/slop/jsfix/jsfix_e2e.py    # rc 0 -- the live lane, 30/30
python3 .agents/slop/abi/abi_gate.py       # rc 0 -- both lanes, 12 rows
```

## 1. The defect, and what it cost

`H.I64` is `I64{hi: U32, lo: U32}` — `helpers.bend:1639-1640`. Both `p.fst` and
`p.snd` were `undefined`, and **`undefined >>> 0 === 0`**, so `i64_of` answered
`0n` for every input. That is a **totalisation, not a misread**: the identity seam
`Dt.i64_trunc` answered `0`, and `0:0` is a plausible row. Counting it as "absent"
would have reported green.

| gate | rows | before | after |
|---|---|---|---|
| `abi/abi_gate.py` (12 rows, both lanes) | 12 | node **3/12** | node **12/12** |
| `jslane2/gen_js_seam.py` (30 rows, node) | 30 | node **0/30** | superseded by `jsfix_gate.py` |
| `jsfix/jsfix_gate.py` (30 rows, node) | 30 | — | node **30/30** |

`gen_js_seam.py`'s 6 rows moved from `jslane2/` to here: its `shipped`/`repaired`
arms are the shipped/pre-repair bytes, and those two states are now respectively
"the tree" and "a plant". Keeping it would have been a second copy of the same
fixture set with a stale claim in it.

## 2. The repair, and what justifies it

`dtype.js:154` reads `p.hi`/`p.lo`; `dtype.js:162` answers
`{$: "tinybendygrad/helpers.I64", hi, lo}`.

Justified against **the declaration** (`abi.json` ABI-2) and against **the backend's
own emitted names** — not against `dtype.c`, because `dtype.c` is what both lanes
were written by reading, which is the thing under dispute:

```
gen/probe.js   body $tinybendygrad$047helpers$i64_of_hi_lo$   {$: "…I64", "hi": _hi_0, "lo": _lo_0}
gen/probe.js   body $tinybendygrad$047helpers$hi32$           const _hi_0 = _x_0["hi"]
gen/probe.js   body $tinybendygrad$047helpers$lo32$           const _lo_0 = _x_0["lo"]
gen/probe.js   body io_run                                    const x = op.run(...op.args, op.kont)
```

The backend **builds** the record with `hi`/`lo`, **reads** it with `["hi"]`/`["lo"]`,
and feeds the seam's return value straight into `op.kont(x)`. So both directions are
forced, and the `$` tag must be the type name the backend itself emits.

`dtype.js:1-18` now names ABI-1…ABI-5 in its header. That header previously claimed
"a `.bend` that runs under both lanes cannot tell which one it got" — refuted by
measurement, and it was the sentence that licensed reading `dtype.c`.

## 3. Locality: the repair is LOCAL, and here is the measurement

**`abi_gate.py` rc is 1 on the pre-repair tree and 0 on this one, and the check that
flipped is the known `FAIL the ABI-4 repair touched ONLY F32 rows`.**

The cause was not an ABI-4 escape. `abi_gate.py`'s `js-repair-abi4` arm carried
ABI-2's edits too (`JS_I64_OF_OLD → JS_I64_OF_FIXED`, `JS_PACK_OLD → JS_PACK_FIXED`),
so it was ABI-2's repair wearing ABI-4's name and the five `abi123_*` rows it moved
were moved by ABI-2. With the repair in the tree those edits are gone from the arm
and the check measures what it claims to.

The same locality measured on 30 rows, where the two halves are separated:

| arm | rows moved | what it is |
|---|---|---|
| `plant-abi2-in-js` | **28/30** | inbound `p.fst`/`p.snd`; answers `0:0` on **every** row |
| `plant-abi2-out-js` | **30/30** | outbound `io_tup`; answers `\x00:\x00`, not a `hi:lo` pair |
| `plant-abi2-both-js` | **30/30** | the file exactly as it shipped |
| `plant-abi3-in-js` | 23/30 | words exchanged inbound |
| `plant-abi3-out-js` | 23/30 | words exchanged **outbound** |
| `plant-abi5-js` | 15/30 | `(hi * 2**32 + lo)` in `Number` arithmetic |

The 2 rows only the outbound plant moves are `floor_mod|-8|4` and `cmod|-8|4`, whose
CPython answer *is* `0:0` — so the inbound totalisation coincides with the truth
there. **An inbound-only plant cannot see the outbound half**, which is why
`plant-abi2-out-js` exists.

## 4. Plant and disarm, **disarm first, and run**

| | rows moved | against |
|---|---|---|
| **DISARM** `p.hi → p["hi"]`, `p.lo → p["lo"]` | **0/30** | `shipped` |
| **DISARM** the same object on one line, field order swapped, `* 1n` | **0/30** | `shipped` |
| **DISARM** both at once | **0/30** | `shipped` |
| **PLANT** inbound `p.fst`/`p.snd` | 28/30 | `shipped` |
| **PLANT** outbound `io_tup` | 30/30 | `shipped` |
| **PLANT** both halves as shipped | 30/30 | `shipped` |
| **PLANT** ABI-3 inbound | 23/30 | `shipped` |
| **PLANT** ABI-3 outbound | 23/30 | `shipped` |
| **PLANT** ABI-5 `Number` arithmetic | 15/30 | `shipped` |

**A disarm is only a disarm after it has moved 0 in fact.** `JS-LANE-GATE.md:§5`
already records one control in this project that *looked* like a re-spelling and
moved 15/30; here the tempting `h * 2**32 + l` in `Number` arithmetic is kept as
**PLANT F** for exactly that reason, and its 15 moved rows are attributed per operand
by `inexact()` — 53 mantissa bits, so `hi * 2**32` is exact only when `hi == 0`,
`hi < 2**21`, or `hi` is a power of two (`2147483648` = `2**31` is why
`int64.min` survives, as predicted and not by luck).

## 5. Every arm is modelled exactly, so no 0 is unexplained

A plant that fires on some rows and is silent on others is only a measurement if the
silence is accounted for. Each arm is modelled in Python and compared on **all 30**,
and the gate prints `unexplained N/30` per arm. All ten read **0/30**. Two model
bugs were found and fixed this way, both of which had produced confident wrong
numbers:

- `CIN["identity"]` returned the **unsigned** pattern, so the model predicted
  `1073741823:4294967294` for `floordiv(-7, 4)` — a number neither the lane nor
  tinygrad would ever produce.
- `CIN["numprod"]` was fed a signed value where it wanted the pattern, so
  `(u >> 32)` was `-1` instead of `4294967295`.

`io_tup` is the one arm with no value model: it builds a `Tuple`, so there is no
`hi:lo` to predict. The gate asserts the **shape** instead — no row answers a valid
`hi:lo` pair.

## 6. ABI-6 — classified, and it is ONE row, not five

`abi.json` said "both lanes answer 0 where tinygrad's helpers raise
`ZeroDivisionError`". That is **true of `ceildiv` and false of the other four**:
`tinygrad/helpers.py:74` and `:77` guard `cdiv` and `floordiv` with an explicit
`if y != 0 else 0`, and `floormod`/`cmod` are derived from them.

| seam | `tinygrad.helpers` | node | cc | |
|---|---|---|---|---|
| `floor_div` | `0:0` | `0:0` | `0:0` | agree |
| `floor_mod` | `0:7` | `0:7` | `0:7` | agree |
| `cdiv` | `0:0` | `0:0` | `0:0` | agree |
| `cmod` | `0:7` | `0:7` | `0:7` | agree |
| `ceildiv` | **`ZeroDivisionError`** | `0:0` | `0:0` | **DIVERGE** |

**1 diverge, 4 agree. Counted `diverge`, never `pass`.** Both lanes agree on all
five, so no lane-agreement check can see the one that diverges — which is exactly
why it has to be counted against upstream instead.

The five rows are in a separate `emit_divergence_rows()` block and enter **no**
agreement count. They have to be: the inbound plant sends `b` to `0n`, and then
`ceildiv(0, 0)` raised `ZeroDivisionError` **inside this gate**. That was ABI-6
arriving through the measuring apparatus, and it is why the model is the *lane's*
arithmetic (`lane()`) rather than the oracle's.

## 7. Not gated on bend's exit

`dtype.bend` is COLD. `bend -o` returns 0 here and the gate **reports** it beside the
row counts and never acts on it (`jsfix_gate.py`, `jsfix_e2e.py`). A missing backend
or a missing row is fatal; bend's return code is not. `rebase-gate.py`'s discipline.

## 8. ABI-4 is still open, and is not this unit's to close

The 12 rows of `abi_gate.py` that are **not** I64 are ABI-4, a different convention
in a different half of the same file:

```
abi4_fp16_1p5     CPython 1.5          node 0
abi4_fp16_1p1     CPython 1.099609375  node 1.0996094
abi4_fp16_m2p25   CPython -2.25        node nan
abi4_fp8to_0x3C   CPython 1.5          node 1
```

`js-repair-abi4`'s three edits make node agree with CPython on 12/12 and byte-equal to
cc on all rows — **in `$TMPDIR` only.** `dtype.js:97` and `:137` still apply `of32`
to an arithmetic **value** (pattern→value applied to a value is `of32(1.5) = 1`, the
smallest f32 subnormal), and `dtype.js:145` still answers `fp8_decode`'s pattern where
the backend consumes a value. That is ABI-4 and ABI-7, and the brief for this unit was
ABI-2 in both directions.

## 9. What could not be fixed

- **`gen_js_seam.py` was left as-is and now aborts.** Its `patch()` asserts
  `READ_SHIPPED` occurs exactly once in `dtype.js`, and that text no longer exists, so
  it exits with `anchor not unique`. I did not rewrite it: all 30 of its rows, its 5
  `FIXTURES` including `int64.min`, its `hi:lo` printing and its
  `tinygrad/helpers.py`-called oracle are reproduced in `jsfix_gate.py`/`jsfix_e2e.py`,
  and its `packed-vs-unpacked` second mutation is gone with the repair. Its stale claim
  (`repaired ... explicitly NOT applied to the tree`) is the reason it should not be
  revived as-is. **This is a defect I introduced and did not clean up.**
- **`gen_f32_seam.py`** is unaffected by the repair (its anchors are `dtype_fp16` and
  `fp8_to`) but is not re-run here; ABI-4's numbers are quoted from `abi_gate.py`.
- `abi.json` ABI-5's text still says `dtype.js:142 answers Number(...)`; that line is
  now 162. It is inside an `undeclared` prose block that the pointer check does not
  read, so the gate stayed green while the prose went stale — **which is the same
  failure the pointer check exists to prevent, in the one place it does not look.**
  Left for the coordinator with the ABI-5 entry.

## 10. Rules earned

- **`JSF-1` — A wrong read that TOTALISES is the worst kind.** `undefined >>> 0 === 0`
  turned a wrong field name into a plausible answer on every input, and `0:0` prints
  as a row. Emit rows so that *absent* and *present and wrong* cannot print alike.
- **`JSF-2` — "Broken in both directions" is two defects, and one plant sees at most
  one.** `plant-abi2-in-js` cannot move `floor_mod|-8|4` or `cmod|-8|4`, because those
  rows' true answer *is* the totalised value. A gate with only an inbound plant reports
  green on a lane whose `pack64` still builds a `Tuple`.
- **`JSF-3` — Separating plants need per-arm MODELS, not per-arm counts.** Every count
  here is explained by an exact Python model of that arm on all 30 rows, which is what
  caught two model bugs that had produced confident wrong numbers.
- **`JSF-4` — Modelling the oracle instead of the lane makes the instrument raise.**
  A plant that zeroes `b` calls `ceildiv(0, 0)`, and `ZeroDivisionError` came out of
  the gate's own arithmetic. ABI-6 arrived through the measuring apparatus.
- **`JSF-5` — A declaration that counts a divergence must CLASSIFY each row.** "5
  divergences" was 4 agreements and 1 divergence. `tinygrad` guards `cdiv` and
  `floordiv`; only `ceildiv` raises.
- **`JSF-6` — Cite a GENERATED body by NAME, never by `file:line`.** Measured here, not
  quoted: editing `dtype.js` moved every `probe.js` body line by **exactly +21**
  (894 → 915 lines; I64 ctor 467 → 488, `hi32` 502 → 523, `op.run` 875 → 896) because
  `bend -o` embeds `import "./x.js"` verbatim. `probe.gen.c` did **not** move — it
  embeds `dtype.c`. All four stale citations were in the generated file, which is why
  the declaration went stale the instant the repair landed, and why `abi.json`'s
  backend citations are now `{file, body, token}`.
- **`JSF-7` — A name citation must resolve to the DEFINITION, not a call.**
  `io_run` appears at `probe.js:701` as an argument and is *defined* at `:861`; the
  citation checked the wrong 160 lines until it was fixed. Two more ways it goes
  wrong: bend's names are `$a$047b$c$` and `$` is not a word character, so `\b$main$`
  can never match; and C writes `static Term io_exec(...)` — a return type between
  `static` and the name — while `io_tup` is a `#define`.
- **`JSF-8` — An arm named for a convention must contain only that convention.** The
  `FAIL the ABI-4 repair touched ONLY F32 rows` was ABI-2's edits inside an arm called
  `js-repair-abi4`. A repair that fixes 30 rows and moves 2 unrelated ones has not
  been localised; neither has one that moves 5 rows for an unrelated reason.
- **`JSF-9` — Once the repair is in the tree, the diagnosis becomes a plant, and the
  base becomes green.** `abi_gate.py`'s ABI-2 control was a three-point `red → green →
  green` on a lane that shipped red; it is now `green → red → green` on two directions,
  and the shipped row count is a measurement rather than a known failure.