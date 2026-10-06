# ABI-4 — WHICH OF THE THREE `of32` SITES WAS ABI-4, MEASURED

Rule prefix: **`ABI4-`**. Instrument: `abi4_gate.py` (98 rows × 15 arms).
As of `135bf0204` the output was `.agents/slop/abi4/abi4-gate.txt`, readable at that
commit; it is **not in the tree now**, and neither is `rows.json`. The 2026-10-06
re-measurement is `path-verdict.rows` (four runs, verbatim) and `probe/*.bend`.

> **THE INSTRUMENT WAS AN EXCEPTION FROM `2026-10-05` TO NOW, AND WAS GREEN BEFORE
> THAT. See `ABI4-7` below, which supersedes the "Gate rc 0, 16 PASS / 0 FAIL" line
> this file used to open with.** That line is still true *as of `135bf0204`* and is no
> longer true of the tree.

Reproduce: `.venv/bin/python checks/abi4_gate.py` — ~2 min when it runs, and today it
refuses in 2 s; the live tree is never written, every arm is built from `pristine` and
from nothing else.

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

## ABI4-7 — THE GATE WAS GREEN, THEN A MOVE MADE IT AN EXCEPTION, AND THE PATH IS NOT WHY IT IS RED NOW

**Measured, 2026-10-06. Artifacts: `path-verdict.rows` (the four runs, verbatim),
`probe/*.bend` (the four seam calls, plus the six-line module that names no file in
this repo).**

### Was it ever green? YES — at `135bf0204`, 2026-10-04, and never since

`git log -S'parents[2]' -- checks/abi4_gate.py` returns **one** commit, `3f0e70ff1`
("cleanup: THE POLICY IS \"PYTHON ONLY\"…"), and that is the commit that **created**
the file at this path — already carrying `parents[2]`. So the constant was never
*changed*; it was **born stale**, or rather born correct and immediately invalidated.

The arithmetic, which is the whole lesson:

| path | depth | `parents[2]` is |
|---|---|---|
| `.agents/slop/abi4/abi4_gate.py` | 3 below root | **the repo root** ✔ |
| `checks/abi4_gate.py` | 1 below root | `/Users/cyberistic/src` ✘ |

So `57d0fc387` ("slopcopies: **110 COPIES DELETED, 126 CITATIONS REPOINTED**") *moved*
the file up two levels, repointed every **citation** to the new path, and carried the
path **constant** across unchanged. `135bf0204` carries the artifact that proves the
green: `.agents/slop/abi4/abi4-gate.txt`, 98/98 on all 15 arms, `shipped 98/98 agree`,
16 PASS / 0 FAIL, `gate rc: 0`. **This is a regression, not the original condition,
and the regression is a MOVE, not an edit.**

### Before: an exception, with no denominator at all

    $ .venv/bin/python checks/abi4_gate.py ; echo $?
    Traceback (most recent call last):
      File ".../checks/abi4_gate.py", line 306, in main
        pristine = JS_LANE.read_text()
    FileNotFoundError: [Errno 2] No such file or directory:
      '/Users/cyberistic/src/tinybendygrad/runtime/dtype.js'
    1

Under the venv it reaches `:306` as reported. **Under bare `python3` it fails one
line earlier and for a different reason** — `:78` `ModuleNotFoundError: No module
named 'tinygrad'`, because `tinygrad` is an *editable* install in `.venv` and nothing
rescues it when `sys.path` is pointed at `/Users/cyberistic/src`. Two interpreters,
two exception sites, **one answer: it has no denominator.** An exception is not a red
gate; it has no denominator and no disagreement, so it was excluded from every count
by being uncategorisable.

### The fix, and the trap inside it

`parents[2]` → **`parents[0]`**, not `parents[1]**. `Path.parents` is 0-indexed, so
`parents[0]` *is* `checks/`'s immediate parent, which is the repo root. Writing
`parents[1]` is **also wrong** (it is `/Users/cyberistic/src/tries`) and I wrote it
first; what caught it was not a review but the assertion added below, which turned the
second mistake into a stated refusal instead of a third exception.

### After: a verdict, and it is RED — on the toolchain, not on ABI-4

    == no backend for arm shipped: rc=1
    SOME PROOFS FAIL
    Error:
    - expected : @-R:Type -> @k:(@_:F32 -> IO.OP<R>) -> IO.OP<R>
    - observed : F32
    5>|     v0 : F32 <- D.Dt.fp16(1.5)
    rc 1

**Denominator: 98 rows × 15 arms = 1,470 comparisons designed, 0 reached.** The gate
now has a number where it had a traceback, and the number is: it dies on the *first*
arm, so **no `NEEDS`, no `FIXES`, no plant, no disarm, no locality fence, and no
`rc_of` at `:498` was ever executed.** The 16-row verdict table is unreachable.

**And the red is not about ABI-4.** All four seams fail identically — `Dt.fp16`,
`Dt.bf16`, `Dt.fp8_to`, `Dt.fp8_from`, *and* the four module-level wrappers
(`float_to_fp16`, `float_to_bf16`, `fp8_to_float`, `float_to_fp8`) — with the same
`expected : @-R:Type -> @k:(@_:F32 -> IO.OP<R>) -> IO.OP<R>`: a two-argument
continuation-passing shape. `probe/min_prim.bend` is **six lines, names no file in
this repository, and calls `F32.add(1.5, 1.0)`** — a primitive, from `Base`. It
fails with the identical error.

> **So no Bend program in this repo that applies a two-argument function compiles
> today, under `bin/bend`. That is a toolchain fact, and it is not this unit's to fix.**

`bin/bend` is `exec bun references/bend/bend2/main.ts`, and that checkout is on
**`main` at `v2.0.34-6-g0187512` — six commits past the tag the tree targets**, not
pinned. The six touch `comp.ts`, `safe.ts`, `main.ts` and `bendtt.lean`, i.e. exactly
the elaboration core, and one is *"A match inside a type goes to `--verdict` at the
goals bend2 checked it at, so an erased field binds dead and a field's type reaches
its arm (#1157)"*. **Suspicious, not proven**: pinning the shared checkout to prove it
would break the six other units running `bend` off it, so it is reported, not
attempted. **A moving `main` behind a lane is the same failure as a moving `parents[N]`:
a constant that expires silently.**

### Inputs that are simply MISSING

- **`checks/abi.json` does not exist anywhere in the tree** (`find . -name abi.json` →
  nothing). `checks/abi_gate.py:49` `DECL = HERE / "abi.json"` therefore raises
  `FileNotFoundError` at `:532` — measured, rc 1. `abi4_gate.py:498` invokes that
  gate, so `:504`/`:505` ("abi_gate.py exits 0 against this tree") would be **false
  for a reason that has nothing to do with ABI-4.** The same slop→checks move took
  `abi.json`'s expectation with it and left the file behind.
- `checks/abi_gate.py:41` also still reads `REPO = HERE.parents[2]` — **the identical
  defect, still unfixed, in the gate this one depends on.** Not mine; reported.

### The gate can now see its own failure (this is the part that is not negotiable)

`sb-gate.sh` already states the rule in prose — *"A gate that exits 0 having run
nothing is WORSE THAN NO GATE, because it is trusted"*, and its rule 1 is *"`cd` to
the repo root and PROVE it. A cd that lands outside is exit 3."* It states it, and it
**applies it to itself and to its own three lanes only**: `$PORT`, `./bin/bend`,
`$BASE`, `$ORACLE`, `$DIFFER`, all literal. It has no repository-wide census of gates,
so **`abi4_gate.py` was never on its radar, and `checks/abi_gate.py` is still in the
same hole it would catch in one line.** That is the answer to "why did it not look at
this gate": it is not a gate over gates, and no gate here is.

So the fix carries the assertion the brief's standard asks for. `refuse()` exits
**3**, prints `REFUSED, NOT A VERDICT`, and asserts `REPO` really holds the tree plus
the presence of every input — a missing input is not a passing input, which is the
`[ -f $BASE ]`-with-no-else shape `sb-gate.sh` retired.

### Plant and disarm, run against the FIX

| run | `REPO` | rc | what it said |
|---|---|---|---|
| **FIX** | `HERE.parents[0]` | 1 | reaches `run()`; `no backend for arm shipped` |
| **PLANT** | `HERE.parents[2]` *(the regression, restored)* | **3** | `REFUSED … /Users/cyberistic/src is not the repo root` |
| **PLANT** | `HERE.parents[1]` *(the near miss)* | **3** | `REFUSED … /Users/cyberistic/src/tries is not the repo root` |
| **DISARM** | `HERE.parent` | 1 | **byte-identical to FIX**, stdout *and* stderr |

The plant that puts `parents[2]` back does not reproduce the old `FileNotFoundError`
— **it produces a stated refusal.** That is the fix surviving its own regression:
the failure is now a number the gate reports about itself instead of an exception it
throws. And the disarm moves **nothing**, which is the only correct count.

### What is still unsettled

1. Whether the six unpinned Bend commits are the cause. Reported, not measured;
   measuring needs the shared checkout, which is six other units' compiler.
2. Whether `abi4_gate.py`'s 98-row fixture set still *matches* `dtype.bend`'s seam
   signatures **once bend works again**. All four seams now look two-argument to the
   compiler while `dtype.bend:748` reads `def Dt.fp16(+x: F32) -> F32` and
   `dtype.bend:1126` calls `Dt.fp16(x)` in a direct application — so either the
   compiler's reading is the wrong one or the tree has drifted. **Unmeasured, and
   the gate cannot answer it until it can compile a row.**
3. `abi.json`. Nothing in the tree declares ABI-4 any more, so the declaration half of
   this gate's argument has no file to cite.
