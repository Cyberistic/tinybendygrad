# FRESHNESS: WHAT CAN EVER FIRE, AND WHAT LEAVES A TRACE

**HEAD `c3c4120f4556dadde82511f6bd96cd6a2c3bd5ab`** (`AGENTS.md: the corpus is green, reproducible, AND current`).
**Measured 2026-10-20T17:42Z – 2026-10-20T17:56Z.** `sysctl -n vm.loadavg` read **14.58** at the start
(> 12), so this session did the minimum: reads, greps, and one walk. No corpus run, no gate run.

**WHAT I WAS NOT ALLOWED TO RUN, AND THEREFORE DID NOT: `checks/differ.py` (any subcommand), ANYTHING
UNDER `gates/`, `checks/e2e*`, `checks/sweep.py`, `checks/bounded.py`, pytest/mypy/ruff.** Every number
below that names a gate's *behaviour* is read out of that gate's own source or out of a ledger it
wrote — never a fresh run of it. Where a number is mine it says so and names the command.

**THE VERDICT: THE CLAIM IS PARTLY TRUE, AND THE PART THAT IS TRUE IS THE PART THAT WAS ALWAYS
TRUE. `AGENTS.md:154` (present at HEAD) says:**

> `13 FRESHNESS INSTRUMENTS, 0 REACHABLE FROM ANY SURFACE` — `.git/hooks/` HAS 13 FILES AND 0
> NON-`.sample`, `core.hooksPath` IS UNSET, `.github/workflows/` HAS 9 FILES AND 0 NAME A GATE, AND
> `gates/artifacts/` IS GITIGNORED (`.gitignore:214`).

| the claim's four parts | measured at HEAD | holds? |
|---|---|---|
| `.git/hooks/` has 0 non-`.sample` | `ls .git/hooks/ \| grep -vc '\.sample$'` = **0** | **YES** |
| `core.hooksPath` is unset | `git config --get core.hooksPath` → rc=1 | **YES** |
| `.github/workflows/` has 9 files | `git ls-tree -r HEAD -- .github/workflows/` → **10** files; `find .github/workflows -type f \| wc -l` → 10 | **NO — 10, not 9** |
| `.github/workflows/` names 0 gates | `.github/workflows/edge-gates.yml` names `gates/edge-runner.py` (3×), `gates/pincensus-gate.py`, `gates/pincensus-pop.py`, `checks/gatesweep.py`, `checks/differ.py` | **NO — exactly 1 of the 10 names a gate** |
| `gates/artifacts/` is gitignored | `git check-ignore -v gates/artifacts/` → `.gitignore:214:gates/artifacts/`, rc=0; `git ls-tree -r HEAD -- gates/artifacts/` → **0** tracked paths | **YES** |
| 13 freshness instruments, 0 reachable | 13 is right (re-derived below); **0 is not** | **NO — the corpus's own predicate now scores 1** |

**WHY THE CLAIM WENT STALE, WITH A COMMIT.** `gates/corpusfresh-gate.py:22` — the census that owns
the "13" — records its own measurements as of `2026-10-20T00:56Z`: *"`.github/workflows/` 11 tracked
files, all upstream tinygrad's; 0 name any gate"*. `edge-gates.yml` was added **16h 36m later**, in
commit `ac186c3d9` (`edge: the committed surface that runs the gates, and the trace of the run`,
2026-10-20 19:32:18 +0300 = 16:32:18Z), which IS an ancestor of HEAD. **The census was not re-run
after the surface appeared.** `AGENTS.md:154` copied the census's stale reading.

---

## 1. THE 13, BY NAME, WITH `file:line` — RE-DERIVED, NOT COPIED

The census owns the population: `gates/corpusfresh-gate.py:83`
`FRESH_TOKENS = ("substrate_digest", "REPRO_SUBSTRATE", "substrate-start", "st_mtime_ns")`, applied
by `is_freshness_instrument()` (`:109`) to every entry point `gates/gates-pop.py:discover()` returns
(`gates()` at `:100`), read AS TEXT (`:110` — importing a gate RUNS it). The census says at `:74-75` it
names "13 of the 277 entries". I re-derived it with a read-only grep of the four tokens over
`gates/` and `checks/`, then confirmed each hit is an entry point (`__main__` present):

| # | instrument | the freshness judgement it makes |
|---|---|---|
| 1 | `checks/differ.py` | live substrate digest (`:1210`) + `REPRO_SUBSTRATE` witness (`:353`, `:1465`) — is the recorded corpus verdict current |
| 2 | `checks/substrate-current.py` | the live substrate digest vs the recorded one — **computes a digest, judges no age** |
| 3 | `checks/substrate-manifest.py` | manifest of the substrate's inputs — computes, does not judge |
| 4 | `checks/substrate-id.py` | content-addressed substrate id — computes, does not judge |
| 5 | `checks/disagree-gate.py` | the corpus disagreement verdict over the recorded `D/` summary |
| 6 | `gates/arenasrc_census.py` | arena-source digest census — computes, does not judge |
| 7 | `gates/corpusfresh-gate.py` | **the census itself** — is any freshness instrument reachable from a surface |
| 8 | `gates/corpusverdict-gate.py` | **is the recorded `graphcmp` verdict current**: recorded digest vs `differ.substrate_digest()` (`:170`) |
| 9 | `gates/corpuswitness-gate.py` | two witnesses compared by `os.stat().st_mtime_ns` ordering (`:48`, `:153`) |
| 10 | `gates/corpuswitness-plant.py` | the PLANT for #9 (rewrites rows, restores mtimes at `:169`) — a control, not a judge |
| 11 | `gates/corpuslane-gate.py` | is the `graphcmp` CPython lane alive and still reading upstream |
| 12 | `gates/prose-census.py` | do the PROSE numbers still equal the gates' own totals lines |
| 13 | `gates/gendirs.py` | the generated-directory digest — computes, does not judge |

**The census's own docstring already admits the imprecision** (`:74-82`): *"several of the 13
(`substrate-id.py`, `substrate-manifest.py`, `gendirs.py`) merely COMPUTE a digest rather than
judging one"*, and it names itself. **The census's classifier is a population of files that mention
four token strings, not a population of freshness instruments.** Two counterexamples, both measured:

* `gates/banner-gate.py:184` `claim_artifact_fresh()` compares **the census transcript's mtime
  against the gate source's mtime, in days** (`:191`) — a true age comparison, and it is NOT in the 13.
* `gates/gapcensus.py:460` `unit_corpus()` compares the newest artifact mtime under
  `runs/graphcmp/D/` against the re-vendor commit's committer time and emits
  `corpus.artefacts_OLDER_by` (`:495`) — a true age comparison, and it is NOT in the 13.

So the true freshness population is **larger than 13**, and the corpus's is a superset in one
direction (it includes digesters) and a **subset** in the other (it misses the two age
comparators). `instruments.rows` lists **26**: the 13, the 2 age comparators the classifier misses, the
consumers of the age rows (`gates/gapcensus-gate.py`, `checks/runs-artifacts.py:550`
`state()`/`ARTIFACTS-STALE`, `gates/retention-check.py:342`), the trace-makers
(`gates/help-census.py:226`, `gates/pincensus-gate.py:379`), and five `.agents/slop/` instruments.

**EXCLUDED, NAMED, WITH THE REASON** (so a reader can disagree):
`checks/sweep.py:1110 live_set()` — uses an mtime cutoff, but it asks *which agent units are live*,
not whether an artifact is current against its code; `checks/substrate.py` — a cold-file sweep, no age
comparison; every `os.utime` caller under `.agents/slop/` — those are PLANTS, they CREATE staleness
to test something else, and they are not judges.

---

## 2. THE SURFACES, ENUMERATED BY DISCOVERY

| surface | measured | survives a fresh clone? |
|---|---|---|
| `.git/hooks/` | **14 files, ALL `*.sample`**, 0 non-`.sample` | **NO** — it is inside `.git/`, untracked, and a clone gets git's OWN samples. The count is git's, not the tree's: this machine has 14, the 2026-10-07 report measured 13 (`.agents/slop/hooks/REPORT.md:24`), and neither number is a property of the repository. |
| `core.hooksPath` | unset (rc=1) | n/a |
| `.github/workflows/` | **10 files, 10 tracked, no subdirectories**. ONE names a gate: `edge-gates.yml` (the only file with `run:` steps that touch this tree). `test.yml` mentions "GATED" only inside `ALLOWED_GATED_READ_IMAGE` (`:333`) — not a gate. | **YES** |
| `gates/artifacts/` | gitignored, `.gitignore:214`, **0 tracked paths** | **NO** |
| `runs/` | gitignored, `.gitignore:262` (this is where `runs/graphcmp/D/` lives) | **NO** |
| `.agents/slop/` | **NOT ignored — 6070 of the 6075 tracked `.agents/` paths are under it** | **YES**, but it is a report directory; nothing in it calls anything |
| `gates/edge-runner.py` + `gates/edge-trace.rows` + `gates/edge-cost.rows` | all three tracked; `edge-gates.yml:96` runs the runner | **YES** — the runner is the program, the workflow is its caller |
| `checks/gatesweep.py` | tracked; the LOOP over the whole gate population | YES as a program, **nothing fires it** |
| `gates/runner.py` | tracked; a preconditioned runner over the same population | YES as a program, **nothing fires it** |
| `gates/help-census.py` + `gates/help-census.rows` | both tracked; the census writes the ledger at `:73` | YES as a program, **nothing fires it** |

**DOES ANY SURFACE RUN A FRESHNESS INSTRUMENT? YES — ONE, AND IT IS A NO-OP.**
`.github/workflows/edge-gates.yml:96` runs `gates/edge-runner.py`. Its selection is three
discovered populations (`gates/edge-runner.py:27-41`): **F1** the gate population
(`checks/gatesweep.py:population()`, 279 members); **F2** the members whose OWN source holds a pin
that OWN code reads (the CAN-FAIL class, by `gates/pincensus-pop.py`'s `rule_a()`/`readers()`),
**17 members**; **F3** the measured cost ledger `gates/edge-cost.rows` against
`BUDGET_SECONDS = 30` (`:103`) and `BUDGET_MB = 3072` (`:104`).

The **committed trace** `gates/edge-trace.rows` (written `2026-10-20T17:22:27Z`, `HEAD=852216853`)
has **20 rows**. Of the 13 freshness instruments, **exactly one appears**:

```
gates/edge-trace.rows:4   checks/differ.py   RAN-UNASSIGNED   UNASSIGNED   UNASSIGNED(2)   rc=2   0.36s   25MB
```

**And that invocation measured nothing.** `gates/edge-runner.py:383-393` records why: `differ.py`
has **no bare mode** — it is a mode selector with four — so a bare invocation exits 2, a code no
vocabulary names, and the edge counts it without charging it. **So the one freshness instrument a
clone-surviving surface invokes is invoked in the one way that cannot answer anything.**

**THE OTHER 12 ARE NOT CANDIDATES AT ALL**, so the trace has no row for them — and no row for them
is indistinguishable from no row for a gate that does not exist.

**AND THE CHAIN THAT WOULD REACH ALL 13 IS BROKEN AT ONE NODE.** `checks/gatesweep.py` — the loop
that walks the population and runs every member — **is** an F2 candidate, and it is **skipped**:

```
gates/edge-trace.rows:6   checks/gatesweep.py   OVER-BUDGET   SKIP   MEASURED-30.31s
gates/edge-cost.rows:6     checks/gatesweep.py   30.31   143   SKIP   TIMED-OUT
```

So the chain is `.github/workflows/edge-gates.yml` → `gates/edge-runner.py` → `checks/gatesweep.py`
→ the 13, and it is severed at the middle link by a 30-second budget against a measured cost of
**"≥ 30.31 s, TIMED-OUT"** — i.e. the cost ledger records that it did not finish, not how long it
takes. **A budget is the only thing between the tree and thirteen freshness instruments firing.**

---

## 3. REACHABILITY, PER INSTRUMENT — THE CRITERION STATED FIRST

**`reachable_yes_no` = "is there a COMMITTED, CLONE-SURVIVING surface that INVOKES this without a
human asking?"** Not "is it in a runner's population" (that is true of all 25 and separates nothing),
and not "does a surface MENTION it" (that is a count of prose, see §5).

| reachable | instruments | how |
|---|---|---|
| **YES** | `checks/differ.py` | invoked by `gates/edge-runner.py` (`edge-trace.rows:4`) — as a bare no-op |
| **YES** | `gates/edge-oracle-pin-gate.py` | invoked by the edge (`edge-trace.rows:11`, `RAN PASS rc=0`) — a pin-**viability** instrument, not in the 13 |
| **NO** | the other 12 of the 13 | in `checks/gatesweep.py`'s population only; that sweep is OVER-BUDGET and skipped |
| **NO** | `gates/pincensus-gate.py` | **NAMED IN PROSE** at `edge-gates.yml:3` and `:4` — and never invoked: absent from `edge-trace.rows` and `edge-cost.rows` |
| **NO** | `gates/banner-gate.py:184`, `gates/gapcensus.py:460`, `gates/gapcensus-gate.py`, `checks/runs-artifacts.py:550`, `gates/retention-check.py:342`, `gates/help-census.py:226` | in the sweep population only; nothing fires it |
| **NO** | the five `.agents/slop/` instruments | tracked, in a report directory, fired by nothing |

---

## 4. THE TRACE QUESTION — "NOBODY ASKED" vs "NOBODY WAS TOLD", PER INSTRUMENT

The census states the question itself at `gates/corpusfresh-gate.py:31-35`: *"both produce zero rows,
but only one of them leaves a trace, and this tree keeps **no trace of an invocation at all** — every
gate's output goes to `gates/artifacts/`, which `.gitignore:214` ignores … so from a fresh clone
'was this gate ever run?' and 'does this gate exist?' have the same answer: nothing."* It measures
that itself at `:269-274` (`record` row: `artifacts_ignored=True`, `artifacts_tracked=0` → FAIL).

**MEASURED, AND THE ANSWER IS PER-INSTRUMENT, NOT GLOBAL. Two committed ledgers answer it, and both
are dated `2026-10-17`:**

| ledger | tracked? | rows | written | answers "does it exist?" | answers "was it run?" |
|---|---|---|---|---|---|
| `gates/gates-pop.ledger.tsv` | YES | 225 | 2026-10-17 07:24 | **for 6 of the 13** | no |
| `gates/help-census.rows` | YES | 226 | 2026-10-17 06:55 | for 6 of the 13 | **for 6 of the 13** (`--help` run: verdict, rc, token, peak_mb, seconds) |
| `gates/edge-trace.rows` | YES | 20 | 2026-10-20 17:22:27Z | no | **for `checks/differ.py` only** (and as a no-op) |
| `gates/edge-cost.rows` | YES | 20 | 2026-10-20 16:36:03Z | no | for 20 candidates only |
| `gates/artifacts/<name>/` | **NO** (gitignored) | — | — | no | **no** |

**SPLIT THE 13:**

* **6 of the 13** — `checks/differ.py`, `checks/substrate-current.py`, `checks/substrate-manifest.py`,
  `checks/disagree-gate.py`, `checks/substrate-id.py`, `gates/gendirs.py` — have a committed
  EXISTENCE row (`gates/gates-pop.ledger.tsv`) **and** a committed RUN row
  (`gates/help-census.rows`). **A fresh clone can say "this instrument exists and was invoked on
  2026-10-17."** But both ledgers are three days stale, and neither says whether it has run *since*.
* **7 of the 13** — `gates/arenasrc_census.py`, `gates/corpusfresh-gate.py`,
  `gates/corpusverdict-gate.py`, `gates/corpuswitness-gate.py`, `gates/corpuswitness-plant.py`,
  `gates/corpuslane-gate.py`, `gates/prose-census.py` — have **no committed existence row, no
  committed run row**, and their output destination is `gates/artifacts/<name>/`
  (e.g. `gates/corpusfresh-gate.py:65`, `gates/corpusverdict-gate.py:66`,
  `gates/corpuswitness-gate.py:108`, `gates/corpuslane-gate.py:90`), which is gitignored. **They were
  created 2026-10-18…20, after the two ledgers were written — that is WHY they are missing.**
  **For these seven, "was this gate ever run?" and "does this gate exist?" have the same answer:
  nothing. THE CLAIM IS EXACTLY TRUE FOR SEVEN OF THE THIRTEEN, AND FALSE FOR THE OTHER SIX.**

---

## 5. THE PREDICATE THE "0 REACHABLE" NUMBER IS COMPUTED WITH CANNOT SEE A RUN FROM A MENTION

`gates/corpusfresh-gate.py:154-163` — the census:

```python
surfaces = [(p, p.read_text(errors="replace")) for p in (*hooks, *flows)]
out[n] = [ ... for p, body in surfaces if stem in body]
```

**Byte containment.** A comment is bytes. The census's HIT therefore scores **a prose mention** the
same as **an invocation**. At HEAD:

* `checks/differ.py`'s stem `differ.py` appears at `.github/workflows/edge-gates.yml:66` — **in a
  comment** ("`checks/differ.py`'s `ORACLE_PIN` names two REVISIONS"). So the census would score
  **told = 1, untold = 12** — NOT `told = 0`.
* And the invocation that actually exists (the edge running it as an F2 candidate) is a **bare
  no-op**, so the HIT and the RUN are two different things and the predicate conflates them.

**So `AGENTS.md:154`'s "0 REACHABLE FROM ANY SURFACE" is FALSE AT HEAD — it should read "1 of 13 is
named by a surface, and that one is named in prose and invoked as a no-op" — and the number it quotes
is a count of MENTIONS, not of RUNS.** That is the same class as the one `AGENTS.md` already names:
*a predicate that cannot see its population cannot be wrong, because it cannot be anything.*

---

## 6. THE CHEAPEST CHANGE THAT MAKES A FRESHNESS INSTRUMENT REACHABLE FROM A SURFACE A CLONE HAS

**WHICH SURFACES SURVIVE A CLONE:** `.github/workflows/*.yml` (tracked, fires on push/PR/dispatch);
`gates/edge-runner.py` + `gates/edge-trace.rows` + `gates/edge-cost.rows` (tracked);
`gates/help-census.py` + `gates/help-census.rows` (tracked); `checks/gatesweep.py` (tracked);
`gates/runner.py` (tracked); `.agents/slop/**` (tracked, 6070 paths).
**WHICH DO NOT:** `.git/hooks/` (untracked, inside `.git/`, and 0 real hooks besides);
`gates/artifacts/` (gitignored, `.gitignore:214`); `runs/` (gitignored, `.gitignore:262`).
**A HOOK-BASED ANSWER DOES NOT SURVIVE A CLONE** — `.agents/slop/hooks/REPORT.md` §4 already records
why (the directory is shared by every live unit, untracked, and outside the tree's history), and
`edge-gates.yml:9-12` says the same.

**THE CHEAPEST COMPLETE CHANGE — 2 FILES, 3 LINES, NO NEW LIST, AND IT REUSES THE RULE THE EDGE
ALREADY FOLLOWS:**

> *"A GATE'S REQUIRED INPUT BELONGS BESIDE THE GATE IN GIT"* — `gates/edge-runner.py:47-52`, the
> reason `gates/edge-trace.rows` and `gates/edge-cost.rows` are tracked and `gates/artifacts/` is not.

**THE CHANGE, EXACTLY:**

1. **`gates/corpusfresh-gate.py:65`** — move the census's own output out of the gitignored artifact
   directory and beside the gate, in git:
   `ART = HERE / "artifacts" / "corpusfresh-gate"` → `ART = HERE` (with the rows file renamed
   `corpusfresh.rows`, beside the gate). **ONE LINE.** Today the census writes its answer to a path
   `.gitignore:214` ignores, so the instrument that measures "was anybody told" destroys its own
   answer — the same defect `gates/edge-runner.py:47-52` names and fixed for the edge.
2. **`.github/workflows/edge-gates.yml`** — one step, before the existing `COMMIT THE TRACE` step
   (`:132-144`):
   ```yaml
   - name: THE FRESHNESS CENSUS
     run: |
       set +e
       .venv/bin/python gates/corpusfresh-gate.py --report 2>&1 | tee -a "$RUNNER_TEMP/edge.out"
       exit 0
   ```
3. **`.github/workflows/edge-gates.yml:138-143`** — add the one path to the existing commit step:
   `git add gates/edge-trace.rows gates/corpusfresh.rows`.

**Why this is the cheapest thing that works:**
* the workflow is the **only** clone-surviving automatic surface, so the call must go there;
* `gates/corpusfresh-gate.py --report` is **rc=0 by design** (`:293-294`), needs no `bend`, and is the
  instrument that already knows the freshness population **by discovery** — so this adds **no hand
  list**, and it prints the `told`/`untold` tally (`:259-264`) that IS the answer to the claim;
* `gates/corpusverdict-gate.py` is the gate whose answer is the whole question ("is the recorded
  verdict current for this tree?"), it **needs no `bend` and cannot damage anything** (its own
  docstring `:35`: *"IT NEEDS NO `bend` AND CANNOT DAMAGE ANYTHING. It reads two files and hashes a
  declared population"*), and it should be added to the edge's candidate set (change 2 below) rather
  than invoked here, so the two rows keep their own schema;
* **the census's rows are a DIFFERENT schema from the edge's** (`name<TAB>key=value` against
  `gate, status, verdict, token, rc, seconds, peak-mb`), so they belong in their OWN tracked file —
  appending them to `gates/edge-trace.rows` would put two grammars in one file, and this tree has
  already paid for that (`checks/gatesweep.py`'s `PROJECTION` clause exists because two instruments
  with two walk rules produced two numbers nobody could read).

**THE TWO THINGS THAT ANSWER MUST NOT HIDE — BOTH MEASURED, BOTH STATED:**

1. **ON A FRESH CLONE THE CORPUS FRESHNESS INSTRUMENTS CANNOT MEASURE ANYTHING, AND THEIR HONEST
   VERDICT IS `REFUSED`, NOT `PASS`.** Their subject is `runs/graphcmp/D/`, and `runs/` is gitignored
   (`.gitignore:262`). A clone has no corpus to be stale about. `checks/runs-artifacts.py:550` already
   has the right word for it: `REFUSED, ARTIFACTS-ABSENT`. **The change above makes the absence
   VISIBLE; it does not make the corpus fresh.** The instruments whose subject IS in git — the pin
   and substrate ones (`checks/differ.py`, `gates/pincensus-gate.py`,
   `gates/edge-oracle-pin-gate.py`) — are the ones that can actually answer in CI.
2. **THE EDGE'S CANDIDATE SELECTION IS THE CHEAPEST THING TO FIX, AND IT IS NOT THE BUDGET.**
   `gates/edge-runner.py:215-244` (F2) admits only members holding a CAN-FAIL pin, so the 12
   freshness instruments are **not candidates** — raising `BUDGET_SECONDS` (`:103`) would NOT bring
   them in, and it would not bring back `checks/gatesweep.py` either unless the budget exceeded the
   sweep's **unknown** cost (`edge-cost.rows:6` records `TIMED-OUT` at 30.31 s, not a duration).
   **A second, DISCOVERED candidate arm — the freshness class, taken from
   `gates/corpusfresh-gate.py` LOADED BY PATH rather than typed — is what actually reaches the 13.**
   Its risk must be stated: that classifier is a SUPERSET that includes
   `gates/corpuswitness-plant.py` (a PLANT that rewrites rows and restores mtimes) and
   `gates/corpusfresh-gate.py` itself (a census that is **red by design**, rc=1 unless `--report`),
   so the arm must exclude plants or the edge will charge a FAIL for a gate that is supposed to be red.

**THE TRACE-ONLY CHEAPEST OF ALL, IF ONLY EXISTENCE MATTERS:** one line in
`gates/help-census.py`'s ledger writer — it already runs the whole population with `--help` and
writes a TRACKED ledger (`gates/help-census.rows`). **Re-running it puts a row for every one of the
13 into a tracked file**, including the seven that have none, and it costs one command. It is a
*`--help`* run, so it records existence and invocation, not a verdict.

---

## 7. THE CONTROL — AND IT PASSES, ON A DIFFERENT GATE THAN THE BRIEF NAMED

**THE BRIEF'S CONTROL GATE IS `gates/index-arm-gate.py`. THAT FILE DOES NOT EXIST.** The file is
**`checks/index-arm-gate.py`** (`find . -name 'index-arm-gate.py'` → `./checks/index-arm-gate.py`).
That is a detail. The reachability half is not a detail:

**`checks/index-arm-gate.py` is UNREACHABLE under the criterion stated in §3.** It is named by no
workflow; it is invoked only by `gates/runner.py` (delegated **by path** at `:119`, sha-pinned at
`:116`) and by `gates/docnum-claim-gate.py:143` as a lane — and **both of those are themselves fired
by nothing committed**. The brief's premise *"which the sweep does run"* is **true** (it is in
`checks/gatesweep.py`'s population, and `gates/help-census.rows:45` records its run: `REFUSED`,
rc=3, 25.0 MB, "53 path(s) a bare `git commit` acts on RIGHT NOW") — and it does not rescue the
premise, because the sweep is never fired either.

**SO THE CONTROL WAS BUILT AND PASSED ON THE RIGHT PAIR:**

| | instrument | class | evidence |
|---|---|---|---|
| known-reachable | **`checks/differ.py`** (the corpus freshness oracle; one of the 13) | **REACHABLE** | `gates/edge-trace.rows:4` — invoked by the edge without a human asking |
| known-unreachable | **`gates/corpusverdict-gate.py`** (the flagship "is the recorded verdict current" gate) | **UNREACHABLE** | absent from `gates/edge-trace.rows`, from `gates/edge-cost.rows`, from `gates/help-census.rows`; named by no workflow; only in `checks/gatesweep.py`'s population, which is OVER-BUDGET and skipped |

**AND THE CONTROL ALSO SHOWS WHY THE LOOSE CRITERION MUST BE REJECTED.** Under *"some committed
program in the tree would run it"*, `checks/index-arm-gate.py`, `gates/corpusverdict-gate.py` and all
**13** land in the **same** class — the sweep's population — so that criterion **cannot separate a
known-reachable from a known-unreachable gate and is therefore not the criterion that answers "can it
ever fire"**. The strict criterion (§3) separates them, which is why §3 is the one the table uses.
**`instruments.rows`' `reachable_yes_no` column therefore agrees with the brief on the SHAPE of the
answer and disagrees on the brief's example gate, for a measured reason.**

---

## 8. WHAT IS STILL UNANSWERABLE, AND WHAT I DID NOT DO

* **I DID NOT RUN `gates/corpusfresh-gate.py`** (forbidden). Everything I say about what it *would*
  report at HEAD is a **re-derivation of its own predicate from its source** (`:83`, `:109`, `:154`,
  `:259`) plus its **own committed trace** — not an observation of its output. **The `told = 1`
  figure is a re-derivation and is labelled as such.**
* **THE 13 IS THE CENSUS'S FIGURE, AND THE CENSUS'S POPULATION IS A TOKEN CLASSIFIER, NOT A
  POPULATION OF FRESHNESS INSTRUMENTS** (§1). Two true age comparators are outside it. A reader who
  wants "every instrument that checks freshness" should read `instruments.rows` (25 rows) and not the
  13.
* **THE NUMBER OF TRACKED WORKFLOWS MOVES.** It was 11 at `2026-10-20T00:56Z` (the census's reading),
  9 when `AGENTS.md:154` was written, and **10 at HEAD**. It is a moving denominator and should be
  quoted with its timestamp, like every other count in this tree.
* **`.git/hooks/`'s FILE COUNT IS GIT'S, NOT THE TREE'S.** 14 here, 13 in the 2026-10-07 report, 0
  non-`.sample` in both. Only the **0** is a property worth asserting.

## DELIVERABLES

* `.agents/slop/freshness/instruments.rows` — 26 instruments, TAB-separated:
  `instrument · what_it_checks · surface · reachable_yes_no · evidence`.
* This file.
