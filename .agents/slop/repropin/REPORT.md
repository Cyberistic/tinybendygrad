# THE DENOMINATOR IS 2. `D0-repro.txt` IS A PIN, ON ITS OWN ARTIFACT.

**MEASURED 2026-10-07.** Every number below is an output of
`.venv/bin/python .agents/slop/repropin/measure.py`, saved verbatim in `measure.out`. It runs no
`bend`, writes nothing into `runs/graphcmp/D`, and begins with `pinindep`'s own control —
`derive.selfcheck()` — which **RE-DERIVES `D0-run-summary.txt` from the 241 artifacts with
`differ.py`'s own expressions and refuses to report unless it matches byte for byte**:

```
CONTROL OK -- rederive(live) == D0-run-summary.txt BYTE FOR BYTE
```

so a perturbation below that moved nothing would be a broken instrument, not a finding.

## WHAT A PIN IS, AND WHY THAT MATTERS MORE THAN ITS VALUE

`checks/differ.py:843` `unhealthy()`, read at `:849`:

```python
got = dict(ln.split("=", 1) for ln in text("D0-run-summary.txt").splitlines() if "=" in ln)
return [f"{k}={v} (expected {PINS[k]})" for k, v in got.items() if k in PINS and v != PINS[k]] \
    + [f"{k} ABSENT" for k in PINS if k not in got] + preconditions_bad(got)
```

**A pin is not a string to append to a dict. It is a triple — `(artifact, key, expected)` — and the
artifact is the half that was missing.** Every one of the 17 was `(D0-run-summary.txt, key, literal)`,
so all 17 shared one subject and `17/17 green` was one run's seventeen rows. That is the whole
shape, and it is why appending an 18th key to that dict would have been worth nothing.

## THE NEW PIN

| | |
|---|---|
| artifact | `runs/graphcmp/D/D0-repro.txt` — `checks/differ.py:300` `REPRO_ARTIFACT` |
| pins | `checks/differ.py:301` `REPRO_PINS = {"repro-rc": "rc=0"}` |
| reader | `checks/differ.py:870` `repro_bad()` |
| writer | `cmd_repro`, `:1085` / `:1089` — now writes `repro-rc=rc=0` / `repro-rc=rc=1` |
| judged by | `checks/corpus-figure.py` `run_health()`, which calls `differ.repro_bad()` **by reference** |

**One key, not three.** `repro-files` is `len(snap())` — measured **241 today, 242 after `repro`
writes its own artifact** — so it grows by one on the second `repro` and is an inventory, not a
claim. `repro-identical` equals `repro-files` exactly when `repro-rc` is `0`, so a pin on it could
only restate the one. Pinning either would be pinning a number that must be re-pinned whenever an
artifact is added, which is `graphs=34`'s defect wearing a new name.

## 1. THE DENOMINATOR: BEFORE 1, AFTER 2

Method: `measure.py` §A, patching `Path.read_text`/`read_bytes`/`open` around the **real**
`unhealthy()` and the **real** `repro_bad()`, pointed at a scratch copy — the same method
`pinindep/layer1.py` used, so the two readings are comparable.

```
`unhealthy()` opens 176 `.txt`; a pin VALUE is parsed out of ['D0-run-summary.txt'] (17 of 17 live there)
`repro_bad()` opens   1 `.txt`; a pin VALUE is parsed out of ['D0-repro.txt'] (1 of 1 there)

BEFORE  17 pins over 1 artifact  -> the denominator was 1 RUN
AFTER   17 pins over 1 artifact + 1 pin over 1 artifact = 2 DISTINCT ARTIFACTS THAT CARRY A PIN
        pins per artifact: [('D0-repro.txt', 1), ('D0-run-summary.txt', 17)]
```

**The denominator is 2, not 18.** MAX pins per artifact is unchanged at 17 — **that is the point**,
because the second file was read by nobody before. The gain is a second *subject*, not a second
number.

**The 174 files `unhealthy()` opens are NOT witnesses.** They feed `preconditions_bad()`'s
`device_of_run()` — the four `dev`/`lc_all`/`noopt`/`pythonhashseed` rows. `pinindep` measured
that; §A measures it again here, and the two agree.

### The independent-witness count, `pinindep`'s own method

`pinindep` derived **10 independent measurements** as `12 witnesses − 2 algebraically-determined`.
Applying the same arithmetic:

| | witnesses | algebraically determined | independent |
|---|---|---|---|
| before | 12 | 2 | **10** |
| after | **13** | 2 | **11** |

**11, not 12** — `repro-rc` is a free number in its own artifact, so it adds one witness and one
measurement, and removes no redundancy (§6). **The honest headline is not the count: it is that the
denominator for the question "would this run repeat?" went from 0 runs to 2 runs.**

## 2. SENSITIVITY: FOUR STATES, PLUS A CONTROL THAT FAILS

`measure.py` §B asks the **real** `repro_bad()` over a scratch copy. Every state names its offender;
none prints a count of green.

```
PASS  green -- `repro-rc=rc=0`
FAIL  RED -- `repro-rc=rc=1`, two runs DIFFERED
        -> repro-rc=rc=1 (expected rc=0, from D0-repro.txt)
FAIL  KEY ABSENT -- the writer's row moved
        -> repro-rc ABSENT from D0-repro.txt
FAIL  FILE ABSENT -- `repro` was never run to completion
        -> D0-repro.txt ABSENT -- the SECOND MEASUREMENT was never taken, so the denominator for
           `repro-rc` is 0 runs rather than 2. Run `checks/differ.py repro` to take it.
FAIL  CONTROL -- the PREVIOUS writer's shape, `repro-rc=0`
        -> repro-rc=0 (expected rc=0, from D0-repro.txt)
```

**The fifth line is the one that matters, and it is a pin that FAILS.** `cmd_repro` wrote
`repro-rc=0` until this change; the pin is `rc=0`, matching `census-rc`'s shape. So the pin catches
a **shape** move, not only a value move — a writer that renames its row cannot leave the pin
green, which is the difference between a pin and a label. **A MISSING pin is the same failure with
no reading at all, so absence is a complaint and not a pass** (lines 3 and 4 above).

## 3. INDEPENDENCE: THE TWO VERDICTS MOVE ON DISJOINT ARTIFACTS

`measure.py` §C, each perturbation alone:

```
edit `D0-repro.txt` only  : unhealthy() green -> green (+0);  repro_bad() green -> 1 complaint
edit the SUMMARY only     : unhealthy() ['graphs-agree=31 (expected 32)'];  repro_bad() STAYS GREEN
```

So the new pin is not a re-reading of the 17. It is a second witness.

## 4. `run`'s EXIT — THE RECOMMENDATION, AND THE REASON

**RECOMMENDED, AND IMPLEMENTED: `cmd_run` DOES NOT CONSULT `PINS`. `run` MEASURES; A SEPARATE
READER JUDGES. THEY MUST STAY APART.**

Measured by AST (`measure.py` §E, and `ast.walk` for `Name` nodes): **`cmd_run` reads `PINS`:
`False`; `unhealthy` and `repro_bad` read it: `True`.**

The trade, stated both ways:

* **Merging them** (`cmd_run` consulting all 17 + 1 before returning 0) would make `run` refuse to
  exit on a red row. It cannot be done: the pins are hand-written literals that move when the port's
  next fix lands — `differ.py:240-280` says so in its own comment — so a red run would refuse to
  *record* the row that would let a human re-pin, and the only way to clear it would be to edit
  the gate until it agreed. Worse, it makes the producer the judge of its own output, which is the
  inverse of the AGENTS.md rule.
* **Keeping them apart** costs one thing: `differ.py run` alone still exits 0 on a run that is 15
  pins red. That is already true today, is already documented (`differ.py:682`, and
  `pinindep` §7), and is **correct** — it is a measurement's exit status, not a health verdict.

**They must not be merged.** `corpus-figure.py` IS the separate reader and already was one
(`run_health()`), so nothing needed inventing. What changed is that its verdict now has a
denominator of 2 and prints them side by side:

```
RUN HEALTH : OK -- 17 of 17 pins green AND the SECOND WITNESS agrees: 2 artifact reads,
            D0-run-summary.txt (17 of them, one run) and D0-repro.txt (1 of 1, TWO clean runs
            byte-compared)
```
```
RUN HEALTH : **FAILED** -- 17 of 17 pins green over ONE artifact, plus 0 of 1 over `D0-repro.txt`
            (RED). RED: D0-repro.txt ABSENT -- the SECOND MEASUREMENT was never taken ...
```

Measured on the live tree today, `DEV=CPU .venv/bin/python checks/corpus-figure.py`: **rc=1**, with
the second line naming the absence. Before this change the same command printed `17 of 17 green` and
rc=0. That is the intended behaviour change and it is the point: **the absence of the second
measurement must not read as agreement.**

### Why `repro_bad()` is a FUNCTION BESIDE `unhealthy()` and not a row inside it

Not taste — a liveness failure, measured by order (`measure.py` §E):

```
order inside `cmd_repro`: clean_run() at offset 169, the artifact is written at offset 1183
  -> the health check runs 1014 chars BEFORE the file exists.
```

`clean_run()` calls `unhealthy()` **from inside `cmd_repro`**, one run before `D0-repro.txt` is
written. A health check demanding that file would demand a file the running command cannot yet
produce: `repro` could never report a healthy run, `clean_run` would exhaust its attempts, and the
gate would be deleted. **A gate that can never pass is worse than no gate.**

## 5. `artefacts_ok()` HAD TO CHANGE, AND THE CHANGE IS NOT A LOOSENING

`D0-repro.txt` is now in `declared()` (`:346`), so `checks/no-txt.py`'s `.txt` carve-out and the
`UNEXPECTED` arm see it — measured: the excused count is unchanged at **175** because the file is
not on disk, and a `.txt` this project writes that nothing declares is an orphan.

`artefacts_ok()`'s `MISSING` arm is now `declared() − REPRO_LITERALS` (`:900`). Measured live:
`artefacts_ok()` returns `[]` and `gates/retention-check.py` clause IV still reads
`IV OK runs/graphcmp/D/`. Without the carve-out it would report `MISSING D0-repro.txt` after every
single run — a guard permanently red, which is its own documented failure mode.

## 6. REDUNDANCY AMONG THE 17 — UNCHANGED, AND THE NEW PIN IS NOT DERIVABLE

`measure.py` §D, the same arithmetic `pinindep/redundancy.py` used:

```
graphs-answered == graphs - graphs-unset            : True  (34 - 0 = 34)   2 free numbers, 3 pins
stable-pairs + stable-failed + stable-differ == 5   : True  (5 == 5)       a PARTITION, 2 free, 3 pins
=> 17 pins, 2 algebraically determined, 15 free. UNCHANGED.
```

**Which pins are algebraically redundant:** `graphs-answered` (it is `n − u`) and one of
`{stable-pairs, stable-failed, stable-differ}` (a partition of a fixed 5, so any two determine the
third). **`pinindep`'s 10, not 12, stands; this task does not touch it.**

**Is `repro-rc` derivable from `D0-run-summary.txt`? NO — and that is the question that decides
whether the pin is real.** `measure.py` §E:

```
`cmd_run`   writes `repro-rc`  : False
`cmd_run`   reads  `D0-repro`  : False
`cmd_repro` writes `repro-rc`  : True
the summary carries a repro row: False
```

The summary is written by `cmd_run` from per-graph artifacts; `repro-rc` is written by `cmd_repro`
from the sha256 of **two snapshots of the whole directory**. **No row of `D0-run-summary.txt` is a
function of two runs**, so no pin over that row can witness it. A derived pin is a tautology — a
pin that cannot fail — and **this is not one.**

## 7. WHAT THIS DOES NOT FIX

1. **THE MTIME HOLE. `repro-rc` CAN BE GREEN AGAINST A RUN IT NEVER WITNESSED.** `runs/` is
   `.gitignore`d, so a plain `differ.py run` after a `repro` leaves `D0-repro.txt` untouched with a
   *newer* summary beside it, and the pin reads green. Measured: `D0-repro.txt` is **absent** on
   disk today, and `mtime(D0-run-summary.txt)` is the only clock in play. `pinindep` §5 established
   the defensible rule is the *reverse* of the brief's — refuse an artifact **OLDER** than the claim
   — and the three blockers it names all still stand (`differ.py` takes no `git` dependency and says
   so at `:58-60`; the artifact is untracked, so two clones answer differently). **Reported, not
   closed.** It is the same shape as `pinindep`'s 4 retro-fitted pins, in reverse: those are green
   by copy, this one can be green by neglect.
2. **11 measurements is still not 2.** 13 witnesses behind 2 artifacts means the two files are not
   independent *of each other at file level* — `snap()` hashes the whole directory, so `repro`
   re-observes everything the summary already reported. The independence is of the **attempt**, not
   of the subject matter. That is the strongest claim two clean runs can make, and it is not
   independence between artifacts.
3. **Nothing here makes a `bend` step fail loudly mid-run.** All of `pinindep`'s 11 sensitivity
   perturbations edit a *finished* artifact set; a substrate change during a run is still untested,
   and the tree has been bitten by exactly that twice (`run34`).
4. **`cmd_run` still exits 0 on 15 red pins.** Correct, documented, and unchanged — see §4.
5. **`gates/retention-check.py` was not touched** and does not consult `repro_bad()`. Its clause IV
   reads `unhealthy() + artefacts_ok()` and still answers about ONE artifact. It is not in my
   ownership; the reader that now says 2 is `checks/corpus-figure.py`.
6. **`snap()` will hash `D0-repro.txt` on the second `repro`.** Measured: 241 files today, 242 once
   the artifact exists. Harmless for `repro-rc` (the comparison is A-vs-B) and the reason
   `repro-files` is not pinned, but it means `snap`'s count is not stable across invocations.

## THE TWO-LINE VERSION

`REPRO_PINS = {"repro-rc": "rc=0"}` and `D0-repro.txt` now exist, and `repro_bad()` reads them out of
a **second artifact**. The denominator for "this run is healthy and it repeats" went from **1 run**
to **2 runs**, and a reader cannot be shown `17 of 17` without being shown whether the second
measurement exists — because on the live tree today it does not, and the instrument says so.