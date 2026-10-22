You are one of Cyberistic's agents. He hates unclean code and hacks. He loves his documentations. LOCs IS a measure of quality, the LESS, the better.

**EVERY PRESCRIPTION BELOW THAT MAKES A CLAIM ABOUT THIS TREE CARRIES THE MEASUREMENT THAT MADE IT
TRUE, MEASURED 2026-10-06 BY RUNNING IT. `.agents/slop/agend/REPORT.md` is the audit — every `NEVER`,
every `ALWAYS`, every `MUST`, every named command and every named path, and whether it is true today.
**A LINE IN HERE WITH NO MEASUREMENT AND NO NAMED INSTRUMENT IS A LINE YOU MUST NOT TRUST, AND
DELETING IT IS CHEAPER THAN LEAVING IT.** The cheapest test of a prescription is to FOLLOW it, and
nobody had been doing that: this file told every agent CI uses `SPEC=2`, and `SPEC=2` takes the corpus
census from 70 of 70 program ops (70 of 77 enum members — **THE ENUM DENOMINATOR IS NOW **75**; THIS IS THE **2026-10-06** READING**; 34-graph corpus, read 2026-10-06 14:16) to 26 of 77 (the enum denominator it was measured against; a 25-graph `SPEC=2` reading, not re-taken) with 14 of 25 graphs failing. It also told every agent to put a
gate's inputs under `.agents/slop/`, and **THE LEDGER'S PATH COUNTS ARE **NO LONGER IN **THIS** FILE**, AND **NEITHER ARE `.agents/TOOLS.md`'s OWN** — **THE COUNT IS **A FIXED-POINT PROBLEM AND NOT A STYLE**: MEASURED **2026-10-18**, **ONE COMMIT'S EDITS MOVED IT **401 -> 408** DISTINCT AND **178 -> 179** ABSENT, SO **RE-DERIVE IT** (`.agents/slop/toolsledger/extract.py`, **ASKING `git ls-tree -r HEAD`, **NOT `git ls-files` WHICH IS **THE INDEX**) — the 2026-10-06 reading was 180 of 333 — **14 of them
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
  measured 2026-10-06 13:00 `checks/no-txt.py` exited 1 with **550 HARD and 139 EXCUSED — 689 owned `.txt`** — **RE-MEASURED
  2026-10-18 19:13Z: **183 HARD / 249 EXCUSED / 433 OWNED.** ***THE HARD COUNT IS **NOT A COUNT OF SLOPPINESSES**: **183** OF
  THEM ARE **ONE DIRECTORY**, `.agents/slop/graphcmp-run1/D-published-backup/`, WHICH HOLDS **176** — **A RETAINED EARLIER
  CORPUS RUN** (`filecmp`: **13** identical / **163** differing from live), **AND ITS BASENAMES **ARE** DECLARED **AT **A
  DIFFERENT RELATIVE PATH, SO THE CARVE-OUT CORRECTLY REFUSES THEM.** ***DO **NOT** DELETE IT: **THE REFUSAL **IS **THE
  MECHANISM WORKING.*** **AND THE COUNTS ARE **NOT** TRANSCRIBED HERE **BECAUSE **THEY **CANNOT BE**: **MEASURED, EXCUSED
  READ 249 -> 250 WITH HARD UNMOVED **BECAUSE TWO `differ` RUNS WERE IN FLIGHT** **AND THE 250TH FILE WAS
  `.tmp.D1-graph-commute.txt`, **THE STAGING NAME, COVERED BY CONSTRUCTION.*** **RE-DERIVE BOTH BY RUNNING `checks/no-txt.py`
  AND READING ITS OWN ROWS;** (the HARD count
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
- **THE COMPILER **IS **REACHABLE **AS **`bin/bend`**, **NOT **AS **BARE `bend`** — **MEASURED 2026-10-20: `bin/bend` **IS
  **A **2,097 **B **EXECUTABLE **SHIM **ONTO `references/bend/bend2/main.ts`**, **IT **RUNS**, **AND `command -v bend`
  **FAILS**, **SO **A **BARE `bend` **RESOLVES **TO **NOTHING**.** **IT **IS **GITIGNORED **(`.gitignore:5`), **SO **IT
  **IS **A **LOCAL **CONVENIENCE **AND **NOT **A **TRACKED **FILE** -- **WHICH **IS **WHY **THE **CORPUS **RUNS **IT
  **AS **`./bin/bend`.** ***AND **THIS **LINE **HAS **COST **THE **TREE **A **DAY**: **AN **AGENT **WAS **NEARLY **CONVINCED
  **IT **COULD **NOT **VERIFY **ANYTHING **BECAUSE **`command -v bend` **FAILED** -- **WHILE **A **WORKING **COMPILER **WAS
  **SITTING **AT **`bin/bend`**.* **SO: **RUN **`bin/bend <file>`**, **OR **PUT **`$PWD/bin` **ON **`PATH`** -- **AND **NEVER
  **CONCLUDE **"**THERE **IS **NO **BEND**" **FROM **`command -v bend`**.**
- run `bin/bend guide` to learn it — **MEASURED rc=0, 677 lines. This is the one that works.**
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
  So the `.txt` names there — `len(differ.declared())` = **244** AND **244** on disk, **MEASURED **2026-10-18 19:13Z**, **0
  DECLARED-AND-ABSENT AND **0** ON-DISK-AND-UNDECLARED** — are a contract,
  not sloppiness: `checks/no-txt.py` carves out **`FIVE` GENERATORS' DECLARATIONS**, **NOT** `differ.declared()` **AND
  NOTHING ELSE** — **THIS LINE NAMED ONE** ***(the 2026-10-07 reading said **175** ON BOTH SIDES; **BOTH **MOVED **TO
  **244** **TOGETHER**, **+69**, **WHICH IS **THE **GOOD **NEWS**: **THE DECLARATION **IS **A GENERATOR's OWN
  `declared()`, NOT A HAND LIST, **SO IT MOVED **WITH **THE **THING **IT **DESCRIBES**.)** ***RE-DERIVE **BOTH** SIDES
  WITH `len(differ.declared())` **AND **AN `os.walk` + `endswith` + `os.path.exists` **WALK** -- **`glob` IS **A **TRAP
  HERE**: **`AGENTS.md` RECORDS THAT `glob('*.bend')` RETURNS `[]` WHEN `.bend` FILES **ARE** ON DISK.***
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
  green. TRUST THE RED ONE.**
  **AND AS OF **2026-10-22T12:46Z** (`1f6cdc93f`, **AFTER **TONIGHT's **218 **COMMITS**)
  **THE **CORPUS **IS **GREEN, **REPRODUCIBLE, **AND ***CURRENT*** -- **ALL **THREE, **WHICH **IS **THE **FIRST **TIME **ALL
  **THREE **HELD **AT **ONCE**:
  `graphs=35 graphs-answered=35 graphs-agree=35 graphs-disagree=0 byte-identical=35 graphs-refused=0`,
  `population=4a44f98e3964353a7e11247af8bebbcdb9acab1efbb8be19e933f93cae501ed2`,
  `?=0`, `SHARED cores 52`, `controls 5 of 5`, `conflations 4 of 4`,
  `stable-pairs 5 of 5`, `stable-failed 0 of 5`, `stable-differ 0 of 5`, `expect-moved 0`, `plants-disagree 8 of 8`,
  `oracle-selfcheck=OK`, `census-rc=rc=0`, **`selfcheck=# SELFCHECK: OK`**,
  **`unhealthy() -> 0 line(s)`** (THE READING IS **EMPTY**, NOT "0 COMPLAINTS"), **`artefacts_ok() -> 0`**,
  **`repro_bad() -> 0`**, **AND `repro`: `319 of 319 files identical across two clean runs`**
  (`D0-repro.txt`: `repro-files=319 repro-identical=319 repro-rc=rc=0`).
  ***AND ***THE **PART **THAT **MAKES **IT **CURRENT **RATHER **THAN **MERELY **GREEN**:***
  **`substrate-start == substrate-end == live == e83c9f1698d80f2f9211bf84c8e7cd3b0b4a1472618de5c4f4efbc5fe1af0864`** -- **THE **RUN **DESCRIBES **THE **WORKING
  **TREE **AS **IT
  **STANDS**, **AND `substrate-head=1f6cdc93f4ec91706a0d3ac7b88fc228555c0b3c` **IS **THE **COMMIT **IT **WAS **TAKEN **ON** --
  **AND **IT **WAS **HEAD **ITSELF **WHEN **THE **RUN **WAS **TAKEN** (`git rev-parse --short HEAD` **WAS**
  `1f6cdc93f`), **AND **THE **WORKING **COPY's **SUBSTRATE **EQUALS **HEAD's** (399 **TRACKED **PATHS, **0
  **DIFFERING, **0 **MISSING**), **AND **THE **LIVE **DIGEST **IS **THE **RUN's **RECORDED **DIGEST.**
  **⚠ AND **THE **STRONGEST **FORM **OF **THE **CLAIM **IS **ALSO **THE **FRAILEST**, **AND **THIS **TREE
  **DEMONSTRATED **IT **WITHIN **A **MINUTE **OF **ITS **BEING **WRITTEN**: **MY **OWN **NEXT **COMMIT
  **TOUCHED **ONLY `AGENTS.md`**, **SO **HEAD **MOVED **TO `c978aabcb` **AND **THE **RUN's **`substrate-head`
  **IS **NOW **AN **ANCESTOR **OF **HEAD **AGAIN.**  **MEASURED: `git diff --name-only ecde3623a HEAD` **IS
  **EXACTLY **`AGENTS.md`,**0 **SUBSTRATE **PATHS **DIFFER, **AND **THE **DIGEST **IS **UNCHANGED.**
  **SO **THE **MECHANISM **IS **NOW **DEMONSTRATED **RATHER **THAN **ASSERTED**: **A **COMMIT **THAT **FOLLOWS
  **THE **RUN **AND **TOUCHES **NOTHING **IN **THE **SUBSTRATE** -- **`AGENTS.md`, **`.agents/**`, **`gates/**` --
  **DOES **NOT **MAKE **THE **RUN **STALE, **AND **THE **DIGEST **IS **WHAT **SAYS **SO.**  **BUT **A **COMMIT
  **THAT **TOUCHES **A **`.bend` **WOULD, **AND **THAT **IS **WHY **THE **FIRST **`run` **OF **TONIGHT **WAS
  **RE-RUN.**
  ***AND ***THE **PART **THAT **IS **A **COVERAGE **HOLE **AND **NOT **A **RESULT** -- **THE `pI(` LANE **IS **DEAD**:***
  **MEASURED 2026-10-22: the corpus's 34 graphs produce **ZERO** `pI(` rows, so **the `ProgramInfo` FIELD LIST **IS
  **NOT **EXERCISED **AT **ALL**, AND **THE **CORPUS **CANNOT **SEE **THE `vars` -> `params` **RENAME** (`9974c9d9b` /
  upstream `a6addc2d4`) -- **WHICH **IS **A **REAL **PORT **CHANGE**, **BECAUSE **UPSTREAM's `params` **IS **EVERY **PARAM,
  **SORTED **BY **SLOT**, **WHERE **THE **OLD `vars` **WAS **THE **ALU-ONLY **LIST.**  **AND **THE **ORACLE's **BRANCH
  **IS **STALE **CODE**: `graphcmp.py:580` **READS `x.vars`, AND **AT **THE **PIN `hasattr(ProgramInfo(), "vars")` **IS
  **False** **AND `hasattr(..., "params")` **IS **True** -- **SO **IT **WOULD **RAISE **IF **A **GRAPH **EVER **REACHED
  **IT.**  **A **GRAPH **WHOSE **PROGRAM **CARRIES **A **BUFFER **PARAM **WOULD **MAKE **THE **TWO **LISTS **DIFFER, AND
  **NO **SUCH **GRAPH **EXISTS **HERE.**  **THE **CORPUS **IS **GREEN **AND **THIS **HOLE **IS **IN **IT.**
  ***AND ***THE **PORT's `Op` **ENUM **IS **EXACTLY **UPSTREAM's `Ops` **ENUM **AT **THE **PIN**, **AND **THE **TWO
  **WAYS **OF **BEING **WRONG **ARE **BOTH **EMPTY**:** MEASURED 2026-10-22, **upstream 75, port 75, 0
  missing, 0 extra.**  **AND **UPSTREAM's `Ops` **ENUM **LIVES **IN **`tinygrad/uop/__init__.py` **AT **THE
  **PIN, **NOT **IN **`ops.py`** -- **SO **A **GREP **OF **`ops.py` **FINDS **NO `class Ops` **AND **A
  **REGEX **THAT **TAKES **ONLY **THE **FIRST `auto()` **PER **LINE **UNDERCOUNTS **BY **HALF** (upstream
  **writes **`BUFFER = auto(); ALLOC = auto()`**).**
  **⇒ AND **THE **FALLOUT **OF **THE **ENUM **BEING **EXACT **IS **THREE **DRIVERS **STILL **CONSTRUCTING
  **OPS **UPSTREAM **DELETED**: `OpsGROUP` (`gates/ptx_render_census_axis.bend`), `OpsFLIP`
  (`oracles/lift-rows.bend`), `OpsX` (`gates/tn_binop_sweep.bend`).  **⇒ AND **THE **PTX **GATE **IS
  **REFUSED, **NOT **RED: **IT **CANNOT **RUN **AT **ALL** -- **AND **A **GATE **THAT **IS **REFUSED **IS
  **A **DEAD **GATE, **AND **THE **DIFFERENCE **MATTERS.**
  **⇒ AND **UPSTREAM's `group()` **WAS **NOT **DELETED **WITH **THE **OP**: `4e0192eaf remove Ops.GROUP
  (#18637)` **REMOVED **THE **ENUM **MEMBER **AND **CHANGED **WHAT **THE **METHOD **BUILDS** (now
  `Ops.STACK.after(...)`), **AND **THE **PORT's `UOp.group` **MATCHES **UPSTREAM **EXACTLY** -- so **THE
  **PORT **IS **RIGHT **AND **THE **DRIVERS **ARE **STALE.  **DO **NOT **"FIX" **THE **PORT.**
  **⇒ AND **THE **GENERAL **LESSON: **A **DRIVER **THAT **CONSTRUCTS **AN **OP **UPSTREAM **DELETED **IS
  **A **DRIVER **PINNED **TO **AN **OLDER **UPSTREAM, **AND **THE **PIN **IS **INVISIBLE** -- **A **FIXTURE
  **AGAINST **AN **UNSTATED **REVISION **IS **A **FIXTURE **AGAINST **NOBODY.**

  ***AND ***THE **75 **HAS **A **HISTORY, **AND **IT **IS **UPSTREAM's **OWN:** MEASURED 2026-10-22 on the enum's
  **OWN **MEMBER **COUNT**: **77 -> 76** at `4e0192eaf remove Ops.GROUP (#18637)` (2026-10-06) and
  **76 -> 75** at `900880433 remove Ops.FLIP [pr] (#18729)` (2026-10-11) -- **WHICH **IS **THE **COUNT **AT
  **THE **PIN, **AND **WHICH **IS **THE **PORT's **COUNT.**  **⇒ THE **PORT's `Op` **ENUM **IS **EXACTLY
  **UPSTREAM's `Ops` **ENUM **AT **THE **PIN**, **AND **THE **TWO **UPSTREAM **DELETIONS **ARE **EXACTLY
  **WHAT **TOOK **IT **THERE.**
  **⇒ AND **A **TEXT **CENSUS **OVERSTATES**: **A **UNIT **THAT **FIXED **THE **DRIVER **CORRECTED **MY
  **CENSUS, **WHICH **COUNTED **TEXT **AND **NOT **CODE**: `OpsGROUP` **WAS **A **REAL **COMPILE **ERROR**;
  `OpsFLIP` **WAS **A **LATENT **STALE **REFERENCE **IN **A **FRAGMENT** (whose **standing **condition **IS
  **A **DIFFERENT **ONE**: *"expected : 'def', 'type' or 'law'"* -- **BARE **STATEMENTS **AT **TOP **LEVEL**,
  **NOT **`OpsFLIP`**); **AND `OpsX` **WAS **A **PLACEHOLDER **IN **A **COMMENT**, **AND **THE **FILE
  **COMPILES.**  **⇒ A **CENSUS **THAT **NAMES **A **BROKEN **DRIVER **WITHOUT **SAYING **WHETHER **IT
  **IS **BROKEN **IS **A **CENSUS **OF **NAMES.**
  **⇒ AND **THE **PTX **AXIS **WAS **STALE **BY **+14 **ROWS **FOR **A **REASON **THAT **NO **INSTRUMENT
  **SAW:** the 2026-10-16 **re-vendor **moved **A **BUFFER's **SIZE **OUT **OF **THE **`ParamArg` **AND **INTO
  **A **SIZE **CONST **SRC**, so **CPYTHON's **OWN **GRAPHS **GAINED **A **NODE** -- **15 **FIXTURES **GAINED
  **ONE, `f14_skips` **LOST **ONE** -- **AND **THE **AXIS's **BYTES **HAD **NOT **MOVED, **AND **THE **GATE
  **THAT **WOULD **HAVE **SAID **SO **WAS **REFUSED **ON **THE **COMPILE **ERROR.**  **⇒ THE **DRIVER **IS
  **NOW **GENERATED**, **AND **IT **CARRIES **A `# UPSTREAM-PIN <path> <sha256>` **LINE **PER **FILE **THE
  **ORACLE **READS** -- **DERIVED **FROM **THE **ORACLE's **OWN **IMPORTS **PLUS **EACH **SYMBOL's **DEFINING
  **MODULE**, **WHICH **IS **HOW **`tinygrad/uop/__init__.py` **GETS **IN **AT **ALL** (the **oracle **imports
  **`Ops` **RE-EXPORTED **THROUGH **`ops.py`**).**

  ***AND ***THERE **IS **NOW **A **COMPILE-LEVEL **CHECK **OVER **THE **WHOLE **PORT**: `checks/port-compile-gate.py`
  **COMPILES **EVERY **FILE **AND **READS **THE **VERDICT **TOKEN** -- **165 of 169 COMPILE, 4 ARE **COLD
  **BY **DESIGN** (`LAWS.bend`, `PROOF.bend`, `PROOF2.bend` -- EACH **DECLARES **IT **IS **NOT **A **PROOF
  **YET** -- **AND `sz.bend`, **WHOSE **COLDNESS **IS **A **MEMORY **CEILING**, **NOT **A **VERDICT**:
  **MEASURED `KILLED-ON-MEMORY` **AT **2100 MB **UNDER **A **2048 **CEILING **AND **4197 MB **UNDER **A
  **4096 **ONE**).  **⇒ AND **A **ROW-LEVEL **INSTRUMENT **CANNOT **NOTICE **THAT **ITS **SUBJECT **DOES **NOT
  **COMPILE**: **`runtime/support/autogen.bend` **HAD **NOT **COMPILED **FOR **AT **LEAST **TWO **COMMITS**,
  **AND **THE **COMMIT **THAT **AUDITED **ITS **ROWS **SAID **"THE **PORT **IS **AT **0 **ROWS"** -- **A **FILE
  **THAT **PRINTS **ZERO **ROWS **IS **INDISTINGUISHABLE, **TO **SUCH **AN **INSTRUMENT**, **FROM **A **FILE
  **THAT **PRINTS **NONE**.  **IT **IS **NOW **149 **ROWS, **AND **36 **OF **THEM **AGREE **WITH **CPYTHON.**  **THE
  **COST **IS **147 s **FOR **169 **FILES **= **0.87 s **PER **FILE, **ONE **BEND **AT **A **TIME**, **SO **IT
  **IS **A **NIGHTLY **OR **PRE-MERGE **GATE, **NOT **A **PER-COMMIT **ONE.**

  ***AND ***THE **SCOPE **OF **THAT **DIGEST **IS **THE **WORKING **TREE **AND **NOT **THE **COMMIT** -- **AND **THE
  **TREE **ALREADY **SAYS **SO, **IN **`checks/differ.py:1275`**:** *"MOVE-DETECTION AND COMMIT-IDENTITY ARE THE SAME
  PROPERTY, AND A `ls-tree`-BASED DIGEST CANNOT MOVE DURING A RUN -- IT WOULD `PASS` ON EXACTLY THE MIXTURE IT
  EXISTS TO CATCH."*  **SO **THE **WORKTREE **PAIR **STAYS **AND **`substrate-head` **IS **ADDED** -- **AND **THE **COST
  **IS **MEASURED:** **THE **DIGEST **COVERS **389 **MEMBERS **OF **WHICH **14 **ARE **IN **NO **COMMIT **AT **ALL**
  (**`bin/bend` **IS **`.gitignore:5`**, **AND **THE **WALKS **SWEEP **UP `*-mut.bend` **/ `.bak` **PROBE
  **SCRATCH**), **SO **A **FRESH **CLONE **HASHES **375** **AND **REPORTS **A **DIFFERENT **SUBSTRATE **FOR **THE
  **SAME **COMMIT**.**  **MEASURED 2026-10-22, THE **SAME **CLASS **IN **A **NEW **PLACE**: **THE **WORKING **COPY
  **CARRIED **SEVEN **GITIGNORED **FILES **INSIDE **THE **WALK** -- **A **`.bak`, **THREE `*mut.bend` **AND **THREE
  **PROBES** -- **AND **THE **DIGEST **HASHED **EVERY **ONE**, **SO **A **UNIT **THAT **DROPPED **A **MUTATION
  **PROBE **IN **THE **TREE **MOVED **THE **CORPUS's **FRESHNESS **PIN**.**  **THAT **IS **THE **MECHANISM **BEHIND
  **EVERY **"THE **DIGEST **MOVED **AND **IT **WASN'T **ME"** **REPORT **TONIGHT** -- **AND **THE **GAP **THE **TREE
  **NAMES **IS **EXACTLY **THE **ONE **THAT **CLOSES **IT**: **NONE **OF **THE **READERS **NAMED **THE **WORKTREE
  **SCOPE **IN **THE **ROW's **KEY.**  **DO **NOT **"FIX" **THE **DIGEST **TO **BE **A **`ls-tree` **DIGEST** -- **THAT
  **WOULD **UNDO **A **DELIBERATE **DECISION **AND **BLIND **THE **MID-RUN **MIXTURE.**
  ***AND **THE **RUNS **TOOK **271 s / 975 MB** (`run`) **AND **540 s / 920 MB** (`repro`), **TOKEN `WITHIN-LIMITS`***
  -- **AND **THE **`MACHINE: VIOLATED` **LINE **IS **NOT **ATTRIBUTABLE **TO **THE **CHILD**: **THE **REPRO'S **WAS
  **`loadavg 512.1` ON **12** CORES **WITH **SWAP **AT **0.92 **OF **41.00 GiB** FREE, **AND **THE **LOAD **WAS **NOT
  **MINE** -- **IT **WAS **`ty` **AND **OrbStack.***
  ***AND ***THE **LESSON **OF **THE **SESSION**, **AND **IT **IS **NOW **MEASURED **RATHER **THEN **ANECDOTED**:***
  **THE **CORPUS **WAS **GREEN **AT **`00:16Z` **AND **THEN **WAS **STALE **WITHIN **THE **HOUR** -- **BECAUSE **A **UNIT
  **WAS **PORTING `tinybendygrad/extra/` **AND **EVERY **`.bend` **EDIT **MOVES `substrate_digest()`.** **SO **A **GREEN
  **CORPUS **IS **NOT **A **CERTIFICATE **UNTIL **THE **TREE **STOPS **MOVING.** ***AND **TONIGHT **THE **SAME **THING
  **HAPPENED **A **SECOND **TIME, **AND **THE **RUN **SAID **SO**: **THE **FIRST **`run` **OF **TONIGHT **RECORDED
  **`substrate-start=8adec7c5…` **AND **`substrate-end=58c50569…` -- **IT **STRADDLED **A **`.bend` **EDIT **A **UNIT
  **LANDED **MID-RUN**, **AND **THE **VERDICT **WAS **STILL **34/34** -- **SO **A **GREEN **RUN **OVER **A **MOVING
  **TREE **IS **NOT **A **CERTIFICATE **EITHER, **AND **THE **RUN'S **OWN **TWO **DIGESTS **ARE **WHAT **SAY **SO.***
  **AND **`gates/corpuswitness-gate.py`'s `claim` **ROW **IS **NO **LONGER **A **LITERAL** (`c22292d4f`): **IT **IS **THE
  **CONJUNCTION **OF **FOUR **ROWS **THE **GATE **ALREADY **EMITS**, **AND **A **WITNESS **SAYING `repro-rc=rc=0` **AND **ONE
  **SAYING `rc=1` **NOW **PRODUCE **DIFFERENT **ROWS** (`verdict.reported` TOO, `9c66365b7`).** **A **ROW **THAT **CANNOT
  **GO **RED **IS **WORSE **THAN **NO **ROW** -- `differ.py`'s **OWN **PLANT **3: "if it does not go red, the row is a
  label."***
  **AND: **THE **REACHABILITY **CENSUS, **RE-MEASURED **2026-10-21T20:10Z** (`gates/reachability-gate.py`)** --
  **`.github/workflows/` **HAS **10 **FILES **AND **1 **NAMES **A **GATE** (`edge-gates.yml` -> `gates/edge-runner.py`)**,
  **`.git/hooks/` **HAS **14 **FILES **AND **0 **NON-`.sample`**, **`core.hooksPath` **IS **UNSET**, **AND
  `gates/artifacts/` **IS **GITIGNORED** (`.gitignore:214`)**. ***BUT **THE **OLD **"0 **REACHABLE" **READING **WAS
  **A **COUNT **OF **A **DIFFERENT **THING**: **THERE **ARE **321 **GATES** (DISCOVERED, **NEVER **LISTED**), **20 **ARE
  **REACHABLE** -- **ALL **20 **OFF **ONE **WORKFLOW** -- **AND **73 **CHAINS **END **IN **NOTHING**, **A **GATE **NAMED
  **ONLY **BY **AN **UNREACHABLE **GATE** **IS **STILL **UNREACHABLE**.**  **AND **`gates/edge-trace.rows` **IS **IN **GIT
  **AND **HAS **21 **ROWS** (20 **SAY `RAN`**) **AT `HEAD=7f3ba0875` -- **AND **IT **SAYS **10 **OF **22 **GATES **ARE
  **`DEAD`**, **AND **SEVEN **OF **THEM **RUN **NOW** -- **SO **THE **TREE's **ONLY **RECORD **OF **WHAT **RUNS **IS
  **STALE, **AND **IT **IS **A **DATED **RECORD **THAT **NAMES **ITS **HEAD**.**  **THE **DIFFERENCE **BETWEEN **"NOBODY
  **ASKED" **AND **"NOBODY **WAS **TOLD"** IS **A **TRACE, NOT **A **VERDICT** -- **AND **THE **TRACE **IS **NOW **A
  **GATE** THAT **REFUSES **WHEN **THE **WIRING **IS **GONE**, **SO **"NO **GATE **IS **RUN" **AND **"ALL **GATES **ARE
  **RUN" **CANNOT **LOOK **THE **SAME**.***
  **AND **THE **INDEX **IS **STILL **ARMED** (8958 `ls-files` **AGAINST **8977 `ls-tree`**) **AND **A **STALE **BLOB **IS
  **INVISIBLE **TO **A **COUNT** -- **SO **`gates/indexstale-gate.py` **NAMES **THE **8 **PATHS **WHERE **THE **INDEX
  **AND **HEAD **SHARE **A **PATH **AND **DISAGREE **ABOUT **ITS **BYTES**, **AND **A **BARE **`git commit` **WOULD **REVERT
  **THEM**.** **THE **INDEX **WAS **NOT **REPAIRED** -- **AND **EVERY **COMMIT **IN **THIS **SESSION **WENT **THROUGH **A
  **PRIVATE **ONE**.**
  (`D0-repro.txt` mtime **`Oct 21 23:31`**, **THE **RUN **OF **2026-10-21T20:31Z**). **EVERY GRAPH IN THE 34 IS
  BYTE-IDENTICAL, AND THE VERDICT **REPRODUCES** — **WHICH ARE **TWO **DIFFERENT **CLAIMS** AND **ONLY THE
  SECOND **IS **PROVEN.** **ALL **THREE **MALFORMED **TREES **ARE **ORPHANED** AND **ALL **THREE **ARE **NAMED**:
  `d57bc484` (**UNOWNED** — **AND **IT **IS **THE **ONE **THIS **FILE **NAMED **ONLY **BY **COUNT**, **WHICH **TWO
  UNITS **REPORTED **AS **A **GAP **INDEPENDENTLY** — **A **CENSUS **THAT **RECORDS **A **COUNT **WITHOUT **THE
  NAMES **IS **NOT **A **CENSUS**), `d83cf685` (OWNED BY `591f6b499`), `3a60f33f` (OWNED BY `63b64ebad`);
  **NONE IS AN ANCESTOR OF HEAD**, **SO A PUSH OF HEAD WOULD NOT
  CARRY THEM.** **AND `git diff HEAD` IS **UNRELIABLE **ON **THIS **TREE** **RIGHT **NOW**: THE ARMED INDEX
  LISTS FRESH FILES AS DELETIONS, SO IT REPORTED **120** DELETIONS ON A FILE WHOSE `git hash-object`
  **EQUALS `HEAD:`** — **USE `git hash-object` vs `git rev-parse HEAD:<path>`, AND `git show --stat`,
  WHICH **HOLD.** **See `checks/README.md` and `.agents/slop/difftxt/`.
- `e2e.py` — **the SEVEN-stage end-to-end gate**, and `e2e.sh` beside it. Do not rewrite it to tidy it.
  **NEVER RUN ON THE REAL TREE.** Stages 2-7 need `bend`, `node` and `cc`, so **run it with nothing else
  compiling**, and under the sum-precondition above.
  **WHAT IS TRUE AS OF 2026-10-19 (`212f1443`), ALL OF IT MEASURED:**
  - **THE GATE HAS **NEVER** BEEN RUN ON THE REAL TREE.** Every stage verdict in this file is from a transcript, and
    the one on disk is **OLD — READ **ITS **MTIME**, **NOT **A **DURATION**: A **DURATION **IN **PROSE **ROTS **HOURLY
    WHILE **THE **REST **OF **THE **SENTENCE **STAYS **TRUE**, **AND **THIS **SENTENCE **HAD **ONE** (`.agents/slop/e2epy/artifacts/live.port.out`, mtime **`Oct 7 23:25`**).
    ***AND IT **IS **NOT **GITIGNORED** — ONLY `runs/` **IS** (`.gitignore:262`) — **SO `git status` **WOULD **HAVE
    SHOWN **IT **CLEAN **AND **PROVED **NOTHING**.** THE **MTIME **IS **THE **PROOF.**
  - **`.agents/slop/ops_bend-milestone-expected.txt` **DOES **NOT **EXIST** — IT **WAS **RENAMED **TO **`.md`**, AND
    THE LOADER **NOW **RESOLVES **IT **BY **STEM** (`ops_bend-milestone-expected`), NOT BY EXTENSION: **A
    `.txt`-THEN-`.md` FALLBACK **IS **A **HAND **LIST**. **`runtime/dtype.js` **IS **ABSENT **FROM **`tinygrad/runtime/`**
    **— **AND **THAT **QUALIFICATION **IS **THE **WHOLE **POINT**: **`tinybendygrad/runtime/dtype.js` **EXISTS** (8,884 B,
    **IN HEAD**), **AND **AN **UNQUALIFIED **"**ABSENT **ENTIRELY**" **IS **READ **AGAINST **THE **DIRECTORY **THAT **HAS
    **IT**; **ALWAYS **QUALIFY **THE **TREE.** `cdp.mjs`'s counterpart **IS **ALSO **ABSENT**. **THE "**BOTH EXIST**"
    **CLAIM **WAS **FALSE **ON **BOTH **COUNTS.**
  - **STAGE 7 **SKIPS** BECAUSE `run-f64.sh` REFUSES A COLD SUBSTRATE. **IF **THAT **IS **STILL **TRUE**, THE GATE
    EXITS **4**, **NOT **0** — **AND **THAT **IS **THE **GATE **BEING **HONEST, NOT **A **DEFECT **TO **HIDE**;
    `AGENTS.md`'s OWN RULE SAYS A `SKIP` **IS **NOT **A `PASS` **AND **THE **EXIT **STATUS **SAYS **SO.** **DO **NOT **
    REPORT **HOW **TO **MAKE **IT **GREEN.**
  - **STAGE 8 **IS **RETIRED** AND `verdicts.py` **MEASURES **`PROSE 7 live: 1..7 | 1 RETIRED: 8`** — **SO **THE
    `PROSE names [0] the CODE does not emit` **DEFECT **THIS **PARAGRAPH **USED **TO **CITE **WAS **REPAIRED **ON
    2026-10-15** (`verdicts.py:39-46`), AND **THE `rc=1` **IS **NOW **ENTIRELY **DENOMINATOR**, NOT PROSE.**
  - **`BODY_SHA` IS **A **CONTENT **PIN, NOT **A **BEHAVIOUR **CLAIM**, **DECLARED **AS **SUCH **IN **THE **FILE**
    (`checks/e2e.py`) — **BECAUSE **A **HASH **OF **A **WHOLE **FILE **CANNOT **TELL **A **COMMENT **FROM **CODE**,
    **AND **A **COMMENT-ONLY **EDIT **HAD **STOPPED **THIS **GATE **FROM **STARTING.** **ITS **REMEDY **IS **THE
    RULE: **MOVE **THE **PIN **IN **THE **SAME **COMMIT**, **DECLARE **THE **DELTA **IN `ORACLE_EDITS`, **AND **KEEP
    THE **THREE **PLANTS **FIRING.** **A **BARE **RE-FREEZE **WAS **MEASURED **INSUFFICIENT** — **IT **MOVES **THE
    COMPLAINT **FROM **CHECK **3** TO **CHECK **2.**
  - **AND **THE **DEFECT **THE **CENSUS **COULD **NOT **SEE, WHICH **IS **THE **GENERAL **FORM:** **`.agents/slop/e2e_port/run-port-mm.sh:107`
    EMITS `== 6/6` **AND `.agents/slop/f64/run-f64.sh:78` EMITS `== 7/7`.** ***SO **A **STAGE's INNER LANE **PRINTS
    A `== n/m` BANNER **AT **ALL**, **WHICH **RE-OPENS **STAGE 6 **IN `.agents/slop/e2estage8/verdicts.py:75 blocks()`** --
    ***AND **A **RE-RUN **WILL **NOT **GO **GREEN **UNTIL **THOSE **TWO **ARE **MOVED.** ***THE **OPEN **QUESTION
    IS **WHETHER **A **STAGE's INNER LANE **MAY **PRINT **SUCH **A **BANNER** — **AND **NO **INSTRUMENT **IN **THE
    TREE **NOTICES **THAT **A **COMPARISON **ARTIFACT **IS **OLDER **THAN **THE **CODE **IT **COMPARES.**
- `checks/no-txt.py` — **THE RULE IS REAL; THE CLAIM "there is no `.txt` file in this project" IS NOT.
  IT EXITS 1 AT 2026-10-06 13:00 WITH **550 HARD AND 139 EXCUSED (689 OWNED)** — AND THAT NUMBER MOVES, SO IT CARRIES THE READING
  THAT PRODUCED IT — AND IT PRINTS A SAMPLE AND THEN
  it prints 40 paths and then `... and 510 more`, SO IT DOES NOT "PRINT EACH PATH" EITHER.** `.rows` is expected values,
  `.out`/`.err` are captured streams, `.tsv` is tabular, `.md` is prose. See Development, above.
- `checks/substrate-check.sh` — import-graph and cold-file sweep over the `.bend` tree. **THE BARE NAME
  `substrate-check.sh` RESOLVES TO NOTHING: `command -v` is absent and there is no root-level file. The real gate
  is a 46-line shim onto `.venv/bin/python checks/substrate.py` (**766 lines at 13:00, 841 at 13:03 —
  it was 765 when written; the file is being edited live**).**
- `gates/*.py` — per-def gates, and they are **Python, never shell** (measured 2026-10-07: 56 `.py`, 0 `.sh`; `ls gates/*.py | wc -l`).
  A gate names its `.bend` driver and its CPython oracle; its OUTPUT goes to `gates/artifacts/`.
  **BUT DO NOT PUT A GATE'S INPUTS UNDER `.agents/slop/`. THAT PRESCRIPTION IS WHAT DELETED THEM.**
  `.agents/slop/` is being pruned and it holds no protection: `checks/sb-gate.sh:76` now reads its
  baseline from the GIT-TRACKED `oracles/schedule-bodies/BEFORE-rows.rows`, but it still `exit 3`s —
  **the CPython oracle `.agents/slop/schedule-bodies/sb-oracle.py` is absent (measured 13:02)** — and
  `e2e.py:99`
  now calls that defect **REPAIRED**: the fixture is recovered from git to the tracked
  `gates/cstyle-live.rows` (`e2e.py:99-106`) — **stage 7 SKIPs on a COLD SUBSTRATE, not on the fixture.**
  **RE-MEASURED RULE AND ITS NUMBERS (2026-10-07): of the **333** distinct paths `.agents/TOOLS.md` names, **164 are present and
  **THE DENOMINATORS BELOW ARE THE **2026-10-07** READING AND **BOTH MOVED**; RE-DERIVE THEM** — **gone** now
**179**, **85 of those under `.agents/slop/`** (**THE ONLY FIGURE THAT DID NOT MOVE**), and **6 of the gone are INSTRUMENTS
BY `extract.py`'s LEXICAL `kind()`** — **DOWN FROM 16, AND THAT IS A **CLASSIFIER** CHANGE NOT A **RECOVERY**: a rule's
 would-be
  enforcer** (`.agents/slop/toolsledger/extract.py` regenerates this). **BY CONTENT IT IS **14**, NOT 16:
`lostinst` VERIFIED 14 — **13 RECOVERABLE** (every restore `git cat-file blob` non-empty, 110 B – 23,711 B, all 14
distinct) AND **1 GONE: `.agents/slop/xd1/mutate.py`** — NO BLOB IN ANY REF, AND ALL 75,336 HISTORY PATHS CONTAIN NO
`xd1/mutate.py`. THE OTHER TWO ARE CLASSIFIER ERRORS: **`xd1/pin` IS A REVISION REFERENCE** (WHICH `git cat-file -t`
ANSWERS AS `commit`) AND **`runs/elf-checkonly-2026-10-04.txt` IS A
CAPTURED STDOUT** (110 B of `ALL PROOFS CHECK`). **A BASENAME REGEX MATCHED THE WORD `pin` AND THE SUBSTRING `check`,
WHICH IS DOCTRINE 1's FAILURE REPRODUCED INSIDE THE CENSUS OF DOCTRINE 1.** **AND ALL 16 APPEAR **ONLY** UNDER
`extract.py`'s RULE A: EVERY EXTENSION-GATED RULE DROPS `xd1/pin`, BECAUSE IT HAS NO EXTENSION — **THE SAME STRUCTURAL
BLINDNESS ONE LEVEL DOWN.** **A GATE'S
  REQUIRED INPUT BELONGS BESIDE THE GATE **IN GIT** — AND NOT IN `gates/artifacts/`, WHICH THIS LINE USED TO
  RECOMMEND. THAT DIRECTORY IS `.gitignore`d **AND** IS WHERE GATE RUNS WRITE, SO ONE `rm -rf gates/artifacts`
  DELETES ANYTHING KEPT THERE AND GIT CANNOT RESTORE IT. MEASURED: `e2efix` RESTORED STAGE 7's DELETED FIXTURE
  THERE AND IT WAS **GONE** ON THE NEXT READ; IT NOW LIVES AT THE TRACKED `gates/cstyle-live.rows`.** **A PATH INSIDE
  A SWEPT TREE IS DELETABLE WHILE THE GATE STILL NAMES IT, AND SO IS A PATH INSIDE A GITIGNORED OUTPUT DIRECTORY.**
**AND `jj git colocation` ARMS GIT's INDEX BY DESIGN, MEASURED IN ISOLATION WITH NO OTHER PROCESS PRESENT:** create an
  untracked file, run `jj status`, and `git ls-files -s -- <it>` answers `e69de29b` — git's EMPTY blob — with
  `git status --porcelain=v2` reading `1 .A N...` and **`git diff --cached` NAMING NOTHING**. `jj util snapshot` does the
  same, and that is the command the VisualJJ branching server issues on its own. **MEASURED ON THIS TREE: `882` such
  placeholders, `7.9 MB` across `149` owner directories, and `git diff --cached` STILL NAMES `0`.** **A BARE `git commit`
  OVER AN INTENT-TO-ADD IS NOT A DESTRUCTION, IT IS WORSE — IT COMMITS THE PREVIOUS CONTENT** (isolated: bare → `28` B
  of base, `git commit -a` → `31` B of live); **THE HAZARD IS SILENT REVERSION, NOT AN EMPTY BLOB.** **`jj` **IS **NOT
  READ-ONLY **HERE, **AND **`jj status` **IS **ONLY **THE **COMMAND **I **HAPPENED **TO **NAME**: **IT **CLEARED **ANOTHER **UNIT'S **STAGED
  **WORK **AT **`01:55:39Z`** (`jj op log`: `import git head` + `snapshot working copy`, both `args: jj status`), **AND **A **SECOND **UNIT
  **PROVED **THE **HAZARD **IS **`jj` **GENERALLY **— **ITS **LAST **OP **IS **LITERALLY **`snapshot working copy, args: jj op log`**,
  **SO **A **DOCUMENT **THAT **NAMES **ONE **COMMAND **WHILE **MISSING **THE **MECHANISM **IS **A **CITATION **OF **AN
  **INCIDENT, **NOT **OF **A **CAUSE** — **THE **MECHANISM **IS **THAT **`jj` **COLOCATED **STAGES **INTO **GIT's **INDEX
  **ON **WORKING-COPY **SNAPSHOT, **AND **EVERY **`jj` **SUBCOMMAND **THAT **SNAPSSHOTS **DOES **IT**.** **COMMIT THROUGH A
  **PRIVATE INDEX — `GIT_INDEX_FILE=.git/agent-index-<unit>` — NEVER `git add -A`** — **AND
  `GIT_INDEX_FILE` DOES **NOT** SURVIVE BETWEEN SHELL CALLS, WHICH IS HOW ONE COMMIT SILENTLY NO-OP'D.**
  **THE OLD LINE NAMED **ONE** SHARED PATH FOR EVERY UNIT, AND A SHARED PATH IS THE SHARED STATE.
  **`<unit>` MUST BE A STRING **YOU CHOOSE ONCE** AND REUSE IN **EVERY** COMMAND OF **EVERY** STEP, AND IT
  **CANNOT BE `$$`** -- **MEASURED 2026-10-17: `$$` IS **THE SHELL's** PID AND **CHANGES EVERY CALL**, SO
  `agent-index-$$-<boottime>` IS **A DIFFERENT PATH EVERY TIME**.** A UNIT FOLLOWED THE *LETTER* OF THE
  PREVIOUS WORDING -- `GIT_INDEX_FILE` SET IN EACH COMMAND, AS IT SAYED -- **AND SPLIT `read-tree` +`git add`
  (CALL **1**) FROM `git commit` (CALL **2**), **SO THE SECOND INDEX WAS EMPTY AND THE COMMIT CARRIED **7 533
  FILES / 2 555 203 DELETIONS**. REPAIRED WITH `git reset --soft HEAD~1`; `HEAD:tinygrad` MATCHED `upstream`
  AGAIN AND **141** `.bend` FILES WERE NEVER TOUCHED.** **SO THERE ARE **TWO** INDEPENDENT REQUIREMENTS AND THE
  OLD WORDING STATED **ONE**: **(a)** SET `GIT_INDEX_FILE=` **IN THE SAME COMMAND** (FOR THE PREFIX), **AND
  (b)** THE ***VALUE*** **MUST BE BYTE-IDENTICAL ACROSS EVERY COMMAND** -- **WHICH NO `$$`-BASED FORM CAN BE,
  AND WHICH THIS DOCUMENT **NEVER SAID.** USE A NAME YOU PICK, OR A SESSION ID, AND PASTE THE **SAME** ONE
  EVERY TIME. **THE UNIQUENESS HALF IS STILL RIGHT: `kern.maxproc` IS `4000` SO **A PID ***ALONE*** REPEATS
  ACROSS RESTARTS** AND A LATER UNIT WOULD INHERIT A DEAD UNIT's INDEX; `kern.boottime`'s `sec` READS
  `1792006632` AND IS CONSTANT FOR THE LIFE OF THE BOOT. ALSO `awk '{print $4}'` YIELDS IT **WITH A ***TRAILING
  COMMA***, SO `tr -d ','` MATTERS.** **IF THE PATH ALREADY EXISTS, **DO NOT REUSE IT AND **DO NOT `rm` IT** --
  A FILE THAT EXISTS MAY BE A **LIVE** UNIT'S, AND DELETING IT IS THE SAME SHARED-STATE FAILURE ONE LEVEL DOWN:
  **APPEND `-2`, `-3`, ... AND RETRY.**
  **AND `git show --stat` IS **STILL** THE CHECK -- RUN IT **IN THE SAME COMMAND**,
  BECAUSE THE NEXT COMMIT OVERWRITES `HEAD` AND THE CHECK IS GONE.**

  **AND ON 2026-10-22 THE HAZARD FIRED ON THE ORCHESTRATOR, AND THE PRESCRIPTION ABOVE IS
  **MEASURED** TO BE **THE UNSAFE FORM** -- SO HERE IS THE CORRECTION, AND IT IS THE THIRD
  INDEPENDENT CONFIRMATION OF `--only` THAT THIS FILE ALREADY CARRIES.** MEASURED WITH
  `.agents/slop/idxrace/idxrace.py` (Python, throwaway repo, the race INJECTED IN EVERY TRIAL,
  40 trials per recipe, the other unit PATHPEC-SCOPED): **RECIPE A -- `PARENT=$(git rev-parse
  HEAD)` THEN `git read-tree "$PARENT"` THEN `git add` THEN `git commit`, WHICH IS WHAT THE
  PARAGRAPH ABOVE DESCRIBES -- SWEEPS **40 OF 40****, with a real `DELETED d.txt` AND a real
  `REVERTED b.txt`; **RECIPE B -- RE-SEED FROM THE CURRENT `HEAD` IMMEDIATELY BEFORE `git add`,
  AND RE-SEED AGAIN IF `HEAD` MOVED -- SWEEPS **0 OF 40**; RECIPE C -- **NO SEED AT ALL**,
  `git commit --only -m "msg" -- <path>` -- SWEEPS **0 OF 40** FOR A **TRACKED** PATH. **THE
  CAPTURE IS THE DEFECT, NOT THE `read-tree`**: A PARENT
  CAPTURED IN AN EARLIER COMMAND AND USED LATER IS A **STALE TREE**, AND ANOTHER UNIT'S COMMIT
  IN THE GAP TURNS IT INTO **866 DELETIONS ACROSS 5 PATHS -- INCLUDING
  `tinybendygrad/device.bend` (441 LINES, A SUBSTRATE FILE) AND THREE
  `.agents/slop/linkbuf/` TOOLS** -- WHICH IS EXACTLY WHAT HAPPENED TO THE ORCHESTRATOR'S OWN
  COMMIT `64169355a` ON 2026-10-22. **`git show --stat` CAUGHT IT AND THE CONCURRENT SESSION
  RE-LANDED IT ON TOP (`4f189e21c`) WITHOUT BEING ASKED, SO NOTHING WAS LOST -- BUT THE
  PRESCRIPTION THAT PRODUCED IT IS STILL WRITTEN DOWN HERE.** **SO: PREFER
  `git commit --only -m "msg" -- <path>`. IT IS BOUNDED BY CONSTRUCTION -- THE PATHSPEC IS THE
  BOUNDARY -- IT NEEDS NO INDEX SEED, AND THEREFORE IT HAS NO WINDOW TO LOSE.** **AND IF YOU
  MUST SEED: RE-SEED FROM THE CURRENT `HEAD` AND RE-CHECK, AND KNOW THAT IT CAN STILL REFUSE,
  WHICH IS SAFE BUT USELESS.**
  **⚠ AND `--only` **REFUSES** A **NEW (UNTRACKED) PATH** ON **THIS **GIT** -- MEASURED 2026-10-22 on
  **git 2.50.1 (Apple Git-155)**, IN A THROWAWAY REPO: `git commit --only -m "new" -- NEW.txt` ANSWERS
  **"pathspec 'NEW.txt' did not match any file(s) known to git"**, **rc=1** -- **SO THE "0 OF 40 ON A
  NEW FILE TOO" HALF OF RECIPE C **DID **NOT **REPRODUCE**, AND THIS FILE SAID IT DID.**  **THE
  FIX IS A **BOUNDED** `git add -- <the new path>` **FIRST**, AND THEN THE `--only` FORM: MEASURED, THE
  COMMIT THEN CARRIED **EXACTLY 1 FILE** AND **15 FOREIGN STAGED FILES WERE STILL STAGED AND
  UNTOUCHED.**  **AND **THE **PRIVATE-INDEX **FORM **ARMS **THE **SHARED **INDEX **AGAINST **THE **NEW
  **FILES** -- MEASURED 2026-10-22: WITH A **PRIVATE** INDEX THE NEW FILES LAND IN HEAD BUT **NOT** IN
  THE SHARED INDEX, **AND A BARE `git commit` **BY **ANOTHER **UNIT **WOULD **THEN **DELETE **THEM**.**  **SO
  FOR A **NEW** FILE: **`git add -- <path>` **ON **THE **SHARED** INDEX, **THEN
  `git commit --only -m "msg" -- <path>`.**  FOR A **TRACKED** FILE: **`--only` **ALONE, **AND **THE
  **PRIVATE** INDEX **IF** YOU **CANNOT **USE **THE **SHARED **ONE**.** **AND TWO SPELLING TRAPS THAT MADE MY OWN MEASUREMENT VACUOUS
  FIRST: `git commit --only -- <path> -m "msg"` PUTS `-m` AFTER `--`, SO `-m` IS READ AS A
  **PATHSPEC** AND THE COMMIT **NEVER HAPPENS** -- WHICH READS AS A CLEAN PASS BECAUSE THE
  OTHER UNIT'S COMMIT IS THEN `HEAD`; AND **A RECIPE MEASUREMENT MUST ASSERT THAT THE COMMIT IT
  IS MEASURING LANDED**, BECAUSE A COMMIT THAT DID NOT HAPPEN IS A **REFUSAL**, AND A REFUSAL
  IS A DIFFERENT CLASS.** **NEVER `git add -A` -- MEASURED HERE AGAIN: IT PUTS ANOTHER UNIT'S
  WORK INSIDE YOUR COMMIT.  **⚠ AND `git add <dir>` **IS **THE **SAME **HAZARD **WITH **A **PATH**:
  MEASURED 2026-10-22, I **DID `git add checks/`** TO LAND THE TREE's OWN PUBLISHED INSTRUMENT
  OUTPUTS, **AND **IT **SWEPT **IN **SIX **FILES **THAT **WERE **NOT **INSTRUMENT **OUTPUTS** -- **FOUR
  `checks/.tmp-*.py` **STAGING **COPIES **OF **OTHER **GATES** (which **is **the **worst **kind **to
  **commit: **A **FILE **THAT **LOOKS **LIKE **THE **THING **IT **SHADOWS**), **PLUS **A **`.err` **AND **A
  **`.out`.**  **⇒ THE RULE **IS **"**STAGE **BY **PATH**", **AND **NOT **"NEVER `git add -A`"** -- a
  **DIRECTORY **IS **NOT **A **PATH**.**  **AND **THE **HOLE **IS **CLOSED**: `.gitignore` **NOW
  **COVERS **`checks/.tmp-*`, **`checks/*.out` **AND **`checks/*.err`**, **SO **THE **NEXT **`git add
  checks/` **CANNOT **SWEEP **THEM **AGAIN.**
  **AND NOW ***ALSO*** RUN `git fsck --no-progress`, BECAUSE `--stat` **CANNOT** SEE A MALFORMED COMMIT AT ALL.**
  **AND A **SCRIPT **THAT **OTHERS **ARE **EXECUTING **IS **SHARED **STATE **TOO**, **AND **EDITING **IT
  **IN **PLACE **IS **THE **HAZARD** -- MEASURED 2026-10-22, **AND **I **CAUSED **IT**: I edited
  **`checks/bendlock.sh`** IN PLACE WHILE A UNIT WAS RUNNING IT, **AND **A **SHELL **READS **A **SCRIPT
  **BY **BYTE **OFFSET**, **SO **THE **OTHER **UNIT's **SHELL **RESUMED **MID-LINE **AND **RAN `st.`
  **INSTEAD **OF `stat`** -- ITS **FIRST **VERIFY **RUN **DIED **WITH **EXIT **127 **AND **A **PLANT
  **REFUSED **FOR **A **REASON **UNRELATED **TO **THE **SUBSTRATE**.  **THE **CLASS **IS **THE **INDEX's
  **CLASS: **A **PATH **THAT **OTHERS **TOUCH **IS **A **SHARED **PATH**, **AND **THE **INDEX's **RULE
  **IS **THE **RULE** -- **DO **NOT **TOUCH **A **PATH **OTHERS **HOLD**.  **A **FILE **THAT **OTHERS
  **ARE **EXECUTING **IS **A **PATH **OTHERS **HOLD**, **AND **THE **SAFE **FORM **IS **TO **WRITE **A
  **NEW **PATH **AND **LEAVE **THE **OLD **ONE **ALONE**.**
  **MEASURED 2026-10-17, AND IT IS THE ONE CHECK EVERY UNIT IN THIS SESSION MISSED:** **A PUSH OF THIS TREE FAILED
  WITH `remote: error: object d83cf685…: duplicateEntries: contains duplicate file entries` / `remote: fatal:
  fsck error in packed object` / `remote unpack failed` -- A COMMIT WHOSE TREE LISTED **`gates` TWICE**.** IT WAS
  THE **435-FILE ARMED-INDEX SWEEP**, IT WAS AN ANCESTOR OF `HEAD`, **AND EVERY LOCAL COMMAND READ IT AS FINE.**
  `git fsck --no-progress` NAMES **3** SUCH TREES IN **UNDER A SECOND**, ***AND IT WAS ONLY RUN BECAUSE THE PUSH
  FAILED.*** **`git show --stat` ANSWERS "WHAT CHANGED"; `git fsck` ANSWERS "IS THIS COMMIT ***MALFORMED***" -- AND
  **THE SECOND QUESTION IS THE ONE THAT BLOCKS A PUSH.** **SO: **BOTH**, **IN THE SAME COMMAND**.**
  **AND **A **PRIVATE `GIT_INDEX_FILE` **IS **NOT **ENOUGH**, **MEASURED 2026-10-19, **AND **THIS **CORRECTS **THE
  **RECIPE **ABOVE**: IT **ISOLATES **THE **INDEX **AND **NOTHING **ELSE** — **NOT **THE **WORKING **TREE, NOT **THE
  BRANCH **REF. A **CONCURRENT **UNIT **REVERTED **ANOTHER **UNIT's **WORK **TWICE**, AND **THE **REFLOG **IS **THE
  PROOF:**
```
73e431d73  unit A: the fix (+77/-12)
d87584cdf  unit B: lands e2e.py/e2e.sh at their PRE-73e431d73 bytes
383a8e5e6  unit A: restore
reset HEAD~1   unit B: drops the restore
f09f490e  unit A: re-land
reset -> 383a8e5e6   unit B: resets back ONTO the restore commit
```
  **AND `git diff --stat <before> d87584cdf -- checks/e2e.py checks/e2e.sh` IS **EMPTY** — **SO `d87584cdf` **IS **A
  PURE REVERT CARRYING NONE OF ITS OWN EDITS: **THE DOCUMENTED HAZARD** — *"A COMMIT CARRYING A STALE INDEX WRITES THE
  PREVIOUS CONTENT, AND THE SYMPTOM IS SILENT REVERSION."* **SO **THE **CONTROL **IS **NOT **"USE **A **PRIVATE INDEX":
  IT IS **"**AFTER **EVERY **COMMIT **BY **ANY** UNIT**, **CHECK `git show --stat` **FOR **THE **FILES **YOU **CARE
  ABOUT**, AND **IF **YOUR **BYTES **ARE **GONE**, **RE-LAND **ON **TOP** — **NEVER `reset` **SOMEONE **ELSE's COMMIT
  **AND **NEVER **REBASE**."** ***AND `f09f490e` **WAS **LEFT **AS **A **DANGLING **BYTE-IDENTICAL **DUPLICATE, WHICH
  IS **THE **CORRECT **OUTCOME: **A **RE-LAND, NOT **AN **AMEND.****
  **WHY THE PRIVATE INDEX, MEASURED 2026-10-17 IN A THROWAWAY REPO (`.agents/slop/idxpriv/`), NOT ON REAL
  WORK: `--only` IS **ALREADY BOUNDED**, AND THE FIX IS **NOT** ABOUT CONCURRENCY.** **`--only` CARRIED
  **EXACTLY ONE PATH** AGAINST **EVERY** SHAPE `checks/index-arm-gate.py` NAMES — `FOREIGN-ADD`, `DELETION`,
  `STALE` AND `INTENT` — **4 of 4 BOUNDED** (`contam.py`); **36 CONCURRENT ONE-PATH COMMITS THROUGH **ONE**
  SHARED INDEX SWEPT **0** (`race.py`, `12` TRIALS × `3` UNITS); AND `22` `--only` COMMITS UNDER A
  CONCURRENT INDEX WRITER SWEPT **0** (`route.py`). **SO **THE **ONLY **ROUTE **MEASURED **THAT **SWEEPS **IS
  **A **COMMIT **WITH **NO **PATHSPEC**: `route.py` `BARE` **CARRIED 19 PATHS** — **9 FOREIGN ADDS + 9
  DELETIONS + ITS OWN 1 — WHICH IS THE ARITHMETIC OF THE `591f6b499` OUTAGE (`252` + `182` + `1` = `435`),
  SO THE PATHSPEC IS THE BOUNDARY AND A SHARED INDEX IS WHAT PUTS ANOTHER UNIT'S WORK **INSIDE** IT.**
  **THE FIX, MEASURED: TWO UNITS, SAME REPO, SAME LOST PATHSPEC, THE **ONLY** DIFFERENCE BEING WHETHER THEY
  SHARE ONE INDEX FILE — `ISOLATED shared`: MY BARE COMMIT CARRIED **9** OF THE OTHER UNIT's PATHS;
  `ISOLATED private`: **0**.** **AND THREE CONCURRENT COMMITS THROUGH THREE PRIVATE INDEXES, EACH NAMING
  ONE DISTINCT PATH, EACH INDEX DELIBERATELY CONTAMINATED WITH `7163` OF HEAD's OWN PATHS FIRST, LANDED
  THREE COMMITS THAT `git show --stat` READS AS **`1 file changed`** EACH (`three.py`, commits `311e47657`,
  `271cfdca6`, `4014b7857`).**
  **AND THE COST OF THE OLD PRESCRIPTION, MEASURED OVER THE `62` COMMITS OF 2026-10-17: `35` WERE ONE-PATH
  AND `27` MULTI-PATH, AND OF THOSE `27` **`25` CARRY `46` PATHS OR FEWER** — SO `60` OF `62` COMMITS
  (**`97%`**) WERE BOUNDED AND EXACTLY **`1` IN `62` (`1.6%`)** SWEPT (`591f6b499`, repaired by `02329daf`).
  **SO THE PRESCRIPTION WAS **NOT WRONG**, IT WAS **INCOMPLETE**, AND THE MISSING HALF WAS **NOT** THE
  CONCURRENCY CLAUSE `a2da165` RECORDED: `race.py` MEASURED THAT CLAUSE **UNSUPPORTED** (`0` SWEEPS IN `36`
  SHARED-INDEX CONCURRENT COMMITS). THE MISSING HALF WAS **THAT NOTHING CHECKED `--stat`.**
  **THE CLASS IS **A **SHARED **WRITABLE **PATH **NAMED **IN **AN **INSTRUCTION**, AND THE INDEX IS **ONE**
  INSTANCE, **MEASURED 2026-10-17: `AGENTS.md` ITSELF NAMES **THREE** MORE — `.agents/slop/` (LINE 21, "ALWAYS
  PLACE THEM UNDER"), WHICH TWO UNITS **DO** SHARE (`git log --since=2026-10-16 --name-only` COUNTS **3**
  COMMITS ON `.agents/slop/unrunnable-recipes/REPORT.md` AND `2` EACH ON TWO OTHERS); `.agents/TODO.md`
  (LINE 23), THE **HIGHEST-TRAFFIC SHARED FILE IN THE TREE** AT **`61` OF `131` COMMITS** SINCE 2026-10-16
  (`18 928` LINES); AND `gates/artifacts/<name>/` (LINE 132), WHICH IS `.gitignore`d AND WHOSE SHARED KEY IS
  **THE `name` THE GATE PASSES** (`gates/gatekit.py:392`, `self.dir = ART / name`) — **SO TWO GATES DECLARING
  ONE `name` SHARE ONE DIRECTORY, AND I DID NOT FIND A MEASURED DUPLICATE: MY ONE ATTEMPT TO FIND ONE
  RETURNED A FALSE POSITIVE BECAUSE **MY OWN** NAME-NORMALISATION COLLAPSED `state_census-gate` INTO
  `state_census`, WHICH ARE **TWO DIFFERENT GATES WITH **TWO** DIFFERENT DIRECTORIES. A NEGATIVE RESULT IS A
  RESULT. `checks/index-arm-gate.py` ANSWERS "IS THE DEFAULT INDEX ARMED?" FROM `git ls-tree -r HEAD` VERSUS `git ls-files`, IS `PASS 0`
  DISARMED / `REFUSED 3` ARMED (AN ARMED INDEX IS NOT A WRONG TREE, IT IS A WRONG TOOL), AND DOES **NOT** MODIFY
  `.git/index`.** **AND IGNORED IS NOT UNTRACKED: MEASURED `28,554` IGNORED AGAINST `27` UNTRACKED-NON-IGNORED IS
  ~`1057`:1, SO `git ls-files --others --exclude-standard` — THE ONLY CORRECT "WHAT DOES NOTHING OWN" QUESTION — ANSWERS
  ALMOST NOTHING, AND ANY SWEEP THAT TRUSTS IT REPORTS A CLEAN TREE.**
  The shared plumbing is `gates/gatekit.py` and it holds nothing but the three lanes, the row counts
  and the diff — the rows, the divergences and the pins are the gate's own. `gates/README.md` records
  why the shell form is retired, with the four ways a shell gate failed here (`&&` masking a diff
  under `set -e`; an `EXIT` trap returning `rm`'s status; `<( )` not parsing under `sh`; `${=SUB}` never
  expanding and a hash guard comparing `""` to `""`).
- `gates/msgdiff-gate.py` — **a commit MESSAGE against its own DIFF**, the guard `jjreset`'s
  mass-delete gate names as its residual (*it cannot see a wrong message*). It is a gate on
  `gatekit`'s five exits and returns **`REFUSED` (3), not `FAIL`**, when a message claims a
  deletion its diff does not witness; `MESSAGE_DIFF_ACK=` records the explanation and passes.
  MEASURED 2026-10-07: `range --since=2026-10-06T12:00 HEAD` is **147 commits, 146 PASS, 1
  REFUSED**, and the refusal is the one real defect — `00b101574`'s *"Deleted the superseded
  `oracles259/plants.py`"* over an **empty `git diff-tree --diff-filter=D`**, the file present in
  that tree at blob `e6e31707`; `--plant` is six states, `rc=0`. **IT CANNOT SEE A CLAIM THAT NAMES
  NOTHING CHECKABLE** — the relayed `41%`, a dead pid, an invented config key — and it **counts
  pids rather than judging them**, because a pid is a live measurement in an immutable message.
  It is a SEPARATE gate from the mass-delete guard (that one's subject is the DIFF, this one's is
  the MESSAGE; one commit with two subjects cannot say which failed), and the PROSE layer
  (`citeresolve`: 2 448 claims) is a different population for a different instrument. See
  `.agents/slop/msgdiff/REPORT.md`.


## The two doctrines. Everything below is a measured instance, not a principle.


### 1. AN INSTRUMENT DECLARES ITS POPULATION BY DISCOVERY, OR IT IS NOT A GATE

**Six instruments in this repo got this wrong, and one governing document got it wrong too. Every one
of the seven was found in a single session, which is why this section exists.**

| instrument | population was declared by | what it cost |
|---|---|---|
| `checks/sweep.py` `LIVE_UNITS` | was 14 literal directory names — **removed; `:291` records "LIVE_UNITS lived here, a tuple of 14 names. It is gone"** | six FINISHED units held **2,353 of 4,455 files = 53%** of `.slop`, 100% git-tracked, named by nothing. Its own comment: *"A GUARD THAT IS CORRECT EXCEPT FOR THE LAST DISPATCH IS NOT A GUARD, IT IS A COINCIDENCE WITH THE DISPATCH ORDER."* |
| `checks/sweep.py:658` `ORACLE_WORD` | a **basename regex** | **670 of 675** ORACLE files were classified by FILENAME and **5 were named by a live gate**. |
| `checks/differ.py:artefacts_ok()` | was `find -name '*.txt'` | **fixed, and re-verified today**: pointed at an empty directory it now returns **139 `MISSING`**; the glob returned `[]`, and *"the rename only revealed a guard that was never one."* |
| `checks/repro-paths.py:64` `REF` | a five-item **SUFFIX SET**, `(?:sh\|py\|bend\|mjs\|json)` — **fixed 2026-10-15, AND THE FIX WAS RETRACTED IN WHOLE** | **THE `.mjs` REPAIR BOUGHT `6 of 15` `e2e.py` STAGE INPUTS AND MOVED THE TOOL'S OUTPUT BY *EXACTLY ZERO*; THE SET WAS STILL BLIND TO `164` OF THE `715` PATHS THE REPORTS NAME.** AND **IT WAS NOT MERELY BLIND — IT STOPPED AT A *REMEMBERED* EXTENSION, SO A PREFIX OF A PATH WAS READ AS THE PATH, WHICH WROTE FALSE ROWS IN BOTH DIRECTIONS**: `untrack/REPORT.md:142`'s `...cpython-312.pyc` was read as `...312.py` (a DANGLING row for a name that never existed) and `whosecache/REPORT.md:73`'s `gates/tn_graph_census-gate.py.bak` was read as `...gate.py`, **A FILE THAT EXISTS, so a broken reference counted as RESOLVED**. NOW a permissive extraction intersected with `os.path.exists`. **AND ONE LEVEL UP, THE SAME FILE ASKED `git ls-files` — the INDEX — FOR ITS DENOMINATOR while its TEXT came from `git show HEAD:` (MEASURED: `584` under an armed index, `541` under a disarmed one, SAME TREE) and so INHERITED `GIT_INDEX_FILE` — the identical defect to `index-arm-gate`'s false `PASS`.** |
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
| `SPEC`               | 1                | UOp spec validation after rewrites. **STAY AT 1.** Upstream's own CI runs `SPEC=2` on `test/null/`, but MEASURED: `SPEC=1` 70 of 70 program ops (**70 of 77 enum members — THE ENUM IS NOW **75**; THIS IS THE 2026-10-06 READING**) on the 34-graph corpus, read 2026-10-06 14:16 · `SPEC=2` 26 of 77 enum members, 14 of 25 graphs FAIL, exit 1 · `SPEC=3` 0 of 77 enum members, all 25 FAIL — the `SPEC=2` and `SPEC=3` rows are 25-graph readings, STALE now that the corpus is 34 graphs, and re-taking them needs `bend` |
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
