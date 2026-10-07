# The 103 `.txt` under `runs/graphcmp/D/` — the contract, the experiment, and the decision

MEASURED 2026-10-05. Nothing committed. `checks/differ.py`, `checks/no-txt.py`,
`checks/README.md` and `AGENTS.md` are edited; the two frozen oracles are **byte-identical to
before** (`94e7108d428bae3f…`, `a5d23505b3e93816…`) and there is no pin to move.

## 1. THE INVENTORY, AND IT IS THE ARGUMENT

`.agents/slop/difftxt/inventory.py` imports `checks/differ.py` and builds the set from its own
`WANT` / `CONTROLS` / `PLANTS` / `STAB` plus 13 literals — so no list is typed twice.
Output: `.agents/slop/difftxt/inventory.out`.

**103 names, 25 families. 103 on disk, 0 orphans, 0 declared-but-absent. 103 of 103 are named by
TWO OR MORE INSTRUMENTS.**

| named by | how |
|---|---|
| `checks/differ.py` | writes all 103; reads **12 by name** in its own summary block (`:350-369`); 8 glob sites, of which `:448` was load-bearing |
| `.agents/slop/diffpy/oracle-run.sh` — **sha256-pinned at `differ.py:59`** | writes all 103; reads **12 by name** (`:283-308`) |
| `.agents/slop/diffpy/oracle-repro.sh` — **sha256-pinned at `differ.py:61`** | reads `D0-run-summary.txt` at **`:61`**; globs `*.txt` at **`:105`** and 5 families at `:114-115` |
| `checks/corpus-figure.py:72` — **NOT MINE** | reads `D0-run-summary.txt`, prints `NO RUN SUMMARY`, `main()` returns **1** |
| `checks/README.md` | 16 distinct names (the 19-row table, `differ.py` writes 103) |
| `AGENTS.md:38` | 1 (`D0-run-summary.txt`) |
| `.agents/TODO.md` | 8 |

There is **no split available.** Every one of the 103 is a read by someone. The 12 the oracle's
summary block reads are the *same* 12 `differ.py`'s reads — both compute one summary — so those
names carry the coupling twice.

## 2. THE EXPERIMENT

`.agents/slop/difftxt/rename-experiment.sh` renames ONE extension and changes nothing else, then
runs (a) the FROZEN oracle's `healthy()` and `artefacts_ok()` — extracted **verbatim by line
range** `oracle-repro.sh:60-87` and `:102-119`, digests in `oracle-probe.sh` — and (b)
`differ.py`'s own, against three populations. Artifact: `rename-experiment.out`.

```
pop     files    *.txt    *.rows   healthy artefacts_ok      <- the FROZEN ORACLE
live      151      103         0     FALSE          53
rows      151        0       103     FALSE           0
empty       0        0         0     FALSE           0

pop     artefacts_ok                                          <- differ.py, BEFORE the fix
live      53 finding(s) {'EMPTY': 16, 'ONE-LINE': 37}
rows       0 finding(s)                                          <- reported success
empty      0 finding(s)                                          <- reported success
```

**The pin reported `[] -- PIN INTACT` in all three rows.** So the finding the brief predicted is
confirmed, and it is *worse* than predicted:

> **Row 3 is the real finding. `artefacts_ok()` reported ZERO on a directory holding nothing. It was
> never a guard — a glob is a set of names the guard itself chose, so when those names move it
> inspects nothing and reports nothing. The rename did not break the guard; the rename revealed
> that there was none.**

Three further measurements from the same run, which change the shape of the problem:

1. **`oracle-repro.sh`'s `healthy()` is FALSE on the LIVE tree already.** Its pins read
   `graphs=24` / `graphs-agree=22` / `byte-identical=21`; this driver writes `16` / `14` / `14`
   (`differ.py:126-127` says so). It cannot pass against `differ.py run` and gates nothing today.
   **So the names are load-bearing on the PYTHON side**, plus on `corpus-figure.py`.
2. **`corpus-figure.py` is LOUD, not silent** — `if not summary.exists()` at `:73` prints
   `NO RUN SUMMARY` and `main()` returns 1.
3. **`differ.py`'s `unhealthy()` raised `FileNotFoundError`** on the renamed population. Loud, but
   it names the line that raised and not the run or the pin — the exact failure
   `unhealthy()`'s own docstring says it exists to remove.

## 3. THE DECISION — ANSWER 2, PLUS THE FIX THAT MAKES IT SAFE

**Leave the names. Carve them out explicitly. And fix the guard, because the guard is the actual
defect and the rename is only its excuse.**

Why not 1 (change the contract everywhere):

- **The pin would be retired, not updated.** Editing `oracle-repro.sh` and its pin in one commit
  makes the pin a hash of whatever was just written; it can never fail again. `differ.py:513-519`
  invites a deliberate re-freeze, but that is for a shell whose *behaviour* changed. Nothing here
  changes behaviour — only the extension of files it writes.
- **It destroys the port's justification.** `.agents/slop/differverdict/VERDICT.md`: "**147 of 151
  artifacts are byte-identical.**" That is the measurement that says the Python reproduces the
  shell. Renaming moves 103 of 151 and turns the one interpretable finding — 4 LOST, 4 NEW, which
  is `D6-srcswap-*` vs `D6-matmul-*` — into 107.
- **It leaves 103 orphans.** `cmd_run` prunes 3 stale names and does not clear the directory, so a
  rename produces exactly the defect `cmd_run:339-344` exists to prevent: "a directory carrying a
  PASS-shaped file that no command produces". Fixing that means claiming clause I of `runskeep`,
  which `gates/retention-check.py` (another unit, in flight) owns.

Why not 3 (split): **there is no line to split on.** All 103 are read; the oracle's `healthy()` is
already dead against this driver, so splitting would move 103 names away from the oracle's reads
while leaving them coupled to `corpus-figure.py`, which is not mine to edit.

## 4. WHAT WAS CHANGED

**`checks/differ.py`**

- `declared()` — the 103 names, derived from the driver's own tables. Plus `LITERALS` and
  `REPORTS` (the five diff-report prefixes, which are the same five `oracle-repro.sh:114` globs).
- **`artefacts_ok()` now takes its population from `declared()`**, and reports `MISSING` for a
  declared artifact that is absent and `UNEXPECTED` for one no command writes. After the fix, the
  renamed population gives **103 `MISSING`** where it gave none, and the empty population gives 103.
- **`unhealthy()` names a missing summary** instead of raising.

**`checks/no-txt.py`** — excuses `differ.declared()`, **imported, not copied**, so an orphan `.txt`
under `runs/graphcmp/D/` is still reported. Measured: an orphan moves the hard count 602 → 603 and
`artefacts_ok()` says `UNEXPECTED`. The excuse count is printed on every run, always.

**`checks/README.md`, `AGENTS.md`** — the names, the pin, and the measured 53/0/0 table.

| `no-txt.py` | excused | hard | verdict |
|---|---|---|---|
| before | 0 | 599 | **1** |
| after | **103** | 602 | **1** |

(599 → 602 is other units writing concurrently; the 103 are removed from the hard set, not added
to it. Still red — 602 remain and none of them are mine.)

## 5. VERDICT-NEUTRALITY

`repro 1`, before and after, **byte-identical**: `rc=2`, the same 11 offenders, "no healthy run in 1
attempts -- this is NOT a measurement". `settled()` = `SOME PROOFS FAIL`, so `ready()` is False, the
runner never executes, and this is not a measurement in either direction. Artifacts:
`repro-BEFORE.out`, `repro-AFTER.out`.

`artefacts_ok()` on the live tree: **53 findings before, 53 after** (16 `EMPTY`, 37 `ONE-LINE`) —
the fix adds `MISSING`/`UNEXPECTED`, which are 0 on an unchanged tree. `snap` still prints 151.
`check_oracle()` → `[]`.

## 6. UNSETTLED

- **`differ.py:458` says "Reported, not fixed -- see DIFFPY.md" and `DIFFPY.md` does not exist.**
  In my file. Unchanged by me; it wants either the file or the sentence.
- **Not my `.txt`:** `differverdict/{shell-D,py-D,warm-*,python-*}/` snapshot copies (the artifact-
  SET comparison a rename would destroy), `gates/artifacts/*/{bd,bn,py}.txt`, `checks/{census,
  e2e-mm-gate,gate}.txt`. Left alone.
- **`oracle-run.sh`'s stale pins** (`24/22/21` vs `16/14/14`) make its `healthy()` dead. Correcting
  them would edit a frozen oracle to agree with the answer, so I did not.