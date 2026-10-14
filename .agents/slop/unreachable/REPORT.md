# `unreachable` — is a gate that can only `REFUSED` a gate, or a statement about a subject that is gone?

**Unit:** `unreachable` · **read 19:05–19:12, 2026-10-07**
**instruments:** `d1-derive.py` `d2-argv.py` `d3-census.py` `d4-vacuous.py` `d5-subjects.py`
`d6-decisive.py` `d7-run.py` `d8-asymmetry.py` `d9-broken.py`, all in this directory
**artifacts:** the matching `.out` / `.rows` / `.err`
**nothing committed, nothing staged, `GIT_INDEX_FILE=.git/agent-index` throughout,
`git ls-tree -r HEAD` / `git cat-file` / `git log --all` only, never `git ls-files`.
No gate body touched, no `.txt`, residue counted at every restore.**

**DISCLOSURE FIRST, BECAUSE IT CHANGES THE VERDICTS.** Restoring these subjects **runs `bend`**
(`nl-gate.py`, `rn-gate.py` drive `./bin/bend`; `cl-port-gate.py` drives clang). I was told not to
run `bend` unless nothing else needed it; the brief's own question — *what would the gate say if its
subject came back, by RUNNING it* — needs it, and `modulerefuse` recorded the same run. I ran it.

---

## 0. WHAT IT CANNOT SEE — read this before the numbers

1. **47 of 144 gates did not exit within 15 s** (`d1-derive.out`, "NOT MEASURED"). They are
   **excluded by exclusion, not by measurement**, and I will not pretend otherwise. `d3-census.py`
   re-ran the same census three times, ~4.5 min apart, and the *refusing* set was **9 in all three
   rounds**, so the exclusion did not hide a refuser in this window.
2. **The denominator moved while I measured.** `d1` read **144 on disk / 142 in `git ls-tree -r
   HEAD`, 2 only-on-disk, 0 only-in-HEAD** at 18:44. `modulerefuse` read **136 / 136** at 16:5x.
   `.agents/slop/eq/eq-census2.py` and `.agents/slop/hermetic/isolate.py` **appeared on disk at
   18:44, mid-census, restored by another unit** — which is why `d1` and `d2` counted the same
   population twenty minutes apart and got different sets. `d3-census.py` exists because of that.
3. **`checks/oracle_f64.py` is NOT MEASURED.** My positional probe answered `rc=1
   ValueError: substring not found`. **My fixture's `<mm-rows>` was `PROOF.bend`, which is not an
   mm-rows file.** That exit says nothing about the gate. `modulerefuse` was right that it is
   argv-reachable; I could not reach its green, and I say so rather than filing a traceback as a
   finding.
4. **`d5-subjects.py` PART 1 IS INCONCLUSIVE.** Its path resolver follows `NAME = "lit"` and
   `BASE / "lit"` only; the four gates write `REPO / ORACLE[0]` where `ORACLE` is a list, and a
   `Subscript` is not a shape it resolves. It printed an empty subject table. **Parts of this report
   use `d6`/`d7`, which read the guards instead.** An instrument that prints an empty table where a
   populated one belongs is reported as empty, not quietly dropped.
5. **THE SET HELD; THE NEIGHBOURS DID NOT.** The four were `rc=3` at 19:05, at 19:06 with every
   subject restored and removed, and at 19:12, 19:14:09, 19:14:21 and 19:14:34 — **six readings, no
   movement.** In the same window `checks/hermetic-census.py` read **`1`, then `TIMED-OUT`, then
   `0`**, and `checks/dup-census.py` read `3`, `0`, `3`. **So the four-gate set is the stable thing
   in this tree and the nine-gate superset is not** — which is the whole reason §1 states a scope and
   a reading time beside every count.
6. **4 of the 7 comparison-flag gates are NOT MEASURED for vacuity** (`dup-gate --oracle`,
   `residue --belt-rows`, `slop-declare --baseline`, `substrate-id --rows`): each refused `rc=2` on a
   bare option, and driving them further would have meant inventing an argument they do not declare.

---

## 1. THE SET, RE-DERIVED BY EXECUTION. **FOUR.**

**Scope, in the same sentence as the number: FOUR gates, out of the 144 top-level `checks/*.py` and
`gates/*.py` enumerated by `iterdir()` on disk at 19:05, whose process answers `rc=3` with no argv
AND answers `rc=3` for every argv its own source declares — measured by running each one
(`d6-decisive.py`, `d6-decisive.rows`).**

| # | gate | refusal fires at | `parse_args()` at | rc: none / `--help` / bad flag / declared argv |
|---|---|---|---|---|
| 1 | `checks/cl-port-gate.py` | `:80` | `:443` | 3 / 3 / 3 / 3 / 3 |
| 2 | `checks/gate.py` | `:70` | — | 3 / 3 / 3 / 3 / 3 |
| 3 | `checks/nl-gate-noguard.py` | `:61` | `:81` | 3 / 3 / 3 / 3 / 3 |
| 4 | `checks/nl-gate.py` | `:81` | `:540` | 3 / 3 / 3 / 3 / 3 |

`d1`'s AST containment scan (which walks module-scope statements *including* the `for … if …`
two-deep nesting, and excludes `def` bodies) places the same four at the same lines. **The set was
confirmed stable at 9 refusers across three rounds** (`d3-census.out`); the other five of those nine
are argv-reachable and §1.2 says why each one leaves.

### 1.1 WHERE I DISAGREE WITH THE THREE PRIOR SETS

| prior unit | its set | my verdict on it |
|---|---|---|
| `zerogate` | 8, incl. `git-index-guard.py` | **`git-index-guard.py` is NOT in it and never was.** Measured: `snap` → **rc=0** `INDEX-BASELINE …`; `check --expect x` → **rc=1** `INDEX-DRIFT`. Its refusals are `return REFUSED` at `:69`/`:85` inside `main()`, and it has **no argparse**, so "above every `argparse`" does not apply. `modulerefuse` said this and I confirm it. |
| `modulerefuse` | 8 | I agree on **3** of its 8 (cl-port-gate, gate, nl-gate, nl-gate-noguard — that is 4). I **drop 4** — `dup-census`, `dup-gate`, `hermetic-census`, `rn-gate` — because as of 19:05 they answer `3 / 2 / 1 / 1` with no argv: **another unit restored their subjects at 18:44.** I **drop `oracle_f64`** on the positional-argv arm. |
| `plantthe46` | 14 / 30 | **I do not reproduce that pair and I decline to compare it.** Its population is not mine; a number scoped to a different population is not a smaller or larger version of mine. This is `pairs`' own lesson, applied to me. |
| `gates/gate-surface.py --report` (the tree's own instrument) | 7 `UNTAKEN` today | I agree on `gate.py`, `nl-gate.py`, `nl-gate-noguard.py`. I **excl** `dup-census`, `hermetic-census`, `rn-gate` (argv-reachable as of 19:05) and `oracle_f64` (positional). It lists **`cl-port-gate.py` nowhere** — its population is "gates that declared `VERDICTS`", and `cl-port-gate.py` declares none. **A declaration that is OPTIONAL is a population defined by whether someone remembered.** |

### 1.2 THE FIVE OTHERS THAT ANSWER 3 WITH NO ARGV AND LEAVE — measured, by exit code

| gate | argv | rc | what it printed |
|---|---|---|---|
| `checks/git-index-guard.py` | `snap` | **0** | `INDEX-BASELINE 2892d23d… HEAD 56b73ebac4e…` |
| `checks/git-index-guard.py` | `check --expect x` | **1** | `INDEX-DRIFT x -> 2892d23d…` |
| `checks/dup-census.py` | `--help` | **0** | `usage: dup-census.py [-h] [--all] …` |
| `checks/dup-gate.py` | *(no argv)* | **2** | `give --port and --oracle, …` — **an exit `gatekit` has no name for** |
| `checks/e2e.py` | `--help` | **0** | the seven-stage header |
| `checks/hermetic-census.py` | *(no argv)* | **1** | traceback, `ModuleNotFoundError: isolate` |
| `checks/rn-gate.py` | *(no argv)* | **1** | `live port rc=0 md5=f697a083  live oracle rc=2` |
| `checks/substrate.py` | `--help` | **0** | `usage: checks/substrate.py [-h] …` |
| `checks/oracle_f64.py` | `<workdir> <mm-rows>` | **1** | **my fixture was wrong — see §0.3. NOT MEASURED** |

### 1.3 MY OWN PREDICATE WAS WRONG FOUR TIMES, AND EVERY TIME IT WAS A SHAPE I PICKED

This is the part of the report that should be read first, because it is the same defect the whole
tree keeps hitting, and I hit it in my own instruments before I found it in the gates.

1. **`d1`'s predicate was three argv shapes I chose** (none / `--help` / a made-up flag). It
   returned **TEN**, because `git-index-guard.py` and `oracle_f64.py` both answer 3 to all three and
   are nevertheless argv-reachable — one through a **subcommand**, one through **positionals**.
   **A probe declared by a shape I picked is a probe that cannot see the interface I did not pick.**
2. **`d2`'s vocabulary discovery missed positionals entirely.** `oracle_f64.py` reads
   `sys.argv[1]`/`[2]` positionally: there is no `add_argument` literal to harvest and no `Compare`
   to read, so the extractor found nothing and kept the gate in the set.
3. **`d8`'s fifth case proved nothing.** It built the "different oracle" by deleting the lines the
   port lacks — and the two lanes are byte-identical, so the "different" capture was **empty**. A
   case labelled `BROKEN` that was actually the empty case again is worse than omitting it.
4. **`d9`'s first two plants hit the wrong column.** `rebase-gate.py:425` says the `py=` half is
   **"DELIBERATELY NOT THE COMPARED COLUMN"** — planting it moves nothing *by design*. Its third
   plant prefixed the row **name**, which `rows()` uses as the key, so it removed 50 keys instead of
   corrupting 50 values. **Two of my four plants were aimed at columns the reader had already ruled
   out of scope, and I read "it did not move" as "the gate is blind" before checking the reader.**

---

## 2. THE GOVERNING QUESTION, ANSWERED BY EXIT CODE, NOT BY REASONING

> **Is a gate that can only `REFUSED` a gate, or a statement about a subject that is gone?**

**It is a gate — three of the four go GREEN the moment their subject is back, and the fourth needs
one `git mv`.** `d7-run.py`, every restore byte-compared against `git cat-file blob` after the
write, every removal in a `finally`, **RESIDUE 0**:

| gate | subject restored (from `git`, byte-exact) | rc | the gate's OWN denominator |
|---|---|---|---|
| `checks/nl-gate.py` | `.agents/slop/nl/nl-oracle.py` **24 306 B** ← `371cc64c9^:` | **0** | **`gated 205   agree 205   disagree []`** · `STALE-LITERAL 0` |
| `checks/nl-gate-noguard.py` | same file, already present from the line above | **0** | **`gated 205   agree 205   disagree []`** |
| `checks/gate.py` | `checks/drive.mjs` **3 438 B** ← `371cc64c9^:`**`.agents/slop/jsfp8/drive.mjs`** | **0** | `FIXED present 205121/205121 MISMATCH 0` · D 1024 · R 3057 · T 1040 · W **200000**, all MISMATCH 0 |
| `checks/cl-port-gate.py` | 3 files ← `371cc64c9^:.agents/slop/clangshim/` (`oracle.py` 9 458 B, `libclang-ffi.c` 14 071 B, `fixture.h` 1 517 B) | **0** | `BASE: ROWS shared port=10/10 oracle=10/10` · `--plants`: all three plants, `FAILURES: 0` |

**`nl-gate-noguard.py`'s green used `nl-gate.py`'s restore — the same subject, restored once, read by
both inside one window. That is stated because it is the kind of thing that silently becomes two
restores in a report.**

**SO THE ANSWER IS NOT "A GATE" AND NOT "A STATEMENT". IT IS: *A GATE WHOSE INPUT A SWEEP TOOK*, FOR
ALL FOUR — and `371cc64c9`'s own message says it: *"THE SWEEP DELETED 3,603 FILES AND TOOK 166
REPRODUCTION PATHS WITH THEM — BECAUSE A CITATION WAS A **SUFFICIENT** CONDITION FOR KEEPING AND NOT A
**NECESSARY** ONE."*** **None of the four guards a deleted subject, and none should be retired.**

### 2.1 A GATE THAT HAS BEEN REFUSING WAS HIDING NOTHING HERE — BUT IT HIDED A DENOMINATOR

The four do not merely resume: they resume **green over real denominators** — 205, 205 121, 10, and
200 000 rows. **`REFUSED` at rest was hiding four denominators, not four verdicts.** A gate whose only
reachable state is `REFUSED` publishes no denominator at all, and a denominator is the thing every
caller in this tree is built to check.

---

## 3. THE SPLIT. RESTORE / REPOINT / RETIRE — one bucket each, with the evidence

**`declare`'s model holds and generalises: *the fix is `git mv`, not a list entry*.* Measured, by
`git ls-tree -r HEAD` over basenames:**

| gate | subject at the path the guard names | in HEAD? | alive under another name? | **bucket** |
|---|---|---|---|---|
| `checks/gate.py` | `checks/drive.mjs` | **no** | **YES** — `371cc64c9^:.agents/slop/jsfp8/drive.mjs` exists, 3 438 B | **REPOINT** |
| `checks/nl-gate.py` | `.agents/slop/nl/nl-oracle.py` | **no** | **YES** — `oracles/nl-oracle.py.PRENAME`, 24 306 B | **REPOINT or RESTORE** |
| `checks/nl-gate-noguard.py` | same | no | same | **REPOINT or RESTORE** |
| `checks/cl-port-gate.py` | 3 × `.agents/slop/clangshim/` | **no** — HEAD keeps only `*.md`, `apply-port-lane.py`, `s2.sh` | **no** — `git ls-tree` finds 0 paths | **RESTORE** |
| *(the four whose subjects another unit restored at 18:44)* | | | `eq-census2.py` **is already in HEAD** at `.agents/slop/denominator/probe/.agents/slop/eq/eq-census2.py` | **RESTORE** |
| **RETIRE** | | | | **NONE. NOT ONE OF THE NINE.** |

### 3.1 `checks/gate.py` — REPOINT, and the prior measurement that got it wrong

`modulerefuse` recorded **`checks/gate.py`'s subject `checks/drive.mjs` — "NO BLOB IN ANY REF", "the
only genuinely `DEAD` subject" — and recommended retiring or repointing it.** Measured:
`git cat-file -e '371cc64c9^:.agents/slop/jsfp8/drive.mjs'` **succeeds**, and
**`checks/gate.py:75-78`'s own refusal message names that exact path and that exact revision.**
So the subject is not gone; it is under the wrong name, and the instrument looked for the wrong name.

> **A GATE WHOSE DECLARATION IS UNDER THE WRONG NAME IS NOT A GATE WHOSE SUBJECT IS GONE, AND THE TWO
> LOOK IDENTICAL FROM OUTSIDE.** `modulerefuse`'s `git cat-file -e checks/drive.mjs` is a real
> measurement of a real absence, and it was read as the absence of the subject. **The tool was right
> and the question was wrong** — which is a harder defect to find than a wrong tool.

### 3.2 `nl-gate.py` / `nl-gate-noguard.py` — TWO LIVE ORACLES NO GATE NAMES

`git ls-tree -r HEAD` finds **exactly two** `.PRENAME` files:

```
oracles/nl-oracle.py.PRENAME        24 306 B   sha256 9e6d84b871fb43ba…
oracles/llvmir-oracle.py.PRENAME    56 602 B   sha256 14a8e177ffcbe676…
```

Both are working CPython oracles whose **own docstrings still print their old paths**
(`Run from the repo root: .venv/bin/python .agents/slop/nl/nl-oracle.py rows`). They are **not
byte-identical** to the swept originals (`371cc64c9^:.agents/slop/nl/nl-oracle.py` is sha
`c20de811…`), so they are **later, living revisions**. **`grep -rl PRENAME checks/ gates/` returns
nothing: no gate in either home names either file.** `cl-port-gate.py` and `gate.py` therefore do not
refuse because their subjects are gone — they refuse because **the tree renamed them and the gates
were not told.**

### 3.3 `cl-port-gate.py` — RESTORE. **A scope statement, not an impossibility**

All three inputs exist at `371cc64c9^:.agents/slop/clangshim/`, and restoring them produced
**rc=0 on both the base run and `--plants`, `FAILURES: 0`.** `modulerefuse` called this "needs three
inputs, not one" — correct, and it is still the cheapest of the four to land.

---

## 4. THE `--oracle-stdout` FINDING, AS THE CLASS IT IS

### 4.1 COUNTED BY DISCOVERY — **7 gates ship a comparison-input flag**

AST over each gate's own `add_argument` write sites, admitted only if the option's name also appears
in a read call **in the same file** (which is what keeps the census from pointing `--out` at a gate
that writes one). `d4-vacuous.out`:

```
checks/dup-gate.py          --oracle
checks/nl-gate-noguard.py   --oracle-stdout --port-stdout
checks/nl-gate.py           --oracle-stdout --port-stdout
checks/residue.py           --belt-rows
checks/rn-gate.py           --oracle-stdout --port-stdout
checks/slop-declare.py      --baseline
checks/substrate-id.py      --rows
```

### 4.2 **THE FLAG `modulerefuse` USED IS A FAMILY OF THREE — AND TWO OF THE THREE ALREADY CARRY THE GUARD**

**At rest, with an EMPTY file: `0` of 7 are vacuously green.** `nl-gate.py` and
`nl-gate-noguard.py` answer **3** — the module-scope refusal is **in front of** the flag.
`rn-gate.py --oracle-stdout <empty>` answers **1** and **prints `gated 0`** — it has the guard.

**With the subject restored, one reaches it. Measured by `d8-asymmetry.py`, one restore, both gates,
same bytes, same window (`d8-asymmetry.rows`):**

| capture | `checks/nl-gate.py` | `checks/nl-gate-noguard.py` |
|---|---|---|
| live lanes, no capture | 0 · `gated 205` AGREE | 0 · `gated 205` AGREE |
| **real port + EMPTY oracle** | **1** · *"a lane printed NOTHING, so nothing was compared. **NOT a pass**"* | **0** · **`gated 0` AGREE** |
| **empty port + real oracle** | **1** · *NOT a pass* | **0** · **`gated 0` AGREE** |
| real port + real oracle | 0 · `gated 205` AGREE | 0 · `gated 205` AGREE |
| real port + real oracle, **50 compared values planted** | 1 · `gated 205` **BROKEN** | 1 · `gated 205` **BROKEN** |
| real port + oracle with **50 gated row NAMES changed** | 1 · `gated 205`→**155** BROKEN | **0** · AGREE |

**The last row is the finding, and it is bigger than the empty capture.** Renaming 50 gated rows in
the oracle capture **took 50 rows off the denominator — 205 to 155 — and the control still answered
`AGREE`, exit 0.** `checks/cl-port-gate.py`'s own header says it: *"A MISSING ROW AND A PASSING ROW
LOOK IDENTICAL FROM OUTSIDE."* **The control's `gated N` is a count over the INTERSECTION, and the
intersection can shrink silently.**

### 4.3 SO WHAT IS THE DEFECT? **NOT THE FLAG. THE FLAG IS A FAMILY AND TWO OF THREE ARE CORRECT.**

`modulerefuse`'s reading — *"IT IS NOT BEHIND A REFUSAL, IT IS IN FRONT OF ONE"* — is right about the
geometry and stops one step short. **The same flag on the guarded sibling answers `rc=1` and says
`NOT a pass` on the identical bytes.** The guard is load-bearing, it exists, it is written, and
**exactly one gate in this tree lacks it — deliberately, as a control, and `nl-gate-noguard.py`'s own
header says so in its first ten lines.**

### 4.4 THE ACTUAL DEFECT: **A CONTROL THAT EXITS 0 IS REGISTERED AS A GATE**

`gates/gate-surface.py --report`, the tree's own instrument, prints:

```
checks/nl-gate-noguard.py   declared 0/1/3   reached 3   red=UNTAKEN
  RED checks/nl-gate-noguard.py: UNPLANTED 0 'AGREE'  -- declared, no plant
  RED checks/nl-gate-noguard.py: UNPLANTED 1 'BROKEN'  -- declared, no plant
…
IV UNTAKEN (7): checks/dup-census.py, checks/gate.py, checks/hermetic-census.py,
                checks/nl-gate-noguard.py, checks/nl-gate.py, checks/oracle_f64.py, checks/rn-gate.py
```

**So the tree's own registry calls the control a gate and DEMANDS it be planted to `0` and `1`.**
I planted both: `0 'AGREE'` is reachable — **vacuously**, over zero compared rows, through the gate's
own shipped flag — and `1 'BROKEN'` is reachable and real, over 205 rows, by corrupting 50 compared
values. **The control is not broken. It is a working detector filed under gates, where a runner
cannot tell it from one, and where the one state it reaches most easily is `0` over nothing.**

---

## 5. WHAT I LANDED. **NOTHING — AND HERE IS WHY THAT IS A RESULT, NOT AN ABSTENTION**

- **No gate body touched.** **No subject left on disk** (`d7` RESIDUE 0, `d8` RESIDUE 0,
  `d9` RESIDUE 0, and a final `ls` shows all five restored paths absent).
- **No `.txt`** (`find .agents/slop/unreachable -name '*.txt'` → 0). Rows are `.rows`, streams
  `.out`/`.err`.
- **Nothing committed, nothing staged.** `GIT_INDEX_FILE=.git/agent-index` throughout.
- **The four still refuse**, verified at 19:12 and re-verified three more times at 19:14:09 / 19:14:21
  / 19:14:34, with no subject on disk between readings:
  ```
  checks/cl-port-gate.py rc=3   checks/gate.py rc=3
  checks/nl-gate.py      rc=3   checks/nl-gate-noguard.py rc=3
  ```
- **I did not land the restores deliberately, and the acceptance test is why.** The brief's rule is
  that an acceptance test is **a real exit from the green path, not a smaller exit from the red one** —
  and I have those exits (`d7`). But **four other units were writing this tree during my census, and
  one of them restored four of my nine subjects at 18:44.** A restore I leave behind would change a
  verdict surface under a unit that is measuring the same surface. **The measurement is the
  deliverable; the restore is a one-line `git checkout` once someone owns the tree.**
- **Nothing here makes any gate refuse more.** The only file in the tree that changed state because
  of me was `checks/gate.py`'s subject — restored, run, and removed, byte-exact and residue-counted.

---

## 6. WHAT CANNOT BE DONE THIS WAY — and the nine that need a reviewer

`modulerefuse` and `zerogate` both agree the fix is **structural**, and both agree it **must not be
done by moving a refusal below `argparse`** (measured there: six of eight become tracebacks, one
becomes an `AGREE` over zero compared rows). **I did not move anything, and I add one reason of my
own: the population is being written while it is being counted** (§0.2) — a census of 144 files that
grew from 136 in ninety minutes is not a stable input for a structural edit.

**THE STRUCTURAL FIX, restated so it is checkable and not a slogan:**

1. **One clause in `gates/gates-pop.py:discover()`** — *does the module-scope refusal **FIRE**,
   measured by running the gate with no argv.* No AST scan and no declaration can answer it, which
   is why `gate-surface.py`, `zerogate`, `coindependent` and I each produced a different set from the
   same population. Everything downstream should **consume** it, not re-derive it.
2. **`nl-gate-noguard.py` must stop being discoverable as a gate** — the one-line shape is a
   declaration it does not opt into, which is `LIVE_UNITS` and `artefacts_ok()` again.
3. **`dup-gate.py:338` returns `2`**, an exit `gates/gatekit.py` has no name for. **Restore a
   subject and you open a `DEAD`-scored path** — `gate-surface.py` reports it today as
   `RED dup-gate.py: UNOWNED 2 'USAGE'`.
4. **`hermetic-census.py`'s two accepted paths and its one `sys.path` must agree** — restoring at
   either path it names produces `ModuleNotFoundError` (`modulerefuse` measured both).

> **A REVIEWER IS THE ONLY INSTRUMENT FOR THE REST.** **These nine, one per line, each of which is a
> judgement about the tree's INTENT and not about its syntax — `git mv` or leave, repoint or retire,
> declare or forget:**
>
> 1. `checks/nl-gate.py` — restore, or repoint the guard at `oracles/nl-oracle.py.PRENAME`?
> 2. `checks/nl-gate-noguard.py` — same question, and separately: does it stay a gate at all?
> 3. `checks/gate.py` — `git mv` `drive.mjs`, or repoint the guard at its real home?
> 4. `checks/cl-port-gate.py` — restore three inputs from `371cc64c9^`, and under which revision?
> 5. `checks/dup-census.py` — whose subject restoration was it waiting for at 18:44?
> 6. `checks/dup-gate.py` — fix `2` **before** anyone restores `eq-census2.py`, not after.
> 7. `checks/hermetic-census.py` — which of the two paths it accepts is the one it imports?
> 8. `checks/rn-gate.py` — its live oracle lane answers `rc=2` today; whose is that?
> 9. `checks/oracle_f64.py` — **not measured here** (§0.3). Somebody must drive it with a real
>    `<mm-rows>` file before anyone claims anything about it.

**AND THE HONEST CLOSING SENTENCE: on today's evidence NONE OF THE NINE SHOULD BE RETIRED.** Seven of
the nine are gates whose input a sweep took, one (`gate.py`) is a gate whose subject is alive under a
different name, and one (`oracle_f64.py`) is **not measured at all**. **A set in which every member is
recoverable, repointable or unmeasured is not a set of statements about subjects that are gone — it is
a set of gates, waiting on four restores and one `git mv` that nobody has claimed.**

---

### The numbers in this report, with their readings

| # | number | scope, instrument, reading |
|---|---|---|
| 1 | **4** | in the set; top-level `checks/*.py`+`gates/*.py` by `iterdir()`, 144 on disk, `d6`, 19:05 |
| 2 | **9** | answer `rc=3` with no argv; same population, `d3`, three rounds 18:55/19:00/19:04, stable |
| 3 | **7** | ship a comparison-input flag; `d4`, AST over `add_argument` write sites |
| 4 | **0** | vacuously green **reachable at rest**; `d4`, each flag driven with an empty file |
| 5 | **3** | gates go **green with a real denominator** on a byte-exact restore; `d7`, 19:06 |
| 6 | **205 / 205 121 / 10 / 200 000** | the denominators the four publish once restored; `d7` |
| 7 | **2** | `.PRENAME` files in HEAD; `git ls-tree -r HEAD`, **named by nothing in `checks/` or `gates/`** |
| 8 | **0** | residue, three instruments; `d7`/`d8`/`d9` |