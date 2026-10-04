# DELIVERABLE 2 — does `cstyle-gate.py`'s green survive the correct reader?

## Short answer

**The reader never touched the verdict — measured three ways. The live green, however, is NOT
currently reproducible: the port lane is cold, and it has been cold at FOUR distinct sites over the
course of this unit. The 221/227 is a real measurement of a capture and of one green window; it is
not a statement about the tree as it stands.**

Both facts are measured below with the timeline, because "the green holds" and "the green held
throughout" are different claims and only one of them is true here.

## The green, over a capture AND over one live window, with the correct reader

Three consecutive live runs, byte-identical, exit 0 (output md5 `9b380034336712135a2f6b5755db4215`),
during the one window in which the port lane compiled:

```
live port lane rc=0   live oracle lane rc=0
port rows (rows_strict): 227   oracle rows (rows_strict): 224
the SHARED reader (rebase-gate.py:rows()) over the SAME oracle stdout: 222 names --
  6 only it finds, 8 only rows_strict finds, 216 in common
gated 221   agree 221   disagree []
STALE-LITERAL 0 port `py=` literal(s) disagree with the live call: []
ORACLE-REFUSALS 13 CPython KeyError(s) the oracle reported on stderr: [13 names]
UNREPORTED-REFUSALS 0: every port row that answers `` and the oracle did not name on stderr -- none
EXCLUDED 6 port row(s) CPython cannot answer at all: [6 names]
AGREE
COVERAGE 221/227 port rows compared to a live CPython call, 0 disagreeing; 4 of those are rows
where `_render_dtype` REFUSES; 6 declared exclusions.
```

> **THE SHARED COUNT: 221 gated rows, 221 agree, 0 disagree.
> BOTH DENOMINATORS: 227 port rows and 224 oracle rows.**

227 port rows − 221 gated = 6, and all 6 are named exclusions → **0 uncovered rows**. During that
window the live port lane's stdout md5 was `e039eeff62ce`, **byte-identical to the 06:02 capture**
I was forced onto while the lane was cold, so the capture and the tree agreed exactly once, and that
agreement is itself the evidence that the capture is a faithful stand-in *when the lane is green*.

Reproduced over the capture pair, with the corrected reader and `--oracle-stderr`, from
`cstyle-reader-parity.py`: **exit 0, `AGREE`, 221 gated, 221 agree, 0 disagree** — the same numbers.

## The green survives the reader — by ablation, not by reading the call graph

`cstyle-reader-parity.py` takes the file's **own pre-fix reader out of the committed blob**
(`jj file show -r @-`, `ast`-extracted — *not* re-typed, because a re-typed fork would be a third
reader), binds it back over the post-fix file, and diffs the **whole** printed output:

```
[2a] READER ABLATION, same code and same two lane texts. fork reader rc=0   shared reader rc=0
[2a] IDENTICAL: not one printed line differs
```

Not one line — not the verdict, not a count, not the coverage table. `rows_shipped` reached one
`print` and never reached `judge()`. **The reader was never load-bearing in this file**, so the
defect was a false measurement printed beside a true verdict, not a false verdict.

Attribution is clean and the two defects I fixed are independent. Diffing a saved pre-fix run
(`.agents/slop/cstyle-parity-before.txt`, md5 `b0762e53ccd2`) against the post-fix run shows the
verdict flipped `BROKEN → AGREE` — and `ORACLE-REFUSALS 0 → 13` shows why. **The flip is the stderr
fix, not the reader.** Had I credited the reader because the flip happened in the same edit, that
would have been the same error one level up.

## THE TIMELINE, because the green was NOT reproducible for most of this unit

`tinybendygrad/uop/fold.bend` is **one of the six live units**. It was `M` (uncommitted) for most
of this unit, and the port lane's death **moved four times**, always inside `fold.bend`'s
`sym_dim` family, always a computed value in scrutinee position:

| window | live port lane | error site in `tinybendygrad/uop/fold.bend` |
|---|---|---|
| runs 1–2 | **0 stdout lines, rc=1** | `:1259` `sym_dim.pa` — `match O.ParamArg.vmin_vmax(pa)` |
| runs 3–4 (~15 min later) | **0 stdout lines, rc=1** | `:5321` `dim_str` — `expected : u / observed : u (consumed more than once)` |
| **green window** | rc=0, **227 rows**, stdout md5 `e039eeff62ce` | — |
| runs 5–6 | **0 stdout lines, rc=1** | `:1275` `sym_dim.con` — `match const_i64.go(v)` |
| **final: runs 7–12, 6 of 6** | **0 stdout lines, rc=1** | `:1286–1288` `sym_dim` — `match a:` |

The lane is not merely cold, it is **cold and moving**: a site that failed would be edited away and
a different one fail in the same family, ~15 minutes later, without any change to `cstyle.bend`.
**4 distinct sites, 2 green windows' worth of evidence, and the state at the end of this unit is
COLD.** `fold.bend` is `M` again as of the final measurement.

So the honest sentence is not "the gate is green" and not "the gate is red". It is: **over the
capture pair and over one live window, 221 of 221 gated rows agree, 0 of 227 disagree, 6 exclusions,
0 uncovered — and the port lane is not currently runnable, so the tree has no live verdict at all.**

That is precisely why `cstyle-reader-parity.py` prints a capture's path and md5 on every line and
why `cstyle-gate.py` now says `CAPTURED` rather than `live`. A reader that cannot tell which lane it
is holding cannot be trusted with a verdict about either.

*(One number in my own measurement is discarded rather than reported: a `grep -l` over the six
stdout captures printed "3", which is stale `/tmp` content and not this lane's output. The
authoritative reading is `wc -l` = 0 and `rc=1` on 6 of 6.)*

## What this found and did not fix

* **`tinybendygrad/uop/fold.bend` is cold now and was cold at FOUR distinct sites over this unit.**
  Not my file, not touched. Every one is a computed value in scrutinee position inside `sym_dim.*`,
  which the project already records as a rule at notes position ~306 — so this is not a new rule, it
  is a lane being refactored through a construct that does not parse. **The owner's unit needs to
  land before this gate can say anything about the tree.**
* **`cstyle.bend:1758` emits row names containing `=`.** `kern CUDA  lb=1 = [...]` reads as
  `kern CUDA  lb=1` under `rows_strict` (cut at `" = ["`) and as `kern CUDA  lb` under `rows()`
  (split at the *first* `=`). Both readers find the row and the pair still agrees, but the rule is
  that a row name carries spaces and **no `=`** — and **8 of 227** names break it. **This is a live
  defect in the port's row shape**, invisible to any value-plant: a name that reshapes itself under
  a different reader is only detectable by comparing the two readers' NAME SETS, which the gate now
  does on every run (6 vs 8, named).
* **`cstyle-gate.py --selftest` fails under bare `python3`** —
  `ModuleNotFoundError: No module named 'tinygrad'`, because the self-test writes its oracle to a
  temp dir and runs it by absolute path, so `sys.path[0]` is the temp dir. Pre-existing: reproduced
  against the committed blob, which fails the same way. Passes under `.venv/bin/python` before and
  after my edit. Left alone — it is an environment contract, and the fix (`PYTHONPATH` vs
  `.venv/bin/python`) is a caller's choice, not a defect in the gate.
* **`judge()` gates on the lane's `returncode`.** Correct here, and the dtype.bend trap in
  `agent-core.md` (14 permanently-red laws, exit status not the verdict) does not bite because
  `cstyle.bend`'s own proofs are green — but a `cstyle.bend` that ever inherits an unfillable law
  would report `lane failure` on a lane that is fine. Noted, not changed: no such law exists today,
  and inventing a tolerance for one would be a guess about a lane I cannot run.