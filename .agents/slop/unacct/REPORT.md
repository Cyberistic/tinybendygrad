# THE STATE COUNTED BY NEITHER COLUMN — a census of one `runs/graphcmp/D` run

**HEAD `4b42c0ccf7e53bb140680a19bbcdaddad2f02bf4`** (`arenaparam: the 62 self-parenting nodes are threaded,
and the corpus is 31/34 BEFORE AND AFTER`, 2026-10-18 05:52:39 +0300 — note the subject: the unaccounted
state has already propagated into a commit message as an arithmetic phrase.)
**Measured 2026-10-18T17:22Z–17:31Z.** Artifacts under audit: `runs/graphcmp/D/`, written by the run of
2026-10-18 05:51:48Z. Machine was at ~7/12 load.

**What was run:** `.venv/bin/python .agents/slop/unacct/census.py` and `ast.parse` over three sources
(`.agents/slop/graphcmp.py`, `checks/differ.py`, `checks/corpus-figure.py`) plus text reads of the artifacts.
**What was NOT run, by instruction:** no `bend`, no CPython emit, no `graphcmp`, nothing under `gates/`, no
`e2e`, no `sweep`/`differ`/`bounded`, no pytest/mypy/ruff. So every count below is read off an artifact
somebody else wrote; nothing here re-measures the port. Statements about what the CODE would do, rather
than about an artifact, are marked **[code-read]**.

---

## 0. THE CONTROL (it gates every number below)

The census must reproduce the two numbers it is auditing, from the artifacts alone, and must classify
`loop` as REFUSED. It does (`census.out`, `census.py:245-259`; it prints `CONTROL=FAIL` and writes nothing if it does not):

```
CONTROL=PASS
  ok  corpus() size == graphs=: got 34 want 34
  ok  files_with(D1, AGREE) == graphs-agree: got 31 want 31
  ok  files_with(D1, DISAGREE) == graphs-disagree: got 2 want 2
  ok  census AGREE == summary graphs-agree: got 31 want 31
  ok  census DISAGREE == summary graphs-disagree: got 2 want 2
  ok  loop is REFUSED: got 'REFUSED' want 'REFUSED'
```

The census re-implements `verdict()` (`differ.py:999`), `files_with` (`:496`), `lines_with` (`:473`) and
`anchored` (`:478`) from their source, so it and the run agree by construction rather than by coincidence.
Populations are **discovered**, not named: `graphcmp.GRAPHS` and `differ.WANT/CONTROLS/STAB` are read with
`ast.parse`, never imported (importing `graphcmp.py` binds a Device; a census of a finished run must not
move the machine it measures). Full per-graph table: `graphs.rows` (34 rows). Lanes: `lanes.rows`.

---

## 1. THE GRAPH CORPUS. Denominator = 34.

`graphcmp.GRAPHS` (`graphcmp.py:1667-1676`) declares **34** graph names. All 34 have an artifact; 34 `.err`
siblings exist. State per graph, decided from `D1-graph-<g>.txt` alone:

| state | n | names |
|---|---|---|
| AGREE | **31** | allred alu binblob bit buffer bw cast cdiv commute custom_function flip getaddr group indexed late matmul move mselect mstack mulacc range rangeflat reduce sink special stage sym threefry unshard where wmma |
| DISAGREE | **2** | `gate`, `lin` |
| **REFUSED** (ran, emitted no `VERDICT:` line) | **1** | **`loop`** |
| UNSET (no row in `WANT`) | **0** | — |
| MISSING (no artifact) | **0** | — |
| DEAD (ran, emitted nothing) | **0** | — |

**31 + 2 = 33. The denominator is 34.** The residual is one graph, and it is `loop`.

`D1-graph-loop.txt` is five bytes — `rc=2\n` — and nothing else. `D1-graph-loop.txt.err` names the cause: the
`diff` subcommand compares the two sides' devices and refuses — `py=['N', 'sCPU'] bend=['sCPU']`, "NOT
WELL-POSED, and this is NOT a verdict (exit 2)".

### What the summary says about `loop`, and what it does not

* `D0-run-summary.txt` contains **0 occurrences of the string `loop`** (`grep -c`, measured).
* `graphs-answered=34` is `len(graphs) - len(unset)` = 34 − 0 (`differ.py:722`). It is computed over the
  **TABLE**, not over the artifacts: a graph "answered" means somebody wrote a `WANT` row, which says
  nothing about whether the port emitted anything. So the summary asserts that all 34 were answered while
  one of them produced no verdict at all.
* `loop` **is** surfaced, in three places, and it is important not to overstate the finding:
  `D1-verdicts.txt` prints `loop: VERDICT= EXPECTED=AGREE`; `expect-moved=3` counts it (because `"" !=
  "AGREE"`, `differ.py:563-564`); and the run exits non-zero (`differ.py:796`, `return 1 if unset or moved
  else 0`) **[code-read]**.
* So the defect is exactly and only what it was said to be: **there is no column that attributes the
  state.** The refusal is printed and excluded from the arithmetic. `graphs-agree` and `graphs-disagree`
  are `files_with(...)` counts of FILES CONTAINING A NEEDLE (`:731-732`); an artifact with no `VERDICT:`
  line matches neither. Its discoverability is 34 − 31 − 2, i.e. subtraction.
* `expect-moved=3` is the wrong column for it, not a missing one: it conflates "the verdict moved away from
  the expected one" (gate, lin) with "there was no verdict" (loop). Two different states, one number.

---

## 2. THE OTHER LANES

### 2a. Byte-diff lane `D2-cmp-*.txt` — denominator 34, **14 unaccounted**

Summary rows for this lane: `byte-identical=20` and `not-comparable=0` (both `lines_with` over
`D2-bytediff.txt`). There is **no row for `DIFFERS`**.

| state | n | in a summary column? |
|---|---|---|
| BYTE-IDENTICAL | 20 | yes (`byte-identical`) |
| NOT COMPARED | 0 | yes (`not-comparable`) |
| **DIFFERS** | **14** | **NO — neither** |

The 14: `alu bit bw cdiv commute gate group late lin loop move sym threefry where`.
20 + 0 + 14 = 34. The 14 are discoverable only by subtraction from the corpus size — **the same defect as
`loop`, fourteen times larger.**

**The cross-lane fact that makes this sharp:** `loop` is REFUSED in the verdict lane and DIFFERS in the byte
lane. Both lanes cover the same 34 graphs. The byte lane emits each side with its own
`gc("emit", "--side", side, ...)` (`:604-606`), so it never compares devices and CAN answer for `loop`;
the verdict lane runs `diff --graph`, which does compare devices and refuses. **So two lanes over one
population disagree about how many of the 34 were measured — 33 by one lane's arithmetic, 34 by the other's
— and `graphs=34` does not distinguish them.**

### 2b. Control lane `D3-control-*.txt` — denominator 5, **0 unaccounted**

All five carry `# CONTROL VERDICT: OK`; `controls=5 of 5` (re-derived independently, 5). No unaccounted
member today. **[latent, not measured]** the lane has only that one row, so a control that FAILED and a
control that REFUSED both read `4 of 5`. I did not produce such a control and do not claim one exists.

### 2c. Stability lane `D9-stability-*.txt` — denominator 5 pairs, 0 unaccounted but **1 MISLABELLED**

`stable-pairs=4 of 5`, `stable-failed=1 of 5`, `stable-differ=0 of 5` — all three re-derived and equal to
the summary; 4 + 1 + 0 = 5. Nothing is in no column.

But `loop`'s pair is reported as
`loop: ONE SIDE IS A 0-ROW FAILURE after a retry -- NOT a reproducibility result`, and that sentence is
**false of `loop`**. Measured: `D9-stability-loop-a.txt` and `-b.txt` are each **1 line / 5 bytes, `rc=2`,
and byte-identical to each other**. The guard is `one_line(a) or one_line(b)` (`differ.py:645,648`) **[code-read]**,
so it cannot name a side when both are 0-row, and it says "ONE SIDE" anyway. Consequences:
`stable-pairs=4 of 5` **under-reports** — loop's two runs were a byte-identical, deterministic non-answer;
the lane had no reproducibility failure at all, it had a refusal; and `stable-failed=1 of 5` cannot tell a
deterministic refusal from a genuine non-reproducibility, because one row holds both states.

### 2d. Lanes the summary says nothing about at all **[code-read]**

Present in `runs/graphcmp/D/`, no row in `D0-run-summary.txt`: `D0-ops-probe`, `D0-repro`, `D6-commute-equiv`,
`D6-commute-ordered`, `D6-matmul-equiv`, `D6-matmul-ordered`, `D8-dbg-012`, `D8-dbg-03`,
`D8b-cpython-dbg1-reachability`, `D10-zerorow-guard`.

One of these is a live instance, not a listing: **`D0-ops-probe.txt` crashed.** It is 206 lines, contains
one Python `Traceback`, ending in `IndexError: tuple index out of range` at `tinygrad/uop/ops.py:356`
(`_shape`), and it carries **no `rc=` line** — because `differ.py:691` calls
`capture("D0-ops-probe.txt", ...)` without `stamp_rc=True`, while the census call one line earlier (`:684`)
does pass it. `capture`'s own docstring (`:452-455`) gives the rule: "a step whose output is a TABLE must
say whether the table is finished." The census is stamped, the ops probe is not, and a crashed ops probe is
invisible in the summary. **[code-read for the stamp; measured for the traceback and the missing `rc=`.]**

By contrast `D10-zerorow-guard.txt` reads `rc=0` today because its fixture `.agents/slop/graphcmp-empty.bend`
exists (110 B). Were it absent, `differ.py:676-679` would write `zerorow-guard=REFUSED` **into the
artifact** and nothing at all into the summary **[code-read]** — a REFUSED state with no summary row.

---

## 3. THE SUMMARY WRITER: WHICH STATES IT HAS A ROW FOR

`cmd_run`'s writer is `differ.py:704-760`. It emits **24 rows** (18 explicit + 4 precondition + 2 substrate —
measured: `wc -l` on the artifact), of which **17 are pinned** (`PINS`, 17 keys at `:256-292`, `ast.parse`-counted).

**HAS a row (state → row → how it is computed):**

| state | row | computation |
|---|---|---|
| corpus size | `graphs` | `len(corpus())` — the DECLARATION |
| no expectation written | `graphs-unset` | `len(unset)` — the TABLE |
| has an expectation | `graphs-answered` | `len(graphs) - len(unset)` — a restatement of the two above |
| expectation not held | `expect-moved` | `len(moved)` — conflates moved and absent |
| artifact says AGREE | `graphs-agree` | `files_with('D1-graph-*.txt', 'VERDICT: AGREE')` |
| artifact says DISAGREE | `graphs-disagree` | `files_with('D1-graph-*.txt', 'VERDICT: DISAGREE')` |
| canonical bytes equal | `byte-identical` | `lines_with('D2-bytediff.txt', 'BYTE-IDENTICAL')` |
| a canonical side is 0 bytes | `not-comparable` | `lines_with('D2-bytediff.txt', 'NOT COMPARED')` |
| stability: identical / failed / differ | `stable-pairs`, `stable-failed`, `stable-differ` | `anchored`/`lines_with` over `D9-stability.txt` |
| plants disagree | `plants-disagree` | `files_with('D5-plant-*.txt', 'VERDICT: DISAGREE')` |
| cross, conflations, controls, selfcheck, oracle-selfcheck, census-rc, 4 preconditions, 2 substrate | as named | as named |

**HAS NO row for — measured members, with denominators:**

| state a run can produce | measured instances today | denominator | why no row exists |
|---|---|---|---|
| **artifact carries no `VERDICT:` line (a refusal)** | **1** (`loop`) | 34 graphs | `graphs-agree`/`graphs-disagree` are needle counts over files; there is no complement row |
| **canonical bytes DIFFER** | **14** | 34 graphs | only `BYTE-IDENTICAL` and `NOT COMPARED` have rows; `DIFFERS` is the common case and is the silent one |
| **both sides of a stability pair refused** | **1** (`loop`) | 5 pairs | the `or` guard cannot name a side; the sentence says "ONE SIDE" |
| **a probe lane that crashed** | **1** (`D0-ops-probe`) | 1 such lane | `stamp_rc=True` omitted, and no row for the artifact |
| **DEAD** (ran, emitted nothing) | 0 | — | no row anywhere; `gates/gatekit.py:60` declares the state, `D0-run-summary.txt` never mentions it |

**So the narrow answer is YES: there are four states this run actually produced that `D0-run-summary.txt`
cannot report** — 1 + 14 + 1 + 1 across four different lanes, and three of the four are recoverable only
by subtracting from a denominator. `DEAD`, the fifth state, is unmeasured here rather than absent: nothing
in this run reaches it.

One row in the summary is a *collapsed* pair rather than a missing one **[latent]**: `controls=N of 5`
cannot distinguish failed from refused; `plants-disagree=N of 7` cannot distinguish agreed from refused. No
member of either is in a collapsed state today.

---

## 4. THE MINIMAL CHANGE (proposed, NOT implemented)

### Row 1 — the essential one, and it is FREE

```
graphs-refused=<n>
```
placed immediately after `graphs-disagree` (`differ.py:732`).

**Where computed.** Memoize the verdicts the run *already computes* at `differ.py:563`:

```python
v = {g: verdict(f"D1-graph-{g}.txt") for g in graphs}   # replaces the comprehension's re-read
moved = [f"{g}: VERDICT={v[g]} EXPECTED={WANT[g]}" for g in graphs if g in WANT and v[g] != WANT[g]]
...
f"graphs-refused={sum(1 for x in v.values() if not x)}",
```

**Cost: zero new subprocesses, zero new `bend` runs, zero new file reads.** `verdict()` is *already* called
once per graph at `:563` for every graph in `WANT`, and `graphs-unset=0` means that is all 34. The number
is computed, printed into `D1-verdicts.txt`, and then discarded. The change converts a discarded value into
a summary row. The invariant it makes checkable: `graphs-agree + graphs-disagree + graphs-refused == graphs`.

**The name, and a retraction worth recording.** Call it `graphs-refused`, not `graphs-unanswered`:
`checks/corpus-figure.py:50-51` records that `graphs-unanswered` "was correctly NOT added: it would have
asked `graphs-agree`'s question again." That reason is false of this quantity. `graphs-agree` is
`files_with(...)` — a count of FILES CONTAINING A NEEDLE — while the residual counts ARTIFACTS THAT CARRY
NO NEEDLE, and the two can differ: an artifact carrying both `VERDICT: AGREE` and `VERDICT: DISAGREE` would
be counted in both columns and in neither the residual or the sum. The deliberation rejected the row for a
reason about a question it does not ask. That is why the row is missing: not because nobody thought of it.

### Row 2 — the same defect, fourteen members

```
byte-differs=<lines_with('D2-bytediff.txt', ' DIFFERS')>
```
next to `not-comparable` (`:734`). Cost: one extra pass over a **16,003-byte** file — or free, by counting
the `report` the loop at `:600-617` already builds per graph, which is where `BYTE-IDENTICAL`'s count really
lives. Invariant: `byte-identical + not-comparable + byte-differs == len(graphs)`.

### Row 3 — the mislabelled state

Split the `or` at `differ.py:645,648` so it names what it measured: both sides 0-row → "BOTH SIDES REFUSED
-- NOT a reproducibility result"; exactly one → "SIDE a|b IS A 0-ROW FAILURE". Cost: two boolean tests per
pair, no extra read (both files are already read at `:651` for the byte compare). Then `stable-refused=<n>
of 5` can be a fourth row; until it is, a deterministic refusal and a genuine non-reproducibility share
`stable-failed`.

### Row 4 — the crashed lane

Pass `stamp_rc=True` at `differ.py:691`, exactly as `:684` does, and add
`ops-probe-rc={last_line('D0-ops-probe.txt')}` next to `census-rc` (`:748`). Cost: 6 bytes written and one
read of a file the row already needs.

**If only one of these lands, land Row 1.** It is the only one that costs nothing, and it is the only one
that makes the headline arithmetic close: today `31 + 2 = 33` against a denominator of 34.

---

## 5. WHAT IS NOT CLAIMED

* The corpus was NOT re-run. Every count is read from artifacts written by the 2026-10-18 05:51:48Z run.
  Nothing here says what the port does today; the tree is a moving target and HEAD may have moved since
  17:31Z.
* The 17 `PINS` were not evaluated. Two rows in the summary are RED as text —
  `oracle-selfcheck=# ORACLE SELFCHECK: FAIL` and `census-rc=rc=1` — reported here as measured strings, not
  as a verdict about the port.
* `census.py` imports neither `graphcmp.py` nor `differ.py`; every population is read with `ast.parse`.
* `UNSET=0`, `MISSING=0` and `DEAD=0` are measured over the denominator 34, not assumed. `DEAD=0` is a claim
  about this run only: nothing here establishes that the lane can detect it.
* Rows 3 and 4 of the proposal are **[code-read]**: the guards and the missing `stamp_rc` are cited to lines,
  and the states they would report are counted from artifacts, but no run produced a one-sided failure or a
  second crashed probe.

## FILES

* `.agents/slop/unacct/census.py` — the census and its control.
* `.agents/slop/unacct/graphs.rows` — 34 graphs: `graph`, `artifact`, `state`, `counted_in_summary_column`.
* `.agents/slop/unacct/lanes.rows` — 78 lane members over the four lanes, same four columns.
* `.agents/slop/unacct/census.out` — the control and the tallies as printed.