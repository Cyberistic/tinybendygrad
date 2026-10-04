# DELIVERABLE 2 — does `cstyle-gate.py`'s green survive the correct reader?

## Short answer

**The reader is not why the green was true or false, and the green is not currently reproducible
live.** Both halves, measured.

## The green, over the capture pair, WITH the correct reader

```
AGREE
port rows (rows_strict): 227   oracle rows (rows_strict): 224
the SHARED reader (rebase-gate.py:rows()) over the SAME oracle stdout: 222 names --
  6 only it finds, 8 only rows_strict finds, 216 in common
gated 221   agree 221   disagree []
STALE-LITERAL 0 port `py=` literal(s) disagree with the live call: []
ORACLE-REFUSALS 13 CPython KeyError(s) the oracle reported on stderr: [13 names]
UNREPORTED-REFUSALS 0: every port row that answers `` and the oracle did not name on stderr -- none
EXCLUDED 6 port row(s) CPython cannot answer at all: [6 names]
COVERAGE 221/227 port rows compared to a live CPython call, 0 disagreeing; 4 of those are rows
where `_render_dtype` REFUSES; 6 declared exclusions.
```

**THE SHARED COUNT: 221 gated rows, 221 agree, 0 disagree.
BOTH DENOMINATORS: 227 port rows and 224 oracle rows.**
227 port rows − 221 gated = 6, and all 6 are named exclusions; **0 uncovered rows**.

Lanes: port `.agents/slop/blobrows/CURRENT/tinybendygrad__renderer__cstyle.bend.txt`
md5 `e039eeff62ce` (228 physical lines, 227 rows); oracle
`.agents/slop/cstyle-parity/oracle.txt` md5 `1ddd5a5d574c` (224 physical lines, 224 rows), stderr
`oracle.err`.

## The green survives the reader — measured by ablation, not by reading the call graph

`cstyle-reader-parity.py` takes the file's **own pre-fix reader out of the committed blob**
(`jj file show -r @-`, `ast`-extracted — *not* re-typed; a re-typed fork would be a third reader),
binds it back over the post-fix file, and diffs the **whole** printed output:

```
[2a] READER ABLATION, same code and same two lane texts. fork reader rc=0   shared reader rc=0
[2a] IDENTICAL: not one printed line differs
```

Not one line. Not the verdict, not a count, not the coverage table. The reader was **never**
load-bearing in this file: `rows_shipped` reached one `print` and never reached `judge()`.

Corroborated structurally by the whole-output diff against a saved pre-fix run
(`.agents/slop/cstyle-parity-before.txt`, md5 `b0762e53ccd2`): the verdict flipped
`BROKEN → AGREE` across the pre-fix/post-fix pair, and **`ORACLE-REFUSALS 0 → 13`** shows why.
That flip is the **stderr** fix, not the reader. Attribution is clean and the two defects are
independent.

## But the green is NOT reproducible live, and this is not a small caveat

The live port lane printed **0 stdout lines, rc=1**, on **4 of 4** runs:

| run | error site | message |
|---|---|---|
| 1–2 | `tinybendygrad/uop/fold.bend:1259` `sym_dim.pa` | `match O.ParamArg.vmin_vmax(pa)` — a computed value as scrutinee (the rule already at notes position ~306) |
| 3–4, ~15 min later | `tinybendygrad/uop/fold.bend:5321` `dim_str` | `expected : u / observed : u (consumed more than once)` |

`tinybendygrad/uop/fold.bend` is **M (uncommitted)** and is **one of the six live units**. It moved
between my runs: the first error's site was *fixed* under me and a different error appeared. So the
lane is not merely cold, it is **cold and moving**, and no live verdict about the tree exists at
all. `cstyle-gate.py` is right to exit 1 here, and it does.

**Therefore: the 221/227 is a property of the 06:02 capture, and it is evidence about the capture.**
The reader does not weaken it. The cold lane does.

## Stated plainly

A gate whose green rests on a stale reader is worse than an unwired one. **This gate's green does
not rest on the stale reader** — that is the good news, and it is measured three ways. But the
green also does not currently rest on the *tree*, and the sentence "`cstyle-gate.py` exits 0 with
221/227 clean" is only true of a capture until `fold.bend` compiles. Until then the honest
statement is: *over the capture pair, 221 of 221 gated rows agree, 0 of 227 disagree, 6 exclusions,
0 uncovered, and the port lane is not currently runnable.*

## What this found and did not fix

* **`tinybendygrad/uop/fold.bend` does not compile** — two distinct errors, one of them still live.
  Not mine, not touched, reported back. This is the wall the live green is waiting on.
* **`cstyle.bend:1758` emits row names containing `=`.** `kern CUDA  lb=1 = [...]` reads as
  `kern CUDA  lb=1` under `rows_strict` (cut at `" = ["`) and `kern CUDA  lb` under `rows()`
  (split at the *first* `=`). Both readers find the row, so the pair still agrees — but the rule is
  that a row name carries spaces and **no `=`**, and **8 of 227** names break it. A name that
  reshapes itself under a different reader is exactly what the six-shape control exists to catch.
* **`cstyle-gate.py --selftest` fails under bare `python3`** with `ModuleNotFoundError: No module
  named 'tinygrad'` — the self-test writes its oracle into a temp dir and runs it by absolute path,
  so `sys.path[0]` is the temp dir. Pre-existing (reproduced against the committed blob); passes
  under `.venv/bin/python` before and after my edit. Left alone: it is an environment contract, not
  a logic defect, and the fix is either `PYTHONPATH` or `.venv/bin/python`, which is a caller's
  choice.
* **A cold lane and a lane that fails are different things.** `bend --check-only`'s exit status is
  not the verdict, and neither is a lane's rc when the lane printed *nothing*: this gate gates on
  `p.returncode` and then separately refuses an empty stdout, which is right, but only because
  `judge`'s GUARD 1 catches the shred/empty case downstream.