# `checks/substrate.py --root tinybendygrad` — SLOW, NOT STUCK. And it buffered its answer to exit.

Owner: substrate diag unit.  Tree state: HEAD `7f70b475`, 2026-10-06.  I edit `checks/substrate.py`
only; I did not commit or stage.

## 0. The verdict, in doctrine-2 words

- The bounded reproduction returned **`TIMED-OUT`** (`rc=-9`, peak-RSS 48 MB, 120 s, **stdout 0 B**).
  It is not `DEAD` and it is not `REFUSED`; it is a run that did not finish inside the bound.
- **It is slow by construction, not stuck.** The walk is instant; the cost is one instrument
  subprocess per file, 140 times. Extrapolated full pass ≈ **2.5 min**, not 10.
- **It printed nothing until it was killed, and that is a second, independent defect** (buffering),
  now fixed in HALF 1 without changing a byte of the answer.

## 1. Attribution — walk vs router vs subprocess

| stage | code | measured | method |
|---|---|---|---|
| WALK `os.walk` | `checks/substrate.py:137-141` (`discover`) | **140 files in 0.0007 s** | `time.perf_counter()` around `substrate.discover("tinybendygrad")` |
| ROUTER `endswith` | `checks/substrate.py:371-383` (`instrument_for`) | **0.0000 s** for all 140 | `time.perf_counter()` around `instrument_for(f)` for every discovered file |
| SUBPROCESS per file | `bounded()` `checks/substrate.py:271-273`, called at `:432` (bend), `:446` (node), `:474` (cc); `cc` context emit `:332` | **126 invocations in 120 s; 109 s of that is measured instrument time** | parse the `[bounded] … Ns` records in `run-full.err` |

The walk rewrite (`c19fe318a`) **did not introduce the slowness.** Its diff removed
`if f.endswith(POP_SUFFIXES)` from `discover`; today **all 140 files are already router classes**
(census below), so the population — and therefore the number of instrument subprocesses — is
**identical before and after**. The rewrite's own claim ("changes TODAY's denominator by ZERO") is
CONFIRMED. (It is 140, not the docstring's 144; and 134 `.bend`, not `AGENTS.md`'s frozen 138.)

**Census** (`os.walk` + `splitext`, `.venv/bin/python`): `.bend` 134 · `.js` 3 · `.c` 2 · `.mjs` 1 ·
**total 140**.

**The bounded reproduction, exactly as briefed:**

```
.venv/bin/python checks/bounded.py --seconds 120 --mb 2048 -- \
    .venv/bin/python checks/substrate.py --root tinybendygrad
→ [bounded] TIMED-OUT  rc=-9  peak-RSS=48 MB (ceiling 2048)  120s  … out=0B err=25390B
```

At the kill it had completed **126 instruments** (122 `.bend`, 3 `.js`, 1 `.mjs`) — last file
`tinybendygrad/uop/fold.bend` — plus **2 `.c` files judged `NO INSTRUMENT`**, leaving **12 `.bend`
unvisited** (`uop/{movement,ops,probe-mmcore,render,spec,symbolic,upat,validate,weak}.bend`,
`viz/{__init__,cli,serve}.bend`). 126 instruments in 120 s ⇒ **~0.95 s/file**, so a full pass is
**~133 s + the heavier uop tail**; the tree's own `bounded.py` adds a floor of `POLL=0.25 s` per file
(`checks/bounded.py:120,236`) — 126 × 0.25 ≈ **31 s of pure polling overhead**.

**The `>10 min` the commit message reports is NOT reproduced.** My measurement of the same command
is a 120 s timeout at 95 % of the `.bend` set. I cannot explain the earlier unit's ten minutes from
this tree state; the candidates I can name are (a) a concurrent `bend` from another unit, (b) the
`cc` context emit at `:332` when `.agents/slop/guardfix/probe-c.bend` still existed (a full bend
emit), or (c) a tree in flux. I am reporting the reading, not the story.

## 2. THE CRITICAL QUESTION — did it print anything before it finished? NO.

**Two layers buffered, and both were measured.**

1. **`substrate.py` buffered ALL stdout to exit.** HALF 1 appended every verdict into a list
   (`out`) and never printed it; `run` printed the whole list at `checks/substrate.py:836-837`
   (`for ln in out: print(ln)`). Measured on the instrument-FREE `-n --root tinybendygrad` sweep
   (7.0 s): **first stdout byte at 6.987 s of 7.01 s** — i.e. at exit. Method: `Popen` + `select()`
   on the pipe, timestamp the first successful read.
2. **`bounded.py` buffers both child streams to files**, and writes them only after the child exits
   (`checks/bounded.py:250-252,262`). So even a streaming child is invisible through the wrapper the
   brief names. That is `bounded.py`'s contract (stdout must stay the child's byte for byte), not a
   bug, but it means the CI-shaped invocation can never show progress.

**Fix landed (streaming, answer unchanged).** `checks/substrate.py`:
`half1(..., emit)` now emits each verdict as it is taken; `run` passes `emit=print(flush=True)`
(`:779-786`). Lines and their order are identical — HALF 1's lines still come first, in argument
order; only the moment of the write moved. Verified:

- `-n --root tinybendygrad`: **319 lines / 33636 B, rc 1 — identical to the pre-change reading.**
- Edited vs `git show HEAD:checks/substrate.py` on the 7 smoke inputs
  (`tiny.bend`, `broken.bend`, `empty.bend`, `bare.txt`, `no-such-file.bend`, `dtype.c`, `dtype.js`):
  **stdout byte-identical, 2278 B, rc 1 both sides.**
- Observability: a 2-file run now puts its **first byte at 0.403 s of 1.09 s** (was at exit).

I did **not** add a `--limit`/`--only`: that narrows the judged population, which is the whole point
of the rewrite. The fix is streaming only.

## 3. What it DID find

**Instrument-free full sweep** (`-n --root tinybendygrad`, rc 1):

| line | reading |
|---|---|
| `POPULATION` / `files=` | **140 discovered**, by `os.walk` |
| `UNJUDGED` | **0 of 140** — every file is a router class |
| `ROUTE` (under `-n`) | all suppressed; none judged |
| `PROVENANCE` | port=119 non-port=21, of which **not-in-index=1**, no-upstream=21 |
| `PORT ALARM` | **1** — `tinybendygrad/test/_probe/v5.bend` is not in the git index |
| `TOTALS` | refs=35900 exact=35900 suffix=0 unresolved=0 unseen=45114 missing_module=0 dead_import=42 |
| `COVERAGE` | qualified=81014 checked=35900 **UNSEEN=45114 (55.7 %)** |
| `BAD` | **0** |

The single finding is the pre-existing PORT ALARM, not the rewrite.

**`NO INSTRUMENT` = 2, and it is the `cc` instrument that is DEAD.** Both `.c` files route to `cc`,
but `cc` needs `C_PROBE` = `.agents/slop/guardfix/probe-c.bend`, which is **absent**
(`os.path.isfile` = False); `Ctx.ok()` (`:325-330`) returns False before any `cc` runs, so
`dtype.c` and `sz.c` print `NO INSTRUMENT … cc and a compiling bend C context are both required`.
Measured on the 6 non-`.bend` files: `ROUTE bend=0 cc=0 node=4 no-instrument=2 (of 6)`, rc 0,
the 4 `.js`/`.mjs` WARM. This is a **gate measuring nothing on a whole class** — correctly labelled
`NO INSTRUMENT` (not a pass), but the instrument itself is missing.

## 4. PLANT — the walk sees what a suffix filter would hide (two states)

`-n --root tinybendygrad`, planted `tinybendygrad/runtime/ops.staged-blob-plant` (a name with no
router class — exactly what `if f.endswith(POP_SUFFIXES)` would have dropped):

| state | `files=` | `UNJUDGED` |
|---|---|---|
| absent | **140** | **0** |
| present | **141** | **1**, naming `tinybendygrad/runtime/ops.staged-blob-plant` |

Planted and removed; `os.path.exists` = False afterward. **The rewrite's reason is demonstrable on
its own example.**

## 5. Side finding (not mine)

`.agents/slop/substrate/diff.py --sets smoke` reports `DISAGREE` (oracle 24 lines vs port 25), and
the ONLY stream difference is the `COVERAGE …` line the port emits:
`checks/substrate.py:696-699` has no counterpart in the frozen oracle. This is **pre-existing and
unrelated to my change** (HEAD's `substrate.py` emits it too). I did not repair it — it is a
port/oracle contract question, not a walk question.

## 6. One-line answer to the brief

The walk was never the slow part (0.7 ms, 140 files). The slowness is 140 instrument subprocesses at
~0.95 s each (**≈2.5 min**, `TIMED-OUT` at the 120 s bound), and **all of its stdout was buffered
until exit** — now streamed, byte-for-byte identical, so a caller can tell slow from stuck.
