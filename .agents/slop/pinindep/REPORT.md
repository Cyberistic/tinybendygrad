# `RUN HEALTH : OK — 17 of 17 pins green` IS ONE MEASUREMENT WEARING SEVENTEEN HATS

**MEASURED 2026-10-07** by `.agents/slop/pinindep/{derive,sens,indep,table,layer1,mtime,redundancy}.py`.
Every number below was taken by running one of those seven, against the live
`runs/graphcmp/D/` (241 files) and `checks/differ.py:240-280`. No `bend` ran; nothing was
written into `runs/graphcmp/D`.

## THE CONTROL, FIRST, BECAUSE EVERY NEGATIVE BELOW DEPENDS ON IT

`derive.py` recomputes `D0-run-summary.txt` from the 241 artifacts using `differ.py`'s OWN
expressions (`checks/differ.py:571-628`) with its OWN helpers imported by path. It
reproduces the live summary **byte for byte**, and every instrument refuses to report if it
does not (`derive.py:129`, exit 1). So a perturbation below that moves nothing is a real
null, not a broken instrument.

```
CONTROL OK -- rederive(live) == D0-run-summary.txt BYTE FOR BYTE
```

---

## 1. THE HEADLINE: ALL SEVENTEEN PINS ARE READ OUT OF ONE FILE

There are **two** layers, and they have different answers, so both are given.

### Layer 1 — the read path (`differ.py:819-828`). **MAX = 17 of 17.**

`unhealthy()` reads `D0-run-summary.txt` and **all 17 pins are `key=value` rows of that one
file**. `unhealthy()` also *touches* 174 other files, but those reads belong to
`preconditions_bad()`'s `device_of_run()` — they feed the four `dev`/`lc_all`/`noopt`/
`pythonhashseed` rows, **not** any of the 17 pins. Measured by tracing `Path.read_text`/
`read_bytes`/`open` under a scratch copy (`layer1.py`): 175 files touched, **1 of them
carries all 17 pin values**.

So the brief's hypothesis is confirmed in the strongest available form:

> **17 of 17 pins read `D0-run-summary.txt`. 17/17 green is ONE run's 17 rows, and the
> denominator is 1, not 17.**

### Layer 2 — the witness (which artifact can MOVE a pin). **MAX = 3, DISTINCT = 12.**

This is the number that is actually informative, and it is measured by perturbation, not by
reading source lines (`sens.py`, results in §3). A pin's *witness* is the artifact family
whose contents its value is derived from.

| # | pin | witness artifact family |
|---|---|---|
| 3 | `graphs` · `graphs-answered` · `graphs-unset` | **NO ARTIFACT** — `graphcmp.GRAPHS` + `WANT`, both source |
| 2 | `expect-moved` · `graphs-agree` | `D1-graph-*` (34 verdicts) |
| 2 | `byte-identical` · `not-comparable` | `D2-cmp-*` → `D2-bytediff.txt` |
| 2 | `stable-pairs` · `stable-failed` · `stable-differ` | `D9-stability-*` → `D9-stability.txt` |
| 2 | `census-rc` · `oracle-selfcheck` | `D0-coverage-census.txt` |
| 1 each | `plants-disagree` · `controls` · `cross` · `conflations` · `selfcheck` | `D5-plant-*` · `D3-control-*` · `D4-cross-range.txt` · `D7-conf.txt` · `D0-selfcheck.txt` |

**MAX = 3** (the three corpus pins), **DISTINCT WITNESSES = 12**, **DEAD PINS = NONE**.

### THE TRUE INDEPENDENT-MEASUREMENT COUNT: **10, not 17**

Twelve witnesses, minus two arithmetic redundancies, measured in `redundancy.py`:

* `graphs-answered` **is** `n − u` — measured `True`. Three pins, two free numbers `(34, 0)`.
* `stable-pairs + stable-failed + stable-differ = 5` — measured `True`, and `len(STAB) = 5`.
  A **partition**: three pins, two free numbers `(pinned, split)`.
* `D0-coverage-census.txt` yields two pins from ONE subprocess exit plus one printed line.

> **17 pins · 12 witnesses · 2 of those witnesses algebraically over-determined
> → 10 independent measurements.**
> **1 artifact · 1 run.**

`differ.py` already says a version of this about the corpus triple (`differ.py:582-587`:
*"three views of two numbers, so one of them is a restatement"*) — and then pins all three
anyway.

---

## 2. THE DEPENDENCY GRAPH OF THE 17 PINS — THE DELIVERABLE

Arrows are **derivation**, not sequence. Nodes are artifacts; `()` is a count.

```
                        .agents/slop/graphcmp.py  GRAPHS  +  checks/differ.py  WANT      [SOURCE]
                                             │
                        ┌────────────────────┼────────────────────┐
                        ▼                    ▼                    ▼
                  graphs=34         graphs-unset=0      graphs-answered=34
                   [free n]           [free u]          ══ REDUNDANT ══ n−u
                        └────────────────────┬────────────────────┘
                                             │  (no artifact: cannot see a run at all)

 D1-graph-*.txt  (34)              D2-canon-{py,bend}-*.txt (68)  →  D2-cmp-* (34)  →  D2-bytediff.txt
        │                                     │                                              │
        ├─ expect-moved ────┐                  └──────────────┬───────────────────────────────┤
        └─ graphs-agree  ───┤                                  │                               │
                  ┌─────────┴──────────┐                       ├─ byte-identical (32)          │
                  │ INDEPENDENT        │                       └─ not-comparable (0)           │
                  │ (measured, §3)     │                                    INDEPENDENT
                  └────────────────────┘

 D9-stability-*-{a,b}.txt (10)  →  D9-stability.txt  ── one file, five lines
                    ├─ stable-pairs  (5)   [free]
                    ├─ stable-failed (0)   ═╗ PARTITION, sum = 5 = len(STAB)
                    └─ stable-differ (0)   ═╝

 D5-plant-*.txt (7)   → plants-disagree (7/7)
 D3-control-*.txt (5) → controls (5/5)
 D4-cross-range.txt   → cross (1/1)
 D7-conf.txt          → conflations (4/4)
 D0-selfcheck.txt     → selfcheck
 D0-coverage-census.txt (ONE subprocess) → oracle-selfcheck, census-rc

              ┌─────────────────────────────────────────────────────────────┐
              │  ALL OF THE ABOVE ARE WRITTEN AS ROWS INTO ONE FILE:        │
              │                    runs/graphcmp/D/D0-run-summary.txt        │
              └─────────────────────────────────────────────────────────────┘
                                     │  ONE `differ.py run`, ONE substrate state
                                     ▼
                    checks/differ.py:240-280   PINS = 17 literals
                                     │
              ┌──────────────────────┼───────────────────────┐
              ▼                      ▼                       ▼
     differ.unhealthy()     corpus-figure.run_health()   retention-check.py
       (gates/retention-      run_health()               CLAUSE IV
        check.py:346)          (checks/corpus-figure.py:184-209)
              │
              └──→ "RUN HEALTH : OK — 17 of 17"
```

**Edges that mean something:**

* **`graphs`/`graphs-unset`/`graphs-answered` have NO artifact parent.** They are a function
  of two source files. No run, no port, no bend step can move them. They pin the *table*, not
  the *world*.
* **`D9-stability` is a partition** — this is the tree's own `run34` finding, and it is why
  `stable-pairs` was replaced by `stable-failed`/`stable-differ` rather than deleted. **Two
  identical failures compare equal**, and a `5/5` on `stable-pairs` alone would have been
  exactly that trap. The tree got this one right.
* **`D0-coverage-census.txt` has two parents for two pins** — `census-rc` is the subprocess's
  exit, `oracle-selfcheck` its printed line. Same file, so same subprocess died.

---

## 3. SENSITIVITY: DOES A PIN GO RED WHEN ITS ARTIFACT IS EDITED?

**MEASURED. Every one of the 17 does. There are no dead pins.** Eleven perturbation
families, each the smallest realistic edit that family's own regression would make, each on a
scratch copy (`sens.py`; `runs/graphcmp/D` never written):

| family perturbed | pins that MOVED |
|---|---|
| `D1-graph-matmul.txt` | `expect-moved`, `graphs-agree` |
| `D2-cmp-matmul.txt` | `byte-identical`, `not-comparable` |
| `D9-stability-group-a.txt` (bytes) | `stable-pairs`, `stable-differ` |
| `D9-stability-group-a.txt` (0-row branch) | `stable-failed`, `stable-pairs` |
| `D5-plant-dtype.txt` | `plants-disagree` |
| `D3-control-matmul.txt` | `controls` |
| `D4-cross-range.txt` | `cross` |
| `D0-selfcheck.txt` | `selfcheck` |
| `D7-conf.txt` | `conflations` |
| `D0-coverage-census.txt` (`rc=`) | `census-rc` |
| `D0-coverage-census.txt` (selfcheck) | `oracle-selfcheck` |

**`dead pins (no witness): NONE`** (`table.py`). This is the answer to the `coindependent`
question asked of PINS rather than EXITS: unlike the 79-of-107 declared exit codes that have
never fired, **every one of the 17 pins is reachable by an edit a real regression makes.**

### AND THE TWO SHARED-ARTIFACT PAIRS ARE *INDEPENDENT*, MEASURED

The stronger question is not "can it move" but "can it move **alone**" — `indep.py` builds the
states `sens.py` cannot reach, by perturbing so one pin of a shared artifact moves and its
sibling must not:

| shared artifact | claim under test | outcome |
|---|---|---|
| 34× `D1-graph-*` | `graphs-agree` vs `expect-moved` | **INDEPENDENT** — a superseded `VERDICT: AGREE` moves `graphs-agree` alone; `expect-moved` reads the LAST verdict via `verdict()` while `graphs-agree` counts the substring anywhere via `files_with()` |
| `D2-bytediff.txt` | `byte-identical` vs `not-comparable` | **INDEPENDENT** — `BYTE-IDENTICAL`→`DIFFERS:` moves one; `NOT COMPARED` moves the other |

This is worth stating plainly because it is **not** the project's assumption. `differ.py`'s
own comment at `:263-268` says `graphs-agree` "nets out, and so misses the case where one row
moves to AGREE while another moves to DISAGREE" — **that is a statement about the pin's
value, and it is correct; it is not a statement about the pin being redundant, and it is
not one.** `expect-moved` is what catches the netting, and both are needed.

### WHAT THE SWEEP DOES *NOT* TEST — a pin can move and still be a weak claim

The perturbation proves each pin is *sensitive*. It does not prove each pin is
*independent across runs*: all 11 perturbations are edits to a **finished** artifact set.
Nothing here perturbs the **substrate** mid-run, and the tree has already paid for exactly
that twice (`run34`: the port was rewritten 10 s *after* `D2-bytediff` landed, and every
subsequent bend step wrote a 0-row failure while the run kept the last healthy values).

---

## 4. IS 17/17 GREEN A STRONGER STATEMENT THAN 1/1 GREEN? — THE ONE-SENTENCE ANSWER

> **No: 17/17 green is one run's seventeen rows read out of one file, so it is a *stronger
> statement about one measurement* and a *weaker statement than a second measurement* — and
> the tree already makes the second measurement and throws it away, because
> `differ.py repro` prints its verdict to stdout and writes no artifact any pin can read.**

Stated precisely, in the project's own vocabulary:

* **What 17/17 green DOES establish:** that one finished run's twelve artifact families are
  each internally consistent, and that ten derived numbers match values written down before
  the run. That is a real, non-trivial claim, and it is not `1/1`.
* **What it does NOT establish:** that the run would repeat. The denominator for
  *reproducibility* is **1 run**, and nothing in the 17 pins can see a second one.
* **The trap, named:** `AGENTS.md` warns that *"a gate that exits 0 having measured nothing is
  worse than no gate."* 17/17 is **not** that — every pin has a witness and moves when its
  artifact moves (§3). But it is the adjacent failure: **a gate that exits 0 having measured
  everything ONCE.**

### THE CHEAPEST THING THAT WOULD TURN ONE MEASUREMENT INTO TWO — AND THE TREE ALREADY HAS IT

**`differ.py repro` (`differ.py:975-993`) is exactly the second measurement.** It runs two
clean runs and sha256-compares all 175 artifacts. Measured:

```
repro writes a file:                NOTHING into runs/graphcmp/D
repro's verdict:                    sys.stdout.write(...)   <- stdout only
its two snapshots live in:          a tempfile.TemporaryDirectory, deleted on exit
```

**And no pin reads it.** `PINS` contains no repro-shaped key; the three `stable-*` pins are a
*different* two-run measurement (2 runs of 5 graphs, not 2 runs of the run). `corpus-figure.py`
and `retention-check.py` call `unhealthy()`, which never sees `repro`'s verdict.

> **THE FINDING: the second measurement already exists, costs ~2× a run, and is DISCARDED to
> stdout while seventeen first-measurement rows are pinned on disk.**

**The cheapest fix, in order of cost:**

1. **`repro` writes one row.** `cmd_repro` already knows `n of n files identical across two
   clean runs` — it computes the string at `differ.py:988` and prints it. Writing that one
   line into a declared artifact (so `declared()` / `no-txt.py`'s carve-out follow it by
   construction) makes the second measurement **pinnable**. This is the whole fix: one
   `write()`, one `LITERALS` entry, one pin. **It is not landed here** — see §6.
2. *Cheaper still, and zero new state:* have `corpus-figure.py` print `repro`'s verdict **in
   the same line** as `RUN HEALTH`, so `OK — 17 of 17 (repro: 175 of 175)` is one sentence a
   reader cannot split. Costs no new artifact and no new pin.
3. *Separate runs per pin:* **not worth it and not wanted.** It would multiply substrate-warm
   cost by ~12 for a statement that is strictly weaker than (1), because 12 separate runs
   measure the substrate 12 times and the corpus zero times coherently.

**A second run compared byte-for-byte is the right shape** — and `repro` already is it. What
is missing is only that its result **reaches the disk**.

---

## 5. THE MTIME PROBLEM — `citeresolve` WAS RIGHT AND THE DIRECTION IS THE MIRROR

`grep mtime checks/differ.py checks/corpus-figure.py` → **nothing**. The pins carry no time
whatsoever, and nothing in `unhealthy()` reads a timestamp. `runs/` is `.gitignore`d
(`.gitignore:179`) and untracked. So a pin against a live artifact is true and false in the
same paragraph, exactly as described.

**MEASURED, both directions (`mtime.py`), per pin, via `git log -S` on the exact
`"key": "value"` pair:**

| direction | count | what it means |
|---|---|---|
| artifact **NEWER** than the pin's commit | **13 of 17** | the pin was written down first, a run then **CONFIRMED a prediction** — green is earned |
| artifact **OLDER** than the pin's commit | **4 of 17** | the pin was **COPIED FROM** that artifact — green is a tautology, the pin cannot fail |

The 4 retro-fitted today are `graphs-unset`, `graphs-answered`, `graphs-agree`,
`byte-identical` — all written by `45c81ce11` at 06:02:24, **17.1 min after** the artifact
they are matched against (05:45:17).

> ### THE BRIEF'S RULE IS THE MIRROR OF THE DEFENSIBLE ONE.
> The brief asks for: *refuse an artifact **NEWER** than the commit that set it.*
> **MEASURED CONSEQUENCE: that rule would redden 13 of 17 pins today — the 13 that are doing
> real work — and pass the 4 that cannot fail.** A prediction confirmed by a later run is the
> *strongest* thing a pin can do; refusing it would punish the tree for working.
>
> **The defensible rule is the reverse: a pin must REFUSE (REFUSED) an artifact OLDER than the
> commit that set it — because that artifact PREDATES the claim and cannot witness it.**

In `gatekit`'s vocabulary this is **`REFUSED` (exit 3)**, not `FAIL`: a precondition — *a run
newer than the pin* — is absent. There is no sixth verdict, and none is needed.

### THE INSTRUMENT PREDICTED THE RETRO-FIT SET EXACTLY — a real out-of-sample check

`mtime.py` flagged 4 pins as retro-fitted **from mtimes alone**, with no reference to any
commit's contents. Git then confirms which pins commit `45c81ce11` actually *moved*:

```
pins whose VALUE 45c81ce11 moved : byte-identical, graphs-agree, graphs-answered, graphs-unset
pins my mtime instrument flagged  : byte-identical, graphs-agree, graphs-answered, graphs-unset
PREDICTION HOLDS                 : True
```

Two independent methods — file timestamps and version-control content — agree on the same
four pins with no shared input. **The 4 retro-fits are exactly the 4 pins that had to be
moved**, i.e. the ones whose green is currently a copy rather than a test.

**What a pin SHOULD do when the artifact is newer than the pin:** nothing. That is the green
case. **When it is older:** `REFUSED`, naming both clocks, because the pin has never been
tested.

---

## 6. WHAT I LANDED, AND WHAT BLOCKS THE REST

### LANDED: nothing in `checks/`.

The rule is **clearly correct in direction** (§5, measured) and **not landable here**. Three
blockers, each measured:

1. **`differ.py` has no `git` dependency, and says so on purpose.**
   `checks/differ.py:58-60`: *"Pinning the committed body instead would be a check against
   `git`, which is a dependency this file does not otherwise have."* Measured: `imports git:
   False`. The brief's own instruction says to land *"only if clearly correct"* — and adding
   a VCS dependency to a file that documents avoiding it is a **design change**, not a fix. It
   is not mine to make unilaterally, and `AGENTS.md` is explicit that `checks/differ.py` is a
   frozen-oracle-bearing instrument.
2. **The artifact is untracked** (`.gitignore:179 /runs/`). Its mtime is a fact about *this
   working tree*, not about the commit — so **two clones at the same commit would answer
   differently**, which is the change-detector shape `AGENTS.md` calls harmful. Any rule
   keyed on it must be scoped to a working tree and say so in its own output.
3. **I do not own `gates/retention-check.py` or `corpus-figure.py`'s reading path** (read-only
   per brief), and the fix touches both consumers' verdicts.

### THE CHANGE, AT `file:line`, FOR WHOEVER LANDS IT

* **`checks/differ.py:240-280`** — the `PINS` dict becomes a pin **plus** its witness commit
  date, so the pin carries when it was set. Cheapest form that adds no VCS dependency: a
  sibling `PIN_SET_AT` literal written by hand, checked against `git log -S` by a gate, rather
  than read from git at runtime.
* **`checks/differ.py:827`** — `unhealthy()`'s two comprehensions gain one clause: a pin whose
  artifact is **older** than its commit returns
  `f"{k} REFUSED -- artifact predates the pin ({artifact_mtime} < {pin_commit})"`.
  **No new verdict, no new exit code, no sixth state** — `REFUSED` is `gatekit`'s existing 3,
  and `unhealthy()` returns a list of strings, so every consumer already treats it as red.
* **`checks/differ.py:989`** — `cmd_repro` writes its `REPRO: {n} of {n} files identical`
  string to a declared artifact instead of only `sys.stdout`. Add the name to `LITERALS`
  (`:289`) so `declared()` and `checks/no-txt.py`'s carve-out follow **by construction**
  (doctrine 1: the population is a generator's declaration, never a second copy).
* **`checks/corpus-figure.py:184-209`** — print `repro`'s row beside `RUN HEALTH`, so
  `OK — 17 of 17 (repro 175 of 175)` cannot be read as `OK` alone.

**Cheapest of all, and it is the one I would actually do:** item 2 alone. It makes the
strongest claim the tree can make today — *one run's numbers, confirmed by an independent
second run, byte for byte* — with **one `write()` and no new pin**.

---

## 7. WHAT IS STILL WEAK, STATED PLAINLY

* **The denominator for reproducibility is 1.** Ten independent measurements, one run.
* **`repro` has never been recorded.** Its verdict lives only on a tty. The tree *has* a
  second measurement and no memory of it.
* **`differ.py run` consults no pin before exiting 0** (measured: `"PINS" in cmd_run` →
  `False`). `cmd_run` returns `1 if unset or moved` — it honours **2** of the 17
  (`graphs-unset`, `expect-moved`). The other 15 are enforced by *callers*
  (`unhealthy()` → `repro`, `retention-check.py`, `corpus-figure.py`), never by the producer.
  That is a defensible architecture — the run *measures*, the health gate *judges* — but it
  means `differ.py run` alone is **not** a health gate, and must never be cited as one.
* **All 11 sensitivity perturbations edit a finished artifact set.** A substrate change
  *during* a run is the untested failure mode, and the tree has been bitten by it twice.
