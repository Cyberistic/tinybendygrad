# Paste-ready OLD → NEW for every MOVED claim

**21 `MOVED` of 46 re-measured. Moment: 2026-10-06, 12:59–13:03 +0300. HEAD `4887f2483`→`9c947d0ac`.**
Each OLD is the **exact current line**; each NEW is paste-ready. Where a number is volatile
(`ruff`, `.txt`, `substrate.py`) the NEW **carries its moment**, per the header sentence, instead
of a fresh bare number. Nothing was applied.

---

### 1 · `.txt` HARD count — `AGENTS.md:39` (also `:116`)

OLD (`:39`):
```
  measured today `checks/no-txt.py` exits 1 with **572 HARD and 139 EXCUSED — 711 owned `.txt`** (the HARD count
```
NEW:
```
  measured 2026-10-06 13:00 `checks/no-txt.py` exits 1 with **550 HARD and 139 EXCUSED — 689 owned `.txt`** (the HARD count
```

### 2 · same, the gate section — `AGENTS.md:116`

OLD (`:116`):
```
  IT EXITS 1 TODAY WITH **572 HARD AND 139 EXCUSED (711 OWNED)** — AND THAT NUMBER MOVES, SO IT CARRIES THE READING
```
NEW:
```
  IT EXITS 1 AT 2026-10-06 13:00 WITH **550 HARD AND 139 EXCUSED (689 OWNED)** — AND THAT NUMBER MOVES, SO IT CARRIES THE READING
```

### 3 · the sample tail — `AGENTS.md:118`

OLD (`:118`):
```
  `... and 513 more`, SO IT DOES NOT "PRINT EACH PATH" EITHER.** `.rows` is expected values,
```
NEW:
```
  it prints 40 paths and then `... and 510 more`, SO IT DOES NOT "PRINT EACH PATH" EITHER.** `.rows` is expected values,
```

### 4 · TOOLS.md ledger, header — `AGENTS.md:10`

OLD (`:10`):
```
gate's inputs under `.agents/slop/`, and **173 of the 333 paths `.agents/TOOLS.md` names are gone — **14 of them
```
NEW:
```
gate's inputs under `.agents/slop/`, and **180 of the 333 paths `.agents/TOOLS.md` names are gone (measured
2026-10-06 13:00; it was 173 when written — the 7 that moved are the `oracles/*.txt`→`.rows` rename) — **14 of them
```

### 5 · TOOLS.md ledger, the body — `AGENTS.md:129`

OLD (`:129`):
```
  **RE-MEASURED RULE AND ITS NUMBERS: of the **333** distinct paths `.agents/TOOLS.md` names, **160 are present and
  **173 are gone** — **96 of those under `.agents/slop/`** — and **16 of the gone are INSTRUMENTS, a rule's would-be
```
NEW:
```
  **RE-MEASURED RULE AND ITS NUMBERS: of the **333** distinct paths `.agents/TOOLS.md` names, **153 are present and
  **180 are gone** — **96 of those under `.agents/slop/`** — and **16 of the gone are INSTRUMENTS, a rule's would-be
```

### 6 · TOOLS.md ledger, the doctrine table — `AGENTS.md:167`

OLD (`:167`):
```
| `.agents/TOOLS.md` | **333 paths: 160 present, 173 gone (96 under `.slop/`); **14 INSTRUMENTS by content**, 13 recoverable + `xd1/mutate.py` GONE** | A ledger that names a path it does not own is a list. |
```
NEW:
```
| `.agents/TOOLS.md` | **333 paths: 153 present, 180 gone (96 under `.slop/`) at 2026-10-06 13:00; **14 INSTRUMENTS by content**, 13 recoverable + `xd1/mutate.py` GONE** | A ledger that names a path it does not own is a list. |
```

### 7 · differ PINS are red — `AGENTS.md:97-98`

OLD (`:97-98`):
```
  **THE LIVE RUN IS NOT HEALTHY AND TWO INSTRUMENTS DISAGREE ABOUT IT: `differ.py`'s `PINS` are red on
  2 of 17 (`census-rc` absent, `oracle-selfcheck=# ORACLE SELFCHECK: FAIL`) and
```
NEW:
```
  **THE LIVE RUN IS HEALTHY AGAIN AND THE TWO INSTRUMENTS NOW AGREE: `differ.py`'s `PINS` are green on
  17 of 17 (`census-rc=rc=0`, `oracle-selfcheck=# ORACLE SELFCHECK: OK`; measured 2026-10-06 13:00 against
  `runs/graphcmp/D/D0-run-summary.txt`), and
```

### 8 · retention says IV FIRES graphcmp/D — `AGENTS.md:99-100`

OLD (`:99-100`):
```
  `gates/retention-check.py` says `IV FIRES runs/graphcmp/D/` and exits 1, while `corpus-figure.py`
  prints `RUN HEALTH : OK` and exits 0 because its `run_health()` reads 3 of those 17. TRUST THE RED
  ONE.** See `checks/README.md` and `.agents/slop/difftxt/`.
```
NEW:
```
  `gates/retention-check.py` says `IV OK runs/graphcmp/D/` (the run's own measure is healthy; its rc=1
  is now clause V's `gates/artifacts/` — `0/11 dirs can report health`), and `corpus-figure.py`
  reads **all 17** pins (it imports `differ.PINS`) and prints `RUN HEALTH : OK` only when all 17 are
  green. TRUST THE RED ONE.** See `checks/README.md` and `.agents/slop/difftxt/`.
```

### 9 · corpus-figure reads 3 of 17 — `AGENTS.md:100`

Covered by #8 (the old text is one paragraph). If a separate edit is wanted, the clause
``because its `run_health()` reads 3 of those 17`` has no OLD/NEW of its own — apply #8.

### 10 · `ruff` count — `AGENTS.md:221`

OLD (`:221-223`):
```
  and `ruff check .` RUNS — and it reports **18755** errors, rc=1, so "the tree lints" is FALSE. **THE `797` THIS
  LINE CARRIED WAS WRONG BY 23x, AND `18755` CARRIES ITS OWN TIME: AN EARLIER UNIT SAW 18752, THEN 18754, ON A RE-RUN
  WITH NO EDIT BY IT, BECAUSE OTHER UNITS WERE WRITING THE TREE WHILE IT COUNTED. QUOTE THIS NUMBER WITH A TIMESTAMP OR
```
NEW:
```
  and `ruff check .` RUNS — and it reports **18781 at 12:59:48, 18797 at 13:00:36, 19677 at 13:02:53, 19679 at
  13:03:01** (four reads, 193 s apart, same command, no edit by this unit), rc=1, so "the tree lints" is FALSE.
  **THE `797` THIS LINE USED TO CARRY WAS WRONG BY 23x, AND THE COUNT CARRIES ITS OWN TIME: OTHER UNITS WERE WRITING
  THE TREE WHILE IT COUNTED. QUOTE THIS NUMBER WITH A TIMESTAMP OR
```

### 11 · `substrate.py` line count — `AGENTS.md:122`

OLD (`:122`):
```
  is a 46-line shim onto `.venv/bin/python checks/substrate.py` (765 lines).**
```
NEW:
```
  is a 46-line shim onto `.venv/bin/python checks/substrate.py` (**766 lines at 13:00, 841 at 13:03 —
  it was 765 when written; the file is being edited live**).**
```

### 12 · `*-mutate.py` harness count — `AGENTS.md:246`

OLD (`:246`):
```
  *in the right direction*: `.agents/slop/` holds 40+ `*-mutate.py` and `*-selftest.py` harnesses, because
```
NEW:
```
  *in the right direction*: `.agents/slop/` held 40+ `*-mutate.py` and `*-selftest.py` harnesses (9 + 7
  survive at 2026-10-06 13:00; the rest were pruned), because
```

### 13 · `uv.lock` packages — `AGENTS.md:31`

OLD (`:31`):
```
  all absent from `.venv`, and `uv.lock`'s 586 packages exist to run upstream's Python, not to build ours.
```
NEW:
```
  all absent from `.venv`, and `uv.lock`'s 173 `[[package]]` entries (2026-10-06 13:00; the lock is
  `version = 1`) exist to run upstream's Python, not to build ours.
```

### 14 · `oracle_py.py` is deleted — `AGENTS.md:214`

OLD (`:213-214`):
```
  `.agents/TOOLS.md`'s *Pin vs xd1/head* section records the instrument that pinned this; the file
  itself, `.agents/slop/oracle_py.py`, IS AMONG THE 99 DELETED PATHS, so the rule has no enforcer left.**
```
NEW:
```
  `.agents/TOOLS.md`'s *Pin vs xd1/head* section records the instrument that pinned this; the file
  itself, `.agents/slop/oracle_py.py`, WAS among the 99 deleted paths and **was restored at
  2026-10-06 13:01 (5551 B) — verify it still exists before citing this line, it appeared mid-run.**
```

### 15 · `rebase-gate-selftest.py` no longer runs — `AGENTS.md:191-193`

OLD (`:191-193`):
```
indistinguishable from agreement."* **BUT THAT FILE NO LONGER RUNS** (`import oracle_py` →
`ModuleNotFoundError`, rc=1; `oracle_py.py` is one of the 99 deleted paths), **so the template exists as
prose over dead code — which is exactly the state doctrine 1 above forbids, in this file.**
```
NEW:
```
indistinguishable from agreement."* **AND THAT FILE RUNS AGAIN** (measured 2026-10-06 13:02: `oracle_py.py`
was restored, so the import succeeds and the harness reaches its assertions) — **but it now dies with
`KeyError: 'cpython:renderer_oracle'` at `rebase-gate-selftest.py:1095`, rc=1, so the six-state template
it documents is driven by a harness that cannot finish.**
```

### 16 · `corpus-figure.py:137` is the read — `AGENTS.md:90`

OLD (`:90`):
```
  (both verified today), and `checks/corpus-figure.py:137` (`:72` is `module_from_spec`, NOT the read).
```
NEW:
```
  (both verified today), and `checks/corpus-figure.py:175` (`:170` is the summary path; `:72` is
  `module_from_spec`, NOT the read).
```

### 17 · the `103` is stale — `AGENTS.md:93-95`

OLD (`:93-95`):
```
  else, and renaming them means the pin has to move with them in one commit. **THE 103 IN
  `checks/README.md:51-58` AND `checks/no-txt.py:19-30` IS STALE — this file, `checks/README.md` and
  `checks/no-txt.py` are THREE WITNESSES TO ONE SUPERSEDED NUMBER, SO FIX ALL THREE OR SAY WHY ONLY ONE
  IS AUTHORITATIVE.**
```
NEW:
```
  else, and renaming them means the pin has to move with them in one commit. **THE `103` WAS FIXED IN BOTH
  WITNESSES (measured 2026-10-06 13:00: `checks/README.md:51-58` now says `139`, and `checks/no-txt.py`
  now computes `len(differ.declared())` and names no number at all) — so only this file still needs it
  moved off `103`.**
```

### 18 · `e2e.py:510` returns 4 — `AGENTS.md:107` (also `:184`)

OLD (`:107`):
```
  RETURNS 4, NOT 0** (`e2e.py:510`), and `checks/e2e.sh:335` likewise `exit 4`. **A SKIP IS NOT A PASS AND
```
NEW:
```
  RETURNS 4, NOT 0** (`e2e.py:514`), and `checks/e2e.sh:335` likewise `exit 4`. **A SKIP IS NOT A PASS AND
```

OLD (`:184`):
```
**`SKIP IS NOT PASS`, and the exit status says so: `e2e.py:510` returns 4 and `checks/e2e.sh:335`
```
NEW:
```
**`SKIP IS NOT PASS`, and the exit status says so: `e2e.py:514` returns 4 and `checks/e2e.sh:335`
```

### 19 · `sb-gate.sh:76` names the absent baseline — `AGENTS.md:126-127`

OLD (`:126-127`):
```
  `.agents/slop/` is being pruned and it holds no protection: `checks/sb-gate.sh:76` names
  `.agents/slop/schedule-bodies/BEFORE-rows.txt` — **absent, so the gate exits 3** — and `e2e.py:99`
```
NEW:
```
  `.agents/slop/` is being pruned and it holds no protection: `checks/sb-gate.sh:76` now reads its
  baseline from the GIT-TRACKED `oracles/schedule-bodies/BEFORE-rows.rows`, but it still `exit 3`s —
  **the CPython oracle `.agents/slop/schedule-bodies/sb-oracle.py` is absent (measured 13:02)** — and
  `e2e.py:99`
```

### 20 · `e2e.py:99` calls it a DELETED FIXTURE — `AGENTS.md:127-128`

OLD (`:127-128`):
```
  `.agents/slop/schedule-bodies/BEFORE-rows.txt` — **absent, so the gate exits 3** — and `e2e.py:99`
  calls `cstyle-live/port.txt` a "DELETED FIXTURE" (`e2e.py:99-100`) — **absent, so stage 7 SKIPs.**
```
NEW:
```
  `.agents/slop/schedule-bodies/BEFORE-rows.txt` — **absent, so the gate exits 3** — and `e2e.py:99`
  now calls that defect **REPAIRED**: the fixture is recovered from git to the tracked
  `gates/cstyle-live.rows` (`e2e.py:99-106`) — **stage 7 SKIPs on a COLD SUBSTRATE, not the fixture.**
```

### 21 · `sweep.py` citations — `AGENTS.md:162`, `:163`

OLD (`:162`, LIVE_UNITS):
```
| `checks/sweep.py:266` `LIVE_UNITS` | 14 literal directory names | six FINISHED units held **2,353 of 4,455 files = 53%** of `.slop`, 100% git-tracked, named by nothing. Its own comment: *"A GUARD THAT IS CORRECT EXCEPT FOR THE LAST DISPATCH IS NOT A GUARD, IT IS A COINCIDENCE WITH THE DISPATCH ORDER."* |
```
NEW:
```
| `checks/sweep.py` `LIVE_UNITS` | was 14 literal directory names — **removed; `:291` records "LIVE_UNITS lived here, a tuple of 14 names. It is gone"** | six FINISHED units held **2,353 of 4,455 files = 53%** of `.slop`, 100% git-tracked, named by nothing. Its own comment: *"A GUARD THAT IS CORRECT EXCEPT FOR THE LAST DISPATCH IS NOT A GUARD, IT IS A COINCIDENCE WITH THE DISPATCH ORDER."* |
```

OLD (`:163`, ORACLE_WORD):
```
| `checks/sweep.py:658` `ORACLE_WORD` | a **basename regex** | **670 of 675** ORACLE files were classified by FILENAME and **5 were named by a live gate**. |
```
NEW:
```
| `checks/sweep.py:239` `ORACLE_WORD` | a **basename regex** | **670 of 675** ORACLE files were classified by FILENAME and **5 were named by a live gate**. |
```

### 22 · `repro-paths.py:57` REF — `AGENTS.md:165`

OLD (`:165`):
```
| `checks/repro-paths.py:57` `REF` | `(?:sh\|py\|bend)` | **6 of 15** `e2e.py` stage inputs invisible (2 `.mjs`). *"RESTORING THEM MOVED THIS TOOL'S OUTPUT BY EXACTLY ZERO."* |
```
NEW:
```
| `checks/repro-paths.py:57` `REF` | `(?:sh\|py\|bend\|mjs\|json)` — **fixed** | **6 of 15** `e2e.py` stage inputs were invisible (2 `.mjs`). *"RESTORING THEM MOVED THIS TOOL'S OUTPUT BY EXACTLY ZERO."* |
```

---

## Not replaced here (UNMEASURED, not wrong)

`SPEC=2` corpus counts (L8, L283); `bend guide` 677 (L54); LAWS 34 / PROOF 18 TODOs (L57, L60);
the `peakrss` census (L68-69); `sz` peaks (L73-75); `bounded.py` 425 rows (L77); the
`398→552→562→553` chain and `830`/`258`/`249`/`225` (L40-47, L171); `18752/18754` (L222); the four
change-detector counts (L261-265); `wk-f32-gate` rc=0 (L197); the ~180 flag rows (L276-453).

These need `bend`, or they are dated events a re-run cannot settle. **Marking them `UNMEASURED` is
the correct verdict, not deleting them** — the rule they prove may still hold.
