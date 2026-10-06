# `checks/substrate.py` — what it measures, and the sweep nobody runs

Unit: substrate2.  Repo HEAD at measurement: `705e7a644a3c0ce1c037320d23a614221a14ad60`.
All python run as `.venv/bin/python`, never bare `python3`.  **`bend` was NOT run** (another unit
holds it); every claim below that needs `bend` is labelled and its lane is left `READ-ONLY`.
Raw captures in this directory: `names-only.out`/`.err`, `node-lane.out`, `plant.log`,
`pop.bend.list` (the 138-file population, discovered by `os.walk`).

The bare name `substrate-check.sh` resolves to nothing (`command -v` absent, no root file — measured
earlier by the orchestrator).  The real gate is `checks/substrate-check.sh` (46 lines, `wc -l`) — an
`exec` shim onto `.venv/bin/python checks/substrate.py` (765 lines, `wc -l`).

---

## 1. WHAT IT MEASURES (one claim, one `file:line`)

**HALF 1 — per-file parse/syntax verdict, routed by file EXTENSION** (`instrument_for()`,
`substrate.py:305-317`):

| suffix | instrument | verdict |
|---|---|---|
| `.bend` | `bend --check-only` | WARM iff first merged line == `ALL PROOFS CHECK` (`:359-368`) |
| `.c` | `cc -fsyntax-only` + bend's emitted C context | WARM iff `rc==0` (`:392-417`) |
| `.js`/`.mjs` | `node --check` | WARM iff `rc==0` (`:373-391`) |
| anything else | — | `NO INSTRUMENT`, never COLD (`:317`) |

Pre-gate `MISSING`/`EMPTY` at `:332-343` (0 lines OR 0 bytes → a `+1` finding).  The class router is
**a SUFFIX SET** (`path.endswith(...)`, `:311-317`) — Doctrine 1.

**HALF 2 — import-graph name resolution** (`half2()`, `:546-621`): for each file, parse
`^import (?:\./)?<path>.bend as <Alias>$` (`IMPORT`, `:485`), build the union of names the imported
modules DECLARE (`decls()`, `:507-535`: `def`/`type`/`law` at col 0 + indented variants), then resolve
every `Alias.name` reference (`REF`, `:490`).  A ref is `exact`, `suffix-only` (only a suffix matched —
a finding, `:602-605`), `unresolved` (`NOT DECLARED IN <module>` — a finding, `:606-609`), or `unseen`
(the alias is not an import alias at all — **not** a finding, `:591-594`).  `BAD` = deduped problem
sites (`:620`).  A missing import TARGET is caught: `missing_module` (`:581-583`, `:617-618`).

**PROVENANCE** (`provenance()`, `:422-481`): `port` iff `git ls-files --error-unmatch -- <p>` (`:444`)
AND `tinygrad/<...>.py` exists (`:450-451`); the **PORT ALARM** (`:465-472`) fires for any path under
`tinybendygrad/` that is not in the index.

**ORACLE PIN** (`ORACLE_PIN`, `:82-85`; `oracle_drift()`, `:111-128`; enforced in `main()`, `:744-752`):
sha256 of `.agents/slop/substrate/oracle-check.sh` = `6d1000712f0f…600e` (verified on disk, matches).

### THE DOCTRINE-1 FINDING — the population is a HAND LIST

`run(files, ...)` (`:688`) iterates **`files`, which is `argv[i:]`** (`split_leading()`, `:144-166`;
`main()`, `:754-755`).  **There is no `os.walk`, no glob, no generator declaration anywhere in the
file.**  The instrument cannot name its own population, so `SUBSTRATE CLEAN: N file(s)` is relative to
whatever the caller typed and carries **no denominator of the tree**.

Its own usage line admits this — `find tinybendygrad -name '*.bend' | xargs checks/substrate.py`
(`:683`).  And **no tracked caller runs that line.**  Every executable invocation site passes a hand
list of one or two files:

- `checks/run-f64.sh:105` → `"$ROOT/tinybendygrad/renderer/cstyle.bend"` — **1 file**
- `checks/disarm.sh:27` → `"$PROBE" tinybendygrad/runtime/zzread.bend` — **2 files**

So AGENTS.md's *"import-graph and cold-file sweep over the `.bend` tree"* names a **capability, not an
occurrence**: the full-tree sweep is performed by nobody automatically.  That is the doctrine-1
finding, in the stronger form — not a wrong list, but **no population declaration at all**.

---

## 2. RUNNING IT — rc AND verdict token, WITH DENOMINATORS

### 2a. MISUSE is refused (no bend)
`.venv/bin/python checks/substrate.py` with zero args → **rc=3**, `REFUSED: no files given…`
(`refuse()`, `:672-685`).  Correct: `SUBSTRATE CLEAN: 0 file(s)` would be indistinguishable from a
green run.  (Not a `SKIP`; a `REFUSED`, exit 3.)

### 2b. Full `.bend` population — `READ-ONLY — compiles bend`
HALF 1's `.bend` lane calls `bend` (`:361`), and the `.c` lane calls `bend -o` to build the C context
(`Ctx.ok()`, `:266`).  **I did not run `bend`.**  So I report the population run under `-n`
(HALF 2 + PROVENANCE, zero `bend` invocations — `opts.names_only` short-circuits the bend lane at
`:351-353`).  Population (denominator) discovered by `os.walk("tinybendygrad")`: **138 `.bend`**
(files under `tinybendygrad/`: 152 = 138 `.bend` + 2 `.c` + 3 `.js` + 1 `.mjs` + 1 `.mut` + 7
`.staged-*` junk).

```
ROUTE   bend=0  cc=0  node=0  no-instrument=0  (of 138 file(s))   <- 0 because -n suppressed verdicts
PROVENANCE  port=113  non-port=25   of which not-in-index=1 no-upstream=25   (of 138)
PORT ALARM  1 file(s) inside tinybendygrad/ are not in the index.
DENOMINATOR .bend handed=138, of which non-port=25  =>  the port count to compare against is 113
TOTALS refs=36783 exact=36783 suffix=0 unresolved=0 unseen=47275 missing_module=0 dead_import=37
BAD 0
SUBSTRATE NOT CLEAN: 1 finding(s) across 138 file(s) …
RC = 1        VERDICT TOKEN = SUBSTRATE NOT CLEAN
```

Reading: **HALF 2 is CLEAN over all 138** (`BAD 0`; 36,783/36,783 refs exact, 0 unresolved, 0 missing
modules).  The single `+1` finding is the **PORT ALARM** on `tinybendygrad/test/_probe/v5.bend`
(untracked).  So the gate is **RED AT REST for a reason that is not a defect in the `.bend` port** —
see §3.

Coverage honesty: the instrument prints `unseen=47275` against `refs=36783` — **it declares that 47,275
qualified refs (56% of qualified refs) are outside its vision** (unaliased `import Base` surface).

### 2c. HALF 1 end-to-end WITHOUT bend — the `node` lane
4 `.js`/`.mjs` files (`os.walk`), full gate (no `-n`):
```
WARM  webgpu_call.js  WARM dtype.js  WARM sz.js  WARM webgpu_call.mjs
ROUTE bend=0 cc=0 node=4 no-instrument=0  (of 4)  |  TOTALS … unseen=111  |  BAD 0  |  RC=0
SUBSTRATE CLEAN: 4 file(s), all non-empty, each judged by its OWN instrument, all cross-file names resolved.
```
This proves HALF 1 and the verdict tokens with a real instrument; **only the `.bend` (and `.c`) COLD
counts are unmeasured by me** — `READ-ONLY — compiles bend`.

### 2d. The oracle pin CAN fail (so it is not a comment)
Non-destructive, via `SUBSTRATE_ROOT` on a scratch root:
- oracle MISSING → **rc=3** `ORACLE DRIFT: … MISSING -- the frozen oracle is gone`
- oracle WRONG sha → **rc=3** `ORACLE DRIFT: … b76ace3d… != pinned 6d100071…`
`READ-ONLY — compiles bend` does not apply here; no bend touched.

---

## 3. FALSE POSITIVES AND FALSE NEGATIVES

**Does it treat a missing import TARGET as resolvable?  NO.**  All 339 `import … as …` lines across
the 138-file population were re-checked: **0 dangling targets** (`missing_module=0`).  A planted
missing module (`import ./ghost.bend as G`) is caught — `missing_module=1`, `BAD 3`, rc=1 (`plant.log`
row 3).  The false-positive direction of Doctrine 1's "99+ absent paths" does **not** reach the `.bend`
import graph; those 99+ are under `.agents/slop/`, which no `.bend` file imports.

**FALSE POSITIVE — the PORT ALARM on a probe.**  `tinybendygrad/test/_probe/v5.bend` is untracked, so
`:465-472` fires `+1`, and the whole run reads `SUBSTRATE NOT CLEAN`.  The alarm's criterion
(untracked path under `tinybendygrad/`) is by construction unable to distinguish **"port file not
tracked"** from **"another unit left a probe on disk"** — its own message concedes *"a probe, a mutant,
or scratch copy"* (`:469-472`).  A reader seeing `1 finding(s)` can mistake a stray probe for a broken
substrate.  This is the gate's single live finding on the whole tree.

**FALSE NEGATIVE — `unseen` is 56% of refs.**  A reference through an UPPERCASE alias that is not an
import alias is counted `unseen` and **is not a finding** (`:591-594`).  Demonstrated: a file importing
`b.bend` and returning `Zzz.missing_whole_world(B.Thing)` — a name **no module anywhere declares** —
scores `unseen=1`, `BAD 0`, **rc=0, GREEN**.  Scaled to the real tree: **`unseen=47275` of the ~84k
qualified refs can be wrong with the gate green.**  The instrument discloses this (`:731-735`), which
is right; but it is a false-negative surface of 47,275 sites.

**FALSE NEGATIVE (smaller) — `dead_import` is reported, never failed.**  37 unused imports
(`:610-611`) do not move a verdict (`:708-712` counts only `BAD` and `PORT ALARM`).

---

## 4. THE PLANT — two distinguishable states

Scratch copy (`.venv/bin/python`, `-n`, no bend).  Fixture: `b.bend` declares
`type Thing is Data:` + `def Thing.make`; `a.bend` imports it.  (`plant.log`)

```
1 GREEN clean          rc=0  BAD 0  NAMES CLEAN: 2 file(s), all cross-file names resolved.
2 RED name-broken      rc=1  BAD 1  SUBSTRATE NOT CLEAN …   (B.Thing.ghost -> unresolved)
3 RED module-absent    rc=1  BAD 3  SUBSTRATE NOT CLEAN …   (missing_module=1, 2 unresolved)
4 GREEN restored       rc=0  BAD 0  NAMES CLEAN: 2 file(s), …
```
Break an import → RED (rc 1); restore → GREEN (rc 0).  **The sweep can go red.**  (This exercises
HALF 2; a HALF 1 `.bend` red would need `bend` — `READ-ONLY — compiles bend`.)

---

## 5. THE FOUR SHELL HAZARDS, PRESENT vs ACTIVE

Checked in **both** `checks/substrate-check.sh` (the shim) and
`.agents/slop/substrate/oracle-check.sh` (the frozen `#!/bin/zsh` body, 474 lines, sha `…600e`).

| hazard | present? | active? |
|---|---|---|
| `&&` masking a `diff` under `set -e` | **NO** | `set -e`/`setopt` appear **zero** times in either file (`grep` rc=1); no `diff` in the oracle. `&&` exists (`oracle:139,192-194,360,454`) but is harmless without `set -e`. |
| `EXIT` trap returning `rm`'s status | **YES** — `oracle-check.sh:167` `trap 'rm -rf "$SCR"' EXIT INT TERM` | **ACTIVE.** The trap body's last command is `rm`; on EXIT the script's status becomes `rm`'s status, not the gate's. Non-zero only on a failed `rm -rf`. |
| `<( )` process substitution | **NO** | `grep` finds none in either file. |
| `${=SUB}` (zsh word-split) | **NO** | `grep` finds none in either file. |

Net: of the four the project catalogued, **one is present and ACTIVE** (`EXIT` trap / `rm`), and the
other three are absent.  The shim's `:44` `[ -f pyproject.toml ] && [ -d tinybendygrad ] || { …; exit 3; }`
is the `A && B || C` shape but is not hazard 1 — there is no `set -e` for it to mask under, and its `C`
is an explicit `exit 3`.

---

## 6. VERDICTS

- **`checks/substrate.py`** — a real two-half gate, memory-bounded, oracle-pinned (the pin fails
  correctly).  **But it is not a "sweep": it declares NO population** (Doctrine 1) — the population is
  a hand list at every call site, and no caller passes the 138-file tree.
- **HALF 2 over the live 138-file tree: CLEAN** (`BAD 0`; 36,783/36,783 exact, 0 unresolved, 0 missing
  modules, 37 unused imports reported-not-failed) — denominator 138.
- **Gate at rest: RED (rc 1, `SUBSTRATE NOT CLEAN`)** — one PORT ALARM on an untracked probe, not a
  port defect.
- **Unmeasured by this unit: the `.bend` COLD count and the `.c` lane** — `READ-ONLY — compiles bend`.
- **False negative surface: `unseen=47275`** of ~84k qualified refs, plus `dead_import=37`, are
  invisible to the verdict.
