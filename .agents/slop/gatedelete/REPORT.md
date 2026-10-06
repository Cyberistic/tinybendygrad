# gatedelete REPORT — the five rows that moved when the arms landed

Unit: `checks/disagree-gate.py` only. Read `AGENTS.md`: populations by DISCOVERY, and
`SKIP`/`DEAD`/`REFUSED` are not passes. I did **not** run `bend`, did **not** commit or
`git add`, and did **not** touch `.agents/slop/graphcmp.bend`/`.py`, `runs/graphcmp/D/`,
`gates/`, or `AGENTS.md`. I own `checks/disagree-gate.py` and `.agents/slop/gatedelete/`.

**The starting defect, re-measured 2026-10-06 (before any edit):**
`.venv/bin/python checks/disagree-gate.py` → `rc=1`; `CITATIONS` FAIL with **exactly three**
failures, all the gate's own NEGATIVE claim firing because the three arms now exist:

```
rows.pick3 now HAS an arm for 'allred', so it is no longer substituted; ...
rows.pick3 now HAS an arm for 'cdiv',   ... ; ...
rows.pick3 now HAS an arm for 'late',   ... ; ...
```

`PIN`/`COVERAGE ARTEFACTS`/`PLANT + DISARM` were `ok`. **The claim was true and is now
false. Leaving it is how a gate goes red for being fixed.**

---

## 1. Per-step verdicts — ONE change at a time, the gate re-run after each

| # | change | gate lane + rc | what moved |
|---|---|---|---|
| 0 | (baseline, none) | `full rc=1`; CITATIONS FAIL (3) | — |
| 1 | `CITES` `1421 -> 1485` | **no edit needed; verified** | at HEAD `graphcmp.bend:1485` reads `def rows.pick3(+name: String) -> O.Found:`; no citation failure named it |
| 2 | negative-claim loop → POSITIVE `arms_wired` | `full rc=0` | CITATIONS FAIL(3) → ok |
| 3 | `PIN`: drop `cdiv`,`late`; `allred` row `6 -> 8` | `pin rc=1` (3 fails) | `set moved ['allred','cdiv','flip','late'] vs ['allred','flip']`; `allred row 6->6 (pin 8)`; `summary no longer reads graphs-disagree=2` |
| 4 | `SUBSTITUTED` `("allred","cdiv","late","matmul") -> ()` | `pin rc=1` (4 fails) | adds `substituted-fixture cluster moved ['allred','cdiv','late','matmul']` |
| 5 | `SUBSTITUTION_ARTEFACTS` `{8 ops} -> {}` + rewire `lane_coverage` | `coverage rc=1` (1 fail) | `py-only op SET moved: ['ALLREDUCE','CDIV','CMOD','CMPEQ','COPY','FDIV','NEG','SUB'], expected []` |
|  | **FINAL** | `full rc=1`; PLANT ok | PIN 4 fails · CITATIONS 2 fails · COVERAGE 1 fail · PLANT ok |

I initially bundled steps 3+4 in one edit (both are asserted inside `lane_pin`); I split
them back out — reverting `SUBSTITUTED` to its old value, running, then re-applying — so
the per-step verdict above is real and not a story.

### Change 2 — REPLACED, not deleted (and why)

Deleting the negative loop would have left the gate with **no** claim about the dispatcher,
which is exactly the state where a removed arm silently returns. A missing arm is not a
refusal: the name falls through to `rows.pick3`'s bottom rung `g_matmul()` — a **REAL
graph** — and the differ then compares two different graphs and reports a disagreement
that is the dispatcher (`AGENTS.md`: a `SKIP` is not a pass). So the claim is now POSITIVE:
each of `allred`/`cdiv`/`late` is routed to `g_<g>()`, and each `def g_<g>()` is defined
exactly once. It goes red when an arm is **removed** — the direction that actually lies —
instead of when one is **added**. It is a pure function of the dispatcher text,
`arms_wired(text)`, so the plant can move it.

---

## 2. FINAL verdict — `ok` cannot be reached here without `bend`, and one lane is red for a FOREIGN reason

Four lanes: `pin`, `citations`, `coverage`, `plant`.

- **`PLANT + DISARM` — ok.**
- **`CITATIONS` — RED, and NOT for anything this unit did.** A foreign, **uncommitted**
  edit to `.agents/slop/graphcmp.bend` (the ADEV `devs` half; mtime `2026-10-06 14:48:11`)
  added a 5-line comment block at `:152`, shifting every later line by **+5**. The gate
  reads the WORKING TREE, so:
  - `:1485` now reads the `late` GROUP line — `def rows.pick3` moved to **`:1490`**;
  - `:764` now reads a `CONST` line — the `OpsGROUP` line moved to **`:769`**.
  At **HEAD** both cites are correct (`git show HEAD:.agents/slop/graphcmp.bend | sed -n
  '1485p;764p'` → `def rows.pick3…` and the `…OpsGROUP…` line). I did **not** re-point
  them: the file is another unit's and its line numbers are not stable, and the task
  explicitly says the `1421 -> 1485` cite is the orchestrator's and already done. **The
  orchestrator must reconcile: either commit that edit and move the two cites to
  `1490`/`769`, or exclude it.** One keystroke either way; I am flagging, not guessing.
- **`PIN` — RED, every failure the STALE RUN.** `runs/graphcmp/D/` is a **25-graph,
  pre-arms** run: `D2-canon-bend-allred.txt` is **byte-identical to matmul's** (`cmp` →
  `IDENTICAL`), `bend_rows=18` (matmul) for all three, and `D0-run-summary.txt` reads
  `graphs=25` / `graphs-disagree=4`. The corpus is now **34** (`wantwire` §1, commit
  `ceb4742fb`). The lane can only go green after **`bend` + `checks/differ.py run`**.
- **`COVERAGE ARTEFACTS` — RED, same stale run** (`D1-graph-*.txt` still carry matmul's
  per-op counts), and it will **stay red after a fresh run** for a second, real reason — §4.

---

## 3. `PIN`'s `allred` row `6 -> 8` is a PREDICTION, and the code says so

`allred` was `NOT A ROW` (its old row 6 was matmul's `CONST arg=l0:2` vs `l0:1`). It now
has an arm, so the bend side **is** asked — but no `bend` run has rewritten the run for it.
`threegraphs` §4 predicts the first disagreement is the **COPY** row (`row 8`) on the
device tuple's NORMAL FORM: py `n(sCPU,sCPU)` vs bend `ssCPU,sCPU` — two renderer spellings
of one value, both sides the differ's own text, so `shape=WRONG VALUE`, `fault=HARNESS`.

**A pin taken from a prediction is a pin that cannot fail.** That warning is written **in
the `PIN` table** (where a reader of the pin lands), not in this file. It is also already
falsified-detectable: against the stale run it *does* fail (`row 6 -> 6 (pin 8)`), so the
pin is red for a true reason rather than silently green.

**The prediction is now DOUBLY suspect** because of the foreign `devs` edit (§2): if that
fix lands whole, the bend COPY renders `n(sCPU,sCPU)` and **agrees**, leaving the
`ALLREDUCE` row (`al(OADD,sCPU,CPU)` vs `al(OADD,n(sCPU,sCPU))`, row 9) as the first
disagreement — or, with the matching `graphcmp.py` half too, `allred` **agrees** and leaves
`PIN` entirely (`threegraphs` §5: `PIN` → `{flip}`). Row 8, row 9, and "allred stays" are
three candidate futures and **only a `bend` run can choose**. The code's row 8 is the
task's instructed value and is marked UNCONFIRMED.

---

## 4. A real finding this unit must not paper over: `SUBSTITUTED`/`SUBSTITUTION_ARTEFACTS` and `names.py`'s hand list

`wantwire` (commit `ceb4742fb`, landed AFTER the task was written) found **FOUR more
substituted graphs** in the 34-graph corpus with **no bend arm**: `custom_function`,
`mselect`, `mstack`, `stage` — all falling through to `g_matmul()`. Consequences for the
five rows I landed:

1. **`SUBSTITUTION_ARTEFACTS = {}` is correct and conservative, and it will go RED after a
   fresh run** with the py-only ops of those four. That is the lane doing its job: `{}`
   asserts "no substitutions", and the four are substitutions. Arming or declaring them is
   a separate unit's job (wantwire §5, phase 2). I did **not** guess their cluster into the
   pin.
2. **`names.py` has the very fault this gate is built to hate.** `substituted` is derived
   by `silent_default_cluster` but then filtered by a **HAND LIST**:
   `any(x in v for x in ("allred", "cdiv", "late"))` (`names.py:263-264`). So
   `got["substituted"]` will read `[]` after the arms land **while the four new clusters
   sit unwatched** — i.e. `SUBSTITUTED = ()` passes not because there are no
   substitutions, but because `names.py` only ever looks for the three names it was told
   about. That is `checks/sweep.py`'s `LIVE_UNITS` fault one level down. `names.py` is not
   my file; **the pin is only as strong as this filter, and the filter is a list.**
3. Therefore the target "`ok` on all four lanes" is **not reachable even with `bend`**
   until phase 2 arms or declares the four — the coverage lane will correctly name them.

---

## 5. PLANT — the positive claim can still go red

`.agents/slop/gatedelete/plant-arms.py` loads `arms_wired` **by path** (the gate's filename
is hyphenated and is not importable) and mutates a **scratch copy** of the dispatcher — the
real `.agents/slop/graphcmp.bend` is not touched:

```
ok    control (intact dispatcher): []
RED   plant: allred arm un-routed -> ["rows.pick3 no longer routes 'allred' to g_allred(); an unarmed name falls through to the g_matmul() fallback and is never compared"]
RED   plant: g_cdiv undefined   -> ['g_cdiv is defined 0 times, expected once']
PLANT ARMS: OK -- the lane can go red          rc=0
```

The control passing is the load-bearing half: **a lane that is `ok` after five edits looks
identical whether it got stronger or was quietly weakened**, so the plant is what proves
the difference.

---

## 6. Files written, and what still owes a run

- `checks/disagree-gate.py` — the five changes + docstring `THREE LANES -> FOUR LANES`,
  `the six -> the disagreements`, and the coverage paragraph rewritten to the empty
  population. `py_compile` OK.
- `.agents/slop/gatedelete/plant-arms.py` — the arm-claim plant.
- `.agents/slop/gatedelete/REPORT.md` — this file.

**Owes `bend` (named lane and why):**
- `PIN` — stale 25-graph run; needs `bend` + `checks/differ.py run`; `allred`'s row is a
  prediction (± the foreign `devs` edit).
- `COVERAGE ARTEFACTS` — same stale run, and after a fresh run the four unarmed graphs
  (`custom_function`/`mselect`/`mstack`/`stage`) keep it red until phase 2.
- `CITATIONS` — not a `bend` issue: a foreign uncommitted `+5` edit moved the two bend
  cites (`1485 -> 1490`, `764 -> 769`); the orchestrator reconciles.
