# WHICH `needs=` CLAUSES CAN FAIL — a census, with the plant and the live number for each

**THESIS UNDER TEST: BEFORE ADDING A `needs=`, ESTABLISH THAT ITS NUMBER MOVES.** A clause invariant
under the change it claims to measure is not a clause. `gates/retention-check.py`'s clause II counted
`return`s for a STRUCTURAL property and deleting the `finally` moved it by ZERO; `G8`'s disarm moved its
count by 0 at every window. This is the same test, applied to **every `needs=` in the tree**.

Nothing in the live tree was mutated. Every fixture is a scratch git tree under
`.agents/slop/needsaudit/scratch/` (created per run, removed at exit); the two producers' hashes are
identical before and after (`checks/residue.py` `70c335f2958cc2db…`, `checks/sweep.py`
`983be5dc0d9db1e4…`) and every run prints that guard. Two independent runs give the same class line:
**`MOVES 10  INVARIANT 0  UNREACHABLE 1`.**

Instrument: `.agents/slop/needsaudit/plant.py`, `.venv/bin/python`. Full transcripts:
`plant.out` (the planted census), `live.out` (the live census over the real tree, 5m09s, `rc=0`,
`live.err` empty). No `.txt` file was created.

---

## 1. THE DENOMINATOR — found by WALK, not from memory

`discover()` walks the tree (skipping `.git`/`.venv`/`node_modules`/`references`/this audit) and applies
two regexes over file text, separating **declaration sites** (code) from **echo sites** (prose and
generated reports, which name a label without computing one).

| rule | regex | labels | declaration sites | echo sites |
|---|---|---:|---|---:|
| A — the literal token | `needs=([a-z][a-z0-9-]+)` | **7** | `checks/residue.py` | 4 |
| B — the tagged verdict | `UNKNOWN:([a-z][a-z0-9-]+)` | **4** | `checks/sweep.py` | 1 |

The union of DECLARED labels is **7**: `owner-decision`, `readlink-target`, `belts-disagree`,
`unstage-self`, `residue-internal-citer`, `commit-or-drop`, `commit-the-report-that-explains-it`.
Rule B's four are all a subset of rule A's seven — the same concept spelled `UNKNOWN:<label>` instead of
`needs=<label>`. So the **clause instances** are **11** (7 in `checks/residue.py`, 4 in `checks/sweep.py`);
the distinct labels are 7.

By rule A the producer is one file, `checks/residue.py`. Two echo sites also declare FIXTURES that name
`residue-internal-citer` (`.agents/slop/slopfinal/{g8.measure,roster.measure}.py`); by rule B four echo
sites exist (`.agents/slop/slopfinal/*.py`, `.agents/slop/unknowns/*.py`). They consume the label; they
do not emit it. **The brief's premise that `verdict_for` has "5" `UNKNOWN:<needs>` is off by one**:
measured by AST, `verdict_for` has **14 `return`s, 4 of them naming `UNKNOWN`**
(`belts-disagree`, `residue-internal-citer`, `commit-or-drop`, `commit-the-report-that-explains-it`).

Dead prior draft: `.agents/slop/slopfinal/needs.move.py` crashes before printing anything
(`AttributeError: 'NoneType' object has no attribute 'partition'`, `rc=1`) — it produced no census. It
covered only the 4 sweep tags and not the 3 residue-only labels.

---

## 2. THE PLANT — each condition changed, the number read twice

Each fixture tree contains exactly one row of the class; the arm changes exactly the condition that
class names, and nothing else. `n` is the count of rows whose `why` carries that `needs=`.
The **verdict pair** is the subject row, before → after.

### 2a. `checks/residue.py` — the literal `needs=` producer

| label | condition it names | n → after | class | verdict pair on the subject row |
|---|---|---:|---|---|
| `owner-decision` | the path holds an `EXCLUDED_DIRS` component | 1 → 0 | **MOVES** | UNKNOWN → UNNAMED |
| `readlink-target` | the row is a symlink (`os.path.islink`) | 1 → 0 | **MOVES** | UNKNOWN → UNNAMED |
| `belts-disagree` | git's `-w -F` and the translate-table belt see different citers | 1 → 0 | **MOVES** | UNKNOWN → CITED |
| `residue-internal-citer` | every citer of the row lives INSIDE the residue | 1 → 0 | **MOVES** | UNKNOWN → CITED |
| `commit-or-drop` | the row is not in `git ls-files` | 1 → 0 | **MOVES** | UNKNOWN → UNNAMED |
| `commit-the-report-that-explains-it` | a TOOL whose own directory has no committed report | 1 → 0 | **MOVES** | UNKNOWN → UNNAMED |
| `unstage-self` | a citer is this instrument's own `SELF` report | 0 → 0 | **UNREACHABLE** | row → *"the two citation belts disagree; git sees [], the scanner sees `.agents/slop/residue/000-the-residue.md`"* |

The `belts-disagree` fixture is the minimal reproducer for **residue's** belt pair: a citer reading
`gate.sh` (both belts see it) beside a citer reading `gate.sh.bak` (git's word boundary splits on `.`,
the translate table does not), so belt A is a strict superset of belt B. Deleting the second citer makes
the belts agree and the row becomes `CITED`.

`unstage-self` is structurally unreachable: `belt_self_cited` fires only when `belt_a == belt_b` **and**
`belt_b` holds a `.agents/slop/residue/` path — but belt A is `git grep … :(exclude).agents/slop/residue/**`,
so belt A can never contain that path, so the `belt_a ^ belt_b` branch above it returns `belts-disagree`
first at every witness strength. The generous index (the SELF report *is* a citer) still yields
`belts-disagree`, as printed.

### 2b. `checks/sweep.py` — the tagged `UNKNOWN:<label>` producer

Sweep's belts are a different pair (`mentioned_filenames` regex vs `whole_path_tokens`), so the reproducer
differs: a citer reading `gate.sh-extra` yields `gate.sh` for the regex (its final segment is
`\.[A-Za-z0-9]+`) and `gate.sh-extra` for the scanner.

| label | n → after | class | verdict pair on the subject row |
|---|---:|---|---|
| `belts-disagree` | 1 → 0 | **MOVES** | UNKNOWN:belts-disagree → KEEP-CITED |
| `residue-internal-citer` | 1 → 0 | **MOVES** | UNKNOWN:residue-internal-citer → ORACLE |
| `commit-or-drop` | 1 → 0 | **MOVES** | UNKNOWN:commit-or-drop → DELETE |
| `commit-the-report-that-explains-it` | 1 → 0 | **MOVES** | UNKNOWN:commit-the-report… → DELETE |

---

## 3. THE LIVE NUMBER — a plantable clause can still never fire

Planting proves a clause *can* decide a row. `live_census()` additionally runs the production pipeline
in memory over the real tree (`3959` walked rows; `1161` reach `residue.classify`, i.e. `sweep=DELETE`)
and counts what fires **today**.

| producer | label | live count | fires? |
|---|---|---:|---|
| residue.py | `owner-decision` | 62 | **FIRES** |
| residue.py | `readlink-target` | 185 | **FIRES** |
| residue.py | `belts-disagree` | 66 | **FIRES** |
| residue.py | `residue-internal-citer` | 317 | **FIRES** |
| residue.py | `commit-or-drop` | 0 | **NEVER FIRES** |
| residue.py | `commit-the-report-that-explains-it` | 0 | **NEVER FIRES** |
| residue.py | `unstage-self` | 0 | **NEVER FIRES** |
| sweep.py | `belts-disagree` | 84 | **FIRES** |
| sweep.py | `residue-internal-citer` | 265 | **FIRES** |
| sweep.py | `commit-or-drop` | 114 | **FIRES** |
| sweep.py | `commit-the-report-that-explains-it` | 110 | **FIRES** |

### The two residue clauses that are DEAD IN THE CALLER, not broken in the clause

`residue.main()` does `residue_rows = [r for r in rows if r[2] == "DELETE"]` where `r[2]` is
`sweep.verdict_for(...)`. `sweep.verdict_for` returns `UNKNOWN:commit-or-drop` for exactly the rows
`residue`'s `untracked` branch names, and `UNKNOWN:commit-the-report-that-explains-it` for exactly the
rows its `witness` branch names — same `tracked` set, same `TOOL_EXT`, same `witness_committed`. So those
rows are never `DELETE`, never reach `residue.classify`, and **the two duplicate clauses contribute zero
to the production report while sweep's originals fire 114 and 110 times.** They are not unreachable in
`classify` (the plant drives them 1 → 0), they are unreachable in the *pipeline that calls it*. What
would make them live: delete the duplicated branches from `residue.classify`, or widen the DELETE filter
that feeds it — a decision for the owner, not this census.

### The one clause that is structurally dead

`unstage-self` fails both tests: 0 planted (no fixture reaches it) and 0 live. The belt that was added to
notice the self-citation fix being undone is the one branch the fix makes impossible — the exclusion is
belt A's pathspec, and belt A's blindness is what the disagreement branch tests for.

---

## 4. THE THREE CLASSES

Counting **clause instances** (label × producer, denominator 11):

- **MOVES — 10.** Six in `residue.py` (`owner-decision`, `readlink-target`, `belts-disagree`,
  `residue-internal-citer`, `commit-or-drop`, `commit-the-report-that-explains-it`) and all four in
  `sweep.py`. Each has a planted `n ≥ 1 → 0` and a verdict pair.
- **INVARIANT — 0.** No clause in this tree survived its own condition being changed.
- **UNREACHABLE — 1.** `residue.py`'s `unstage-self`, shadowed by `belts-disagree` because belt A excludes
  the SELF path belt C looks for.

Counting **rows that actually fire today** (the condition-that-never-fires test): **8 of 11 clause
instances fire; 3 never fire.** Of the three: `unstage-self` is structurally unreachable; `residue.py`'s
`commit-or-drop` and `commit-the-report-that-explains-it` are plantable but dead in the production
caller.

---

## 5. HOW TO REPRODUCE

```
.venv/bin/python .agents/slop/needsaudit/plant.py          # planted census  -> plant.out
.venv/bin/python .agents/slop/needsaudit/plant.py --live   # live census     -> live.out (≈5 min)
```

Both exit 0. No production file is written; the live-tree hash guard is printed by every run.
