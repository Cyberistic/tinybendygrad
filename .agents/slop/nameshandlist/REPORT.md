# The substitution discovery: `rows.pick3` vs `GRAPHS`, derived, with no hand list

**Reading taken 2026-10-06 15:22:40 +03 at `git rev-parse HEAD` = `7f70b4750`.** The tree's
`.agents/slop/graphcmp.bend` is **MODIFIED by `armfour` and moving under this unit** (`git
status` = ` M`; mtime moved 14:56 → 15:20:59 during the session, 29 arms → 33). Every number
below is therefore quoted WITH the state it was read from, and the discovery RE-READS the file
on every call by construction.

**Artifacts:** `.agents/slop/disagree/names.py` (the discovery), `checks/disagree-gate.py`
(consumes it), `.agents/slop/nameshandlist/plant.py` (the two-state plant).

---

## 1. The two hand lists, quoted

The task's `checks/names.py` **does not exist** (`glob` finds none). The gate's reader is
`.agents/slop/disagree/names.py`, named at `checks/disagree-gate.py:53`
(`NAMES = ROOT / ".agents" / "slop" / "disagree" / "names.py"`). `:263-264` is there.

| # | file:line | the list |
|---|---|---|
| A | `.agents/slop/disagree/names.py:263-264` (before this change) | `substituted = sorted({g for v in clusters.values() if any(x in v for x in ("allred", "cdiv", "late")) for g in v})` — a filter that names the three it already knows |
| B | `checks/disagree-gate.py:58` | `ARMED = ("allred", "cdiv", "late")` |
| C | `checks/disagree-gate.py:99` | `SUBSTITUTED = ()` |

**The task's `disagree-gate.py:75-90` is the `PIN` table (`armfour`'s region), not a hand
list.** The substituted hand list is `:99`, whose twin literal is `ARMED` at `:58`.

**Do they agree? YES, literally.** `("allred", "cdiv", "late")` at `names.py:264` is
character-identical to `ARMED` at `disagree-gate.py:58`, and `SUBSTITUTED = ()` matched the
empty computed result. **So there is no "third finding with no owner" of DISAGREEMENT — but
there are two independent copies of one literal that agree by coincidence-of-editing, not by
construction: nothing ties A to B, and `names.py` does not import `ARMED`.** That is the
second-copy fault one level down.

---

## 2. What a substitution IS, structurally — and the measurement

A graph is **substituted** iff it is in `graphcmp.py`'s `GRAPHS` (the population) **and
`rows.pick3` has no `String.eq(name, "<g>")` arm for it, and the dispatcher's single fallback
builder is a DIFFERENT graph** (`g_matmul()`, whose own name is `matmul`). Then the bend side
builds the matmul while the py side builds the real graph, and the differ compares two
different graphs — a `SKIP`, invisible to a per-graph verdict because the report prints
`ops-reached=n/n` and looks symmetrical.

**The discovery** is `names.py:249` `dispatcher_substitutions(bend, py)`: it reads `pick3`'s
body, takes the armed set from the `String.eq` pairs, takes the fallback as the ONE `g_*()`
call no arm routes to, reads `GRAPHS`' keys, and returns the difference minus the fallback's
own name. It RAISES if the fallback is not exactly one.

**MEASURED (both states, by `.agents/slop/nameshandlist/plant.py`):**

| dispatcher read | arms | substituted it finds |
|---|---|---|
| `git show HEAD:.agents/slop/graphcmp.bend` | 29 | **4 — `custom_function`, `mselect`, `mstack`, `stage`** |
| working tree (`armfour`'s arms, uncommitted) | 33 | **0** |

At the session's first read (15:19, 29 arms) it was **4**; at 15:21, after `armfour` landed the
four arms, it was **0**. **The hand list could name only 3 (`allred`/`cdiv`/`late`), and the
four `wantwire` found never existed to it.** The discovery names all four.

**A stale-artifact bug the old filter also had:** the old cluster method, run on the stale
25-graph `runs/graphcmp/D`, returned `['allred', 'cdiv', 'late', 'matmul']` — it counted
**`matmul` as substituted**, because `matmul` is in the cluster the filter selected, even
though `matmul` IS the fallback and is not substituted. The derived method excludes it
(`g != fallback`).

---

## 3. The second axis, moving — read at run time, never a count

`rows.pick3` was at `.agents/slop/graphcmp.bend:1490`; **`armfour` moved it to `:1556`** during
this session, and added 4 arms (29 → 33). The discovery holds no line number and no count: it
finds `def rows.pick3` by `text.index`, slices to `def rows.pick(`, and re-reads both source
files on every call. **A discovery that baked 29/34 would be a hand list with extra steps.**

---

## 4. Authority, and the import

**`names.py` is the AUTHORITY** — it DERIVES the set from `GRAPHS` against the dispatcher's own
arms, on every call. **`disagree-gate.py` now CONSUMES it**: its JSON is already loaded by path
(`subprocess` at `checks/disagree-gate.py:135`, field read at `:159`), and the second copy
`SUBSTITUTED = ()` is **DELETED** (`:96-102` is the comment that replaced it). The gate's lane
now asserts the derived set is **EMPTY** — a substitution is always a defect (a `SKIP`), so
emptiness is the health claim and it goes RED the instant a graph is un-armed, with no list to
edit.

The two-line change, for the record:

```python
# was  :156-157
  if got["substituted"] != list(SUBSTITUTED):
    fails.append(f"the substituted-fixture cluster moved: {got['substituted']}")
# now  :159-161
  if got["substituted"]:
    fails.append(f"names with no arm in rows.pick3, falling through its fallback: "
                 f"{got['substituted']}")
```

**Measured**: `checks/disagree-gate.py --lane pin` no longer reports a substituted failure (the
remaining failures are the stale 25-graph run vs `armfour`'s re-pinned `PIN` — not this unit's);
`--lane plant` = `ok`; `--lane coverage` still fails on the same stale run (`ALLREDUCE CDIV CMOD
CMPEQ COPY FDIV NEG SUB` py-only), which is the artifact-side belt doing its job, not the
discovery.

---

## 5. The plant — two states, on a scratch copy

`.agents/slop/nameshandlist/plant.py`, never the tree's file:

| state | discovery |
|---|---|
| HEAD blob (the four arms absent) | `['custom_function', 'mselect', 'mstack', 'stage']` |
| PLANT: `stage`'s whole `Bool.pick` arm removed from a scratch copy | `['stage']` |
| PLANT restored | `[]` |
| working tree | `[]` |

rc=0, and the harness FAILS if the plant does not name the removed graph or the restore does
not return the working-tree reading. **The discovery goes red when an arm is removed and back
to green when it is restored — a discovery that cannot is one that cannot see the next one.**

---

## 6. Count delta, and whether arming edits a list

- `len(SUBSTITUTED)` old = **0** (the `()` expectation, which happened to match).
- discovered old (HEAD blob) = **4**; discovered now (working tree) = **0**.
- Graphs changing class: **`custom_function`, `mselect`, `mstack`, `stage` → SUBSTITUTED** (in
  the old code they were in NO list at all), and **`matmul` → NOT substituted** (the old filter
  wrongly named it). `allred`/`cdiv`/`late` are in the old hand list but are NOT in the derived
  set — they are ARMED.
- **Will `armfour`'s four arms LEAVE the discovered set automatically? YES.** The set is derived;
  measured 4 → 0 as the arms landed, with **no edit to any list**. That is the whole point: a
  hand list would have needed four new names written into it (and the next un-armed graph would
  be invisible again).

---

## What this unit did NOT do

- Did **not** touch `.agents/slop/graphcmp.bend`, `runs/graphcmp/D/`, `gates/`, `AGENTS.md`.
- Did **not** commit or `git add`.
- The `silent_default_cluster` artifact-side belt remains and is still printed, but it is no
  longer the authority: it reads the RUN and can LAG the dispatcher (the 25-graph run predates
  `armfour`'s arms). The derived set is the harness's current state.
