# ABI-4 — WHICH OF THE THREE `of32` SITES WAS ABI-4, MEASURED

Rule prefix: **`ABI4-`**. Instrument: `abi4_gate.py` (98 rows × 15 arms).
Output: `abi4-gate.txt`. Rows persisted: `rows.json`. Gate **rc 0, 16 PASS / 0 FAIL**.

Reproduce: `python3 checks/abi4_gate.py` — ~2 min, the live tree is never
written; every arm is built from `pristine` and from nothing else.

## The answer, in one line

**`dtype.js:143` (B) and `dtype.js:151` (C) are ABI-4 at the seam — the inbound and
outbound crossings. `dtype.js:103` (A) is ABI-4's error class applied one call
inside the lane, on C's path, and no fixture can tell it from C. None is
incidental; all three are load-bearing.**

| site | NEEDS | FIXES | separable by row? |
|---|---|---|---|
| B `of32(x)` on `dtype_fp16`'s declared `F32` argument | 10 | 10 | **yes** — `NEEDS(B)` touches no `fp8_to` row |
| C no `of32` on `dtype_fp8_to`'s declared `F32` answer | 40 | **10** | **yes** — and the only site with a row set of its own |
| A `of32(v)` inside `fp8_decode`, on an intermediate | 30 | **0** | **no** — `NEEDS(A) ⊆ NEEDS(C)`, all 30 shared |

`NEEDS(s)` = rows green as shipped and red with site *s* re-broken.
`FIXES(s)` = rows *s* is sufficient, alone, for.

## How it is known, and not read

`NEEDS`/`FIXES` are row sets, so the claim is arithmetic over 98 rows rather than a
reading of three functions. Two row classes do the separating:

- **`FIXES(C)`'s ten rows are `fp8_decode`'s early NaN/Inf returns.** They return
  straight out of a branch and never build the intermediate `v`, so they are fixed by
  C and are blind to A. That is the entire separation, and `abi_gate.py`'s 12-row
  probe has exactly one `fp8_to` row, which needs A *and* C — so its ABI-4 arm could
  never have separated them, and its "repair touched ONLY F32 rows" failure was a
  fixture entanglement first and an arm entanglement second.
- **The inversion rows name the wrong representation instead of merely being wrong.**
  `Dt.fp16(x: F32)` receives a *value*, so `Dt.fp16(1073741824.0)` arrives as the JS
  number 1073741824, whose own f32 pattern is `0x40000000` — the value 2.0. Broken:
  `1.5`. CPython: `inf`. A lane reading its argument as a pattern answers `2`, which
  says *which* representation it used; `fp16(1.5) = 0` cannot.

## The conversion is forced ONTO the seam — measured, not chosen

The alternative spelling (`fp8_decode` answers a value, the seam's `of32` removed) is
green on 88/98 and red on **exactly** `FIXES(C)`. So it is not equivalent: the
conversion placed at `fp8_decode`'s `return` is bypassed by 10 of its 44 reachable
rows, because those rows never reach the `return` that has it. `dtype.bend`'s
signature says the seam owes a value; the lane's control flow says where the
conversion has to live.

## Plant and disarm, disarm first

Three disarms (re-spellings of the shipping text at one site each — `v * 1`,
`x * 1`, `>>> 0`): **0 / 0 / 0**, the only correct count.
Three plants, each a **second** mutation and not a copy of the break:
`of32` moved to the return (**30**), the **reverse** converter `bits32` at the
argument (**8**), a **double** `of32` at the seam (**40**).

## Locality, three ways, and one of them was missing

- **By row set**: the repair moved 41/98 rows and **0** outside `abi4_*`.
- **By content**: the repair's 20 diff lines name no other ABI's token — and the same
  fence now runs over **all 15 arms**, because the historical entanglement was an arm
  quietly carrying two conventions, and a fence on the one arm that mattered today is
  a fence that will be wrong tomorrow. Planted: adding one `JS_I64_OF_FST` edit to the
  ABI-4 plant turns `abi_gate.py` red on **both** fences (the row fence *and* the
  content fence), rc 1.
- **By the tree**: this gate patches a copy, so it could not see the tree's own
  syntax. It did not, and that mattered — see ABI4-4.
- `jsfix_gate.py`'s 30 rows are all `Dt.i64_*` and no arm here touches an I64 helper,
  so its moving 0 is a **theorem about its row set**, not evidence of locality. Its
  rc is the only thing claimed for it.

## ABI4-4 — a dangling paren passed 98/98 here, and `abi_gate.py` called a dead lane green

The repair landed with a stray `)` in `fp8_decode`. `node` exited 1 with empty stdout.
`abi4_gate.py` reported **98/98** and `abi_gate.py` reported **"node agrees with
CPython on 12/12"**, because both measure a *patched copy* and neither looked at
`node`'s exit status. Absent rows are excluded from `vs()`'s `bad` by design — so a
lane that printed **nothing** counted as a lane that was **never wrong**.

Both gates now `sys.exit` on `node`'s exit status or a short row set, and
`abi4_gate.py` additionally asserts that the shipped tree's rows equal the full
repair's, so "the tree IS the repair" is a row comparison rather than an intention.

**A green that was earned by a lane that did not run is the most expensive kind, and
it took two instruments to get one.**

## ABI4-5 — the declaration's `undeclared` block is now read

`abi_gate.py`'s pointer check read `abi[i]["site"]` and nothing else, which is exactly
where the stale citation was found today. It now checks every `<path>:<line>` in
`undeclared` too. An entry may opt out with a third element
`{"historical": true, "why": ...}`, and exactly one does: **ABI-8**, which narrates a
measurement that *was* true (`probe.js` moved 894 → 915). Checking history is a
permanent false red, and a guard that is always red on a class of entries is a guard
whose green is worth less than its red. The **author** of the prose declares which
claims are live. One live reference was stale and is fixed: ABI-5's `dtype.js:162` →
`:168`.

Planted: `tinygrad/helpers.py:74` → `:740` in ABI-6 gives 1 stale, rc 1. Reverted: 0,
rc 0.

## ABI4-6 — the two generators, measured

Neither is in this unit's ownership (`.agents/slop/jslane2/`), so neither was edited;
both are dispositioned here so neither can be mistaken for a passing gate.

- **`gen_js_seam.py` — QUARANTINED BY SUPERSESSION. Still aborts, by design of its
  own anchors.** `READ_SHIPPED` is ABI-2's pre-repair `p.fst`/`p.snd` text and occurs
  **0** times now, so it exits with `anchor not unique (0x)`. Its content is
  reproduced, and exceeded, by `checks/jsfix_gate.py` and `jsfix_e2e.py`:
  the same 30 rows, the same `int64.min` fixture, the same `tinygrad.helpers`-called
  oracle, and 10 arms instead of 4 — including the *outbound-only* plant that
  `gen_js_seam.py` lacked and which is what proved ABI-2 was two defects.
  **Do not re-anchor it; there is nothing left for it to measure.**
- **`gen_f32_seam.py` — RUNS, AND IS NOW GREEN. This is the third, independent
  witness.** Before the repair it measured **3/6** and `lanes disagree on 3/6`
  (`fp16_1p5`, `fp8to_0x3C`, `fp8to_0x7F_e5m2`). It has now been re-run for the first
  time and reports **6/6, lanes agree 6/6, rc 0**. Output kept at `gen-f32-seam.txt`.
  It is the corroboration worth having, because its comparison is *weaker* than
  `abi_gate.py`'s — `repr(float(s))` with no f32 round-trip — so its pass is not an
  artefact of normalisation, and its row set overlaps neither of the other two gates'
  sets in any interesting way. It carries one defect, reported not fixed: its `norm`
  is `repr(float(s))`, so it would have called `fp16(1.1)` a lane disagreement for a
  formatting reason (`1.0996094` vs `1.099609375`) — which is `abi_gate.py`'s JSL2-7,
  and it only escapes because no `1.1` row is in its `CASES`.

## The row set, and why 98 and not 12

12 fp16 · 44 fp8_to over all four fp8 kinds and 11 patterns each · 10 bf16 ·
32 fp8_from. Every expectation is `tinygrad.dtype` **called**, and a raising oracle is
**fatal** rather than counted — which caught `td.dtypes[...]` being unsubscriptable,
which had marked 44 correct rows red and the repaired lane as disagreeing with CPython.
The `loc_*` rows (bf16, fp8_from: seams where no value crosses at all) exist to be a
fence, and the repair moved none of them.
