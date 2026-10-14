# `declare` — a walk over tracked `.agents/slop/*/` directories, and what it cannot decide

Measured **2026-10-07T03:11Z** by discovery. Instrument `checks/slop-declare.py` (338 lines);
evidence and plants beside this file. **No commit, no `git add`, no `@`** — so
`.agents/slop/declare/` and `BASELINE.tsv` are **untracked**, and the walk reads `git ls-files`,
so this unit's own directory is not yet in the population it walks. `AGENTS.md`,
`tinybendygrad/`, `checks/no-txt.py`, `gates/` and every other unit's files untouched.

```
.venv/bin/python checks/slop-declare.py            # rc 0  -> declare.out
.venv/bin/python checks/slop-declare.py --baseline # the 48-row baseline, printed, never written
.venv/bin/python .agents/slop/declare/plant.py     # rc 0  -> plant.out, 12 assertions
.venv/bin/python .agents/slop/declare/compare.py   # rc 0  -> compare.out, COMPARE.tsv
```

---

## 0. WHAT THE WALK CANNOT SEE. Read this before the numbers, because the numbers are smaller than they look

**A WALK DETECTS ABSENCE. It cannot author a declaration and it cannot judge one.**
`AGENTS.md` doctrine 1 says an instrument that cannot see its population cannot be wrong because
it cannot be anything; the same is true of one that cannot read what it finds.

1. **IT CANNOT TELL AN ABSENT DECLARATION FROM AN UNWRITTEN ONE.** A `REPORT.md` is a human
   artifact. Turning **48** rows into declarations is 48 decisions, and no walk makes any of them.
   The tool names; a person decides. That is the whole honest ceiling.
2. **IT CANNOT TELL WHETHER A DECLARATION IS TRUE.** `citeresolve` measured **2 448 committed
   prose `<path>:<N>` claims, 165 unresolved and 1 777 never positively checked, including
   essentially every `REPORT.md` written that night.** So a `REPORT.md` is not a checked claim —
   **it is an unchecked one that happens to have a filename.** This walk counting it as "declared"
   is counting a filename, not a fact, and `REPORT.md` is on exactly the same footing as the
   1 777: neither has been positively checked.
3. **IT CANNOT CLASSIFY A DECLARATION BY NAME.** `DECLARATIONS` is a five-name set. §4 measures
   what that costs: **24 of the 48 "undeclared" directories already hold prose under 40 other
   names.** A name set is not a population, and the fix is a rename — never a longer list.
4. **IT CANNOT TELL A MENTION FROM A READER WITHIN CODE.** A `.py` that names a path inside a skip
   list is a citation; `orcdecide` measured exactly this for `plants.py` (3 "readers", 0 opens).
   The walk counts the file and prints nothing about which, so every reader row needs a look.
5. **IT CANNOT SEE UNTRACKED WORK.** It reads `git ls-files`. A `REPORT.md` that was written and
   not `git add`ed leaves the directory **declared in the worktree and undeclared in the census**
   — the same property `orcdecide` relied on when it noted `oracles259/` still counted as
   undeclared because its report was uncommitted. That is correct here (a report nobody committed
   is a report nobody can audit), and it is why this file's own numbers are provisional until
   committed.
6. **IT CANNOT JUDGE THE TRUTH OF WHAT IT PRINTS WHEN THE CLOCK IS DEAD** — see §5, where the
   obvious clock is measured to have **one distinct value**.

## 1. THE CENSUS, AND AGAINST `orcdecide`

Population: `git ls-files`, walked. **No `.agents/slop/*/` directory is named in the instrument.**

| measure | 2026-10-07T03:11Z | `orcdecide`'s own instrument, run now |
|---|---:|---:|
| tracked `.agents/slop/*/` directories | **262** | 261 (it drops itself, by a typed name) |
| DECLARED (`REPORT.md`/`README.md`/`FINDINGS.md`/`MANIFEST.tsv`/`MANIFEST.rows`) | **155** | **154** — the one difference is `orcdecide/` itself, which it excludes |
| UNDECLARED | **107** | 107 |
| UNDECLARED **and** no full-path CODE reader | **48** | 14 |
| … of those, IN PROGRESS (mtime < 24 h) | **13** | not measured |
| … of those, STALE (gated) | **35** | 14 |

**The population is moving.** It read 256, 257, 258, 259, 260, 261, 262 across this session as
units landed directories. `AGENTS.md`: never quote a row count from a job that may still be
running. Every number above carries the timestamp, and every one of them is one `--root` away
from being different.

**`orcdecide` is RIGHT ABOUT THE DECLARATION CENSUS AND WRONG ABOUT THE READER TEST.** Measured
by `.agents/slop/declare/compare.py`, which re-derives `orcdecide/sweep.py`'s own decision
function verbatim — same `KEEP` suffix set, same `SKIP` prefixes, same `big > own` token count,
same typed `("orcdecide",)` self-exclusion — because a comparison that quietly repaired the other
instrument would not be a comparison:

```
DECLARATION census : AGREE 261 of 261 -- the same 261 directories called declared
READER test        : AGREE 183, DISAGREE 78  (29% of the tree)
  of the disagreements, UNDECLARED here and "referenced" by orcdecide : 34  <-- the 14 -> 48 delta
  of the disagreements, DECLARED either way (count unaffected)          : 44  <-- same fault, invisible
UNDECIDED          : orcdecide 14, here 48;  orcdecide's set is a SUBSET of mine: True
```

**Why mine is right and `orcdecide`'s is not, and the cost of getting it wrong.** `orcdecide`
credits a *reader* to any tracked `.md`/`.py`/`.sh`/`.bend`/`.mjs`/`.ts` whose bytes contain
`.agents/slop/<dir>/`. **A `.md` that NAMES a directory is prose about it, and prose is not
liveness** — the same class of error as the basename join, one level up: `sweep.py`'s
`ORACLE_WORD` classified **670 of 675** oracle files by NAME. Measured over the 34 that moved,
their mentions resolve to **108 `.md`, 31 `.py` and 5 `.sh` dir×file pairs**, and for **all 34**
there is no code file outside the directory that opens it by full path — checked one by one, not
read off my own counter. So `orcdecide`'s 14 is a floor, not a count, and **the direction of the
error is the dangerous one**: it makes residue look live, which is how `strays/` nearly got
deleted.

The 44 *declared* directories in the disagreement are the larger half and change no count at
all: the same fault, invisible in any headline number.

## 2. THE 17, BY FULL PATH, AND THE THREE THAT LEFT

`orcdecide` named 17. Three have landed a tracked `REPORT.md` since its run and are gone:

| named on 2026-10-07 | why it left |
|---|---|
| `.agents/slop/citeresolve/` | `REPORT.md` committed in `5cbbd53cb` |
| `.agents/slop/coindependent/` | `REPORT.md` committed in `350252ea4` |
| `.agents/slop/jjreset/` | `REPORT.md` committed in `601e7929c` |

**This is the false-positive risk the brief names, and it is measured, not argued: two of the
three are units' EVIDENCE.** "No report" did not mean "should not exist" — it meant the unit had
not finished writing yet. **A walk that flags a fresh unit's directory as a defect flags every
unit that ever runs**, which is why the gate is a ratchet with a grace window (§5) and not a
requirement.

### The 14 still named, and the 34 the stricter reader test adds

The 14 are exactly `orcdecide`'s set minus those three. The 34 added
(`adev audit bendpin boundedfix ccdead cidsweep coldness cshape deadarm denom ffi-experiment
flip flipbool frombits i64mul jstage loopq notes-sweep offrepo opshapes opspy reach rebase sbgate
selfcheck slopfinal staleruns strays-root surface2 tensor-surface unknowns unshardfold wip`) are
directories that prose mentions and no code opens. All 48 by full path, with age and file count,
are in `BASELINE.tsv` and `declare.tsv`.

### FRESH vs GENUINELY UNDECIDED — and the honest answer is *not* the one the brief expects

`BACKLOG 15.0h · CITEMASS 13.8h · RUN34B 14.4h · PREFIXTXT 13.2h` are inside 24 h; the oldest is
`WIP` at **108 h**. But **"fresh" here means "written recently", not "somebody is working on it
now"**: the newest file in the whole gated set is 5.8 h old and the newest *this session* is
mine. **13 of 48 are inside the grace window and 35 are outside it, over a span of 83.9 h.**

So, measured: **the residue is overwhelmingly NOT fresh work.** 35 of 48 are 24–108 h old and
nothing in the tree has touched them since; the "in progress" reading is an artifact of this
session, and saying so is worth more than the number. The 13 inside the window are not
necessarily in progress either — they are simply recent, and the window cannot tell the two apart,
which is the honest limit of a timestamp.

## 3. `REPORT.md` OR `MANIFEST.tsv` — AND WARN OR REFUSE?

**PICK: `REPORT.md` as the declaration the walk REQUIRES (recognised by name), `MANIFEST.tsv` as
an equally valid one (and the better one when the declaration is per-file), and the gate WARNs by
default through a ratchet — it does not refuse, and it does not require.**

The trade, honestly:

| | `REPORT.md` | `MANIFEST.tsv` |
|---|---|---|
| what it can hold | a claim, an instrument, a verdict, a "why" | `path · verdict · why · restore`, per file |
| who can write it | any unit, in its first minute | a unit that has already decided each file |
| machine-checkable | **no** — 1 777 unchecked prose claims | yes, column for column |
| precedent | 155 of 262 directories | `strays/` (53 rows) is the reason `prune3` could audit a directory with no report; `oracles259/` (259 rows) is the same shape |

`strays/MANIFEST.tsv` is the load-bearing precedent and it settles the question: **a directory
without a `REPORT.md` is not undeclared if it holds a `MANIFEST.tsv`**, because `prune3` audited
it. So the walk accepts both, and requires neither absolutely.

**THE TRADE I AM MAKING, AND WHY.** A walk that *requires* a declaration is red at rest: 107 of
262 declare nothing today, and making that green is 107 human decisions. `AGENTS.md`: *"A
PRE-COMMIT GATE THAT CANNOT PASS TEACHES NOTHING AND WILL BE SKIPPED."* A gate that is skipped is
worse than no gate, because it looks like coverage. So:

> **The gate's claim is the claim it can keep: THE SET DID NOT GROW.** 48 names are baselined;
> a name LEAVING is the gate working and is never punished; a NEW name appearing is a FAIL once
> it ages past the grace window; and everything — all 48, with ages and file counts — is printed
> on every run whether or not it is gated.

**What a NEW unit does in its first minute — the whole design, stated as behaviour:**

```
t=0    mkdir .agents/slop/myunit && write the script
       -> the walk names it IN PROGRESS, counts it, and prints it.  It does NOT fail.
t=+1h  still no report, because the unit is mid-run
       -> still IN PROGRESS.  Still printed.  Still not a verdict.
t=+2d  the unit wrote REPORT.md, or wrote nothing and was interrupted
       -> declared: gone from the set, and the gate says so.
       -> nothing written: STALE, not in the baseline, FAIL.  The gate has earned its keep.
```

**So the gate is neither a warning nor a refusal: it is a ratchet with a grace window, and it
prints every name it holds on every run.** A caller reading only `$?` cannot mistake any of the
five outcomes — the exits are `PASS 0 · FAIL 1 · REFUSED 3 · DEAD 5`, matching `gates/gatekit.py`
and `e2e.py`'s `SKIP 4` is not used because nothing here skips.

## 4. THE BIGGEST CORRECTION: **A NAME SET IS NOT A POPULATION, AND I MEASURED WHAT IT COSTS**

This walk carries the doctrine-1 fault the brief warns about — on the *declaration* axis, where
the brief does not. `DECLARATIONS` is five names, and the tree has forty more:

| of the 48 gated directories | |
|---|---:|
| hold prose (≥1 `.md`) under a name **outside** the set | **24** |
| hold no `.md` at all — a script, a capture, or nothing | **24** |

The other names include `CLAIM.md` ×3, `STATUS.md`, `FINDING.md`, `COLDNESS.md`, `JSBF16.md`,
`EXPECTED.md`, `ENUMERATION.md`, `CENSUS.md`, `DEV-GATE.md`, `FLIPR.md`, `notes.md`, `STUB.md`,
`silent2.md`, `00-seed.md`, `00-START.md`, `02-FINDINGS.md`, `REBASE-PLAN.md`,
`SHA256SUMS.md`, `RECORD-222-is-a-reader-not-a-population.md`, and the numbered series
`00-rows.md · 01-proofs-34of34.md · 08-ledger-234counts.md` (in `audit/`) and
`00-rows.md … 04-unsettled.md` (in `opshapes/`).

**Therefore: `107`, `110`, `14` and `48` are all counts of "no declaration **under a name this
tool recognises**", not counts of undecided work. Adding `CLAIM.md` to the set would make 62
directories green without a single human having decided anything — that is `sweep.py`'s
`LIVE_UNITS` and `ORACLE_WORD` again, and it is the one move this report exists to prevent.** The
fix is `git mv CLAIM.md REPORT.md`, one line, per directory — a rename, not a list entry.

## 5. FRESHNESS: TWO CLOCKS, AND THE OBVIOUS ONE IS DEAD

| clock | distinct values over the 35 gated directories | usable? |
|---|---:|---|
| newest commit (`git log -1 -- <dir>`) | **1** | **no** |
| newest file mtime | **46**, spanning 5.7 h … 108 h | yes |

**The commit clock is degenerate, and the reason is an event.** `813bbec3e` (2026-10-07 00:45,
*"RESTORE 6141 FILES DELETED BY THE JJ INDEX WIPE"*) touched **every** `.agents/slop/*/`
directory in one commit, so every directory reads **5.4 h** old. An axis with one value is not an
axis: it would call all 48 fresh and the gate would be green **for the wrong reason** — and this
tree has already paid twice for a green that means nothing.

mtime's weakness is the mirror image: `git clone` and `git checkout` stamp every file with the
checkout instant, so on a fresh clone all 262 read as fresh and the gate is green for the same
wrong reason. **So the clock itself is guarded**: if the whole population's mtimes span less than
`MIN_SPREAD_MIN`, the walk **REFUSES (3)** and says the ruler is missing. Today the span is
**161.6 h** and the gate measures. `commit_age_h` is kept as a column precisely so this
degeneracy stays visible instead of silently becoming the deciding input.

**The first version of that guard had a hole, and the plant found it.** It tested the *gated
subset*; a reset clock makes every undeclared directory FRESH, so the gated set is **empty**,
`if stale` never fires, and the walk answered **PASS** on a tree checked out sixty seconds ago.
The signature is in the **whole population**, and that is what it tests now (PLANT 6).

## 6. THE PLANT — TWO STATES, PLUS THE FALSE POSITIVE THE BRIEF ASKS FOR

`.agents/slop/declare/plant.py`, 12 assertions, `rc=0`. Every plant builds a private `git init`
tree in a `tempfile`; nothing writes into the real `.agents/slop/`, and no plant reads the real
tree's answer for its own verdict.

| | asserts |
|---|---|
| 1a | a tracked directory with nothing that declares it **is named** |
| 1b | the same directory plus a tracked `MANIFEST.tsv` **is not** — the `strays/` precedent |
| 2a | a file that opens `Path("evid")/"x.json"` — **a basename join** — credits **NO reader** |
| 2b | …and the directory is still **declared**, so the trap costs one claim, not two |
| 3a/3b | declared + unread → 0 code readers, and it is in **neither** gated set (`citeresolve`'s shape) |
| 4a/4b | a 2000 stamp is STALE; a stamp from now is IN PROGRESS, counted, not gated |
| 5a/5b | no `.agents/slop/` → **DEAD (5)**; git refuses → **REFUSED (3)**; neither is PASS |
| 6a/6b | four real mtimes → a real verdict; **one** mtime for the whole tree → **REFUSED (3)** |

**PLANT 2 is the answer to "a unit's evidence dir whose reader is only a basename — does the walk
still name it?"** It does not name it (2b) *and* it does not credit the fake reader (2a). Both
halves are true at once and both are asserted, because a walk that fixed the first by loosening
the reader test would have recreated the `orcdecide` trap one line away.

**A bug the plants caught in the instrument, not in a fixture:** `classify()` asked
`not row["declared"]`, and `declared` is `"-"` when absent — a **truthy** string, so `undeclared`
was **always empty** and PLANT 3b passed **vacuously** until PLANT 4b failed. The row now
carries an explicit boolean, and 3b asserts the positive direction too.

## 7. THE ONE-LINE FIX FOR THE 14

**Of `orcdecide`'s 14 that remain, 7 already declare themselves under another name, 3 are pure
captures, and 4 are the real decisions.** Authoring a declaration is 14 human decisions; no walk
can make them, so here is the triage and I have done only the triage.

**ONE `git mv` EACH — the directory is already written, the name is just not the one this tool
recognises (§4).** Author by renaming the file that is already there:

```
bf16fix/STUB.md  -> REPORT.md     devgate/DEV-GATE.md      -> REPORT.md
fp8dec/notes.md  -> REPORT.md     gatespop/ENUMERATION.md  -> REPORT.md
jsbf16/JSBF16.md -> REPORT.md     jslane/00-seed.md        -> REPORT.md
readback/silent2.md -> REPORT.md
```

I would also rename, outside the 14, where the artifact is unambiguously a declaration:
`offrepo/FINDING.md`, `notes-sweep/02-FINDINGS.md`, `unfalsifiable/RECORD-222-…md` (which is
*itself* this report's finding), and `loopq/00-rows.md`. For `audit/` (13 files, a numbered
01–08 series ending in `08-ledger-234counts.md`) and `opshapes/` (`00-rows.md` … `04-unsettled.md`)
I would **write** a `REPORT.md` rather than rename one file, because a numbered series is a
report that has been split and should not be renumbered by hand.

**RETIRE — pure captures whose unit's live instrument is already in `checks/` or `gates/`, with
no reader and nothing to reproduce.** These four also have `prose_mentions == 1`, i.e. the only
thing naming them anywhere is their own commit:

```
backlog/staged-before.rows     (its own commit says the scratch was removed)
censusmarker/before.{out,err}  prefixtxt/notxt.before.out, repro.before.{out,err}
run34b/run.{out,err}
```

`citemass/` (`resolve.py`, `cites-now.tsv`, `resolved-now.tsv`, two `.err`) I would **retire into
`.agents/slop/citeresolve/`, which now has a report** — it is that unit's workshop, it has no
reader by full path (`git grep -l -F '.agents/slop/citemass/'` over code returns nothing), and the
decision belongs to whoever wrote the successor's report, not to a sweep.

**LEAVE NAMED — the four where nobody can decide without reading the code, and I am not going to
pretend otherwise:**

| dir | files | why it is a decision, not a rename |
|---|---:|---|
| `helpers-mut` | 1 | `gate.bend` — a `.bend` gate **nothing runs**. Either it is a live instrument with no caller, or it is `DEAD`. Only running it answers that, and the brief forbids `bend`. |
| `i64div` | 1 | `gate.sh` — same shape. |
| `cshape` | 5 | `cs-plant.py` — a plant. A plant nobody runs is the exact object `plant.py` exists to keep honest. |
| `deadarm` | 5 | `bendarm-merge.py`, `deadarm.py`, `sweep.sh` — a mutation sweep with its own `.sh`. |

**The rest of the 48 stay named and undecided.** `bendpin` (10 files of before/after pin rows),
`boundedfix` (`BEFORE.out`/`AFTER.out`/`REPRO.rows`/`SHA256SUMS.md`), `sbgate` (`CENSUS.md` +
`audit.py` + `plant.py`), `frombits` (`00-stub.md` + `gate.sh` + `mutate.sh`), `opspy`,
`tensor-surface`, `surface2`, `unknowns`, `slopfinal`, `reach`, `jstage`, `selfcheck`, `i64mul`,
`flipbool`, `ffi-experiment`, `rebase`, `staleruns`, `coldness`, `flip`, `denom`, `adev`,
`cidsweep`, `strays-root`, `wip`, and the 13 inside the grace window — each needs a human to say
*keep as a record* or *retire*, and that is not a walk's decision.

## 8. WHAT I DID NOT DO, AND WHAT IS STILL WRONG WITH THIS TOOL

- **I did not `git add` or commit**, so `.agents/slop/declare/`, `BASELINE.tsv` and
  `checks/slop-declare.py` are untracked: **the gate is green only because `BASELINE.tsv` is
  read from the worktree**, and the walk cannot see its own directory until it is tracked.
- **The baseline is 48 names and it is inherited debt, not a verdict.** Every one of them is a
  human decision this report does not make. It exists so the gate can hold a line, and
  `--baseline` prints it so refreshing it is a measured act — **the walk never writes its own
  baseline**, because a gate that rewrites its baseline can bless whatever it is looking at.
- **`orcdecide/sweep.py` still self-excludes with a typed name** (`sweep.py:57`,
  `if name in ("orcdecide",): continue`) — a hand list inside the instrument that exists because
  hand lists rot. I reproduced it verbatim for comparability and did not patch it: it is not my
  file.
- **`checks/` is not uniformly 2-space indented** as `AGENTS.md` claims: over `checks/*.py`,
  **5 518 lines begin at 4 spaces against 2 360 at 2** (`ruff` reports the tree's own count
  separately). This file is 4-space, the majority.
- **`prose_mentions` is reported and deliberately does not decide anything.** It is what
  `orcdecide`'s reader test was measuring, made visible rather than acted on.