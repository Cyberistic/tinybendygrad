You are one of Cyberistic's agents. He hates unclean code and hacks. He loves his documentations. LOCs IS a measure of quality, the LESS, the better.

**EVERY PRESCRIPTION BELOW THAT MAKES A CLAIM ABOUT THIS TREE CARRIES THE MEASUREMENT THAT MADE IT
TRUE, MEASURED 2026-10-06 BY RUNNING IT. `.agents/slop/agend/REPORT.md` is the audit — every `NEVER`,
every `ALWAYS`, every `MUST`, every named command and every named path, and whether it is true today.
**A LINE IN HERE WITH NO MEASUREMENT AND NO NAMED INSTRUMENT IS A LINE YOU MUST NOT TRUST, AND
DELETING IT IS CHEAPER THAN LEAVING IT.** The cheapest test of a prescription is to FOLLOW it, and
nobody had been doing that: this file told every agent CI uses `SPEC=2`, and `SPEC=2` takes the corpus
census from 70 of 70 program ops (70 of 77 enum members; 34-graph corpus, read 2026-10-06 14:16) to 26 of 77 (the enum denominator it was measured against; a 25-graph `SPEC=2` reading, not re-taken) with 14 of 25 graphs failing. It also told every agent to put a
gate's inputs under `.agents/slop/`, and **180 of the 333 paths `.agents/TOOLS.md` names are gone (measured
2026-10-06 13:00; it was 173 when written — the 7 that moved are the `oracles/*.txt`→`.rows` rename) — **14 of them
INSTRUMENTS** (`kind()` COUNTED 16; TWO ARE CLASSIFIER ERRORS, SEE THE CLASS TABLE BELOW).** **A
GOVERNING DOCUMENT THAT NOBODY CHECKS AGAINST REALITY PROPAGATES INTO EVERY BRIEF THAT CITES IT.**

General:

- You must use concise, clean code. No hacks should be used. If you need to write a paragraph-long comment to justify your code, you are doing it wrong. Find a better way.
- Security is above all. Always make it secure (typesafe, fail-safe, auth), then make it work and effectful (effectjs), then make it fast, then make it pretty.
- Shareable logic should be reused. Avoid copy-pasting code. Hoist up if it's needed elsewhere.
- Use Jiujitsu version control for all your code. Make sure to commit often and write meaningful commit messages. If you launch multiple agents, use jiujitsu workspaces to manage them. If you are unsure about how to use Jiujitsu, ask for help. You have access to the jj mcp.
- If you need to create Markdown files to track agent state, always place them under .agents/slop/
- If I ask you to use a repo as reference, and it isn't tiny, you must clone it into `references/` and use it as a reference. Add the repo to `.gitignore` and link it under `references/` in your README. **THE README PART IS OVERRIDDEN AND THE OVERRIDE LIVES IN THE OTHER FILE: `README.md` does not mention `references/` (measured, `grep references README.md` rc=1) and `.agents/TOOLS.md:51-52` says "Do not. The README is off limits. This table is the ledger instead." SO: GITIGNORE IT, AND PUT IT IN `.agents/TOOLS.md`. A DOCUMENT RESTATING A DOCUMENT IS ONE WITNESS, NOT TWO, AND THE TWO DISAGREE.**
- Whenever you finish a task, make sure to tick it off in .agents/TODO.md, If the task is not in TODO.md, add it there and check it off. Keep a progress bar inside TODO.md for each category of tasks. If it's an implementation detail or a small task, do not add it to TODO.md. Only add tasks that are meaningful and require tracking.
- Add TODO comments in the code for any tasks that are not yet completed, so we can use `rg` to search for TODO comments later on.
- Update .agents/TOOLS.md with the tools or libraries you're using, it will act as a ledger and overview for the project.

Development:

- No external dependancies. **MEASURED TRUE FOR THE PORT** — every import under `tinybendygrad/` is `Base`
  or another `.bend` file in this repo, which is the one grep worth keeping. **BUT THE TOOLS ARE NOT IN
  THE VENV AND NO LEDGER SAYS WHICH INTERPRETER A PRESCRIPTION RUNS UNDER: `ruff`, `mypy` and `pytest` are
  all absent from `.venv`, and `uv.lock`'s 173 `[[package]]` entries (2026-10-06 13:00; the lock is
  `version = 1`) exist to run upstream's Python, not to build ours.
  SO "NO EXTERNAL DEPENDENCIES" IS A RULE ABOUT WHAT THE PORT SHIPS, NOT ABOUT WHAT MAY BE INSTALLED TO
  CHECK IT.** 
- **No `.txt` files, ever.** Use `.rows` for expected values and row dumps, `.out`/`.err` for captured
  streams, `.tsv` for tabular, `.md` for prose. `checks/no-txt.py` enforces it. A `.txt` extension is a
  declaration that the author did not know what the file was, and a sweep that reads basenames cannot
  tell a row dump from a diary entry.
  **THE RULE IS RIGHT AND THE TREE IS BEHIND IT, SO THE RULE STAYS WHILE THE COUNT IS NOT A FACT: as
  measured 2026-10-06 13:00 `checks/no-txt.py` exits 1 with **550 HARD and 139 EXCUSED — 689 owned `.txt`** (the HARD count
  MOVES as units write; it read **830** before `oracles/`'s 258 `.txt`-to-`.rows` rename landed, and **258** is the
  exact delta both ways), of which
  `oracle-txt-census.py` classed 249 of the 259 under `oracles/` as ROW DUMPS (the extension was wrong, the content
  is exactly a `.rows`), and 225 of those 259 were NAMED BY NOTHING. **THOSE 259 ARE NOW RENAMED — `oracles/` holds
  277 `.rows` and ONE `.txt` (`rows-bd.txt`, which is 0 BYTES AND DELIBERATELY UNCLASSIFIED), and `no-txt.py`'s HARD
  count fell by EXACTLY 258.** The 139 are excused by
  `differ.declared()` — IMPORTED, not copied — which is the correct shape for a carve-out and the reason
  it never moved while the total moved 398 -> 552 -> 562 -> 553 in one session. Write `.rows`.**
  **A CARVE-OUT MUST BE A GENERATOR'S DECLARATION LOADED BY PATH, NEVER A SECOND COPY OF THE LIST**,
  because a second copy is a contract with no generator and rots without anyone noticing. 
- Always stay turing-incomplete. Any turing completeness must be approved first. 


When using bend:
- run `bend guide` to learn it — **MEASURED rc=0, 677 lines. This is the one that works.**
- use `LAWS.bend` to keep important rules — **the path is `tinybendygrad/LAWS.bend`; there is no
  `LAWS.bend` at the repo root, so the bare name resolves to nothing.** `--check-only` reports
  `Error: 34 TODOs found. The code is incomplete, and not a valid proof yet.`
- **run `bend PROOF.bend` before committing** — **the path is `tinybendygrad/PROOF.bend`; there is no
  `PROOF.bend` at the repo root, so the bare name resolves to nothing. AND THE GATE IS RED AT REST:
  `--check-only` reports `Error: 18 TODOs found. The code is incomplete, and not a valid proof yet.`
  (both measured today under `checks/bounded.py --mb 2048`, verdict token `WITHIN-LIMITS`, peak 6 MB).
  **A PRE-COMMIT GATE THAT CANNOT PASS TEACHES NOTHING AND WILL BE SKIPPED — so until those TODOs land,
  run it to see the COUNT GO DOWN and do not report the red as a verdict about your change.**
- **PARALLELISE EVERYTHING THAT IS NOT A `bend` PROCESS. FOR `bend`, THE PRECONDITION IS THE SUM, NOT
  THE COUNT: parallelise only when the sum of the concurrently-running files' MEASURED peak RSS is under
  60% of `hw.memsize`. THE PER-FILE NUMBERS ARE IN `.agents/slop/peakrss/census.rows` — USE THAT TABLE, NOT
  A NUMBER YOU REMEMBER.** The population is BIMODAL, which is why the rule is a sum and not a ban:
  `nir` 1,152 MB · `sz` 1,108 MB · `ops_python` 864 · `nn/onnx` 777 · `uop/symbolic` 745 · `dtype` 683-699 ·
  `helpers` 204 · **median 207 · 43 of 138 under 50 MB** — the `138` is the frozen
  `.agents/slop/peakrss/census.rows` reading (2026-10-05 20:59) over the port's `.bend` files; **the port is
  134 `.bend` as of 2026-10-06T12:19Z, HEAD `7f70b475`, `find tinybendygrad -name '*.bend' | wc -l`**. So `dtype ‖ helpers ‖ nn/onnx` is 1.4 GB and
  safe, while `sz ‖ sz` is 2.8-3.1 GB and is not, on a machine whose OOM was recorded when it had half
  today's RAM. **`checks/bounded.py --mb` IS A PER-PROCESS WATCHDOG, NOT A MACHINE BUDGET** — it polls one
  child's RSS and kills that child, so two children under the same ceiling can together exceed it, and it
  will never see the sum. **MEASURED, `sz.bend --check-only` alone: 1,383 / 1,435 / 1,547 MB on three runs
  today** (`.agents/slop/substrate/SUBSTRATE.md` says 1,468, `.agents/slop/PEAKRSS.md` says 1,152, and
  `census.txt` says 1,108 — FIVE NUMBERS FOR ONE FILE, WHICH IS WHY THE RULE IS A SHAPE). **Read the
  verdict TOKEN (`KILLED-ON-MEMORY`/`TIMED-OUT`/`WITHIN-LIMITS`), never the exit code** —
  `checks/bounded.py`'s own header records a unit that lost 425 rows by believing the status.



The gates at the top of the tree, and what each one CLAIMS. Run `--help` before trusting one:

- `checks/differ.py run` / `repro` / `snap` — the `graphcmp` corpus: CPython-vs-port VERDICT and
  DENOMINATOR per graph, canonical byte identity, controls, cross, plants, conflations, the
  coverage census, and (repro) that one run is reproducible. Artifacts in `runs/graphcmp/D`,
  read `D0-run-summary.txt` first; `checks/README.md` names every file. **`.agents/slop/graphcmp-run.sh`
  and `.agents/slop/graphcmp-repro.sh`** are the shims onto it (they are NOT at the repo root), and the
  shell bodies are the oracle in `.agents/slop/diffpy/`, **sha256-pinned in code at `differ.py:61`
  (`ORACLE_PIN`; `:58` is a comment) and read BY ARTIFACT NAME — `oracle-repro.sh:61` and `:105`
  (both verified today), and `checks/corpus-figure.py:175` (`:170` is the summary path; `:72` is
  `module_from_spec`, NOT the read).
  So the **139** `.txt` names there — `len(differ.declared())` = **139**, and 139 on disk — are a contract,
  not sloppiness: `checks/no-txt.py` carves out `differ.declared()` (imported, not copied) and nothing
  else, and renaming them means the pin has to move with them in one commit. **THE `103` WAS FIXED IN BOTH
  WITNESSES (measured 2026-10-06 13:00: `checks/README.md:51-58` now says `139`, and `checks/no-txt.py`
  now computes `len(differ.declared())` and names no number at all) — so only this file still needs it
  moved off `103`.**
  **THE LIVE RUN IS HEALTHY AGAIN AND THE TWO INSTRUMENTS NOW AGREE: `differ.py`'s `PINS` are green on
  17 of 17 (`census-rc=rc=0`, `oracle-selfcheck=# ORACLE SELFCHECK: OK`; measured 2026-10-06 13:00 against
  `runs/graphcmp/D/D0-run-summary.txt`), and
  `gates/retention-check.py` says `IV OK runs/graphcmp/D/` (the run's own measure is healthy; its rc=1
  is now clause V's `gates/artifacts/` — `0/11 dirs can report health`), and `corpus-figure.py`
  reads **all 17** pins (it imports `differ.PINS`) and prints `RUN HEALTH : OK` only when all 17 are
  green. TRUST THE RED ONE.** See `checks/README.md` and `.agents/slop/difftxt/`.
- `e2e.py` — **the SEVEN-stage end-to-end gate**, and `e2e.sh` beside it. Do not rewrite it to tidy it.
  **NOT GREEN, AND NOT FOR THE REASON PREVIOUSLY WRITTEN HERE.** Stages 3, 4, 5 and 6 all **PASS** on the
  last transcript, and `.agents/slop/xd2/cdp.mjs` and `.agents/slop/ops_bend-milestone-expected.txt` —
  the two inputs an earlier revision of this file called deleted — **BOTH EXIST**. The only stage that
  measures nothing is **7**, which SKIPs because `run-f64.sh` refuses a cold substrate, so **`e2e.py`
  RETURNS 4, NOT 0** (`e2e.py:514`), and `checks/e2e.sh:335` likewise `exit 4`. **A SKIP IS NOT A PASS AND
  THE EXIT STATUS SAYS SO**; a caller reading only `$?` cannot mistake it. Stage 8 is **RETIRED**: its
  denominator was 0 (`runtime/dtype.js` is not one byte of the emitted bundle), so it was retired rather
  than re-pointed. **`.agents/slop/e2estage8/verdicts.py` IS CURRENTLY RED (rc=1)** — not on a zero
  denominator but on `e2e.py: PROSE names [0] the CODE does not emit`, i.e. the docstring still names a
  stage `0` — **so the prose in this file is a THIRD witness to that disagreement and is stale too.**
  Stages 2-7 need `bend`, `node` and `cc`, so **run it with nothing else compiling**, and under the
  sum-precondition above.
- `checks/no-txt.py` — **THE RULE IS REAL; THE CLAIM "there is no `.txt` file in this project" IS NOT.
  IT EXITS 1 AT 2026-10-06 13:00 WITH **550 HARD AND 139 EXCUSED (689 OWNED)** — AND THAT NUMBER MOVES, SO IT CARRIES THE READING
  THAT PRODUCED IT — AND IT PRINTS A SAMPLE AND THEN
  it prints 40 paths and then `... and 510 more`, SO IT DOES NOT "PRINT EACH PATH" EITHER.** `.rows` is expected values,
  `.out`/`.err` are captured streams, `.tsv` is tabular, `.md` is prose. See Development, above.
- `checks/substrate-check.sh` — import-graph and cold-file sweep over the `.bend` tree. **THE BARE NAME
  `substrate-check.sh` RESOLVES TO NOTHING: `command -v` is absent and there is no root-level file. The real gate
  is a 46-line shim onto `.venv/bin/python checks/substrate.py` (**766 lines at 13:00, 841 at 13:03 —
  it was 765 when written; the file is being edited live**).**
- `gates/*.py` — per-def gates, and they are **Python, never shell** (measured: 21 `.py`, 0 `.sh`).
  A gate names its `.bend` driver and its CPython oracle; its OUTPUT goes to `gates/artifacts/`.
  **BUT DO NOT PUT A GATE'S INPUTS UNDER `.agents/slop/`. THAT PRESCRIPTION IS WHAT DELETED THEM.**
  `.agents/slop/` is being pruned and it holds no protection: `checks/sb-gate.sh:76` now reads its
  baseline from the GIT-TRACKED `oracles/schedule-bodies/BEFORE-rows.rows`, but it still `exit 3`s —
  **the CPython oracle `.agents/slop/schedule-bodies/sb-oracle.py` is absent (measured 13:02)** — and
  `e2e.py:99`
  now calls that defect **REPAIRED**: the fixture is recovered from git to the tracked
  `gates/cstyle-live.rows` (`e2e.py:99-106`) — **stage 7 SKIPs on a COLD SUBSTRATE, not on the fixture.**
  **RE-MEASURED RULE AND ITS NUMBERS: of the **333** distinct paths `.agents/TOOLS.md` names, **153 are present and
  **180 are gone** — **96 of those under `.agents/slop/`** — and **16 of the gone are INSTRUMENTS, a rule's would-be
  enforcer** (`.agents/slop/toolsledger/extract.py` regenerates this). **BY CONTENT IT IS **14**, NOT 16:
`lostinst` VERIFIED 14 — **13 RECOVERABLE** (every restore `git cat-file blob` non-empty, 110 B – 23,711 B, all 14
distinct) AND **1 GONE: `.agents/slop/xd1/mutate.py`** — NO BLOB IN ANY REF, AND ALL 75,336 HISTORY PATHS CONTAIN NO
`xd1/mutate.py`. THE OTHER TWO ARE CLASSIFIER ERRORS: **`xd1/pin` IS A REVISION REFERENCE** (`TOOLS.md:645` says it
equals `6c3d401cf324`, WHICH `git cat-file -t` ANSWERS AS `commit`) AND **`runs/elf-checkonly-2026-10-04.txt` IS A
CAPTURED STDOUT** (110 B of `ALL PROOFS CHECK`). **A BASENAME REGEX MATCHED THE WORD `pin` AND THE SUBSTRING `check`,
WHICH IS DOCTRINE 1's FAILURE REPRODUCED INSIDE THE CENSUS OF DOCTRINE 1.** **AND ALL 16 APPEAR **ONLY** UNDER
`extract.py`'s RULE A: EVERY EXTENSION-GATED RULE DROPS `xd1/pin`, BECAUSE IT HAS NO EXTENSION — **THE SAME STRUCTURAL
BLINDNESS ONE LEVEL DOWN.** **A GATE'S
  REQUIRED INPUT BELONGS BESIDE THE GATE **IN GIT** — AND NOT IN `gates/artifacts/`, WHICH THIS LINE USED TO
  RECOMMEND. THAT DIRECTORY IS `.gitignore`d **AND** IS WHERE GATE RUNS WRITE, SO ONE `rm -rf gates/artifacts`
  DELETES ANYTHING KEPT THERE AND GIT CANNOT RESTORE IT. MEASURED: `e2efix` RESTORED STAGE 7's DELETED FIXTURE
  THERE AND IT WAS **GONE** ON THE NEXT READ; IT NOW LIVES AT THE TRACKED `gates/cstyle-live.rows`.** **A PATH INSIDE
  A SWEPT TREE IS DELETABLE WHILE THE GATE STILL NAMES IT, AND SO IS A PATH INSIDE A GITIGNORED OUTPUT DIRECTORY.**
  The shared plumbing is `gates/gatekit.py` and it holds nothing but the three lanes, the row counts
  and the diff — the rows, the divergences and the pins are the gate's own. `gates/README.md` records
  why the shell form is retired, with the four ways a shell gate failed here (`&&` masking a diff
  under `set -e`; an `EXIT` trap returning `rm`'s status; `<( )` not parsing under `sh`; `${=SUB}` never
  expanding and a hash guard comparing `""` to `""`).


## The two doctrines. Everything below is a measured instance, not a principle.


### 1. AN INSTRUMENT DECLARES ITS POPULATION BY DISCOVERY, OR IT IS NOT A GATE

**Six instruments in this repo got this wrong, and one governing document got it wrong too. Every one
of the seven was found in a single session, which is why this section exists.**

| instrument | population was declared by | what it cost |
|---|---|---|
| `checks/sweep.py` `LIVE_UNITS` | was 14 literal directory names — **removed; `:291` records "LIVE_UNITS lived here, a tuple of 14 names. It is gone"** | six FINISHED units held **2,353 of 4,455 files = 53%** of `.slop`, 100% git-tracked, named by nothing. Its own comment: *"A GUARD THAT IS CORRECT EXCEPT FOR THE LAST DISPATCH IS NOT A GUARD, IT IS A COINCIDENCE WITH THE DISPATCH ORDER."* |
| `checks/sweep.py:658` `ORACLE_WORD` | a **basename regex** | **670 of 675** ORACLE files were classified by FILENAME and **5 were named by a live gate**. |
| `checks/differ.py:artefacts_ok()` | was `find -name '*.txt'` | **fixed, and re-verified today**: pointed at an empty directory it now returns **139 `MISSING`**; the glob returned `[]`, and *"the rename only revealed a guard that was never one."* |
| `checks/repro-paths.py:57` `REF` | `(?:sh\|py\|bend\|mjs\|json)` — **fixed** | **6 of 15** `e2e.py` stage inputs were invisible (2 `.mjs`). *"RESTORING THEM MOVED THIS TOOL'S OUTPUT BY EXACTLY ZERO."* |
| `gates/gates-pop.py:95` `HOMES` | `("checks", "gates")` | its own author: *"A LIST, AND IT IS ADMITTED… this is the one universe this file names by hand."* Blind to the literal-list half of the class it exists for. |
| `.agents/TOOLS.md` | **333 paths: 153 present, 180 gone (96 under `.slop/`) at 2026-10-06 13:00; **14 INSTRUMENTS by content**, 13 recoverable + `xd1/mutate.py` GONE** | A ledger that names a path it does not own is a list. |
| **`AGENTS.md` — THIS FILE** | names gates by hand | 17 `checks/*.sh` exist; this file names 3 and calls none of them a population. **The governing document was the seventh member of the class.** |

**THE RULE. A population is (a) a GENERATOR'S OWN DECLARATION, LOADED BY PATH — `differ.declared()`, which
`checks/no-txt.py` and `artefacts_ok()` both ask, which is why the `.txt` carve-out never moved while the
total moved 398 → 552 → 562 → 553; or (b) a DIRECTORY WALK — `os.walk` + `endswith`, because
`glob('*.bend')` returns `[]` when `.bend` is on disk and it did, tracked, 1,890 lines; or (c) a REGEX OVER
THE TREE'S OWN WRITE SITES, with the list admitted in a comment and a ledger so the edit is visible.
A BASENAME SHAPE, A SUFFIX SET, AND A HAND LIST ARE NOT POPULATIONS. AN INSTRUMENT THAT CANNOT SEE ITS
POPULATION CANNOT BE WRONG, BECAUSE IT CANNOT BE ANYTHING.** Never list in this file what an instrument
discovers.

### 2. FIVE VERDICTS, AND `DEAD` IS THE ONE NOBODY WRITES DOWN

`PASS` every stage ran and agreed · `FAIL` a stage ran and got the wrong answer · `SKIP` it could not run,
so it measured nothing · `DEAD` it ran and emitted nothing · `REFUSED` a precondition was absent.

**`SKIP IS NOT PASS`, and the exit status says so: `e2e.py:510` returns 4 and `checks/e2e.sh:335`
`exit 4`** — the old 0 was defended and the defence was true of FAIL and not of SKIP.
**`DEAD` IS NOT A ZERO AND NOT A PASS.** `.agents/slop/rebase-gate-selftest.py:1168-1180` already
declares the SIX such states — *1 DEAD LANE the oracle exits non-zero → BROKEN, naming the lane · 2 EMPTY
OUTPUT prints no `name=value` row → "compared nothing" · 3 NO SHARED ROW NAME · 4 A SHARED NAME DIFFERS ·
5 AGREEMENT · 6 MALFORMED BASELINE* — and its own header says why: *"twelve committed files printed 0 rows
for an hour and a harness reported success, because '0 disagreements' over '0 comparisons' is
indistinguishable from agreement."* **AND THAT FILE RUNS AGAIN** (measured 2026-10-06 13:02: `oracle_py.py`
was restored, so the import succeeds and the harness reaches its assertions) — **but it now dies with
`KeyError: 'cpython:renderer_oracle'` at `rebase-gate-selftest.py:1095`, rc=1, so the six-state template
it documents is driven by a harness that cannot finish.**
`artefacts_ok()` reported zero on a directory holding nothing. **AND THE FIFTH DEFECT WAS CLOSED, AND NOT
IN `checks/sb-gate.sh`, WHICH STILL HAS NO SKIP BRANCH AT ALL (`grep -c SKIP` = 0): `gates/gatekit.py:59`
NOW SPELLS THE FIVE AS EXITS — `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5` — SO `DEAD` HAS EXIT **5**
AND `REFUSED` EXIT **3**. MEASURED GREEN: `wk-f32-gate.py` rc=0, `gatekit.py` rc=0.**
**THE CLAUSE THIS REPLACED NAMED **THREE** THINGS THAT ARE NOW FALSE, NOT ONE: `oracle-selfcheck` READS `OK`
(`46c52f30d`, TWO FULL RUNS OF THE THEN-25-GRAPH CORPUS; the corpus is 34 graphs as of 2026-10-06 14:16), `checks/corpus-figure.py` EXITS **1** WITH `DEV` UNSET (rc=0 **ONLY**
WITH `DEV=CPU`), AND `DEAD` HAS AN EXIT.**
> **AND `checks/sb-gate.sh` EXITS 3 WHEN REFUSED TOO, AND THE TWO 3s SHARE **ZERO** LINES: IT IS SHELL,
GATEKIT IS PYTHON, AND `grep -c gatekit checks/sb-gate.sh` = **0**. A SHARED NUMBER IS NOT A SHARED
VOCABULARY, AND **THIS FILE HAD BEEN READING IT AS ONE** — THE THIRTEENTH STALE CITATION, IN THE FILE THAT
DEFINES THE CLASS.**
**A GATE THAT EXITS 0 HAVING MEASURED NOTHING IS WORSE THAN NO GATE, BECAUSE IT IS TRUSTED.**


When using Python:
- use uv and ty. **MEASURED: `command -v uv` = `~/.local/bin/uv`; `command -v ty` = `~/.local/bin/ty`.**
- **RUN PYTHON THROUGH `.venv/bin/python`, NOT BARE `python`/`python3`. MEASURED HERE: PATH's `python3` is
  3.14 and has no `.pth`, `.venv` is 3.12 and has the editable `tinygrad` install, and a port oracle that
  imports tinygrad answers 30 rows under one and 0 rows plus `ModuleNotFoundError` under the other.
  `.agents/TOOLS.md`'s *Pin vs xd1/head* section records the instrument that pinned this; the file
  itself, `.agents/slop/oracle_py.py`, WAS among the 99 deleted paths and **was restored at
  2026-10-06 13:01 (5551 B) — verify it still exists before citing this line, it appeared mid-run.**
- Run `test/` with `-n12` for speed, e.g. `.venv/bin/python -m pytest test/null/test_dtype.py -x -q -n12`. **MEASURED TODAY: that command is rc=1, `No module named pytest` — `pytest` IS NOT IN `.venv`, so `test/` is the ORACLE this tree cannot currently run. The bare `python3` on PATH is 3.14 and has no `.pth`; `.venv` is 3.12 and holds the editable `tinygrad`.**
- Run `.venv/bin/python -m mypy tinygrad/` to typecheck. **MEASURED TODAY: rc=1, `No module named mypy` — NOT INSTALLED IN `.venv`.**
- Run `python -m ruff check .` to lint
- **THOSE THREE EXACT COMMANDS DO NOT RUN IN THIS TREE TODAY, AND SAYING SO IS THE POINT: MEASURED,
  `.venv` HAS NO `pytest`, NO `mypy` AND NO `ruff` (`No module named …`, rc=1 each), so the three lines
  above are `uv`-installable rather than runnable. `ruff` 0.15.18 IS on PATH at `/opt/homebrew/bin/ruff`
  and `ruff check .` RUNS — and it reports **18781 at 12:59:48, 18797 at 13:00:36, 19677 at 13:02:53, 19679 at
  13:03:01** (four reads, 193 s apart, same command, no edit by the unit that took them), rc=1, so "the tree lints"
  is FALSE. **THE `797` THIS LINE USED TO CARRY WAS WRONG BY 23x, AND THE COUNT CARRIES ITS OWN TIME: OTHER UNITS
  WERE WRITING THE TREE WHILE IT COUNTED. QUOTE THIS NUMBER WITH A TIMESTAMP OR NOT AT ALL.** `checks/`
  and `gates/` are 2-space-indented and are not what `ruff` defaults to. The ledgers do not say which
  interpreter a prescription runs under, and that is why three of them read as done.**
- Read `./tinygrad/viz/README.md` for profiling and debugging rewrite rules. **MEASURED: exists, 93 lines.**
- **Do not do amend commits, and do not REBASE. Always do a new commit if a force push to origin would
  be required.** The previous revision said only "no amend". **`ad117c928` IS **OURS**, NOT UPSTREAM, AND AN
  EARLIER REVISION OF THIS LINE GOT IT BACKWARDS**: `git log -1` READS `author: tinybendygrad
  <tinybendygrad@localhost>`, `Fri Oct 2 19:35:06 2026`, **16 FILES ALL UNDER `tinygrad/`**, AND
  `git merge-base --is-ancestor ad117c928 HEAD` = **YES**. **SO THE RE-VENDOR THAT BROKE A PIN THE TREE CITES
  WAS DONE BY THIS PROJECT, NOT BY UPSTREAM — WHICH IS WHY THE RULE IS ABOUT OUR OWN HISTORY AND WHY THE
  EXCUSE THIS LINE USED TO CARRY COULD NOT HAVE EXCUSED IT.**
  Its message is *"rebase B1: 17 files, the tree imports again, and the GUARD that was supposed to catch this
  is DEAD"* and it names the tool it came from (`rebase-plan.py --json`, `rebase-try.sh`), **AND BOTH ARE NOW
  DELETED, SO THE PLAN THAT RE-VENDORED `tinygrad/` HAS NO SCRIPT LEFT TO AUDIT IT.** **THE PIN SURVIVES:
  `git show 'ad117c928^:tinygrad/uop/ops.py'` STILL ANSWERS EVERY CITATION, `:1398` `dtype: DType =
  dtypes.void` AND `:1404` THE CONDITIONAL `__repr__` — **SO `ad117c928^` IS THE PIN, NOT `ad117c928`.**
- tinygrad has user space PCI drivers for AMD and NVIDIA GPUs. Do not insert the unneeded kernel modules. **MEASURED: `rg -l 'PCIDevice' tinygrad/` = **8 files**; the class is at `tinygrad/runtime/support/system.py:206`, and `ops_amd.py:738` and `ops_nv.py:531` each define `PCIIface(PCIIfaceBase)`.**


Testing:

- **NEVER write unit tests after you write code.** MEASURED, this is the rule the tree most often breaks
  *in the right direction*: `.agents/slop/` held 40+ `*-mutate.py` and `*-selftest.py` harnesses (9 + 7
  survive at 2026-10-06 13:00; the rest were pruned), because
  "unmoved" conflates *no mutation was written* with *written and it did not move* — `.agents/TOOLS.md`
  measured 487 mutations / 15 tables / 30 zeros of which **25 were unclassified**, and
  `.agents/slop/zero-classify.py` (DELETED, one of the 99) was built to settle them by asking whether
  CPython's answer appears in ANY row. **THE HARNESS YOU WRITE IS THE ONE THAT CAN FAIL, SO IT COMES
  FIRST.**
- Highly prefer E2E tests as the sole testing mechanism. Use them to verify complex features work. At the end of E2E tests, produce a verifiable and repeatable artifact.
- If you must test a system in isolation, FIRST write all the ways it could fail, THEN write the code.
- Tautological tests considered harmful.
- Change-detector tests considered harmful.
- Do not create regression tests for bug fixes without a genuine gap in behavior testing.
- Inject time instead of sleeping: production code needing "now" takes it as a parameter, so tests pass a deterministic value instead of faking timers.
- **`test/` IS UPSTREAM TINYGRAD'S SUITE AND IS THE ORACLE, NOT OUR TESTS.** It runs unchanged against
  the Bend build (`python -m pytest test/null/test_dtype.py -x -q -n12` — **but `pytest` is not in `.venv`
  today**, see above). **A test that passes without exercising the Bend lanes is a change-detector, and
  this project has measured four of them:** the `naming-gate` `VERBATIM` count read **283 vs 278** across
  six runs 14 s apart (283 is settled substrate, 278 is substrate-in-flux); `elf.bend`'s row count read
  **353 / 331 / 246 / 355** — **246 WAS A PARTIAL READ OF AN IN-FLIGHT RUN, RETRACTED**;
  `elf-run`'s `354` was the harness's own `done rc=0` echo counted as a proof row; and
  `run-port-mm.sh` on one tree read **rc 1 then rc 0**. **NEVER QUOTE A ROW COUNT WITHOUT THE RULE THAT
  PRODUCED IT, AND NEVER QUOTE ONE FROM A JOB THAT MAY STILL BE RUNNING.** 


Tinygrad Flags

Most important ones are DEBUG and VIZ. You can mock hardware with DEBUG.


### Core UX

| Flag                 | Default          | What it does                                                                        |
| -------------------- | ---------------- | ----------------------------------------------------------------------------------- |
| `DEV`                | `""` (auto)      | Backend selection, `DEV=AMD:LLVM:gfx950`, `DEV=USB+AMD`, etc. See docs/env_vars.md  |
| `DEBUG`              | 0                | 1=ops, 2=+mem/timings, 3=+applied opts, 4=+gen code, 5=+UOps, 6=+linearized, 7=+asm |
| `JIT`                | 1 (2 on OSX/x86) | 0=off, 1=on, 2=on but device graphs off                                             |
| `VIZ`                | 0                | 1=record rewrites and open the viz UI (implies PROFILE)                             |
| `PROFILE`            | VIZ              | 1=enable profiling infrastructure                                                   |
| `SPEC`               | 1                | UOp spec validation after rewrites. **STAY AT 1.** Upstream's own CI runs `SPEC=2` on `test/null/`, but MEASURED: `SPEC=1` 70 of 70 program ops (70 of 77 enum members) on the 34-graph corpus, read 2026-10-06 14:16 · `SPEC=2` 26 of 77 enum members, 14 of 25 graphs FAIL, exit 1 · `SPEC=3` 0 of 77 enum members, all 25 FAIL — the `SPEC=2` and `SPEC=3` rows are 25-graph readings, STALE now that the corpus is 34 graphs, and re-taking them needs `bend` |
| `BEAM`               | 0                | Beam search iterations for kernel optimization                                      |
| `NOOPT`              | 0                | 1=disable all kernel optimizations                                                  |
| `DEFAULT_FLOAT`      | float32          | Default float dtype (HALF, BFLOAT16, FLOAT64)                                       |
| `TRAINING`           | 0                | 1=training mode (used via `Context(TRAINING=1)`)                                    |
| `IMAGE`              | 0                | 1=2d-specific (image) optimizations                                                 |
| `FLOAT16`            | 0                | 1=use float16 for images instead of float32                                         |
| `ALLOW_TF32`         | 0                | 1=allow TensorFloat-32 on Ampere+                                                   |
| `NO_COLOR`           | 0                | 1=disable colored output                                                            |
| `CPU_COUNT`          | host cores       | Threads for CPU kernel launches                                                     |
| `MAX_BUFFER_SIZE`    | 0 (lib default)  | Cap individual buffer size in bytes                                                 |
| `ALLOW_DEVICE_USAGE` | 1                | 0=forbid opening devices (used by viz server)                                       |

### Compiler & kernel search

| Flag | Default | What it does |
|---|---|---|
| `JITBEAM` | BEAM | Beam level for kernels compiled inside the JIT |
| `IGNORE_JIT_FIRST_BEAM` | 0 | Skip beam on first JIT compile |
| `PARALLEL` | cpu count | Worker processes for beam search |
| `BEAM_ESTIMATE` | 1 | 1=score candidates by estimated runtime, 0=real launches |
| `BEAM_UPCAST_MAX` | 256 | Max upcast amount in candidates |
| `BEAM_LOCAL_MAX` | 1024 | Max local size in candidates |
| `BEAM_UOPS_MAX` | 3000 | Max uops allowed in a candidate kernel |
| `BEAM_TIMEOUT_SEC` | 10 | Abort beam after N seconds |
| `BEAM_MIN_PROGRESS` | 0.01 | Minimum estimated-improvement rate to continue |
| `BEAM_MAX_TASKS_PER_CHILD` | 16 | Recycle beam worker processes |
| `BEAM_PADTO` | 0 | Allow PADTO optimization in beam |
| `BEAM_STRICT_MODE` | 0 | Stricter candidate acceptance |
| `BEAM_DEV_TIMEOUT` | 1 | Per-launch device timeout during beam |
| `BEAM_DEBUG` | 0 | Beam search trace |
| `BEAM_LOG_SURPASS_MAX` | 0 | Log when candidates exceed uops/upcast/compute limits |
| `IGNORE_BEAM_CACHE` | 0 | 1=ignore cached beam results |
| `CACHELEVEL` | 2 | Kernel cache level (0=no cache) |
| `CCACHE` | 1 | 0=disable the compiler cache |
| `SCACHE` | 1 | 0=disable the scheduler cache |
| `LRU` | 1 | 1=LRU eviction for the disk cache |
| `CACHEDB` | — | Disk cache database filename |
| `XDG_CACHE_HOME` | std | Base dir for the tinygrad cache |
| `DISABLE_HTTP_CACHE` | 0 | 1=never reuse `fetch()` downloads |
| `USE_TC` / `TC` | 1 | 0=disable tensor cores |
| `TC_SELECT` | -1 | Force a specific tensor-core candidate |
| `TC_OPT` | 0 | Tensor-core optimization level |
| `WINO` | 0 | 1=enable Winograd convolution |
| `TRANSCENDENTAL` | 1 | 1=force software transcendental decomposition |
| `NOLOCALS` | 0 | 1=disable local memory |
| `SPLIT_REDUCEOP` | 1 | 0=disable splitting large reduces into two kernels |
| `REDUCEOP_SPLIT_THRESHOLD` | 32768 | Min elements before reduce splitting applies |
| `REDUCEOP_SPLIT_SIZE` | 22 | Log2 cap on split reduce output size |
| `DISALLOW_BROADCAST` | 0 | 1=forbid broadcasting (catches hidden expands) |
| `DISABLE_FAST_IDIV` | 1 | 0=enable fast integer division (marked broken for some indexing) |
| `USE_ATOMICS` | 0 | 1=allow atomics for embedding backward |
| `FUSE_OPTIM` | 0 | 1=fuse optimizer apply into the compute graph |
| `MAX_KERNEL_BUFFERS` | 0 | >0=split kernels with more than N buffers |
| `MV` | 1 | 0=disable matrix-vector tensor-core opt |
| `MV_BLOCKSIZE` | 4 | MV opt: block size |
| `MV_THREADS_PER_ROW` | 8 | MV opt: threads per row |
| `MV_ROWS_PER_THREAD` | 4 | MV opt: rows per thread |
| `OCCUPANCY_FLOOR` | 4096 | Skip local-group candidates below this global size |
| `ALLOW_HALF8` | 0 | 1=allow 8-wide half loads in memory coalescing |
| `ALIGNED` | 1 | 0=disable aligned vector loads in cstyle renderers |
| `DMC` | 0 | 1=skip memory coalescing pass |
| `UPAT_COMPILE` | 1 | 0=interpreted (slow) pattern matcher instead of compiled |
| `EXPAND_SSA` | 0 | SSA expansion toggle (rarely used; dev knob) |

### Scheduler, JIT & graph

| Flag | Default | What it does |
|---|---|---|
| `JIT_BATCH_SIZE` | 32 | Max kernels per JIT batch |
| `NO_MEMORY_PLANNER` | 0 | 1=disable buffer reuse by the memory planner |
| `PCONTIG` | 0 | 1=allow partial contiguous in rangeify |
| `DEBUG_RANGEIFY` | 0 | Rangeify debug output |
| `TUPLE_ORDER` | 1 | 1=tuplize linearizer sort order |
| `RING` | 1 | Ring allreduce: 0=off, 2=force |
| `ALL2ALL` | 0 | All-to-all allreduce: 1=on, 2=force |
| `ALLREDUCE_CAST` | 1 | 1=cast before allreduce |
| `RING_ALLREDUCE_THRESHOLD` | 256000 | Min elements to prefer ring/all2all for ndev>2 |
| `LATE_ALLREDUCE` | 1 | 0=do allreduce early instead |
| `GRAPH_ONE_KERNEL` | 0 | 1=allow single-kernel graph capture |
| `UNSAFE_ALLOW_JIT_BUFFER` | 0 | 1=allow capturing buffers during JIT (unsafe) |
| `REALIZE` | 0 | llm: realize weights at load |
| `HALF` | 1 | llm: cast loaded weights to float16 (0=keep dtype) |

### Debug, validation & dev infra

| Flag | Default | What it does |
|---|---|---|
| `CHECK_OOB` | 0 | 1=check out-of-bounds in the PYTHON backend (slow) |
| `VALIDATE_WITH_CPU` | 0 | 1=validate every kernel's output against CPU |
| `ASSERT_COMPILE` | 0 | 1=assert on any device compile (no-compile enforcement) |
| `TYPED` | 0 | 1=typeguard runtime type checking on import |
| `DEBUG_LINEARIZE` | 0 | Print linearizer decisions |
| `DEBUG_RANGEIFY` | 0 | Rangeify debug output |
| `DEBUG_GC` | 0 | GC debugging at exit |
| `DEBUGONNX` | 0 | ONNX parser debug |
| `ONNXLIMIT` | -1 | Parse only first N onnx nodes |
| `TRACE` | 0 | PYTHON backend: print every executed op |
| `PRINT_MATCH_STATS` | 0 | Print pattern-match counts per rewrite |
| `TRACK_MATCH_STATS` | 0 | Record per-rule match stats (pickle) |
| `CAPTURE_PROCESS_REPLAY` | 0 | Capture kernels for process-replay tests |
| `REWRITE_DATA` | — | Path to rewrites pickle for viz (`--rewrites-path`) |
| `PROFILE_DATA` | — | Path to profile pickle for viz |
| `BROWSER` | — | viz: auto-open browser at this host |
| `PORT` | 8000 | viz server port |
| `NOSKIP` | 0 | AMD sqtt: don't skip decode categories |
| `TEST_PICKLE` | 0 | Dev knob for pickle testing |
| `DEVICE_IN_FUNCTION_BUG` | 0 | Dev knob reproducing a device-in-function bug |

### Device & runtime (cross-backend)

| Flag | Default | What it does |
|---|---|---|
| `THREADS` | 1 | 0=single-threaded CPU renderers (llvmir/cstyle/x86) |
| `CC` | clang | C compiler for the CLANG backend |
| `LLVMOPT` | 1 | 0=disable LLVM optimization passes |
| `MM_DEBUG` | 0 | Memory-manager map/unmap trace |
| `GMMU` | 1 | 0=disable GPU MMU usage |
| `EMULATED_DTYPES` | "" | Dtypes to emulate (e.g. bfloat16) |
| `NULL_ALLOW_COPYOUT` | 0 | Allow copyout on the NULL device |
| `REMOTE` | "" | Comma-separated remote tinygpu PCIe devices |
| `APL_REMOTE_SOCK` | temp path | Socket path for remote device IPC |
| `REMOTE_TIMEOUT` | 60 | Remote device timeout |
| `VFIO` | 0 | 1=use VFIO for PCIe device access |
| `IOCTL` | 0 | 1=import the ioctl test harness (nv/amd/qcom/dsp) |
| `TINYFS_ENDPOINT` | localhost:6767 | tinyfs server address |
| `TINYFS_TIMEOUT` | 60 | tinyfs request timeout |
| `ASYNC_COPY_WORKERS` | 4 | tinyfs async copy pool size |
| `HCQ2` | 1 | Opt into the newer HCQ implementation paths |
| `HCQ_NUM_SDMA` | ≤8 | HCQ copy queue count |
| `HCQDEV_WAIT_TIMEOUT_MS` | 30000 | HCQ device wait timeout |
| `HCQ_VISIBLE_DEVICES` | — | Deprecated; errors with guidance |

### Backend-specific

| Flag | Default | What it does |
|---|---|---|
| `CUDA_PATH` | /usr/local/cuda | CUDA headers location |
| `NV_DEBUG` | 0 | NV driver debug (≥4 dumps register writes) |
| `PMA_BUFFER_SIZE` | 512 (MiB) | NV PMA buffer size |
| `ROCM_PATH` | /opt/rocm | ROCm installation path |
| `AMD_AQL` | — | AQL packet path for AMD |
| `AMD_DISABLE_SDMA` | 0 | 1=disable AMD SDMA copy engines |
| `AMD_SDMA_BIND` | 0 | 1=bind SDMA queues to devices |
| `AMD_KFD_QUEUE_PRIORITY` | 7 | KFD queue priority override |
| `WAVES_PER_SH` | 0 | AMD: force waves-per-SH in COMPUTE_RESOURCE_LIMITS |
| `SQTT_BUFFER_SIZE` | 256 | AMD thread-trace buffer size |
| `SQTT_EVENT` | -1 | AMD: record only this sqtt event id |
| `MAX_SQTT_PKTS` | 50_000 | Cap decoded sqtt packets |
| `PMC_COUNTERS` | — | AMD performance counters to enable |
| `AM_DEBUG` | 0 | am (bare-metal AMD) debug level |
| `AM_RESET` | 0 | am: reset device at init |
| `AM_POWER_LIMIT` | 0.0 | am: cap power (fraction) |
| `MOCKDSP` | 0 | 1=use the mock DSP device |
| `QCOM_PRIORITY` | 8 | QCOM KGSL context priority |
| `FIX_METAL_ICB` | — | Metal indirect-command-buffer workaround |
| `WEBGPU_BACKEND` | auto | WebGPU native backend (Metal, Vulkan, ...) |
| `MLX_IP` | 10.0.0.1 | mlx (RDMA NIC) device IP |
| `EMULATE` | — | Deprecated; errors and points at `DEV=PYTHON::` |

### Optimizer / training knobs

| Flag | Default | What it does |
|---|---|---|
| `SUM_DTYPE` | float32 | Accumulation dtype for sum reductions |
| `OPTIM_DTYPE` | float32 | Optimizer parameter dtype |
| `CONST_LR` | 0 | 1=scalar (unscheduled) learning rate |
| `BENCHMARK_LOG` | "" | llm: write benchmark events to this log |
| `OPENPILOT_HACKS` | 0 | Compatibility behaviors for openpilot models |
| `CAPTURING` | 1 | Internal: graph-capture state (dev knob) |
| `TRACEMETA` | 1 | Internal: include metadata in traces |