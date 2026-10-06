# THE UNOWNED 71 — who wrote them, who reads them, what breaks without them

Instrument: `checks/unowned.py`. Reproduce with
`python3 checks/unowned.py --from .agents/slop/stale71/set77.rows` (the `--from` is not
decoration: six units are running and the dirty set grew from 77 to 134 paths during this unit).
The file is named `set77` because it holds 77 paths, of which 71 are the brief's and 6 arrived
after it was written — see §1.

**THE HEADLINE, AND IT CHANGES THE PREMISE.** While this unit was measuring, commit
**`afd395686`** landed. It is not on `HEAD` (`git merge-base --is-ancestor afd395686 HEAD` → rc 1);
it lives only on `refs/jj/keep/afd39568618a8cbe330fad3ac6f1864c0738821b`, its parent is
`ec08adcfb`, and **its commit message is 1 byte — a newline.** It carries 118 files and
**76 of the 77 paths in this inventory.**

So the 71 are not lost and they are not unowned. They are **snapshotted under a change-id with an
empty description**, which is strictly worse than unowned: an unowned path can be found by
`git status`, and this one cannot, because a reader who lands `afd395686` sees a green tree with
no message explaining what 118 files are for.

## 1. THE 71, TABLED

`CIT` = whole-token mentions in committed files. `EXE` = mentions inside a string literal in a
code file (a path in a `#` comment is prose wearing a code file's clothes). `WRT` = a committed
site writes it.

| PATH | OWNER | CIT | EXE | WRT | VERDICT |
|---|---|---|---|---|---|
| `checks/rows-*.rows` (51) | `afd395686` | 0 | 0 | – | **GENERATED** via `checks/census.py:64` |
| `.agents/slop/helpers-tc-gate.{rows,bn,bd,rows.err,bn.err,bd.err}` (6) | `afd395686` | 2–7 | 0 | – | **GENERATED** via `helpers-tc-gate.sh:34` |
| `.agents/slop/residue/{000,002,003}-*.md` (3) | `afd395686` | 5–11 | 2–3 | 1 | **GENERATED** by `checks/residue.py:586` |
| `.agents/slop/e2e/{e2e_mm,webgpu_call}.mjs` (2) | `afd395686` | 7–10 | 3–4 | 1 | **GENERATED** by `e2e_mm_run.mjs:54,56` |
| `checks/gen/{probe.js,probe.gen.c}` (2) | `afd395686` | 24–29 | 1–3 | – | **GENERATED** by `checks/abi_gate.py:508` |
| `.agents/slop/ops_bend-milestone-expected.txt` | `afd395686` | 28 | **6** | 0 | **LOAD-BEARING** |
| `.agents/TODO.md` | `afd395686` | 348 | **7** | 0 | **LOAD-BEARING** |
| `.agents/slop/notes/bend2-constraints.md` | `afd395686` | 404 | **36** | 0 | **LOAD-BEARING** (see §5) |
| `.agents/slop/shells/README.md` | `afd395686` | 41 | **9** | 0 | **LOAD-BEARING** (see §5) |
| `.agents/slop/webgpu_call.fresh.mjs` | `afd395686` | 5 | **1** | 0 | **LOAD-BEARING** |
| `tinygrad/tinygrad` | `afd395686` | 1 | 1 | 0 | **DANGLING SYMLINK — see §4** |
| `bin/bin` | `afd395686` | 0 | 0 | 0 | **DANGLING SYMLINK — see §4** |

**Tally of the 71: 64 GENERATED · 6 LOAD-BEARING · 1 INERT (and that one is a hazard, not a
file).**

Six further paths appeared after the brief was written and are *not* in its 71:
`.agents/slop/gendirs/{properties,writetargets}.py`, `.agents/slop/loopq/00-rows.md`,
`.agents/slop/offrepo/{callers.py,reached.tsv,where.py}`. `afd395686` absorbed six of the seven;
`ec08adcfb` (`loopq`) absorbed `loopq/00-rows.md`. The seventh, `offrepo/callers.py`, is `afd395686`'s.

## 2. THE LOAD-BEARING SUBSET, WITH THE IMPORTER FOR EACH

- **`.agents/slop/ops_bend-milestone-expected.txt`** — the only one that is a *gate input*.
  Chain: `checks/e2e.py:434` runs `./.agents/slop/opsbend-milestone.sh`, whose header names it, and
  `.agents/slop/opsbend_milestone_gate.py:27` opens it:
  `EXPECTED = pathlib.Path(__file__).parent / "ops_bend-milestone-expected.txt"`.
  Five committed transcripts already record what its absence does:
  `.agents/slop/e2estage8/artifacts/{live1,post}.{oracle,port}.out` all carry
  `FileNotFoundError: [Errno 2] ... ops_bend-milestone-expected.txt`. **Discarding it turns e2e
  stage 5 from a verdict into a crash.** It is also a `.txt`, so it is one of the 563 hard
  violations `checks/no-txt.py` reports (rc 1). Land it, and rename it to `.rows` in the same
  commit — it is expected values, which is what `.rows` means here.
- **`.agents/slop/webgpu_call.fresh.mjs`** — sole importer `.agents/slop/e2e_mm_run.mjs:52-54`,
  declared on one line and written on the next: `const fresh = join(HERE, "webgpu_call.fresh.mjs")`
  then `await emit(join(ROOT, "tinybendygrad/runtime/webgpu_call.bend"), fresh)`. e2e stage 3 fails
  without it. **But** it is a *generated* file that only exists to be `copyFile`'d to
  `.agents/slop/e2e/webgpu_call.mjs` four lines later, and `.agents/slop/unknowns/after.rows:235`
  already ruled `DELETE` on it. Land the deletion, not the file.
- **`.agents/TODO.md`** — read by `checks/residue.py`, `checks/differ.py`,
  `.agents/slop/difftxt/inventory.py`, `.agents/slop/gatecensus/classify.py`,
  `.agents/slop/gate-roster-arith.py`, `.agents/slop/helpers-tc-gate.sh`,
  `.agents/slop/txtgen/docs-agree-with-driver.py`. A ledger several gates parse is infrastructure.
- **`.agents/slop/notes/bend2-constraints.md`**, **`.agents/slop/shells/README.md`** — see §5.
  Both are `CITED-ONLY` in the sense that matters: no gate opens them, but they are the only place
  a rule is written down, and §5 measures that their citations are decaying.

## 3. WHAT CHANGES IF DISCARDED — MEASURED, PER GROUP

- **51 `checks/rows-*.rows`** — `checks/census.py:60-71` reads the cache when present and
  **regenerates it on miss inside a `try`**. Measured: `python3 checks/census.py` → **rc 0, 25/25
  graphs × 2 lanes = 50/50 `CACHE` hits, 0 emissions, `WALLS: []`.** So discarding changes nothing
  *except* that the files come back. **And that is the finding, not a reassurance:** with the cache
  committed, `census.py` derives its entire census — `reached PY 61 / reached BEND 53 / NEITHER
  16` — from 50 files nobody wrote on purpose. It re-derives nothing. It is green because of
  unowned data, which is the `abi.json` failure mode with the volume turned up and the crash
  removed. **Untrack and gitignore; the census becomes a measurement again.**
- **One of the 51 is an orphan: `checks/rows-trange-bend.rows`.** `trange` is not among the 25
  names in `graphcmp.GRAPHS`, it is the only `-bend` file with no `-py` partner, and its mtime is
  05:05 — 28 minutes before the other 50 (05:32–05:34). It is a cache entry for a graph that no
  longer exists. Discarding it changes nothing at all.
- **6 `helpers-tc-gate.*`** — `helpers-tc-gate.sh:34` sets `GT=.agents/slop/helpers-tc-gate` and
  lines 42/59/62 write `$GT.rows`, `$GT.bd`, `$GT.bn` and their `.err`s. Regenerated on the next
  `sh .agents/slop/helpers-tc-gate.sh`. Inert.
- **3 `residue/*.md`** — `checks/residue.py:586` writes them. They are modified because
  `residue.py` was re-run. Regenerated. Inert.
- **2 `.agents/slop/e2e/*.mjs`** (2.2 MB) — `e2e_mm_run.mjs:54,56`. Inert; this is the same
  emitted-bundle class that got `runtime/dtype.js`'s stage-8 denominator retired at 0.
- **2 `checks/gen/*`** (268 KB) — `checks/abi_gate.py:508` `gendir = HERE / "gen"`. Inert.

## 4. THE TWO PATHS THAT ARE NOT FILES

`afd395686` records both as **mode `120000` — real symlinks**:

```
bin/bin         -> /private/var/folders/yd/…/T/opencode/wt-a/bin
tinygrad/tinygrad -> /private/var/folders/yd/…/T/opencode/wt-a/tinygrad
```

Both targets are **MISSING**. These are scratch-worktree shortcuts, they are dangling on this
machine already, and landing `afd395686` as it stands gives every clone two broken symlinks into
another machine's temp directory. **This is the one item I would block on.** Separately, the
*index* holds both as `100644 e69de29` — `git add -N` intent-to-add placeholders — which would
commit them as **empty regular files** instead. Either way they must not land.

**And the brief's premise about `checks/gen/` is measurably wrong, in a way that matters.**
`git ls-tree HEAD checks/gen/` is **empty** — these are not in HEAD. `git ls-files -s` prints the
*index*, and the index carries `e69de29` for **373 paths**, because someone ran `git add -N`. So
"committed as two empty blobs" is an artefact of reading the index and calling it HEAD.

## 5. PATHS WHOSE ONLY CLAIM ON EXISTENCE IS A CITATION I MEASURED STALE

The brief asks me to test against "the ten stale-citation classes". **There are not ten.**
`checks/citation-gate.py:53` — untracked, another unit's, written at 06:51 — declares **seven**:
`("HOLDS", "STALE-LINE", "WRONG-FILE", "NO-FILE", "STALE-RULE", "PROSE", "PAST-EOF")`. I ran its
classifier against these paths by hand, because its `CITE` regex is `…\.py:(\d+)` and **it
therefore cannot see a single one of the citations that matter here**:

- **`checks/gen/probe.js` — STALE-LINE, twice over.** `.agents/slop/DTYPE-ABI.md:10` claims
  `gen/probe.js` is **894 lines**; it is **1415**. `DTYPE-ABI.md:41` claims `probe.js:777` holds
  `op.run(...op.args, op.kont)`; line 777 is `const _r_0 = _s_0["r"];`.
- **`checks/gen/probe.gen.c` — STALE-LINE.** `DTYPE-ABI.md:10` claims **5,007 lines**; it is
  **8,647**. `DTYPE-ABI.md:39` claims `probe.gen.c:3133` holds `io_eff_rows[c].run(e, fs, w)`;
  line 3133 is `}`.
- **`.agents/slop/helpers-tc-gate.rows` — STALE-LINE and WRONG-FILE.** `revive/REVIVE.md:217`
  describes it as **`helpers-tc-gate.py`**, a name that no longer exists (renamed to `.rows`,
  `.agents/TODO.md:385`), and says **199 lines**; it is **237**. Six committed files still cite the
  dead `helpers-tc-gate.py`.

Both generated pairs clear the brief's test exactly: *held only by a citation, citation is a stale
class, therefore the claim on existence is false* — and on top of that they are regenerable. So
discarding them is **right**, and keeping them is the accident.

`.agents/slop/notes/bend2-constraints.md` (36 execution sites) and `shells/README.md` (9) are the
inverse case: heavily cited, never opened, and the brief's own note is that a citation is a thing
that can be wrong. They stay, and their citations need the same treatment.

## 6. THE PROPOSED GROUPING — ONE PER OWNER, BY EXPLICIT PATH

Do **not** `git add -A`. There are 134 dirty paths now and another unit is mid-run.

1. **`afd395686` — DO NOT LAND AS IT IS.** It is one untitled blob of at least four units'
   work. Either give it a description naming them, or split it. If splitting, the paths are:
   - **generated → drop, then `git add .gitignore`**: `checks/rows-*.rows` (51),
     `checks/gen/probe.js`, `checks/gen/probe.gen.c`,
     `.agents/slop/helpers-tc-gate.{rows,bn,bd,rows.err,bn.err,bd.err}`,
     `.agents/slop/residue/{000-the-residue,002-unknown,003-disagreements}.md`,
     `.agents/slop/e2e/{e2e_mm,webgpu_call}.mjs`
   - **blockers → remove first**: `bin/bin`, `tinygrad/tinygrad`
   - **keep, renamed**: `.agents/slop/ops_bend-milestone-expected.txt` → `.rows`, with
     `opsbend_milestone_gate.py:27` updated in the same commit
   - **keep, delete**: `.agents/slop/webgpu_call.fresh.mjs`
   - **genuinely someone's**: `.agents/TODO.md`, `.agents/slop/notes/bend2-constraints.md`,
     `.agents/slop/shells/README.md` — one commit each, message naming the unit.
2. **`ec08adcfb` (`loopq`) — already landed, message present.** `.agents/slop/loopq/00-rows.md`
   is its. Nothing to do.
3. **`checks/unowned.py` — mine, uncommitted, one commit.** It is the only file I created.

## 7. CROSS-CHECK: `checks/repro-paths.py`

Run, not edited. **rc 1, NOT CLEAN.** 324 committed reports name 314 distinct paths (+2 written as
patterns); **251 resolve, 63 dangle**. Output at `.agents/slop/stale71/repro-paths.out`.
**It flags none of the 71** — because they all exist on disk right now, which is the point: it
answers "does a committed report name a path that does not exist", and the 71 answer the *other*
question, "does an existing path have a recorded purpose". It cannot see that, and neither can
`git status`. Note `.agents/slop/abi/abi.json` is on its dangling list: `abi.json` was restored at
`checks/abi.json`, so that citation is now wrong-*location*, not wrong-existence — a class
`repro-paths.py` does not have a verdict for.

## 8. WHAT I COULD NOT SETTLE

- **Who wrote the 71.** `afd395686` has a 1-byte description and I have no way to recover the
  author. Its file list is consistent with at least four units (gendirs, helpers/tc, e2e, offrepo,
  loopq, devpin). Guessing would repeat the error this unit exists to measure.
- **Whether `afd395686` is intended to land.** It is a jj *keep* op, not on `HEAD`. A keep op can
  be deliberate or abandoned; nothing in the tree says.
- **The 6 post-brief arrivals** (`gendirs/*`, `offrepo/*`, `loopq/00-rows.md`) belong to units
  still writing at 06:31–06:35. I inventoried them but make no claim on their contents.
- **`census.py`'s cached verdicts are unverified.** I measured that it replays 50/50 and emits 0.
  I did not run `--fresh` (that re-emits through `bend`, which I was told not to run), so I cannot
  say whether the cached rows still match what the port produces today. **That is the open
  question, and it is the one that decides whether the 51 files are merely redundant or actively
  misleading.**
- **`checks/citation-gate.py` and `checks/txt-owners.py` are untracked and belong to a live unit.**
  I read `citation-gate.py` to recover the class list and edited nothing.
