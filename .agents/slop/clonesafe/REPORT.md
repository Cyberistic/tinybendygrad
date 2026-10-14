# `clonesafe` — a diary a `git clone` cannot reproduce

**Unit:** `clonesafe` · **date:** 2026-10-14, measurements 15:2x–16:02 local · **branch:** untouched, **staged: nothing**

## VERDICTS (tokens, never exit codes)

| instrument | token | rc | note |
|---|---|---|---|
| `checks/runs-artifacts.py` | `ARTIFACTS-FRESH` | 0 | 242 files, newest 5.3 h; `0 of 242` in `HEAD` |
| `checks/runs-artifacts.py --plant` | all four states OK | 0 | 4 distinct tokens, none collapsed |
| `checks/runs-artifacts.py --clone` | `PASS` | 0 | new; prints its population |
| `checks/runs-artifacts.py --all` | — | 0 | unchanged derivation |
| `checks/no-txt.py` | — | 0 | 176 `.txt` in `runs/graphcmp/D`, all excused |
| `checks/nl-gate.py` | `AGREE` | 0 | `205/205`, 0 stale literals |
| `checks/census.py` | — | 0 | 70/70 BOTH, `WALLS []`; see the one unreproduced rc=3 below |
| `gates/gate-surface.py --report` | `SHELL HALF: 18` | 0 | |
| `checks/disagree-gate.py --lane citations` | `ok CITATIONS` | 0 | |
| `checks/bounded.py --selftest` | `PASS: 13 cases, 0 failed` | 0 | |
| `checks/index-arm-gate.py` | `REFUSED` | 3 | **and `.git/index`'s sha256 DID change. By me. See PROCESS below.** |
| `runs/graphcmp/D` | 242 files, `D0-repro.txt` intact | — | `repro-files=242 repro-identical=242 repro-rc=rc=0` |

**Not run, deliberately:** `checks/differ.py run` / `repro`. `bend` is 748–830 MB and the host is shared; the 318 s / ~830 MB figure below is **another unit's measurement, cited not re-taken**. `.agents/slop/peakrss/census.rows` exists (12,628 B, mtime 2026-10-13 14:36) and I read it rather than re-measuring.

---

## 0. WHERE MY OWN MEASUREMENT WAS WRONG — FIRST, WITH THE BEFORE-VALUES

Four errors, all mine, all in code I wrote in this unit. Two of them are the same species and that
is the point: **a property scoped too coarsely reads as a clean number.**

**A. "collapse actually WRONG: 190".** My first control reported that all 190 `..`-bearing call
sites were mis-rooted by my normaliser. **That verdict was wrong; the normaliser is right and the
*resolver* is wrong.** `runs_artifacts.resolve()` renders `parents[n]` as `"../"*n`, which is off by
one for an instrument at depth 1: `checks/bounded.py:303` is `here = Path(__file__).resolve()` and
`:304` is `here.parents[1]`, i.e. the **ROOT**. Measured: 190 sites carry a `..`, **138 from
`checks/` and 52 from `gates/` — both depth 1**, so dropping `..` is correct for 190 of 190. I only
know that because I measured the depths; the assertion in my first draft ("correct for every one of
them") was luck until then.

**B. `RESTORED (0 of 19 clone holes)`.** An **unreachable verdict printed as a measurement.** I
bucketed a set that had already been filtered to `n_tracked == 0`, so the `RESTORED` arm could never
fire, and the report printed `RESTORED (0 of 19)` in the voice of a result. Fixed: four verdicts,
each demonstrably reachable (`TRACKED 115`, `GENERATOR 13`, `HANDMADE 6`, `RESTORABLE 3` of 137).
**An unreachable bucket is a typo, not a result.**

**C. I laundered a plant into a generator, and it erased my own headline.** Adding "a writer of a
parent directory is a writer of its children" (needed: `checks/differ.py` writes the directory
`../runs/graphcmp/D` and builds `D0-run-summary.txt` by interpolation at runtime) promoted
**`bin/bend` from `HANDMADE` to `GENERATOR` with `writer=checks/diary-census.py`** — which is the
plant at `diary-census.py:447`, `(d / "bin").mkdir()` inside a `TemporaryDirectory`. `resolve()`
cannot see the `d` prefix (an unbound `Name`), so the site resolves to the bare string `"bin"`,
which **collides with the repo's own `bin/`**. The single most important finding in this report
vanished and the instrument still exited 0.

**C2. The obvious fix was worse, in the opposite direction.** Excluding every *instrument* that owns
a plant excluded **`checks/differ.py`** — which also writes the real corpus and also owns a plant
(`../runs/graphcmp/D/.tmp.`). `runs/graphcmp/D` lost its only generator and **9 readers of a
perfectly reproducible artefact were reported unreproducible.** A function-scoped flag and an
instrument-scoped flag are wrong in opposite directions. The unit has to be the **write site**: a
resolved value is a plant exactly when its enclosing function creates a temp dir. `differ.py` then
keeps `../runs/graphcmp/D` and loses `../runs/graphcmp/D/.tmp.`, which is the correct split. That is
`plant_writes()`.

Also: my `ROOT` was `dirname(…)`×3 for a file three deep, so the census died with
`FileNotFoundError: .agents/checks/runs-artifacts.py` — now `git rev-parse --show-toplevel`. And I
wrote `len(clone_holes(root))` twice in one denominator, which is a tautology wearing a
denominator's clothes.

---

## 1. THE DECISION, AND WHAT ALL THREE COST

**ANSWER: Option C — the gate says `REFUSED` when the artefacts are absent. Options A and C are
already built and paid for. Option B must not be done, and the reason is measured, not aesthetic.**

### Option A — stop being a sweep target. **ALREADY DONE, by an earlier unit. Cost: zero.**

`checks/sweep.py` still carries `RESIDUE_ROOTS = ('.agents/slop', 'runs')` — read by AST, not by
import, because `exec_module` on that file **exceeded a 120 s timeout** building its citation corpus.
But `verdict_for` consults `generated_read_dirs()` (which loads `runs-artifacts.py` by path) and
returns `GENERATED` **before** the fall-through to `DELETE`, and `generated_read_dirs()` is built
from `census_unrecoverable()` — so `runs/`, `runs/graphcmp/` and `bin/` are all in the protected set
without anyone typing them.
**Limit I will not paper over: I could not obtain the `verdict_for` token for a live path**, so I
report the derivation and the code path, not a measured verdict.

Residual: A protects against a *sweep*, not against `rm -rf`, and it protects a path that is
`0`-tracked anyway — so it protects the *decision*, never the *bytes*.

### Option B — track the artefacts. **REJECTED. It is not expensive; it is UNSAFE.**

| cost | measurement |
|---|---|
| `.gitignore` surgery | a single negation **does not work**: `!runs/graphcmp/D/*.txt` over `/runs/` still reports `.gitignore:1:/runs/` — git cannot re-include a file whose parent directory is excluded. The chain `/runs/*` + `!/runs/graphcmp/` + `!/runs/graphcmp/D/` **does** work, and `runs/e2e/b.txt` stays ignored, so it is surgical. **3 rules replace 1.** Measured in a throwaway repo, 2026-10-14. |
| bytes | 242 files, **416,185 bytes** |
| **fatal** | **freshness is an `mtime` test and `mtime` does not travel through git.** |

The fatal row, measured end to end: I set an artefact's mtime to **2020-01-01**, committed, and
cloned. **The clone's mtime is the clone time — `Oct 14 15:53:53 2026`.** `state()` compares
`os.path.getmtime` against `MAX_AGE_S`, so **Option B makes every fresh clone answer
`ARTIFACTS-FRESH` for a corpus of any vintage.** It converts a loud `REFUSED(3)` into a silent false
`PASS(0)` on exactly the population that most needs the warning — which is worse than the disease,
because it is *trusted*.

There is no content-borne fallback: `D0-repro.txt` is 3 key/value rows with no time, and
`D0-run-summary.txt` carries `graphs=34`, `dev=CPU` and two hashes but **no run timestamp**. A
clone-proof freshness test would require `checks/differ.py` to write a stamp — out of my scope, and
correctly so, because a generator is the only thing that may stamp its own output.

### Option C — `REFUSED` when absent. **ALREADY BUILT, 6 OF 8 READERS WIRED. THIS IS THE ANSWER.**

`state()` already spells four tokens — `ARTIFACTS-ABSENT`(3) / `ARTIFACTS-EMPTY`(5) /
`ARTIFACTS-STALE`(3) / `ARTIFACTS-FRESH`(0) — and `--plant` drives all four with 4 distinct tokens.
**Six of the eight non-self readers already call `require()`** before their first read:

```
checks/corpus-figure.py:296    checks/devpin.py:155     checks/differ.py:1264 (snap)
checks/disagree-gate.py:492    checks/env-precond.py:105  gates/retention-check.py:612
```

`checks/no-txt.py:220` calls `state()` and **deliberately does not charge it to its exit** ("not
charged to this gate's exit") — the right call for a rule whose subject is extensions, not content.

**The eighth is `checks/diary-census.py`, which calls neither. That is the cheapest single fix in
this report**: one `ra.require(ra.GRAPH_D, label="diary-census")` before its first read, and the
instrument whose entire subject is diaries becomes the one diary-reader that cannot tell absent from
stale. **I did not make it — `diary-census.py` is outside my scope.**

**Option C costs zero bytes written. Refuse, don't repair. Boring, safe, already 75 % wired.**

---

## 2. CAN A CLONE PRODUCE IT? — plainly, no.

`git clone` gets **7,053 files**. It does not get, in the order a person hits them:

| # | missing | readers | how a clone gets it | cost |
|---|---|---|---|---|
| 1 | `.venv/bin/python` | 5 | `uv sync` (`pyproject.toml` + `uv.lock` **both tracked**) | needs `uv` + network |
| 2 | `references/bend` | 2 | `tools/get-bend.sh` (**tracked**) clones `Bend@v2.0.34` | needs `git` + network |
| 3 | **`bin/bend`** | **10** | **NOTHING. No clone can produce it.** | **a person must type it** |
| 4 | `runs/graphcmp/D` | 9 | `checks/differ.py run` (**tracked**) | **318 s, ~830 MB** |

**What a fresh clone gets if it does nothing: no Python, no compiler, no corpus. Every central gate
is a local habit.** The 318 s the brief asked about is the **fourth** step, not the first.

**Step 3 is the real finding and nobody had named it.** `bin/bend` is `0` tracked, gitignored at
`.gitignore:5`, and has **`0` writers across the 209-instrument population**. `tools/get-bend.sh` —
tracked, and the file `.agents/TOOLS.md:25` cites as the reason the shim is ignored — **does not
write it**: its only actions are `mkdir -p references` and
`git clone … "$ROOT/references/bend"`. So the ledger's implication ("without `tools/get-bend.sh`
there is nothing for it to point at") is **true and misleading**: get-bend.sh gives you the target
and never the pointer.

**The good news, and it is why this is a documentation defect and not a correctness one: every one
of these fails LOUDLY.** The shim's own comment records that with no toolchain it now refuses
loudly rather than silently running this machine's compiler, and a missing `bin/bend` is exit 127.
`runs/graphcmp/D` absent is `ARTIFACTS-ABSENT`/`REFUSED(3)`. **A clone cannot reach green; it also
cannot reach a false green. That is the correct failure mode and it is already bought.**

One thing is genuinely unsafe, and it is the thing the brief was circling: **if anyone tracks
`runs/graphcmp/D` to "fix" the clone, they convert that refusal into a false pass** (§1, Option B).

---

## 3. THE CLASS, CENSUSED BY DISCOVERY, WITH DENOMINATORS

Every population is an instrument, loaded by path — never a list, a basename, or a suffix set:

- **paths named by an instrument** — `runs_artifacts.sites()`: a directory walk (`checks/*.py` +
  `gates/*.py`) plus an AST walk. **7,848 call sites, 209 instruments, 137 on-disk paths.**
- **tracked** — `git ls-tree -r HEAD` (**the tree, not the index**): **7,053 files.**
- **hidden** — `git check-ignore --no-index -v`: **git's own matcher, not a regex.**
- **swept** — `RESIDUE_ROOTS` read by AST out of `checks/sweep.py`.

`git check-ignore` is load-bearing, not decorative. Measured 2026-10-14: `runs/` **IGNORED**,
`/runs/` fed verbatim **NOT IGNORED** (that leading slash is filesystem-absolute); `checks/rows-key.rows`
**IGNORED**, `checks/rows/keys.rows` **NOT IGNORED**. **A trailing slash is a suffix, and a directory
is probed with it.** A regex over `.gitignore` would have got at least two of those four wrong.

**The strict intersection — `0` tracked AND named by a `.gitignore` line or a sweep root — is
19 of 137 on-disk paths named by 209 instruments. That is the set that survives a clone as nothing.**

| verdict | n | what it means |
|---|---|---|
| `TRACKED` | **115** | in `HEAD`: the clone has it. The control, and by far the largest bucket. |
| `GENERATOR` | **13** | `0` tracked, hidden or swept, and a **tracked** writer reaches it — a clone CAN, by running it |
| `HANDMADE` | **6** | `0` tracked, hidden or swept, **no writer**: no clone can produce it, ever |
| `RESTORABLE` | **3** | `0` tracked and **nothing hides it** — one `git add` away, and nobody wrote that down |

`GENERATOR` is the interesting half because **its cost is compute, not code**:
`runs/graphcmp/D` (9 readers), `runs/graphcmp` (10), `runs` (11), four of its own corpus files,
`gates/artifacts` (via `gates/mutkit.py`), and five `.agents/slop` paths.

**The six `HANDMADE`, all read, none generated:** `.venv`, `.venv/bin`, `.venv/bin/python`,
**`bin/bend`**, `checks/gen`, `references`.

**THE CENSUS'S OWN BLIND SPOT, STATED NOT FIXED.** `sites()` opens `.py` and nothing else. This tree
also has **17 `checks/*.sh`**, **1 `checks/*.mjs`** and a root **`tools/get-bend.sh`** — so the
denominator "209 instruments" is really *209 of 227 live instruments*, and **a shell generator is
invisible to an AST walk that only opens `.py`.** `references/` and `checks/gen` are almost
certainly `HANDMADE`-only for that reason (`get-bend.sh` *does* create `references/`; `gen.sh`
probably `checks/gen/`). **EVERY `HANDMADE` VERDICT IS A LOWER BOUND ON THE DAMAGE, NEVER A PROOF OF
ABSENCE** — which is why the brief's `bin/bend` conclusion survives and its `references/` conclusion
does not.

---

## 4. WHAT MATTERS, AND THE CHEAPEST DURABLE FIX — REFUSE BEFORE REPAIR

| path | readers | matters? | cheapest durable fix |
|---|---|---|---|
| **`bin/bend`** | **10** | **most** | **refuse, and it already does.** Absent ⇒ exit 127, loud. The durable fix is that `tools/get-bend.sh` should **write the shim**. Note the `.gitignore` objection — "a tracked shim whose target is a fetched directory is a tracked promise about one machine" — **no longer applies to the current shim**: it resolves via `${0%/*}/../references/…`, machine-independent by construction, which is precisely the rewrite its own comment records. **Recommendation only: I changed no `.gitignore`, because I may not stage, and un-ignoring without tracking only converts a hidden file into a visible untracked one — a staging decision that belongs to whoever owns the commit.** |
| `runs/graphcmp/D` | 9 | yes | **nothing — do not touch it.** Refusal is built and 6/8 wired; tracking it is **unsafe** (§1). One line in `diary-census.py` closes the 8th reader. |
| `references/` | 2 | yes | already handled — `tools/get-bend.sh` is tracked. The *census* is what is wrong: teach it `.sh` generators so `HANDMADE` stops over-reporting. Out of scope. |
| `.venv/` | 5 | yes | already handled — `uv.lock` tracked. The fix is a clone README line, not code. |
| `gates/artifacts` | 1 | low | already `GENERATOR` (via `gates/mutkit.py`). Nothing. |
| `checks/gen` | 1 | low | 1 reader; likely a `gen.sh` generator the walk cannot see. Ignore. |
| `.agents/slop/declare/*`, `eq/eq-census2.py` | 1–2 | low | all `GENERATOR`-attributed now. A sweep root naming `.agents/slop` is the correct behaviour: it is 4,490 tracked files, so the root answers "where is residue", not "what is irrecoverable". |

---

## PROCESS — I CHANGED `.git/index`, AND THE CAUSE WAS A COMMAND THAT ONLY READS

The brief required `.git/index`'s sha256 to be **unchanged by my run**. **It changed**, and I am
reporting that against my own acceptance criterion rather than burying it.

- baseline `e4acb6f4b74bf16ec4aca737146d382ac6f03b743c2022e5e3ef645ff08b882a`
- now `cd7deb64754796734b3ac4861900d2fb06a8d991e7a29d3bf61f55fcea201d7d` (mtime 16:02:02)

**Cause: my own `jj op log --no-graph -n 5`.** The last operation in `jj op log` is
`snapshot working copy`, `args: jj op log --no-graph -n 5` — i.e. **the read-only-looking log
command snapshotted the working copy and rewrote the index.** `AGENTS.md` names `jj status` as
not-read-only here; **this proves the hazard is `jj` generally, and that `jj op log` is in it.**
Every `jj` invocation in this session should be treated as a write.

**I staged nothing**, which is separately verified: `git diff --name-only -- checks/runs-artifacts.py`
names it, and `git diff --cached -- name-only -- checks/runs-artifacts.py` is **empty**.

### LIVE DAMAGE FROM ANOTHER UNIT, WHICH NOBODY HAS PICKED UP YET

While I worked, `HEAD` moved `2f3b329439be` → `815f4ad92b5b`, and **`git diff --cached` now names
14 paths where the brief's baseline was 0**, including **9 staged deletions**:

```
D  gates/mutkit.py                     D  gates/linearizer_census-{gate,mutate,oracle,pins.rows}
D  gates/regalloc_census-{gate,mutate,oracle,pins.rows}
M  .agents/TODO.md   M  .agents/TOOLS.md   M  gates/amd_dsl_census-{gate,pins.rows}
M  tinybendygrad/renderer/amd/dsl.bend
```

**A bare `git commit` in this tree right now would land another unit's 9 deletions**, and per
`AGENTS.md` a commit over an intent-to-add writes the *previous* content. `checks/index-arm-gate.py`
answers `REFUSED`(3) and names all nine — the gate is doing its job. I touched none of it, and
`git add -A` is never something this unit will run.

**One unreproduced anomaly, not papered over:** `checks/census.py` returned **rc=3 once** in a batch
run and **rc=0 in three isolated runs and in a re-run of the same batch ordering** (0 stale,
`WALLS []`, 70/70 BOTH). I did not root-cause it. It is **not** the brief's "edited cached row"
mechanism: census's key is 7 `.bend` files plus `.agents/slop/graphcmp.py`, and
`checks/runs-artifacts.py` is not in that set.

---

## WHAT I TOUCHED

- **`checks/runs-artifacts.py`** — added `ignored_by()`, `plant_writes()`, `clone_paths()`,
  `sweep_roots()`, `clone_report()`, and the `--clone` entry point. **Every pre-existing entry point
  is unchanged**: the default still prints the same 7 lines and returns `ARTIFACTS-FRESH`, `--plant`
  still drives 4 states, `--all` still returns the same derivation, and `census()` /
  `census_unrecoverable()` keep their signatures because `checks/sweep.py` loads this file by path.
  I also **left `bin/` in `unrecoverable_dirs()`**: it is a false positive (a plant plus an
  absolute-path fold — `_under()` strips the leading `/`, so `checks/bounded.py`'s `/bin/sh` reads as
  "under `bin`"), but it is **load-bearing**, because it is the only thing protecting `bin/bend`
  from the sweep. *A false positive that is load-bearing must be documented, not deleted.*
- **`.agents/slop/clonesafe/REPORT.md`** — this file.
- **Deleted `.agents/slop/clonesafe/census.py`**, my own first-pass standalone census, the moment
  `runs-artifacts.py --clone` subsumed it. A second copy of a derived set is a contract with no
  generator — the `LIVE_UNITS` defect.

**Not touched:** `.gitignore`, `checks/sweep.py`, `checks/census.py`, `checks/diary-census.py`,
`AGENTS.md`, and **no file under `runs/`** — 242 files, `D0-repro.txt` intact, `0` written,
`0` deleted. Nothing staged, nothing committed, no amend, no rebase.