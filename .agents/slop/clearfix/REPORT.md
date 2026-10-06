# `clearfix` — the two gates' `sys.exit(2)`, and which of three answers closes it

**THE BUG, on the live tree, unplanted.** `gates/mixin-op-gate.py:92` and
`gates/beautiful-mnist-gate.py:89` call `sys.exit(2)` **before** `GATE.run()`, so `_clear()`
never runs and the previous GREEN run's files survive a red run. `mixin-op-gate` is red on
this tree right now for an unrelated reason that happens to BE this shape: its `ORACLE_PIN`
names `178cf5f74e923c4a` and the file is `e8792d0ff1ad9d1a`, because `57d0fc387` repointed
the oracle copy's own usage line without re-freezing the pin. Nobody planted anything.

**THE ANSWER: OPTION 2 — `_clear()` in `Gate.__init__`.** One line in `gates/gatekit.py`,
which belongs to another unit, so it is measured here and **REPORTED, NOT APPLIED**.
`gates/` is byte-identical to `HEAD`.

## three commands, three verdicts

```
.venv/bin/python .agents/slop/clearfix/clearfix-repro.py   # REPRO.rows  -- 2 gates x 3 beats x 3 lanes
.venv/bin/python .agents/slop/clearfix/plant-disarm.py      # PLANT.rows  -- P1/P2/P3/P4
.venv/bin/python .agents/slop/clearfix/gate-matrix.py       # MATRIX.rows -- all 9 gates, both lanes
```

## the repro, both gates, STALE as sha256 against that lane's own previous green run

`NOW` = frozen pre-fix gate + committed `gatekit`. `FIX` = the **live gate, unedited** +
repaired library. `OPT2` = the **frozen pre-fix gate** + repaired library.

| beat | NOW | FIX | OPT2 |
|---|---|---|---|
| A0 green (pin live) | rc=0, 6 files | rc=0, 6 files | rc=0, 6 files |
| **A1 drift (pre-run `sys.exit`)** | **rc=2, 6/6 STALE** | rc=2, **EMPTY** | rc=2, **EMPTY** |
| A2 disagree (diff inside `run()`) | rc=1, EMPTY | rc=1, EMPTY | — |

Identical for `mixin-op-gate` and `beautiful-mnist-gate`. `REPRO HOLDS`.

**The seven artifacts, named, and their fate on a red run** — `bd.out`, `bd.rows`, `bn.out`,
`bn.rows`, `gate.bin`, `py.rows` (six; the seventh, `*.sub`, was renamed to `*.rows`/`*.out` by
a concurrent unit mid-build — see *three things that were not as the report said*). Under
`NOW/A1` all six survive **byte-identical to the previous green run**; under `FIX/A1` and
`OPT2/A1` the directory is **EMPTY**. A red run now leaves nothing to diff by accident.

**A0's "6/6 STALE" is not printed** and that is deliberate: A0 compares a run against itself,
so every file is trivially identical. A green row reporting a staleness count would score a
healthy run as the bug.

## why option 2, by measurement

| | what it is | measured |
|---|---|---|
| **1** remove the early exit | **not a caller-side change at all**: `run()` lives in `gates/gatekit.py`, has no drift hook, and `Gate.__init__` takes no pins. It is a **larger** library change than option 2 | built and run: costs **3 `bend` processes to learn a sha256 does not match**. Bounded: the refusal is **peak-RSS 0 MB, 0 s**; a green run of the same gate is **peak-RSS 1,728–1,941 MB, ~10 s** against a 2,048 MB ceiling |
| **2** `_clear()` in `__init__` | one line | **survives P1a/P1b/P1c — an early exit at MODULE SCOPE, before `Gate(...)` exists — because the directory was emptied at construction and no later exit can put a file back** |
| **3** public `clear()` + caller `try/finally` | a library change **plus** a per-caller edit | works **only in the right place**. With `clear()` correctly placed before the first check: EMPTY. With `clear()` placed between the drift check and `run()` — a plausible-looking edit — **6/6 STALE**, because `sys.exit(2)` is two lines above it |

`bmn` is a coin flip at 2,048 MB and **the old side was killed too** (`stalefix` §3), which
is the argument for not bounding: `bounded.py` returns 3 for memory and 4 for time and neither
is a status these lanes produce, so bounding is a verdict change dressed as safety.

## plant and disarm

* **P3** marker bytes planted into a promoted `py.rows`, then a drift run: **STALE against the
  planted bytes.** sha256 reads the file's content, not its presence.
* **P2** `_clear()` deleted from `__init__`: **6/6 STALE — the bug is back.** The repair is
  what made the difference, and that is removable.
* **P1** the early `sys.exit(2)` re-inserted into a repaired gate at three positions —
  module scope, after construction, beside the drift check — each with its own anchors,
  `ast.parse`d, and each disarmed by rebuilding from `HEAD` and **sha-verifying**:
  `f34a33dfb493764a` after every one. **All three: EMPTY.**
* `gates/mixin-op-gate.py` is byte-identical to `HEAD`. The matrix and repro never write to
  `gates/` at all.

## every gate, both lanes

| gate | HEAD | OPT2 |
|---|---|---|
| **mixin-op-gate** | **6 STALE** (pre-run exit) | **0** |
| **beautiful-mnist-gate** | **6 STALE** (pre-run exit) | **0** |
| ew-consts, ew-explog, i64-shl, i64-shr, wk-f32 | 0 (red inside `run()`) | 0 |
| bc-u32, wk-cd | **NO BASELINE** — red on a `diverges` pin, promote nothing | — |

`VERDICT: 2 of 2 MEASURED gates stranded artifacts under HEAD, 0 under OPT2.` The seven
zeroes are **controls** — they are red *inside* `run()`, where `_clear()` already runs, so
they are clean under every lane. **An instrument that fires on everything measures nothing**,
and that is why they are run and reported rather than omitted.

## is clause II measurable now? NO, and it cannot be made so by fixing it

`II FALSE gates/gatekit.py: 15/17 exits after the first write` is **red for the wrong
reason**, and clause II is **unmeasurable as written** — the brief is right and the instrument
says so itself.

`writer_exits` counts `return` statements and compares their **line numbers** to the first
`self.dir` access. A `try`/`finally` has **no line-number signature**: `run()` has 17 returns
and **16 of them sit inside a `try` whose `finalbody` calls `_settle(ok)`**, so all 16 run it
on the way out.

**THE DECISIVE MEASUREMENT:** delete the `finally` from `run()` entirely and clause II still
reports **15/17**. Removing the construct that makes those 15 exits safe does not move the
number by one. It is measuring the line, and the line is not the risk.

The number also does not respond to the three answers — `15/17` under HEAD, under option 2
(unchanged), under option 3 (unchanged), and `15/**18**` under option 1, i.e. **the better the
answer the worse the number**, because routing the drift through `run()` adds a `return`.
The information clause II needs *is* in the AST (16-of-17 coverage is one comprehension away);
clause II does not read it. Rewriting it that way is a **new measurement, not a fix** — and
**do not extract a helper to make it pass: that zeroes the denominator, a green with no
denominator.**

**AND THE BLIND SPOT IS THE POINT.** Clause II reads `gates/gatekit.py`. The exits that
stranded these files are in `gates/<gate>.py`. Its denominator does not contain them:

```
call-site census, denominator 2 exits per gate:
  mixin-op-gate        1/2 exits BEFORE run()   clears before run()=[]
  beautiful-mnist-gate 1/2 exits BEFORE run()   clears before run()=[]
```

## three things that were not as the report said

1. **The artifact count is 6, not 7, and the names moved.** A concurrent unit renamed
   `py.txt`→`py.rows` and `bd/bn.txt`→`.out` (`gates/gatekit.py:59-60`), so the report's seven
   `*.txt` names are six `*.rows`/`*.out` files plus `gate.bin` today. The P3 marker plant
   hardcoded `py.txt` and died on `FileNotFoundError`; it now finds the oracle lane **by
   prefix** from the directory the run actually produced.
2. **`mixin-op-gate`'s pin is stale as COMMITTED** — measured, planted by nothing: `57d0fc387`
   changed the frozen shell's own usage line from `sh .agents/slop/...` to
   `sh oracles/gateport/...` and the pin was not re-frozen. That is why the matrix can measure
   this gate at all without planting a byte.
3. **Four defects in this harness, all of which produced a confident wrong answer first.**
   Each is recorded at the line that fixes it: a shared scratch root deleted a *staged*
   `.tmp.gate.bin` mid-compile and `ld` reported a failure that never happened (`errno=2`);
   the frozen `gatekit` could not resolve drivers that live in `gates/`, so **six of nine
   gates read as broken**; the green and red beats ran in **different directories**, so the red
   beat began empty and `beautiful-mnist-gate` printed `cleared`; and `bounded.py`'s verdict
   token goes to **stderr**, so reading only stdout printed `NO TOKEN` for a run that had
   completed. The recurring harness defect was in my instrument four times over.

## the reported change, for whoever owns `gates/gatekit.py`

```python
# gates/gatekit.py, in Gate.__init__, immediately after:
        self.dir = ART / name
        self.dir.mkdir(parents=True, exist_ok=True)
+       self._clear()   # the directory is empty before ANY check in ANY caller can fail
```

One line, no call-site edit, survives an early exit at module scope. `gates/` is unmodified
by this unit. CLAUSE II is left alone, as instructed — but it should be relabelled
**UNMEASURED** rather than FALSE, since `15/17` is invariant under deleting the `finally`.