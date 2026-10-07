# THE NINE — `corpus()` 25, `WANT` 16, and the nine that RAN with nothing said about them

MEASURED 2026-10-06, substrate **WARM** (`ALL PROOFS CHECK`), `DEV=NULL`, `ENV` exactly as
`checks/differ.py:44-48`. Owned: `checks/differ.py`, `.agents/slop/unsetexp/`.
**NOT COMMITTED.** Nothing under `runs/graphcmp/D/` was regenerated: every row below is read
from the shared run of 2026-10-06 00:27–00:31 (`graphs=25 graphs-agree=19 not-comparable=0`),
which is the tree as found. Re-measurement is in `trials.tsv`, written to THIS directory.

## 0. THE TABLE. WHAT IT EMITS / WHAT IT EMITTED / WHETHER IT AGREED

`D` = `runs/graphcmp/D/D1-graph-<g>.txt`. "census" is the per-op NODE counts the artifact prints
under `OPS REACHED`, as `py/bend`; a census where the two columns differ is a graph whose OP SET
differs, which is a different failure from a field that differs on a matched node.

| graph | what it emits (fixture) | what it EMITTED (`D`) | census py/bend | shape of the disagreement | verdict | byte-identical? |
|---|---|---|---|---|---|---|
| `alu` | `group(sqrt,reciprocal,a**a,log2,exp2,sin,trunc,detach)` over one `f32 (4,3)` | nodes 14/14, shared-cores=14, only-py=0, only-bend=0, **field-mismatches=0** | identical, 13 ops | none | **AGREE** | YES 828 B |
| `bit` | `group(<<, >>, //, %)` over one `i32 (4,3)` | nodes 10/10, cores=10, 0/0, **field-mismatches=0** | identical, 9 ops | none | **AGREE** | YES 599 B |
| `bw` | `(a@b).sum().gradient(a,b)` — the corpus's first BACKWARD graph, reaches `EXPAND` | nodes 32/32, cores=32, 0/0, **field-mismatches=0** | identical, 10 ops | none | **AGREE** | YES 2066 B |
| `move` | `group(pad, shrink, contiguous_backward, bitcast(int))` — four movement ops | nodes 22/22, cores=22, 0/0, **field-mismatches=0** | identical, 9 ops | none | **AGREE** | YES 1329 B |
| `where` | `group((a<a).where(a,a), (a<a))` | nodes 8/8, cores=8, 0/0, **field-mismatches=0** | identical, 7 ops | none | **AGREE** | YES 478 B |
| `flip` | `group(a.flip(0))` — FLIP alone, its own graph | nodes 6/7, cores=5, only-py=1, only-bend=2, **field-mismatches=0**, rung3.5-crossrefs=1 | `GROUP 0/1` — the port adds a GROUP | **SHAPE**: the FLIP's `arg` reads `py=n(b1,b0)` vs `bend=n(i1,i0)`; `arg` is in the core, so the node goes one-sided and cascades. `field-mismatches=0` because nothing matched. | **DISAGREE** | NO |
| `allred` | `copy_to_device(('CPU','CPU')).allreduce(ADD)` — the only route to `ALLREDUCE` + `COPY` | nodes 9/18, cores=5, only-py=4, only-bend=13, **field-mismatches=0**, rung2-pairs=0 | `ALLREDUCE 1/0 COPY 1/0 RANGE 1/0` vs `MUL 0/1 PERMUTE 0/2 REDUCE 0/1 RESHAPE 1/4 STACK 1/4` | **SHAPE**: the port emits **no `ALLREDUCE`, no `COPY`, no `RANGE`** and 13 nodes py has none of | **DISAGREE** | NO |
| `cdiv` | `group(fmod, div(rounding_mode='trunc'))` over two `i32 (4,3)` — the only route to `CDIV`/`CMOD` | nodes 10/18, cores=3, only-py=4, only-bend=12, **field-mismatches=0**, rung2-pairs=3 | `CDIV 1/0 CMOD 1/0 GROUP 1/0` vs `MUL 0/1 PERMUTE 0/2 REDUCE 0/1 RESHAPE 2/4 STACK 1/4` | **SHAPE + a field**: the unpaired `ALLOC` is `dtype py=i32 bend=f32`, `shape py=(l0:12) bend=(l0:15)` | **DISAGREE** | NO |
| `late` | `graph_rewrite` over `(a-b), neg, eq, a/b` — the LATE-REWRITE path | nodes 12/18, cores=5, only-py=6, only-bend=12, **field-mismatches=0**, rung2-pairs=1 | `CMPEQ 1/0 FDIV 1/0 NEG 1/0 SUB 1/0 GROUP 1/0` vs `MUL 0/1 PERMUTE 0/2 REDUCE 0/1 RESHAPE 2/4 STACK 1/4` | **SHAPE + a field**: the unpaired `ALLOC` is `shape py=(l0:12) bend=(l0:15)` | **DISAGREE** | NO |

**FIVE AGREE, FOUR DISAGREE. Not one of the nine is a wrong VALUE on a matched node: all nine
read `field-mismatches=0`.** Every disagreement in this table is a node-set difference (values on
nodes that never pair, or nodes that never exist on the other side) — which is the *shape* class
`spine`'s unit named, not the `lin`/`loop` class (one located field on 45 and 24 matched cores).

## 1. THE SECOND BELT, AND WHAT IT DOES AND DOES NOT SETTLE

`D2-cmp-<g>.txt` compares the two canonical emissions byte for byte — a different code path from
the rung pairing above, so it is a genuine second opinion about the same two emissions.

| | `VERDICT: AGREE` | canonical bytes |
|---|---|---|
| 25 graphs | 19 | 19 BYTE-IDENTICAL |
| the four DISAGREE | 6 | 6 `DIFFERS` |

**The two channels select the SAME 19 and the SAME 6 — a perfect correlation, measured over all
25.** So the verdict machinery is not a stub that says AGREE: it says DISAGREE on six. What the
correlation does **not** establish is that the six disagreements are *localized* correctly, and it
says nothing at all about whether an AGREE is *true* — both channels consume the same two
emissions, so a fault in the port's *renderer* that both would faithfully report as identical
passes both. That is why the 14 AGREE rows in `WANT` below are marked "corroborated by a second
channel", not "verified".

## 2. HOW MANY OF `WANT`'s 16 HAVE ONE OBSERVATION AND NOTHING TO CORROBORATE IT

**Answer: 14 of 16 — every graph whose expectation is `AGREE`.** The two `DISAGREE`s (`lin`,
`loop`) each carry a named, located, *independent* cause; nothing else does.

| evidence | measurement |
|---|---|
| commits touching `checks/differ.py`, ever | **4** |
| commit that introduced every `AGREE` key | **1** — `6d5509216` (2026-10-04), all 14 at once |
| pickaxe `-S'"<key>": "AGREE"'` per key | exactly one hit each, the same commit; never revised |
| run artifacts recording a verdict per graph | **1** (`runs/graphcmp/D/D1-graph-*.txt`, 2026-10-06) |
| independent second channel for those 14 | `D2-cmp-<g>.txt` BYTE-IDENTICAL on all 14 (§1) |
| pre-existing claim in the fixture's own docstring | **1 graph of 25** — `g_flip`: `EXPECTED TO DISAGREE, ON \`arg\``, with the CPython measurement and `ops.bend:1066` |

So the honest count is two-part and both parts matter:

* **14 have exactly one observation** of the verdict (`D1-graph-<g>.txt`, one run) and **no
  independent corroboration that they are anything but `AGREE`** — because nothing in the repo
  ever claimed otherwise. The byte-identity channel corroborates the *emissions*, not the verdict.
* **1 of those 14, `flip`, is not in this set at all**: it is one of the four DISAGREE and is the
  only graph in the corpus whose fixture docstring predicts its verdict, from a CPython call, with
  a port file:line. `g_flip`'s claim predates this measurement and shares no code path with it.

**IF THE NINE WERE WRITTEN AS NINE `AGREE` ROWS, THE TABLE WOULD BE 23 OF 25 CLAIMS WITH ONE
OBSERVATION AND NOTHING BEHIND THEM.** That is the trap, and it is real: the bar for an `AGREE`
row is "nothing has ever disagreed", which is not a measurement — it is the state of a corpus that
has not been compared. **Answer 1 is therefore NOT available for the five AGREE graphs, and this
file does not take it.**

## 3. WHICH OF THE THREE ANSWERS, PER GRAPH, AND THE MEASUREMENT THAT DECIDED IT

| graph | answer | measurement that decided it |
|---|---|---|
| `flip` | **2 — record the disagreement** | `g_flip`'s docstring predicts `DISAGREE` on `arg` from a CPython call and `ops.bend:1066`. **The only row in the corpus whose expectation predates the measurement.** 3/3 trials stable. |
| `allred` `cdiv` `late` | **2 — record the disagreement** | **`emit --side bend` for each of the three AND for `matmul` is the same 18 lines and the same sha256 (`9f39a6e3ee7a0e30…`).** Four names, one emission; the bend-only block of `cdiv` and `late` is byte-identical to each other. `matmul` itself is byte-identical to CPython, so these three are rendered as the WRONG FIXTURE. 3/3 trials stable each. |
| `alu` `bit` `bw` `move` `where` | **3 — declare the gap, keep the refusal** | 14 of the 16 pre-existing rows were bare `AGREE` with one observation and no independent corroboration (§2), so answer 1 for five more makes 19 of 20. Their `AGREE` is forced rather than observed (3/3 stable, byte-identical, `RESIDUALS IN THIS RUN: none`), so an `AGREE` row would assert nothing the `D2-cmp-*` pin does not already assert. |

`WANT` is now **20 rows**: `graphs-answered=20`, `graphs-unset=5`. **`checks/differ.py`'s `run`
still exits 1, deliberately** — the gap is measured, named per graph, and the exit status is the
refusal. `census.py` still reports it, `want/selftest.py` now fails its three 9/16 assertions
(their file; reported in §7).

## 4. THE SHAPE DISAGREEMENT, AND WHERE IT IS WORTH NAMING

* **The `field-mismatches=0` trap.** All nine read `field-mismatches=0`, which reads like
  "nothing differs" and means "nothing was COMPARED": no two nodes pair, so no field is compared.
  Of the 19 AGREE graphs only `binblob` and `buffer` carry a non-zero ledger residual, so
  **20 of 25 graphs compare every field in full** — the other five compare something and call
  the comparison agreement.
* **`allred` / `cdiv` / `late`: SHAPE, and a field that follows from it.** Not one node pairs
  (`cores=5/3/5` against `9/18`, `10/18`, `12/18`). The only field-level mismatches the differ
  can print are on rung-2 pairs, which it builds from *leftovers* — so on `cdiv` it reports
  `ALLOC dtype py=i32 bend=f32` and `shape py=(l0:12) bend=(l0:15)` **because the graph is a
  different graph, not because a dtype arm is wrong.** Do not read those two lines as a dtype
  defect.
* **`flip` is the only VALUE-shaped one**: `arg py=n(b1,b0)` vs `bend=n(i1,i0)`, `arg` in the core
  so the node cascades, and the port adds one `GROUP`.
* **Named for `.agents/slop/disagree/`'s unit, not diagnosed here:** the bend-only 12-node block
  (`ALLOC f32 (l0:15)`, `CONST l0:1`, `STACK (l0:3)`, `RESHAPE (l0:4,l0:1,l0:3)`, `CONST l0:5`,
  `STACK (l0:2)`, `STACK (l0:3)`, `RESHAPE (l0:1,l0:3,l0:5)`, `PERMUTE`, `MUL`,
  `PERMUTE`, `REDUCE rd(OADD,i1)`) is identical in `cdiv` and `late` and is that block plus one
  `RESHAPE (l0:3,l0:5)` in `allred`. Evidence: `trials.tsv` + the `trial-<g>-1.rows` beside it.

## 5. THE PINS, AND WHY EACH IS A DIFFERENT QUESTION

| pin | asks | NOT the same question as |
|---|---|---|
| `expect-moved=0` (new) | did the rows that EXIST turn out to be right? | `graphs`/`graphs-answered`/`graphs-unset` (how many rows), `graphs-agree`/`graphs-disagree` (how many artifacts carry a verdict, unset graphs included) |
| `graphs-unset=5` (was 9) | how many corpus graphs have no row | `expect-moved` — a missing row is not a wrong row, and `selftest.py` CASE 3 proves the two do not absorb each other |

**THE BRIEF'S PROPOSED `graphs-unanswered` IS NOT ADDED, AND THE MEASUREMENT IS WHY.**
`graphs-unanswered` = "compared and no expectation" is `graphs-unset` under a second name, and a
health gate that answers one number in two spellings is the same conflation as demanding
`agree == total` when `WANT` records deliberate `DISAGREE`s — the mistake
`corpus-figure.py` made and fixed. **It already exists, once, as `graphs-unset`.**

**`graphs`, `graphs-answered` and `graphs-unset` ARE `n`, `n - u` AND `u` — three views of two
numbers.** A pin on all three can only ever catch what a pin on any two catches. They are kept
because each NAMES a different thing to a reader, and `expect-moved` is the first line in that
summary that is not a view of `n` and `u`.

**`corpus-figure.py` NEEDS NO CHANGE.** Read, not edited: it reads `graphs`, `graphs-agree` and
`not-comparable`, tests `not-comparable == 0`, and all three are unchanged in name and meaning.
Its comment says `agree == total` "CAN NEVER HOLD OVER A HEALTHY RUN OF THIS CORPUS" — still
true, and now true for four more graphs.

## 6. PLANT AND DISARM, RUN AGAINST THE DRIVER

`.agents/slop/unsetexp/selftest.py` — **rc 0, 26 assertions, ALL PASS.** It imports the real
`checks/differ.py`, points `GCMP` at a throwaway `graphcmp.py`, moves `ROOT`/`D` into a temp dir
(`ROOT` moves because `cmd_run` ends with `D.relative_to(ROOT)`), stubs the ONE function that
would run `bend` (`capture`, the three oracle probes), and calls the real `cmd_run`. **No `bend`
runs; `runs/graphcmp/D/` is never written.** It answers by RUNNING, per the `txtgen` lesson that
four static checks re-deriving from the same tables found zero drift.

| case | forced state | asserted |
|---|---|---|
| 1 | **disarmed**: table closed, every row right | rc 0, `expect-moved=0`, `unhealthy()` does NOT name the pin, and all 25 `D1-graph-*.txt` exist with bodies — a check that reads an artifact nobody wrote proves nothing |
| 2 | **planted**: `matmul`'s row says AGREE, the stub emits DISAGREE | rc ≠ 0, `expect-moved=1`, pin named by `unhealthy()`, offender named in the refusal, and the other 24 rows NOT reported |
| 3 | **planted**: a row deleted | rc ≠ 0, `graphs-unset=1`, `graphs-answered=24`, **`expect-moved` stays 0**, graph still run |
| 4 | **negative**: an UNANSWERED graph made to DISAGREE | rc ≠ 0, triaged as "the table is behind the port", `expect-moved` stays 0, all five gaps named |
| 5 | **planted**: a verdict planted on a graph whose row was deleted | `expect-moved=0` — reported, not compared — and the run still refuses |

**Three methods, none sharing a parser**: the exit status, a tokenizer written in `selftest.py`,
and `unhealthy()` (the driver's own `text()` against `PINS`). **The table is reset at the top of
every case, not only in the `finally`** — case 3's deleted row leaked into case 4 until it was
fixed, which is the same class as the repro where a `rmtree` between beats made both sides read
`NOTHING`.

## 7. WHAT I COULD NOT SETTLE, AND WHAT IS NOW FALSE ELSEWHERE

* **`runs/graphcmp/D/` WAS NOT REGENERATED**, so `unhealthy()` against the on-disk run names
  `graphs-answered=16 (expected 20)`, `graphs-unset=9 (expected 5)` and `expect-moved ABSENT` —
  the three resolve on the next `differ.py run` by whoever owns the tree. The two
  `oracle-selfcheck`/`census-rc` offenders are the port's own printers and predate this work.
* **`.agents/slop/want/` IS NOT MINE AND IS NOW TWO FILES BEHIND.** `census.py` reads correctly
  (25 / 20 / gap 5) but still labels the five `UNCOMPARED … NEVER RUN`, which was true when it
  was written and is **not true now — they run**. `selftest.py` fails 3 of its assertions, all
  pinned to the 9/16 state. `DECISION.md` §3 and §4 document `graphs-unset=9` and warn against
  taking its measurements as expectations; §2's argument is the one this work accepts. **Reported,
  not edited.**
* **`D2-cmp` byte identity is a SECOND METHOD, not independence.** Both channels consume the same
  two emissions, so a renderer fault that makes the port emit CPython's bytes is invisible to
  both. `canonical IDENTICAL ⟹ VERDICT AGREE` holds 25/25 with zero counterexamples — measured,
  not proved.
* **NOT SETTLED: whether the five should get rows at all.** The evidence for each is in the
  `WANT` comment; the judgement that a forced `AGREE` is not worth a row is mine and is
  arguable. If the next person disagrees, the five rows are one line each and `graphs-unset`
  goes to 0.
* **NOT SETTLED: `graphs-agree` counting unset graphs.** Unchanged (it counts artifacts), and
  still the right call: filtering it by `WANT` would make one denominator depend on the table
  while `graphs=` depends on the corpus.