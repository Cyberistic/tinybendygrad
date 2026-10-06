# The `AGENTS.md` numbers, re-measured — the tree moved under every one of them

**Moment: 2026-10-06, 12:59–13:03 +0300. HEAD `4887f2483` → `9c947d0ac` *during* the run.**
Every number below is `measured.json` in this directory or the raw capture beside it, each
labelled with the rule that produced it. **Nothing here was committed, and `AGENTS.md` was not
touched.** One read-only file I did not own was written by an instrument and **restored to HEAD**
(`.agents/slop/toolsledger/paths.tsv`, see §6).

`AGENTS.md`'s own rule decides this report's shape:

> **A LINE IN HERE WITH NO MEASUREMENT AND NO NAMED INSTRUMENT IS A LINE YOU MUST NOT TRUST.**

The refinement this run forces: **a line with a measurement and no timestamp is a reading of a tree
that moved after the reading.** 128 commits landed in one session. `ruff` went 18781 → 18797 →
19677 → 19679 in **193 seconds** while I measured it. So a bare number is a *shape* (is it bimodal,
does it move on the same command, is it a count of a moving population), never a *value*.

---

## 1. Denominator

I enumerated **76 measured claims** in `AGENTS.md` (a *measured claim* = a numeric or
`file:line` assertion carrying a reading). Of them:

| re-measured | verdict |
|---|---|
| **46 re-measured** | `MATCH` **25** · `MOVED` **21** · |
| **21 UNMEASURED** | gated on `bend` (12) or a historical reading no longer reproducible (9) |
| **9 UNVERIFIED** | the ~180 upstream flag-table rows (transcribed, not this tree's) |

**21 MOVED of 46 is 46%** — the document's own thesis, confirmed against the document.

---

## 2. The movers this session changed the substrate under (priority)

| # | claim (`AGENTS.md:line`) | measured now (rule) | verdict | cause |
|---|---|---|---|---|
| 1 | `572 HARD and 139 EXCUSED — 711 owned` (L39, L116) | **550 / 139 / 689** (`checks/no-txt.py`, 13:00) | **MOVED** | TREE — 22 `.txt` renamed/removed after the reading |
| 2 | `... and 513 more` (L118) | **`... and 510 more`** (40 printed + 510) | **MOVED · NEVER RIGHT** | CLAIM — `513 = 553−40`; it was copied from the superseded `553` total and never matched the `572` on the line above it |
| 3 | `173 of the 333 paths … are gone` (L10, L129) | **180 of 333** (`extract.py`, 13:00) | **MOVED** | TREE — all **7** flipped paths are `oracles/*.txt→.rows`; the ledger still names the old names |
| 4 | `160 are present` (L129, L167) | **153** (`extract.py`) | **MOVED** | TREE — same 7-path rename |
| 5 | TOOLS `96 under .agents/slop/` (L130) | **96** | MATCH | — |
| 6 | TOOLS `16 are gone` INSTRUMENTS (L130) | **16** (`kind()`), **14 by content** (`.agents/slop/lostinst/REPORT.md`) | MATCH | — |
| 7 | `differ.py`'s PINS red on **2 of 17** (L97-98) | **0 of 17** (`differ.PINS` vs `D0-run-summary.txt`) | **MOVED** | TREE — a fresh healthy run landed (`e88229fd6`); `oracle-selfcheck=OK`, `census-rc=rc=0` |
| 8 | `retention-check.py says IV FIRES runs/graphcmp/D/` (L99) | **`IV OK runs/graphcmp/D/`**; RED on `gates/artifacts/`; **rc=1** | **MOVED** | TREE — the graphcmp run healed; the red moved to a different clause |
| 9 | `corpus-figure.py exits 0 because run_health() reads 3 of those 17` (L100) | reads **all 17** (imports `differ.PINS`); `DEV=CPU` rc=0 | **MOVED** | CODE — the "fifth defect" was closed (`9c947d0ac`) |
| 10 | `ruff reports 18755 errors` (L221) | **18781@12:59:48 · 18797@13:00:36 · 19677@13:02:53 · 19679@13:03:01** | **MOVED** | TREE — units writing the tree; the doc's own line already says "quote with a timestamp" |
| 11 | `checks/substrate.py (765 lines)` (L122) | **766 @13:00 → 841 @13:03** | **MOVED** | TREE — the file is being edited live |
| 12 | `40+ *-mutate.py and *-selftest.py harnesses` (L246) | **9 + 7 = 16** (`find`) | **MOVED** | TREE — `.agents/slop/` pruned |
| 13 | `uv.lock's 586 packages` (L31) | **173** `[[package]]` (lock `version = 1`) | **MOVED** | TREE — lock regenerated (rule for `586` unrecorded) |
| 14 | `oracle_py.py IS AMONG THE 99 DELETED PATHS` (L214) | **exists, 5551 B, restored 13:01** | **MOVED** | TREE — restored *during this run* |
| 15 | `rebase-gate-selftest.py NO LONGER RUNS (import oracle_py → ModuleNotFoundError)` (L191) | **runs**; fails at `:1095 KeyError 'cpython:renderer_oracle'`, rc=1 | **MOVED** | TREE — depends on #14; the mechanism is different |

**#2 is the only `NEVER RIGHT`.** Every other mover is the **tree**, not the claim: those are
fixed by a **timestamp**, and #2 is fixed by a **correction**.

---

## 3. Full table — every measured claim and its verdict

Rule tokens: `.txt`=`checks/no-txt.py`; ledger=`.agents/slop/toolsledger/extract.py`;
`PINS`=`differ.PINS` vs `runs/graphcmp/D/D0-run-summary.txt`; filesize=on disk; `bend`=gated.

| line | claim | measured | verdict |
|---|---|---|---|
| L3 | audit `MEASURED 2026-10-06` | date right, but the tree moved through the day | NOTE |
| L8 | `SPEC=2` 26 of 77, 14 of 25 fail | gated on `bend` | UNMEASURED |
| L10/L129 | 173 of 333 gone | 180 | **MOVED** |
| L11 | 14 INSTRUMENTS (kind 16) | kind 16; content 14 | MATCH |
| L21 | README omits `references/` | `README.md` does not mention it | MATCH |
| L30 | ruff/mypy/pytest absent from `.venv` | all three `No module named` | MATCH |
| L31 | uv.lock 586 packages | 173 | **MOVED** |
| L39/L116 | 572/139/711 | 550/139/689 | **MOVED** |
| L40 | read 830 before; 258 delta | historical | UNMEASURED |
| L42 | 249 of 259 rowdumps | — | UNMEASURED |
| L43 | 225 of 259 named by nothing | — | UNMEASURED |
| L43-44 | `oracles/` 277 `.rows`, 1 `.txt` | 277 / `oracles/rows-bd.txt` | MATCH |
| L45 | HARD fell by exactly 258 | historical | UNMEASURED |
| L47/L171 | total moved 398→552→562→553 | historical; conflicts with L116's 572 | UNMEASURED |
| L54 | `bend guide` 677 lines | gated | UNMEASURED |
| L57 | LAWS `--check-only` 34 TODOs | gated (grep `TODO`=1) | UNMEASURED |
| L60 | PROOF `--check-only` 18 TODOs | gated (grep `TODO`=0) | UNMEASURED |
| L61 | peak 6 MB | gated | UNMEASURED |
| L68-69 | peakrss census columns | table exists; not re-run | UNMEASURED |
| L73-75 | `sz` 1383/1435/1547; 1468/1152/1108 | gated | UNMEASURED |
| L77 | `bounded.py` 425 rows | gated | UNMEASURED |
| L88 | `differ.py:61` ORACLE_PIN, `:58` comment | `:61=ORACLE_PIN`, `:58` comment | MATCH |
| L89-90 | `oracle-repro.sh:61`/`:105` | both exact | MATCH |
| L90 | `corpus-figure.py:137` is the read | read is at **:175** (path at **:170**) | **MOVED·CODE** |
| L91 | `declared()`=139, 139 on disk | 139 / 139 | MATCH |
| L93-95 | `103` in `README.md:51-58` & `no-txt.py:19-30` is stale | README now says **139**; no-txt now derives it | **MOVED·CODE** |
| L97-98 | PINS red 2 of 17 | 0 of 17 | **MOVED** |
| L99-100 | retention `IV FIRES runs/graphcmp/D/`, rc1 | `IV OK`; rc1 on `gates/artifacts/` | **MOVED** |
| L100 | corpus-figure reads 3 of 17 | all 17 | **MOVED·CODE** |
| L102 | seven-stage gate | docstring says SEVEN; 7 emitted | MATCH |
| L104-105 | `cdp.mjs`, `ops_bend-milestone-expected.txt` exist | both exist | MATCH |
| L106-107 | `e2e.py:510` returns 4 | `return 4` is at **:514** | **MOVED·CODE** |
| L107 | `checks/e2e.sh:335` exit 4 | `:335 exit 4` | MATCH |
| L108-109 | stage 8 retired; `dtype.js` not a byte | retired (docstring §8) | MATCH (byte claim UNMEASURED) |
| L110 | `e2estage8/verdicts.py` rc=1, PROSE names `0` | rc=1, same message | MATCH |
| L122 | `checks/substrate.py` 765 lines | 766→841 | **MOVED** |
| L121 | `substrate-check.sh` 46-line shim | 46 lines | MATCH |
| L123 | `gates/*.py` 21, `*.sh` 0 | 21 / 0 (2 under `gates/oracles/`) | MATCH |
| L127 | `sb-gate.sh:76` names `BEFORE-rows.txt`, exits 3 | baseline is now `oracles/schedule-bodies/BEFORE-rows.rows`; exits 3 for a **missing oracle** | **MOVED** |
| L127-128 | `e2e.py:99` calls `cstyle-live/port.txt` a DELETED FIXTURE | `:99` says that defect is **REPAIRED** | **MOVED·CODE** |
| L129-131 | 333 / 160 present / 173 gone / 96 | 333 / **153** / **180** / 96 | **MOVED** |
| L131-133 | 14 content, 13 recoverable, `xd1/mutate.py` GONE | lostinst: 14 / 13 / GONE | MATCH |
| L134 | `xd1/pin` is revision `6c3d401cf324` at `TOOLS.md:645` | `:645` says exactly that | MATCH |
| L135 | `elf-checkonly…txt` is 110 B stdout | in lostinst; bytes not re-read | UNMEASURED |
| L164 | `artefacts_ok()` empty dir → 139 MISSING | **139** | MATCH |
| L163 | `sweep.py:658` ORACLE_WORD basename regex | ORACLE_WORD is at **:239**; counts unmeasured | **MOVED·CODE** |
| L162 | `sweep.py:266` LIVE_UNITS = 14 names | **LIVE_UNITS is gone**; `:266` is a regex | **MOVED·CODE** |
| L165 | `repro-paths.py:57` REF `(?:sh\|py\|bend)` | now `sh\|py\|bend\|mjs\|json` | **MOVED·CODE** |
| L166 | `gates-pop.py:95` HOMES literal | `HOMES = ("checks","gates")` at `:95` | MATCH |
| L186 | SIX states at `rebase-gate-selftest.py:1168-1180` | template present there | MATCH |
| L191-193 | that file no longer runs | runs; `:1095 KeyError`, rc1 | **MOVED** |
| L196 | `gatekit.py:59` five exits | `PASS,FAIL,REFUSED,SKIP,DEAD = 0,1,3,4,5` at `:59` | MATCH |
| L197 | `wk-f32-gate.py` rc=0 | gated on `bend` | UNMEASURED |
| L198 | `oracle-selfcheck` reads OK; `46c52f30d` | OK; commit resolves | MATCH |
| L199 | corpus-figure rc1 with `DEV` unset, rc0 with `DEV=CPU` | rc1 / rc0 | MATCH |
| L202 | `grep -c gatekit checks/sb-gate.sh` = 0 | 0 | MATCH |
| L209 | `uv`, `ty` on PATH | `/Users/…/.local/bin/{uv,ty}`; 0.6.14 / 0.0.78 | MATCH |
| L210-211 | PATH `python3` 3.14, `.venv` 3.12 | 3.14.6 / 3.12.10 | MATCH |
| L214 | `oracle_py.py` one of 99 deleted | exists | **MOVED** |
| L215 | pytest not in `.venv` | `No module named pytest` | MATCH |
| L216 | mypy not in `.venv` | `No module named mypy` | MATCH |
| L220 | ruff 0.15.18 at `/opt/homebrew/bin/ruff` | exact | MATCH |
| L221 | ruff 18755 errors | 18781…19679 | **MOVED** |
| L222 | 18752 then 18754 | historical | UNMEASURED |
| L227 | `tinygrad/viz/README.md` 93 lines | 93 | MATCH |
| L229-239 | `ad117c928` ours, 16 files, ancestor, `:1398`/`:1404` | all four exact | MATCH |
| L240 | `PCIDevice` 8 files; `system.py:206`; `ops_amd:738`, `ops_nv:531` | all exact | MATCH |
| L246 | 40+ mutate/selftest harnesses | 9 + 7 | **MOVED** |
| L247 | 487 mutations / 15 tables / 30 zeros / 25 unclassified | not re-run | UNMEASURED |
| L249 | `zero-classify.py` deleted | absent | MATCH |
| L261-265 | naming-gate/elf/run-port-mm counts | historical | UNMEASURED |
| L283 | SPEC corpus counts | gated | UNMEASURED |
| L276-453 | tinygrad flag tables (~180 rows) | upstream transcription | UNVERIFIED |

**Re-measured: 46. MATCH 25 · MOVED 21.**

---

## 4. What this run could not measure, and why

- **Anything `bend`-gated** (12 claims): `bend guide`, `LAWS`/`PROOF` `--check-only`, the
  `peakrss` census, `sz` peak RSS, `SPEC` corpus counts, `wk-f32-gate` rc. House rule: do not run
  `bend`; the brief forbids it.
- **Historical readings** (9): the `398→552→562→553` chain, `830`, `258`, `249/259`, `225/259`,
  `18752/18754`, the four change-detector counts (`naming-gate 283/278`, `elf 353/331/246/355`,
  `elf-run 354`, `run-port-mm rc1→rc0`). These are dated events; a re-run measures *today's*
  tree, not the event, so it cannot settle the claim.
- **The upstream flag tables**: ~180 rows of `docs/env_vars.md` transcribed. Spot-checked only
  where they carry a parenthetical measurement (`SPEC`).

---

## 5. The header sentence (§5 of the brief)

`AGENTS.md` already says this, **for `ruff` alone**:

> `18755` CARRIES ITS OWN TIME … **QUOTE THIS NUMBER WITH A TIMESTAMP OR NOT AT ALL.**

`ruff` is not special. The `.txt` count `572→550`, the ledger `173→180`, the pins `2→0`, and
`substrate.py` `765→841` all moved for the same reason. Generalise it:

> **A NUMBER WITH A MEASUREMENT BUT NO TIMESTAMP IS A READING OF A TREE THAT MOVED AFTER THE
> READING: TRUST THE SHAPE IT ILLUSTRATES AND THE RULE IT PROVES, RE-MEASURE IT BEFORE YOU CITE
> IT, AND WRITE THE MOMENT BESIDE ANY COUNT THAT MOVES ON A RE-RUN. `ruff` IS NOT SPECIAL — ITS
> LINE JUST SAYS SO FIRST.**

---

## 6. Discipline notes

- **I did not run `bend`.** Its 12 claims are marked UNMEASURED, not guessed.
- **I restored one file I did not own.** `extract.py` rewrites
  `.agents/slop/toolsledger/paths.tsv` as a side effect; I read the old/new split from it (the 7
  flipped `oracles/*.txt`), then `git checkout --` it back to HEAD. It is unmodified again.
- **The tree moved during the run.** HEAD advanced `4887f2483 → 9c947d0ac` mid-measurement
  (`corpus-figure.py` was fixed and committed by another unit). Timestamps are on every reading
  above for exactly this reason.
- **`.agents/TODO.md` was being written by other units** (`git status` shows it `M`). I did not
  touch it.
