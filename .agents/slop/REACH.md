# REACH — the corpus-wide ops denominator, both sides, and one honest DISAGREE

The unit that took this job changed the differ (684 insertions across `graphcmp.py`,
`graphcmp.bend`, `graphcmp-oracle.py`) and then **completed without a text response**,
leaving 268 KB of probes and no report. Everything below was **measured by the
coordinator afterwards**, against the tree as it stands. Nothing is transcribed.

> ## ⚠ THE BLOCK BELOW IS A **HISTORICAL BASELINE**, NOT THE CURRENT NUMBER.
> It reads 22 graphs and 53 of 77. That was **a true measurement of an older corpus**, and
> the file's own §"AND THE +18 IS NOT THE FIVE NEW GRAPHS" says so in prose. It is left
> unedited on purpose: it is the baseline the later addenda below are measured *against*, and
> rewriting it would delete the record of what moved.
>
> **Current, re-measured 2026-10-04 by the `notes-sweep` unit:**
>
> ```
> graphs in corpus      : 24        (was 22)
> ops UPSTREAM (denom)  : 77        (measured len(list(Ops))) -- UNCHANGED
> reached PY            : 59        (was 53)
> reached BEND          : 59        (was 53)
> reached BOTH          : 59        (was 53)   <- the honest coverage number
> py-only  (bend MISSING): []
> bend-only (py MISSING) : []
> reached by NEITHER    : 18        (was 24)
> VERDICTS              : 22 AGREE / 2 DISAGREE (lin, loop -- forward-only on purpose)
> ```
>
> Instrument: `checks/hermetic-census.py --no-publish` (one process per graph, no cache on
> the verdict path), and `graphcmp.py diff --graph <g>` once per graph for the verdicts. Both
> rc=0. The `18 not reached` were derived by me from the census's own per-graph op dicts and
> `{o.name for o in list(Ops)}` — see `.agents/slop/notes-sweep/01-GROUND-TRUTH.md`.
> **Every number in the block immediately under this banner is superseded; the two are kept
> apart rather than merged, because a reader must be able to see which one they are holding.**

## The headline, with its denominator — HISTORICAL BASELINE, 22 graphs, 53 of 77

```
graphs in corpus      : 22
ops UPSTREAM (denom) : 77   (measured len(list(Ops)))
reached PY            : 53
reached BEND          : 53
reached BOTH          : 53   <- the honest coverage number
py-only  (bend MISSING): []
bend-only (py MISSING) : []
reached by NEITHER    : 24
```

**35 -> 53, both sides, zero asymmetry.** A coverage number with no
`py-only`/`bend-only` split is not a coverage statement: it cannot distinguish "the
port reaches everything CPython reaches" from "both reach the same wrong subset".
Measured here, both are empty.

The 24 not reached, named (**this 24 is the 53-era complement and NO LONGER HOLDS — at 59
the complement is 18, listed in the banner above**):
`ALLREDUCE CDIV CMOD CMPEQ COPY CUSTOM CUSTOMI CUSTOM_FUNCTION FDIV GETADDR INS
MSELECT MSTACK MULACC NEG PROGRAM PYLITERAL REWRITE_ERROR SOURCE STAGE SUB THREEFRY
UNSHARD WMMA`

## AND THE +18 IS NOT THE FIVE NEW GRAPHS — that is the finding

The five graphs added (`alu`, `bit`, `where`, `move`, `flip`) were measured against the
union of what the corpus already reached, op by op:

```
# alu     rows=14  ops=13  NEW=[]
# bit     rows=10  ops=9   NEW=[]
# where   rows=8   ops=7   NEW=[]
# move    rows=22  ops=?   NEW=[]
# UNION of the four: 0 new -> 53+0=53 of 77
```

**⚠ `53+0=53 of 77` IS THE ARITHMETIC OF THIS UNIT'S WINDOW, NOT THE COVERAGE NUMBER.**
It was true at the time (22 graphs) and the corpus is now **24 graphs / 59 of 77**; the `0
new` finding is still the finding. `move`'s `ops=?` was left unmeasured here.

**Zero new ops from all four candidate families.** So the move from 35 to 53 is
**not** attributable to this unit's work — it came from graphs landed by earlier units
(`bw`, `sym`, `gate`, `lin`, `loop`, `group`, `indexed`, `commute`) whose arrival the
quoted 35 predates.

> **THE 35 WAS STALE, NOT WRONG.** It was a true measurement of an older corpus. This is
> the ordinary failure of a quoted number: nothing about adding graphs invalidates the
> figure, so it survives in notes, in a brief, and in a `LIMITS.md` section until
> somebody re-measures. **A number that was true when written is not thereby still true,
> and a corpus number ages every time the corpus grows.**

## The five new graphs, one verdict and one denominator each

**⚠ THE `flip` ROW AND EVERY `6/7` IN THIS SECTION ARE SUPERSEDED.** `flip` measured
**AGREE at 6/6** on 2026-10-04. The `7` came from a stale py-side census carrying
`GROUP=1`; `tinygrad/uop/ops.py:558-560` returns a lone src unchanged, so
`UOp.group(a.flip(0).uop)` **is** the FLIP and the py side is 6 nodes. Full derivation:
`.agents/slop/flip/FLIPR.md`; verdict re-measured independently by the `notes-sweep` unit
(`nodes=6/6  ops-reached=5/5 of 77  shared-cores=6  ONLY-PY=0  ONLY-BEND=0  RESIDUALS
B=2/0  VERDICT: AGREE`). **The four other rows below are unchanged and were re-measured.**

| graph | verdict | nodes | `?` ledger |
|---|---|---|---|
| `alu` | **AGREE** | 14/14 | `?=0 ?=0/6` |
| `bit` | **AGREE** | 10/10 | `?=0 ?=0/6` |
| `where` | **AGREE** | 8/8 | `?=0 ?=0/6` |
| `move` | **AGREE** | 22/22 | `?=0 ?=0/6` |
| `flip` | ~~DISAGREE~~ **AGREE** | ~~**6/7**~~ **6/6** | `?=0 ?=0/6` |

### The field-level `?` ledger is not redundant with the verdict — `flip` is the proof

⚠ **The next three passages are the argument that `?=0` does not imply AGREE. It is
STILL A TRUE ARGUMENT, but its only example has since been closed, and the number in it
has moved — so it no longer *proves* anything on its own. Do not cite `flip` as a live
counterexample; cite the surviving one, `loop`.**

**All five read `?=0` on both sides and one of them (`flip`, at the time this was
written) DISAGREEd.** The ledger measures *omission* — a field that was never filled —
and a graph can be complete and still wrong. It is the same reason `shared-cores=5`
coexisted with `field-mismatches=0` here:

```
# AT THE TIME, for flip:  cores=5  ONLY-PY=1  ONLY-BEND=2  field-mismatches=0
#   rung2-pairs=0  rung3.5-crossrefs=1  zip-truncated=0
# MEASURED 2026-10-04: cores=6  ONLY-PY=0  ONLY-BEND=0  field-mismatches=0
```

Every field of every *matched* node agreed, and the graph still had a node on one side
with no counterpart on the other. **"Nothing is missing" is not "nothing is wrong."**

### `flip`'s historical divergence, from the two canonical sides

**⚠ BOTH DIFFERENCES BELOW WERE WRONG ABOUT WHERE THE FAULT WAS, AND THE FLIP UNIT
SHOVED BOTH CAUSES INTO THE FIXTURE.** Kept because the reasoning is the lesson; read
`.agents/slop/flip/FLIPR.md` for the corrections.

```
py   6c6,7
< 2:i6 4:FLIP 3:f32 11:(l0:4,l0:3) 2:i0 1:N 8:n(b1,b0) 5:n(i5)
---
> 2:i6 4:FLIP 3:f32 11:(l0:4,l0:3) 2:i0 1:N 8:n(i1,i0) 5:n(i5)
> 2:i7 5:GROUP 4:void 1:R 2:i0 1:N 1:N 5:n(i6)
```

**Two differences, both structural, neither a field mismatch:**

1. **`FLIP`'s shape argument points at a different node class.** CPython: `n(b1,b0)` —
   two *Buffer* refs. The port: `n(i1,i0)` — two *index* refs. The shape is
   `(l0:4,l0:3)` on both sides, but the elements it points at are not the same kind of
   thing, so the port's `FLIP` is reading its bounds from somewhere CPython is not.
   ⚠ **CORRECTED: `b` is the BOOL atom, `buf` is `z` (`graphcmp.py:324-326`), so py
   `n(b1,b0)` is `(True, False)` — the flip-axis flags — and `n(i1,i0)` is the same two
   values spelled `u32`. NOT a disagreement at all.**
2. **The port wraps the `FLIP` in a `GROUP`; CPython emits it bare.** 7 nodes against
   6. This is the `nodes=6/7` denominator and the sole cause of `DISAGREE`.
   ⚠ **CORRECTED: the `7` was a BUG IN THE FIXTURE.** The extra `GROUP` came from the
   harness calling raw `O.UOp.new` and bypassing upstream's elision, which
   `tinybendygrad/uop/ops.bend` already had. The py side never had 7 nodes.**

`file:line` for both is **not yet established** — the differ reports the divergence in
the canonical stream, not in the port source, so locating it is the next step and is
**not** claimed here.

## The claim NOT made

This does **not** mean the corpus compares training graphs, and it must not be
stretched to say so. `bw` is the gradient of **one eager expression**, and the
scheduler/codegen direction is still **forward-only**: `lin` and `loop` DISAGREE on
purpose, for named measured reasons. **59 of 77** (was 53 when this was written) is
coverage of the **emitter**; it says nothing about coverage of
`schedule -> render -> compile`.

## And the traps this differ has already fallen into, all of which are still live

- **Row counts cannot distinguish two graphs that differ only in which op produced
  them.** The first `g_bw` was the identity PERMUTE: same 32 rows, same 11-op census,
  **every count read it as the same graph.** The ledger caught it (`?` live on 17 of 32).
- **The first float `CONST`** failed on both sides at once — `repr(ConstFloat(1.0))`
  against `F32.show(1.0)` = `1`. Fixed to IEEE-754 bits on both sides, **which is also
  the only spelling that separates two NaNs.**
- **Two identical failures compared equal**, and making differing pairs visible then
  found a truncated file and a 0-byte artefact a summary had called `not-comparable`.
- **`34 of 77` once accepted a non-`Ops` name** — an invented one took it to 35,
  SELFCHECK OK. It now rejects unresolvable names. **Keep that.**
- **`$ALL` still needs `bw:AGREE`** — `bw` measured **AGREE 32/32** on 2026-10-04, so this
  one is done. `graphs-agree=14` should read **22** (was "15", measured 22 on
  2026-10-04: `VERDICT: AGREE` on 22 of 24 graphs, DISAGREE on `lin` and `loop` only);
  `LIMITS.md` §2/§5 still carry stale numbers. **None of these pins is applied.**
  ⚠ **The pin is STILL WRONG IN THE TREE.** `graphcmp-repro.sh:66` greps
  `^graphs-agree=14$` against a run that now prints `22`, so that health gate reports a
  fully correct run as unhealthy — the exact failure §3c of `graphcmp-LIMITS.md` records
  it having caused once already, when it pinned `13`. **`graphcmp-repro.sh` is a gate
  script and out of scope for the `notes-sweep` unit; reported, not patched.**

## One instruction-level trap, for whoever runs this next

`graphcmp.py` **cannot be run with a bare `python3`**, and the failure is silent:

```
$ python3 .agents/slop/graphcmp.py diff --graph alu
ModuleNotFoundError: No module named 'tinygrad'
```

`sys.path[0]` is the **script's** directory, not the cwd, so the repo-root `tinygrad/`
is not on the path. The runner's own invocation is `P=.venv/bin/python`. Under `zsh`,
`$E`/`$P` do **not** word-split (`command not found: env -u PYTHONPATH ...`), and
`timeout` is **not installed** on this macOS — both failures produce **empty output and
a misleading `rc=0`** when captured to a file. Use `perl -e 'alarm N; exec @ARGV'`.

> **AN INSTRUMENT THAT PRODUCED NOTHING MUST NOT BE REPORTED AS A PASS.** Five runs came
> back `rc=0` with zero bytes on both streams here, and only running the command
> **plainly, in the terminal**, surfaced the `ModuleNotFoundError` underneath. This is
> the same defect as `--check-only` passing an empty file, one layer out.

---

# ADDED 2026-10-04 by the `arith` unit — 53 -> 59, all six arithmetic ops

Full report, mutations and walls: **`.agents/slop/arith/REACH-ARITH.md`**. Re-measured with
`checks/both-census.py`, which emits **both sides** — the census that produced the
53 above (`reach/census.py`) counts the **py side only**, so "both sides read 53" was not
produced by an instrument that could have found the two differing.

```
                       BEFORE    AFTER
graphs                  22        24
denominator             77        77     measured len(list(Ops))
reached PY              53        59
reached BEND            53        59
reached BOTH            53        59
py-only                 []        []
bend-only               []        []
NEITHER                 24        18
```

`cdiv` **AGREE** 10/10, `late` **AGREE** 12/12, every ledger marker (`z y u q X! BAD E ?`) `0/0`
on both, `control` OK and `cross` loud on both, three mutations caught in ordered **and**
`--equiv`.

**THE FINDING, which is the reason this unit exists: four of the six are REWRITE-ONLY ops in
this tree, and each one's eager spelling is exactly the LHS of the rule that mints it.**
`elementwise.py:123` (`sub` -> `ADD(a, NEG(b))`), `:82` (`neg` -> `self * -1`), `:336-337`
(`eq` -> `ne(x).logical_not()`), `:255` (float `div` -> `MUL(a, reciprocal(b))`) against
`codegen/decomp/op.py:105,106,117,124-125`. `CDIV` and `CMOD` are the two that the eager module
constructs itself (`elementwise.py:251` and `:226`) and need no rewrite at all. So `g_commute`'s
"CMPEQ is NOT reachable from an eager graph at all" was **true and incomplete** — it was true
because nobody had tried the rewrite route.

**`late` is a graph the port can REPRODUCE but not PRODUCE.** The py side is upstream's
`get_late_rewrite_patterns` on upstream's eager graph; the port's arena is the result written out
node by node. Same shape as `g_gate`. Which four ops the rewrite reaches is the **backend's**
property, read from `Device.default.renderer.code_for_op` exactly as `codegen/__init__.py:350`
reads it: CPU's `ClangRenderer` wants all four, `NullRenderer` wants three.

**Two cautions for the next reader, both measured.**

- **RESOLVED by the `FLIPR` unit, whose addendum is below. This caution is now a HISTORY,
  not a live warning.** `flip` read DISAGREE 6/7 when this unit took its baseline and reads
  **AGREE 6/6** now. **RE-MEASURED 2026-10-04 by `notes-sweep`: `AGREE 6/6` confirmed**, so
  the table at the top of this file has been corrected to match and the four `6/7` readings
  are marked superseded. The `graphs-agree` count this caution worried about is **22**, not
  14 and not 15.
- **`diff --dev NULL` exits 2 and prints NOTHING when captured** (0 bytes on stdout), the
  well-posedness gate refusing `py=['sNULL'] bend=['sCPU']`. Run it plainly. This is the
  "instrument that produced nothing" trap above, hit from the opposite direction: the
  refusal is real and correct, and only its silence under capture is the bug.
  ⚠ **CITATION CORRECTED 2026-10-04:** this wall cited **`graphcmp.py:2869`**, which is a
  `CONFLATION 1` verdict line inside `cross`, not the precondition. The precondition is
  `pdev, bdev = sorted(...)` / `if pdev != bdev:` at **`graphcmp.py:3082-3083`**, printing
  at **`:3084`** and exiting 2 just after.

**The claim still NOT made, unchanged:** this does not mean the corpus compares training
graphs. `bw` is the gradient of one eager expression and `schedule -> render -> compile` is
still forward-only. 59 of 77 is coverage of the **emitter**.

---

# ADDENDUM (2026-10-04, unit `FLIPR`) — `flip` is CLOSED, and the `7` was never upstream's

Full report, both `file:line`s, and the four walls: **`.agents/slop/flip/FLIPR.md`**.
Both edits are in `graphcmp.py` / `graphcmp.bend`, claimed per `flip/CLAIM.md`.
**Nothing committed.**

## The two differences were NOT one cause, and the "7/7" target was wrong

`graphcmp.py:1355` and `graphcmp.bend:1241` both printed a py-side census containing
**`GROUP=1`**. Measured, calling CPython: **`GROUP=0`.** `UOp.group` is not
`UOp(Ops.GROUP, ...)` — `tinygrad/uop/ops.py:558-560` returns a lone src unchanged, so
`UOp.group(a.flip(0).uop)` **IS** the FLIP and the py side is 6 nodes. **That stale
`GROUP=1` is the sole origin of the `7`**, so **`7/7` was never a reachable target. The
denominator is `6/6`.**

## `file:line`, and what each one is

| | where | verdict |
|---|---|---|
| **the extra `GROUP`** | **`.agents/slop/graphcmp.bend:1274`** | **A DEFECT — in the fixture, not the port.** `tinybendygrad/uop/ops.bend:2486-2495` **already has upstream's elision**, committed. The fixture called the raw `O.UOp.new` and bypassed it. Fixed: call `O.UOp.group`. |
| **the `arg` atom `b` vs `i`** | **`.agents/slop/graphcmp.bend:1273`** over **`tinybendygrad/uop/ops.bend:1066`** | **A PORT VOCABULARY GAP, over-reported by the differ.** Not a wrong graph — see below. |

## The brief's reading of difference 2 is wrong, and the correction is load-bearing

**`b` is the BOOL atom. `buf` is `z`** (`graphcmp.py:324-326`). So py `n(b1,b0)` is
**`(True, False)`** — the flip-axis flags — **not "two Buffer refs"**, and
`n(i1,i0)` is the same two values spelled `u32`. **The shape agrees on both sides
(`(l0:4,l0:3)`).** Nothing reads bounds from index refs where CPython reads buffers.

## Why the arg is not a disagreement: MEASURED, calling CPython

```
UOp(Ops.FLIP, src, (True, False)) is UOp(Ops.FLIP, src, (1, 0))   -> True
```

**One node**, in BOTH request orders, and for `Ops.PERMUTE` too — the ucache hashes the
tuple's **values** and `True == 1`. So the stored spelling is decided by *which request
arrived first*, and **`ops.py:428`'s `isinstance(x, bool)` guard is INSERTION-ORDER
DEPENDENT**: intern `(1,0)` first and that node raises `ValueError`, intern
`(True,False)` first and it answers `(4, 3)`. **A "difference" whose sign depends on
request order is not a difference in the graph.**

The port gap is real and stays on the port's wall (`uop/fold.bend:6488-6492` records it):
`ATuple` is `List<&2, U32>`, so `ops.py:428`'s bool half is unimplementable. **It cannot
change an answer** — that guard can only turn an answer into a REFUSAL, so a port that
cannot raise it is strictly MORE PERMISSIVE. A missing **spelling**, not missing
**semantics**.

## Verdict and denominator, before and after

```
BEFORE  flip  nodes=6/7  shared-cores=5  ops-reached=5/6 of 77  ONLY-PY=1 ONLY-BEND=2  DISAGREE
AFTER   flip  nodes=6/6  shared-cores=6  ops-reached=5/5 of 77  ONLY-PY=0 ONLY-BEND=0  AGREE
        RESIDUALS IN THIS RUN: B=2/0   <- the canonicalisation, COUNTED, never a silence
```

**RE-MEASURED 2026-10-04 by `notes-sweep`, independently of the FLIPR unit: the AFTER line
still holds exactly** — `nodes=6/6  shared-cores=6  ops-reached=5/5 of 77  ONLY-PY=0
ONLY-BEND=0  RESIDUALS B=2/0  VERDICT: AGREE`. **So `flip` is closed, and every `6/7`
reading of it in this tree is a superseded number, not an open question.**

**The other 21 graphs did not move.** Whole-line diff of `flip/runs/{BEFORE,AFTER}.txt`,
taken by swapping the claimed baselines in and back out: **one line, `flip`.** 20 AGREE,
2 DISAGREE (`lin`, `loop` — disagreeing on purpose). `selfcheck: OK`. The other unit's
`cdiv` (10/10) and `late` (12/12) both AGREE under the same code.

⚠ **THOSE TWO VERDICT COUNTS ARE A HISTORICAL BASELINE OVER A 22-GRAPH CORPUS, AND
`notes-sweep` RE-MEASURED 2026-10-04: 22 AGREE / 2 DISAGREE over 24 graphs** — the two
extra graphs are `cdiv` and `late`, both AGREE, so both numerator and denominator moved.
The *shape* of the claim ("`lin` and `loop` disagree on purpose and nothing else does")
still holds; only the counts aged.

## The `?` ledger, restated

`flip` read `?=0` while DISAGREEing and reads `?=0` now that it AGREEs. That is the row
working: it measures **omission**. The new `B` row is the same shape of evidence pointed
the other way — it counts what the comparison **declined to take at face value**, so the
`B=2` is on the same footing as `?=0`: neither is a verdict.

## Pins held

* **unresolvable names still rejected** — `--graph not_a_graph` and `--graph Ops.NOPE`
  both fail argparse's `choices`. Keep it.
* `canon_flip` **cannot blind the differ**: `flip/canon-falsify.py` (all `ok`) shows a
  swapped flag, a changed flag value, and a changed tuple LENGTH all still fail to pair,
  while the two spellings pair. A normalisation that cannot be shown to still catch a
  difference is a sweep, not a comparison.
* `selfcheck` **caught** the new ledger marker `B` (`neither an atom letter nor a
  declared literal`) — correctly, because `B` counts a *transformation* and no text scan
  can find it. Declared in `INJECTED`, and the claim is asserted falsifiable in `report`.

## Two walls worth carrying

* **A hand-built fixture can disagree with the port it tests, and the port gets blamed.**
  `graphcmp.bend` builds the arena node by node, so `g_flip` re-implemented `UOp.group`
  wrongly while `ops.bend:2486` had it right all along. **Call the port's own API wherever
  one exists.**
* **A swap-and-restore in a file two agents share is a blind spot.** Between my `cp` and my
  restore a concurrent unit added `g_cdiv`/`g_late` and reshaped `rows.pick3`; `selfcheck`
  then failed at `graphcmp.bend:1375` (`def rows.pick(name: String) -> O.Found: rows.pick3(name)`
  feeding a `+name` parameter — **the callee CONSUMES the name and the caller does not
  offer a `+`**). Not my line, not my edit; **left alone and reported.**

---

## hermetic unit, 2026-10-04 — THE 59 IS UNCHANGED AND THAT IS NOT A PASS

Re-measured under `.agents/slop/hermetic/` (one process per graph, no cache on the verdict
path), three times, and two independent full runs are byte-identical across all 48 row sets:

    graphs 24 | denom 77 (measured len(list(Ops))) | PY 59 | BEND 59 | BOTH 59
    py-only [] | bend-only [] | WALLS []

**The number did not move, and that is the finding rather than a confirmation.** `arith/`'s
published py row sets disagree with a fresh process for **15 of 24** graphs — same row count,
differing only in the `ParamArg` chunk's `slot` (`graphcmp.py:708`) — and the census still read
59 because `ops_of` reads field 1, the op, which the corruption does not touch. So **the earlier
agreement was luck, not verification**, and the corpus's *artifacts* were not reproducible even
though its *number* was stable. What is new is not the 59; it is that the 59 is now computed from
rows that reproduce byte-for-byte.

**The briefed `DEV` defect does not exist.** `graphcmp.py:2977` sets `DEV` and `:2978` imports.
The cited `:2769` is `continue` in `split_debug`, and matches the BASELINE copies where
`load_tinygrad()` is `:2770`. **The wall is still true** — with no `DEV` in the env, a late
assignment asking `NULL` yields `METAL` — and it has a worse second form: with `DEV` already
inherited, the same late assignment yields `CPU` **silently**. One live instance outside this
unit's scope: **`oracles/mm-range.py:12`+`:59`**.

`graphcmp.py` byte-unchanged (`c7096ee70cdfef447aec10cd784ef3ac`); `arith/`'s cache
byte-unchanged (read, never written). Nothing committed.
