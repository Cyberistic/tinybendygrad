# Does `checks/differ.py` reproduce the frozen shell oracle's artifacts? — MEASURED

**Short answer: NO, and not by a hair. 147 of 151 artifacts are byte-identical; the 4 that
are not are 4 LOST and 4 NEW CLAIMS. But the verdict-bearing comparison DID hold: all 16
`VERDICT:` lines and all 16 `ops-reached=<py>/<bend> of 77` denominators agree exactly, and
all 15 summary keys agree. The docstring's "byte for byte" is false on the artifact SET and
true on every verdict.**

Nothing in this tree was edited. `checks/differ.py` and `.agents/slop/diffpy/` are
byte-identical to HEAD (sha256 `4ef5fbdc16d23823`, `94e7108d…`, `a5d23505…`). Every
mutation below was made to a **scratch copy** under this directory and reverted with a
verified sha256. **Nothing committed.**

---

## 0. THE THING THAT HAD TO BE FIXED FIRST, OR NOTHING BELOW IS A MEASUREMENT

**The substrate is COLD in BOTH trees, so the first comparison compared two identical
FAILURES.** This is the "two identical failures compare equal" trap, live, and it is why
`D1-graph-*.txt` must be read as `rc=1` before anything else is believed.

The coldness has **two different causes in two different trees, and they are opposite**:

| tree | `ops.bend` has `AOpLit{op: Op}` | `graphcmp.bend:argstr` has the arm | `--check-only` |
|---|---|---|---|
| **live working copy** | **NO** | **YES** (`graphcmp.bend:398`) | cold |
| **HEAD** | **YES** (`ops.bend:1079`) | **NO** | cold |

`--check-only` reads `expected : cases for ../../tinybendygrad/uop/ops.AOpLit`, every
`emit --side bend` returns **0 rows after 5 attempts**, and all 16 `D1-graph-*.txt` are the
one-line file `rc=1`.

**The commit that did it: `a9491a5c26bb` ("arglit")** — "**`AOpLit{op: Op}` EXISTS, AND MY
BRIEF'S FALLBACK WAS FALSE**". It added the 20th `Arg` constructor to `ops.bend` and did
**not** add the corresponding arm to `argstr` in `graphcmp.bend`. Two units are holding
opposite halves of that one edit.

**Its parent `3a68607fb198` is the last consistent commit and is WARM**
(`ALL PROOFS CHECK`, 666 MB peak, under `checks/bounded.py`). **All numbers below come from a
scratch tree at `3a68607fb198` plus HEAD's `checks/differ.py` and `diffpy/`.** Nothing in the
repo was modified to get there.

⚠ **THIS IS A FINDING, NOT A WORKAROUND I INVENTED: the committed tree cannot run its own
primary gate.** `graphcmp.py` also cannot be run against the live tree at all —
`graphcmp-oracle.py` dies with `AttributeError: module 'graphcmp' has no attribute
load_tinygrad` (six units are contested on `graphcmp.py`; HEAD's copy has the function at
`:283`).

## 1. A TRAP I FELL INTO, BECAUSE IT WILL HAPPEN TO THE NEXT READER

`git archive HEAD` **ships `runs/graphcmp/D/` — 154 committed artifacts.** Left in the
scratch root, the Python driver *appears* to write `D6-srcswap-*.txt` — files it never
produces — purely because the archive left them there. That is **the exact defect the oracle's
own step 14 exists to prevent** ("a directory carrying a PASS-shaped file that no command
produces"), reproduced by the archive instead of by a stale run.

Every comparison here therefore starts from `rm -rf runs/graphcmp/D`. **With the archive in
place the Python wrote 158 files; from empty, 151 — the same as the oracle.**

## 2. PER-FILE DIFF — the whole table

Both drivers from an empty `D/`, warm substrate, sha256 over non-blank lines.

```
oracle wrote 151 files, python wrote 151 files, 147 names in common
BYTE-IDENTICAL: 146   DIFFERING: 1   LOST (oracle only): 4   NEW (python only): 4
```

| # | artifact | both produced? | differing lines |
|---|---|---|---|
| 1 | `D1-verdicts.txt` | yes | **1** (`$WANT` vs `WANT`) |
| 2 | `D6-srcswap-ordered.txt` (+`.err`) | **ORACLE ONLY** | — |
| 3 | `D6-srcswap-equiv.txt` (+`.err`) | **ORACLE ONLY** | — |
| 4 | `D6-matmul-ordered.txt` (+`.err`) | **PYTHON ONLY** | — |
| 5 | `D6-matmul-equiv.txt` (+`.err`) | **PYTHON ONLY** | — |
| 6 | the other **142** artifacts | yes | **0** |

The 142 zero-diff files include every one that matters: all 16 `D1-graph-*.txt`, all 32
`D2-canon-*`, all 16 `D2-cmp-*`, `D2-bytediff.txt`, all 7 `D5-plant-*`, all 5 `D3-control-*`,
all 10 `D9-stability-*`, `D0-coverage-census.txt`, `D0-ops-probe.txt`,
`D8b-cpython-dbg1-reachability.txt`, `D7-conf.txt`, `D8-dbg-*`, `D10-zerorow-guard.txt`,
`D0-selfcheck.txt`, `D0-run-summary.txt`, and every `.err`.

### 2a. `D1-verdicts.txt` — 1 differing line, and it is a literal `$`

```
oracle: ... each with a named cause in the $WANT comment above)
python: ... each with a named cause in the WANT comment above)
```

`oracle-run.sh:79` escapes it (`\$WANT`, inside a double-quoted `echo`), `differ.py:258`
emits `WANT`. The oracle's is the correct spelling — it names the shell variable the reader
is being pointed at. One byte; the Python's is a **dangling reference to a variable that does
not exist in the artifact**.

### 2b. `D6-*` — 4 LOST and 4 NEW CLAIMS. **This is the load-bearing artifact finding.**

```
oracle-run.sh:149   run D6-srcswap-ordered.txt  diff --graph matmul  --plant srcswap
differ.py:300        run(f"D6-{g}-ordered.txt",  "diff", "--graph", g, "--plant", "srcswap")   # g = "matmul"
```

Same command, same bytes of content (`D6-srcswap-ordered.txt` = 38 lines both sides,
`D6-srcswap-equiv.txt` = 31 lines both sides) — **different filename**.

- **LOST (4):** the oracle writes `D6-srcswap-ordered.txt`, `D6-srcswap-equiv.txt` and their
  `.err`s. **The Python writes neither.** Direction: **oracle → Python, a LOST artifact.**
- **NEW (4):** the Python writes `D6-matmul-ordered.txt`, `D6-matmul-equiv.txt` and their
  `.err`s. **The oracle never made these.** Direction: **Python → oracle, a NEW CLAIM NOTHING
  CHECKED** — and per the brief the new claim is the worse direction.

**Why this is worse than it looks: `artefacts_ok()` cannot see it.** It globs `D6-*.txt` by
prefix (`differ.py:449`), so the rename is invisible to the shape check, and `PINS` counts
neither. **A reader following `D6-matmul-*` finds a file the shell never produced, and a
reader following `D6-srcswap-*` finds nothing.** The naming also loses information: the plant
name (`srcswap`) was the more informative of the two, and `differ.py`'s docstring calls this
step "the ordered/`--equiv` split" without naming the graph.

## 3. VERDICT and DENOMINATOR — the claims, read separately

All **16 of 16** `VERDICT:` lines and all **16 of 16** `# DENOMINATOR:` lines **agree**:

| graph | VERDICT | `ops-reached=<py>/<bend> of 77` | nodes |
|---|---|---|---|
| `matmul` | AGREE | 7/7 | 18/18 |
| `reduce` | AGREE | 6/6 | 7/7 |
| `buffer` | AGREE | 4/4 | 5/5 |
| `sink` | AGREE | 2/2 | 2/2 |
| `range` | AGREE | 2/2 | 2/2 |
| `rangeflat` | AGREE | 2/2 | 2/2 |
| `cast` | AGREE | 5/5 | 6/6 |
| `special` | AGREE | 2/2 | 2/2 |
| `binblob` | AGREE | 8/8 | 19/19 |
| `group` | AGREE | 7/7 | 8/8 |
| `commute` | AGREE | 11/11 | 14/14 |
| `indexed` | AGREE | 6/6 | 7/7 |
| `sym` | AGREE | 6/6 | 12/12 |
| **`lin`** | **DISAGREE** | 11/11 | **46/46** |
| **`loop`** | **DISAGREE** | 14/14 | **25/25** |
| `gate` | AGREE | 12/12 | 14/14 |

**`lin` and `loop` DISAGREE on both sides, for the named measured causes** (`applied_opts` /
`CallInfo.cdtype`), and every `ops-reached` is `N/N` on both sides. The 15 summary keys are
identical, including the ones that must move if a step went silent:
`stable-pairs=5 of 5`, `stable-failed=0 of 5`, `stable-differ=0 of 5`,
`plants-disagree=7 of 7`, `controls=5 of 5`, `conflations=4 of 4`, `cross=1 of 1`,
`not-comparable=0`, `census-rc=rc=0`, `selfcheck=# SELFCHECK: OK`,
`oracle-selfcheck=# ORACLE SELFCHECK: OK`.

**`D1-verdicts.txt` therefore says `all 16 graphs: verdict as expected (14 AGREE; lin and loop
DISAGREE…)` on BOTH sides — one with a `$`, one without.** The Python's is computed from
`len(WANT)` and `conjoin(bad)` rather than hardcoded, so it is *more* robust; the oracle's
hardcodes `16`/`14` and would silently lie if the corpus grew. **The Python is better here and
the oracle is the frozen artifact — so this is a FINDING about the frozen shell, not a defect
in the port.** Left unreconciled.

## 4. THE PLANT — the comparison rejects

Two plants, because the first moved nothing and that is a statement about the plant.

**Plant 1 — the pin (`PINS["not-comparable"] "0" → "16"`), the move the brief forbids.**
Applied (`sha256 4ef5fbdc16d23823 → 1a08c3e22ceb335c`, anchor unique, reverted and verified).
**Result: 0 artifacts moved.** `PINS` is read **only** by `unhealthy()` (`differ.py:433`),
which `cmd_run` never calls — so `run`'s artifacts are **blind to a pin edit by
construction**. That is not a broken comparison; it says `run` and `repro` are different
gates, and only `repro` can see a pin. **A pin moved to match the code is a gate deleted —
and on `run` it is invisible.**

**Plant 2 — the sort (`sorted(D.glob("D2-cmp-*.txt"))` → `, reverse=True`, `differ.py:289`),
inside the code path `run` executes and writes.**
Applied (`sha256 4ef5fbdc16d23823 → d09a4d54fff7bbce`, reverted and verified).

```
PLANTED vs UNPLANTED-PYTHON: 1 differing file   -> D2-bytediff.txt
PLANTED vs ORACLE:           2 differing files  -> D1-verdicts.txt, D2-bytediff.txt
VERDICT: THE COMPARISON REJECTED THE PLANT
```

**`D2-bytediff.txt` was byte-identical before the plant and is not after. The comparison
caught it by name.** A comparison that has never rejected anything is not a comparison; this
one has now rejected a reordering it was supposed to be insensitive to.

## 5. THE `repro` HEALTH GATES DISAGREE — a third, larger divergence, and it is a GATE

The two `repro` drivers pin **different numbers for the same summary keys**:

| key | `oracle-repro.sh:66-86` | `checks/differ.py:128` (`PINS`) |
|---|---|---|
| `graphs` | **24** | **16** |
| `graphs-agree` | **22** | **14** |
| `byte-identical` | **21** | **14** |
| the other 11 keys | identical | identical |

**Direction: SHELL → PYTHON, the oracle moved the pins, and the direction that matters.**
**`graphs=24` is UNATTAINABLE — both drivers run the 16 graphs in `ALL`/`WANT`, measured
`graphs=16` on both sides.** So the shell's `healthy()` returns false on **every possible run**
and `oracle-repro.sh` would loop its full `WAIT` and exit 2 with
`# no healthy run in 9 attempts -- this is NOT a measurement`. **The frozen shell's
reproducibility gate cannot pass, ever.** The Python's `16/14/14` **is** attainable and **is**
satisfied by the run above.

**This is exactly the failure REACH.md records for this very pin** ("the exact failure §3c of
`graphcmp-LIMITS.md` records it having caused once already, when it pinned `13`") — and it
means the shell's `repro` has never been run in its current form. **The pins were NOT
reconciled here.** Reported.

### 5a. The `--check-only` first-line question — BOTH key on the text, and BOTH are unsound

`settled()` in both drivers reads the probe's **first line**, never its exit status
(`oracle-repro.sh:39` `2>&1 | sed -n '1p'`; `differ.py:412-414` `stderr=STDOUT` then
`split("\n",1)[0]`). **That part of the port is faithful.**

**But the check is unsound in BOTH, measured:**
- `--check-only` prints **`ALL PROOFS CHECK`, rc=0, for an EMPTY file** (0 bytes). Confirmed.
- A collectively-incomplete file does read `SOME PROOFS FAIL`, but that is the *only* other
  thing it catches — an empty file is a full pass.

**Both drivers inherited the defect identically, so neither is the divergent one.** The fix is
not in scope for this report; the fact is that `repro`'s "wait for the substrate" step would
accept a substrate that emits nothing, in both implementations.

## 6. WHAT IS ASSERTED, AND WHAT IS NOW MEASURED

| claim | before | now |
|---|---|---|
| "reproduces the shell's artifacts byte for byte" | ASSERTED, NOT MEASURED | **FALSE** — 4 LOST, 4 NEW, 1 line differing |
| "reproduces the VERDICT and DENOMINATOR on every input" | ASSERTED | **MEASURED TRUE** on 16/16 graphs, both the verdict and `ops-reached` |
| `D6-*` artifact naming | not checked | **4 LOST + 4 NEW CLAIMS, invisible to `artefacts_ok()`** |
| `repro`'s health pins | not compared | **DISAGREE, 3 keys; the shell's are unattainable** |
| `--check-only` first-line wait | not checked | **both use the text, both accept an EMPTY file** |
| the comparison can reject | never demonstrated | **DEMONSTRATED** (plant 2, `D2-bytediff.txt`) |
| the substrate can run its own gate | assumed | **FALSE in both trees** (`a9491a5c26bb`, two units, opposite halves) |

## 7. THE PLAIN SENTENCE

**No — the Python does not reproduce the shell byte for byte: of 151 artifacts, 147 names are
shared, 146 are byte-identical, 1 differs by a single character (`D1-verdicts.txt`, `$WANT` vs
`WANT`), 4 are LOST (`D6-srcswap-*`) and 4 are NEW CLAIMS the oracle never made
(`D6-matmul-*`) — and on the claims that matter it does reproduce it exactly, all 16 VERDICTs,
all 16 `ops-reached=<py>/<bend> of 77` denominators, and all 15 summary keys agreeing.**

## 8. WHAT I DID NOT DO, DELIBERATELY

- **Did not repin anything.** `PINS` is left exactly as committed. A pin moved to match the
  code is a gate deleted.
- **Did not reconcile the `$WANT` text or the `D6-` rename.** The shell is frozen; if the
  Python is right, that is a permanent, cheap finding.
- **Did not edit any `.bend`, `runtime/**`, `uop/**`, `graphcmp.py`, or another unit's files.**
  The `AOpLit` coldness is a **report**, not a patch: it belongs to whichever unit is holding
  each half, and the two halves are in different trees.
- **Did not commit.**
- `drive.sh` and `py-phase.sh` in this directory are **not mine** (timestamps 05:44 and 06:11,
  hours before this session) — a concurrent unit's files. Left alone.

### Reproduce

```sh
sh .agents/slop/differverdict/mkwarm.sh      # scratch tree at 3a68607fb198 = WARM
sh .agents/slop/differverdict/warmboth.sh    # both drivers, each from an EMPTY D/
.venv/bin/python .agents/slop/differverdict/cmpwarm.py [DANGLING: this instrument was DELETED by the 2026-10-05 prune and is not in git]
```