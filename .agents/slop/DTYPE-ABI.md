# DTYPE-ABI — seven undeclared conventions, and a gate that reads the declaration

Rule prefix: **`ABI-`**. Files: `.agents/slop/abi/`.
**SEVEN, NOT FOUR.** The four named in the brief are ABI-1…ABI-4; the gate found three more.

> ## THIS FILE WAS A STUB AND SAID SO.
>
> It read, in full: `STATUS: stub. conventions not yet cited; measurement not yet built.`
> — **beside 216 KB of instrument**: a 623-line `abi_gate.py`, a declaration in `abi.json`,
> and two generated backends (`gen/probe.gen.c` 5,007 lines, `gen/probe.js` 894).
>
> **A stub that says "not yet built" next to a working gate is a report that lies by
> omission, and it is the same defect as a missing row beside a passing one.** A reader
> checking only the prose concludes the job was not attempted.
>
> **What follows was measured from the gate's own output, not from the stub.** Rule `ABI-`.
> `runtime/dtype.c` and `runtime/dtype.js` are **byte-unchanged** — as instructed.

## The declaration is data, not prose

`abi.json` is read by `abi_gate.py`, which drives both lanes and **attributes every
disagreement to one of the four ids**. Its own `_about` block states the limit of the
site check, which is the sentence that matters most in the whole artifact:

> **"That is a DANGLING-POINTER check, not a behaviour check: it can tell you this document
> has gone stale, and it can NOT tell you a lane conforms. Conformance is measured, in
> `rows`."**

**A declaration that cannot fail is a comment with JSON syntax.** This one can: the cited
`file:line` must still contain the token, and conformance is a separate measurement.

## The two backends are cited, not inherited by assumption

> Generated-file sites (`probe.gen.c`, `probe.js`) are **the BEND BACKENDS, not the
> lanes.** They are cited because **two of the four conventions are actually implemented
> there and only inherited by the lanes.**

```
c    gen/probe.gen.c:3133   io_eff_rows[c].run(e, fs, w)
     "the frame is Term* fs of n = cid_arity(c) slots; ctr_take at :3136 built it"
js   gen/probe.js:777       op.run(...op.args, op.kont)
     "op.args is a JS array of NATIVE values, passed through with NO conversion"
```

**ABI-1 and ABI-4 are properties of the backends, and the lanes merely inherit them.** A
lane written by reading the other lane's *code* inherits nothing — which is exactly how both
bugs happened, and why a comment did not prevent either.

## The four original conventions

| id | statement | bug it shipped |
|---|---|---|
| **ABI-1** | a seam receives a **positional frame** of length `cid_arity(the CID)`; an `H.I64` argument is **ONE slot**, not two | C read `f[0],f[1]` = arg 0 + arg 1 and returned **two allocation addresses** |
| **ABI-2** | a record crosses by **field name** | JS read `p.fst`/`p.snd` against fields `hi`/`lo`; **both `undefined`, and `undefined >>> 0 === 0`**, so `i64_of ≡ 0` and **`i64_trunc`, the identity, was not the identity** |
| **ABI-3** | pair order is `(hi << 32 \| lo)` on both sides | agreed **by coincidence**; `pack64` works by **layout, not contract** |
| **ABI-4** | a scalar crosses as **bits** in C and as a **value** in node | `fp16(1.5)` is **`0`** under node |

## What the gate measures — the numbers, from its own output

```
shipped          node disagrees with CPython on   9/12
js-repair-abi2   node disagrees with CPython on   4/12
disarm-abi2-js   node disagrees with CPython on   4/12    <- the control: SAME, so ABI-2's
                                                              repair is what moved the 5 rows
rows moved (ABI-4 plant): 3/12  ['abi4_fp16_1p5', 'abi4_fp16_1p1', 'abi4_fp16_m2p25']

PASS  the ABI-2 repair fixes every record row
PASS  the ABI-2 repair touched ONLY record rows
FAIL  the ABI-4 repair touched ONLY F32 rows
PASS  the ABI-2 disarm moved 0 against the repair
PASS  all four obligations applied, node agrees with CPython everywhere
PASS  the repaired JS lane is byte-equal to the C lane on all rows
gate rc: 1
```

**`gate rc: 1`, and the FAIL is the honest part.** Applying all four obligations makes node
agree with CPython on **12/12** and **byte-equal to the C lane on all rows** — but **the
ABI-4 repair on its own moves rows outside the F32 set**, so ABI-4 is **not yet correctly
localised**. Reported, not reconciled.

The rows make ABI-4 concrete:

```
abi4_fp16_1p5        CPython 1.5               node 0
abi4_fp16_1p1        CPython 1.099609375       node 1.0996094
abi4_fp16_m2p25      CPython -2.25             node nan
abi4_fp8to_0x3C      CPython 1.5               node 1
```

## The three it found by running it

- **ABI-5 — `Term` is a `u64` in C (`probe.gen.c:171`) and a JS `number` in node
  (`dtype.js:142` answers `Number(...)`).** Nothing states which parts of a value are exact
  in each. **This is the whole `Number`-mantissa question, and ABI-5 is where it belongs.**
- **ABI-6 — the zero-divisor branch: both lanes answer `0` where `tinygrad`'s `helpers`
  raise `ZeroDivisionError`.** **The lanes AGREE**, so it is a divergence from upstream, not
  between lanes — and it is counted `diverge`, **never `pass`**.
- **ABI-7 — `dtype.js`'s own return-style split** (ABI-4's `second_site`) was not localised
  when the document was written; it is now attributed.

## Rules this artifact earns

- **A report is not the work, and a stub is not a status.** The instrument was 216 KB and
  nearly finished; the prose said the measurement did not exist. **Write the report from the
  instrument's output, and if you run out, say which half you wrote.**
- **Attribute every disagreement to an id, or you have two lanes and no conversation.** The
  gate's contribution is not that it found ABI-5…7; it is that a red *can be named*.
- **A paired disarm that moves the same count as the plant proves the plant did nothing.**
  `disarm-abi2-js` reads **4/12**, exactly `js-repair-abi2` — so the 5 rows that changed are
  attributable to ABI-2's repair and to nothing else.

---

# UPDATE — ABI-2 IS REPAIRED IN THE TREE, AND THIS GATE NOW EXITS 0

Unit: `.agents/slop/jsfix/`, rules `JSF-1..JSF-9`. `runtime/dtype.js` was the file the
earlier brief forbade touching; that brief is withdrawn.

**`dtype.js:154` reads `p.hi`/`p.lo`; `dtype.js:162` answers
`{$:"tinybendygrad/helpers.I64", hi, lo}`.** Justified against ABI-2 above and against
the backend's own emitted names — the function `$tinybendygrad$047helpers$i64_of_hi_lo$`
**builds** the record as `{…, "hi": _hi_0, "lo": _lo_0}`, `$…$hi32$` **reads** `_x_0["hi"]`,
and `io_run` feeds the seam's return value straight into `op.kont(x)`. Both directions
are forced. Not against `dtype.c`, which is what both lanes were written by reading.

## The numbers moved

| | rows | before | after |
|---|---|---|---|
| `abi_gate.py` node | 12 | 3/12 | **12/12** |
| `gen_js_seam.py` node | 30 | 0/30 | superseded by `jsfix_gate.py` |
| `jsfix_gate.py` node | 30 | — | **30/30** |

## `FAIL the ABI-4 repair touched ONLY F32 rows` IS NOW `PASS`, AND IT WAS NEVER AN ABI-4 ESCAPE

`abi_gate.py`'s `js-repair-abi4` arm carried **ABI-2's edits as well**, so it was ABI-2's
repair wearing ABI-4's name and the five `abi123_*` rows it moved were moved by ABI-2.
The obligation was never entangled; the **arm** was. With the repair in the tree the arm
carries only ABI-4 edits and the check measures what it claims to. `abi_gate.py` rc 1 → **0**.

## ABI-6 IS ONE ROW, NOT FIVE

The statement above is **true of `ceildiv` and false of the other four**:
`tinygrad/helpers.py:74` and `:77` guard `cdiv` and `floordiv` with an explicit
`if y != 0 else 0`, and `floormod`/`cmod` derive from them. Measured:

```
floor_div  0:0  agree     floor_mod 0:7  agree
cdiv       0:0  agree     cmod      0:7  agree
ceildiv    ZeroDivisionError vs node 0:0 and cc 0:0   DIVERGE
```

**1 diverge, 4 agree**, counted `diverge` and never `pass`. Both lanes agree on all five,
so no lane-agreement check can see the one that diverges.

## Plant and disarm, disarm first and run — 30 rows, 10 arms

DISARM `p.hi → p["hi"]` **0/30** · DISARM the outbound object re-spelled **0/30** ·
DISARM both **0/30** · PLANT inbound **28/30** · PLANT **outbound** **30/30** ·
PLANT both as shipped **30/30** · PLANT ABI-3 in **23/30** · PLANT ABI-3 out **23/30** ·
PLANT ABI-5 `Number` arithmetic **15/30**.

**An inbound-only plant cannot see the outbound half**: the 2 rows only the outbound one
moves are `floor_mod|-8|4` and `cmod|-8|4`, whose true answer *is* `0:0`, so the inbound
totalisation coincides with the truth there. Every arm is matched to an **exact Python
model** on all 30 rows, so no 0 is unexplained.

## ABI-8 — the declaration's own pointers went stale the moment the repair landed

`bend -o` embeds `import "./x.js"` verbatim, so editing `dtype.js` moved every
`probe.js` body `file:line` by **exactly +21** (894 → 915; I64 ctor 467 → 488, `hi32`
502 → 523, `op.run` 875 → 896) and changed no convention. `probe.gen.c` did not move.
**All four stale citations were in the generated file.** Backend citations are now
`{file, body, token}` — **by name** — and `abi_gate.cite_ok` resolves the name to its
**definition**, not a call site (`io_run` appears at `probe.js:701` as an argument and
is defined at `:861`).

## Still open, and not this unit's

**ABI-4.** `dtype.js:97` and `:137` still apply `of32` to an arithmetic value and
`:145` still answers a pattern where the backend consumes one. `abi4_fp16_1p5` is `0`
and `abi4_fp8to_0x3C` is `1` under node. `js-repair-abi4` makes all 12 rows agree **in
`$TMPDIR` only**. **`gen_js_seam.py` now aborts** on a moved anchor and was left that
way — a defect this unit introduced and did not clean up.

---

# UPDATE — ABI-4 IS REPAIRED IN THE TREE, AND IT WAS THREE SITES

Unit: `.agents/slop/abi4/`, rules `ABI4-1..ABI4-6`. `abi_gate.py` rc 0,
27 PASS / 0 FAIL. **The numbers in the two sections above about ABI-4 are now stale
and this section supersedes them**: `node agrees with CPython on 12/12`, the two lanes
disagree on 0/12, and `abi4_fp16_1p5` is `1.5`.

**THE TABLE ABOVE WAS ALSO WRONG IN A SECOND WAY, MEASURED.** It printed
`abi4_fp16_1p1  CPython 1.099609375  node 1.0996094`, i.e. node right. It is not:
that row is `0` under node and was red like the other three. Shipped was **8/12**,
not 9/12.

## WHICH OF THE THREE SITES IS ABI-4 — BY ROW SET, NOT BY READING

`NEEDS(s)` = rows green as shipped and red with site *s* re-broken.
`FIXES(s)` = rows *s* is sufficient, alone, for. 98 rows × 15 arms, every expectation
`tinygrad.dtype`-called, at `checks/abi4_gate.py`.

| site | NEEDS | FIXES | separable by row? |
|---|---|---|---|
| `dtype.js:143` **B** `of32(x)` on `dtype_fp16`'s declared `F32` argument | 10 | 10 | **yes** — `NEEDS(B)` touches no `fp8_to` row |
| `dtype.js:151` **C** no `of32` on `dtype_fp8_to`'s declared `F32` answer | 40 | **10** | **yes** — the only site with a row set of its own |
| `dtype.js:103` **A** `of32(v)` inside `fp8_decode`, on an intermediate | 30 | **0** | **no** — `NEEDS(A) ⊆ NEEDS(C)`, all 30 shared |

**So: B and C are ABI-4 AT THE SEAM, in the two directions the declaration names.
A is ABI-4's error class applied one call INSIDE the lane, on C's path, reachable only
through C — load-bearing for 30 rows, so not incidental, but not a third seam
convention. The three are one error class at two depths and two crossings, not three
coincidences, and the measurement says so instead of the reading.**

`FIXES(C)`'s ten rows are `fp8_decode`'s **early NaN/Inf returns**: they never build
the intermediate `v`, so they are fixed by C and blind to A. That is the entire
separation, and `abi_gate.py`'s 12-row probe has exactly ONE `fp8_to` row, which needs
A *and* C. **The `FAIL the ABI-4 repair touched ONLY F32 rows` episode was a fixture
entanglement before it was an arm entanglement, and de-entangling the arm alone could
not have fixed it.**

The inversion rows name the wrong representation rather than merely being wrong:
`Dt.fp16(1073741824.0)` arrives as the value 1073741824, whose own f32 *pattern* is
`0x40000000` = 2.0, so a pattern-reading lane answers `2` where CPython answers `inf`.

## THE CONVERSION IS FORCED ONTO THE SEAM — MEASURED, NOT CHOSEN

The alternative spelling (`fp8_decode` answers a value, the seam's `of32` removed) is
green on 88/98 and red on **exactly** `FIXES(C)`, because those ten rows never reach
the `return` that carries the conversion. Both spellings were run so this could not be
"I picked the one that went green".

## THE REPAIR

Three lines and **no net line count** in `dtype.js`: the `of32` on `dtype_fp16`'s
argument deleted, the `of32` inside `fp8_decode` deleted, one `of32` added to
`dtype_fp8_to`'s return. Shipped 57/98 → **98/98**. `abi_gate.py` 27 PASS / 0 FAIL rc 0;
`jsfix_gate.py` 18 PASS / 0 FAIL rc 0 at 30/30; `jsfix_e2e.py` rc 0; `e2e.sh` 7/7 rc 0;
`jslane2/gen_f32_seam.py` — never re-run before today — **3/6 → 6/6, lanes agree 6/6,
rc 0**, which is a third independent witness whose comparison is *weaker* than
`abi_gate.py`'s and therefore not an artefact of normalisation.

`abi_gate.py`'s `js-repair-abi4` arm is **deleted**: an arm that applies a repair to an
already-repaired tree is a tautology. `plant-abi4-js` re-breaks all three sites and
`disarm-abi4-js` re-spells all three, both against `shipped`.

## ABI4-4 — A DANGLING PAREN PASSED 98/98, AND A DEAD LANE WAS CALLED GREEN

The repair first landed with a stray `)` in `fp8_decode`. `node` exited 1 with empty
stdout. `abi4_gate.py` reported **98/98** and `abi_gate.py` reported **"node agrees
with CPython on 12/12"** — because both measure a *patched copy*, and `vs()` excludes
absent rows from `bad` by design, so **a lane that printed nothing counted as a lane
that was never wrong**. Both gates now exit on `node`'s exit status or a short row
set, and `abi4_gate.py` asserts the shipped tree's rows equal the full repair's.

## ABI4-5 — THE POINTER CHECK NOW READS `undeclared`, AND AN ENTRY MAY DECLARE ITSELF HISTORICAL

The blind spot is closed: every `<path>:<line>` in `undeclared` is checked. An entry may
opt out with `{"historical": true, "why": ...}`; exactly one does, **ABI-8**, which
narrates a measurement that *was* true (`probe.js` 894 → 915). **A guard that is always
red on a class of entries is a guard whose green is worth less than its red**, so the
author of the prose declares which claims are live. Planted `:74` → `:740`: rc 1.
Reverted: rc 0. One live reference was stale and is fixed (ABI-5's `dtype.js:162` →
`:168`).

## ABI4-6 — THE ARM-ENTANGLEMENT FENCE, ON EVERY ARM

`js-repair-abi4` failed "touched ONLY F32 rows" because the **arm** carried ABI-2's
bytes. A row-count fence cannot see that; a **content** fence can, because it reads the
bytes the arm would apply. `abi4_gate.py` now runs it over **all 15** arms, and
`abi_gate.py` over every non-ABI-2 JS arm. Planted: one `JS_I64_OF_FST` edit added to
the ABI-4 plant turns `abi_gate.py` red on **both** fences, rc 1. The structural half of
the fix is that every arm in `abi4_gate.py` is built from `pristine` and never from
another arm, so an arm cannot inherit an edit even by accident.

`jsfix_gate.py`'s 30 rows are all `Dt.i64_*` and no arm of this repair touches an I64
helper, so its moving 0 is a **theorem about its row set**, not evidence of locality.

## THE GENERATORS — DISPOSITION, NEITHER EDITED (`.agents/slop/jslane2/` is not this unit's)

- **`gen_js_seam.py` — quarantined by supersession, still aborts.** `READ_SHIPPED` is
  ABI-2's pre-repair `p.fst`/`p.snd` text and occurs 0× now. Everything it measured is
  reproduced and exceeded by `checks/jsfix_gate.py` + `jsfix_e2e.py` (same 30 rows, same
  `int64.min`, same `tinygrad.helpers`-called oracle, 10 arms not 4, including the
  outbound-only plant it lacked). **Do not re-anchor it; there is nothing left for it
  to measure.**
- **`gen_f32_seam.py` — runs, and is green.** First re-run today: 3/6 → **6/6, rc 0**.
  Output kept at `.agents/slop/abi4/gen-f32-seam.txt`. One defect reported, not fixed:
  its `norm` is `repr(float(s))` with no f32 round-trip, so it would call `fp16(1.1)` a
  lane disagreement for a formatting reason — it escapes only because no `1.1` row is in
  its `CASES`.
