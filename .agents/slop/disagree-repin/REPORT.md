# DISAGREE-GATE: two pins whose numbers legitimately moved, and a witness nobody re-took

Every number below carries the exact command that produced it and a UTC timestamp.
Nothing here is transcribed. Where a thing was NOT done, the reason is measured, not argued.

**GRANT USED:** `checks/disagree-gate.py` only. `checks/differ.py`, `runs/graphcmp/**`,
`.agents/slop/**` (this report), `gates/**witness*` — all UNTOUCHED. No `.bend` file touched.
`tinygrad/` untouched.

**`checks/disagree-gate.py` IS NOT IN `differ.SUBSTRATE_INPUTS`** — measured 2026-10-18
19:06Z, the 8-tuple is `("checks/differ.py", "checks/devpin.py", "bin/bend",
".agents/slop/graphcmp.py", ".agents/slop/graphcmp.bend", ".agents/slop/graphcmp-oracle.py",
".agents/slop/graphcmp-dbg-oracle.py", ".agents/slop/graphcmp-p13-ops.py")`. **So this unit's
edits CANNOT move `substrate_digest()`**, and `substrate_digest()` measured at
2026-10-18 20:13:05Z is `c74f32ca629d4be9…`, which EQUALS both `substrate-start` and
`substrate-end` of the run the gate reads. No baseline was invalidated by anything below.

---

## 0. THE BRIEF'S PREMISE WAS STALE BEFORE I ARRIVED, AND IT MOVED TWICE WHILE I WORKED

The brief says the disagreeing set is `[]`. **It was `[]` when the brief was written and it is
`[]` now, but it was NOT `[]` for 33 minutes of this session**, and the reason matters because
a pin edited against a moving population is the exact sin this task is about.

| UTC | command | disagreeing set | `substrate-start` vs `-end` |
|---|---|---|---|
| 19:39:53Z | `.venv/bin/python checks/disagree-gate.py` | **`['loop']`** | `cfba180991f5` vs `47066ce85b71` — **MIXTURE** |
| 20:13:19Z | `.venv/bin/python checks/disagree-gate.py` | **`[]`** | `c74f32ca629d` == `c74f32ca629d` — **COHERENT** |

The 19:39Z reading was taken on a run whose own two substrate rows DIFFER, i.e. a mixture that
names no thing. `D1-graph-loop.txt` at that moment read `VERDICT: DISAGREE`, `?=0/32`, and its
own ledger row said the cause was *"the bend fixture was rebuilt to all 52 of CPython's nodes
(it carried 25)"*. **That fixture rebuild is what produced `['loop']`** — it exposed a port
limit that 25 modelled nodes could not reach. **It is the same "25 of the 52 nodes" fact the
brief quotes**, quoted one state earlier. It is a FIXTURE change, not a port regression and not
the Ops re-index.

**By 20:13Z `loop` had gone `DISAGREE` → `rc=2`, NO `VERDICT:` line AT ALL** — REFUSED, not
AGREE. That is why the set is `[]` and why `graphs-agree=33`. See §3.

---

## 1. EACH OF THE FOUR LANES, BEFORE AND AFTER, AND WHICH CAUSE IS WHICH

Command (both readings, unchanged): `.venv/bin/python checks/disagree-gate.py`

| lane | BEFORE 19:39:53Z | AFTER 20:14:08Z | verdict | caused by the re-index? |
|---|---|---|---|---|
| **PIN** | `FAIL`, 2 complaints: `the disagreeing set moved: ['loop'], expected ['flip','unshard']` and `D0-run-summary.txt no longer reads graphs-disagree=2` | **`ok`** | **CAUSED BY A CORRECTNESS FIX** — the port now agrees with CPython on `flip` and `unshard`. NOT the re-index. | **NO** |
| **CITATIONS** | `REFUSED`, 1 complaint: `no line carries 'O.UOp.new(O.Found.ar(mul), O.OpsGROUP{}…'` | **`ok`** (rc=0) | **PRE-EXISTING, AND MEASURED AS PRE-EXISTING** — see below. | **NO** |
| **COVERAGE ARTEFACTS** | `ok` | `ok` | never moved | n/a |
| **PLANT + DISARM** | `FAIL [REFUSED] … this run has none` | **`FAIL [REFUSED] … this run has none`** — **UNCHANGED, AND IT MUST STAY** | the tree got better; a plant with no disagreement to move has no subject | n/a |

Gate exit: **3 (REFUSED) before, 3 (REFUSED) after.** Three lanes PASS; one lane REFUSES.
**DEFECT 1 IS NOT CLOSABLE TO `0` WITHOUT WEAKENING AN INSTRUMENT, and it is not weakened.**

### 1a. CITATIONS — pre-existing, and PROVEN pre-existing rather than asserted

`checks/disagree-gate.py --lane citations` reads **no artifact** (`lane_citations()` never
touches `runs/graphcmp/D`), so it was safe to run while a `repro` was in flight. It is safe
under a concurrent substrate edit, and that is how the 19:06:47Z reading was taken.

```
.venv/bin/python checks/disagree-gate.py --lane citations        # 2026-10-18T19:06:47Z
FAIL  CITATIONS
        [REFUSED] .agents/slop/graphcmp.bend: no line carries 'O.UOp.new(O.Found.ar(mul), O.OpsGROUP{}, [O.Found.i(add)'; the bend fixture builds that GROUP by hand, bypassing `UOp.group`
RC=3
```

The command that DECIDED pre-existence — `git log -S`, not `grep -c` on a string:

```
git log --format='%h %ad %s' --date=short -S'O.UOp.new(O.Found.ar(mul), O.OpsGROUP{}' -- .agents/slop/graphcmp.bend
  3001661a7 2026-10-18 graphcmp.bend BUILDS AGAIN, AND THE CORPUS VERDICT IS 4/34, NOT 34/34   <-- REMOVED IT
  bbe246aca 2026-10-09 whichgroup: THE PORT WAS NEVER WRONG ABOUT `flip` …                       <-- LAST PRESENT
```

and on `HEAD`…`HEAD~5` the needle reads **0, 0, 0, 0, 0, 0** (`git show <r>:.agents/slop/graphcmp.bend | grep -c`). **So the lane was red before any unit working today touched it, and the brief's instruction not to attribute it to the re-index is CORRECT and is now measured.**

**The cause is a defect that was FIXED, which is a pin failing because the tree got better** —
the same one-directional rot `arms_wired` was written to close, nine lines below it in the same
table. `bbe246aca` (2026-10-09) proved `UOp.group` of ONE src RETURNS THE src, so `g_flip`
builds no group node at all; that is still true at `tinygrad/uop/ops.py:537`
(`if len(srcs) == 1 and isinstance(srcs[0], UOp): return srcs[0]`). `69bfc2ee9` (2026-10-18,
"RE-INDEX Ops: GROUP and FLIP out, 77 -> 75") then made the hand-built GROUP **unspellable**,
so the old needle asserts something the COMPILER now forbids.

---

## 2. WHAT THE PIN ON `['flip','unshard']` WAS RECORDING, AND WHAT REPLACED IT

### It was recording: "**THESE TWO GRAPHS DISAGREE**"

Not "these two graphs are watched", not "these two graphs are fragile". `lane_pin` compares
`named` (the graphs whose run verdict is `DISAGREE`) against `sorted(PIN)`, and `PIN`'s four
columns are `row`, `fields`, `shape`, `fault` — **all four describe a disagreement and none of
them can spell "agrees"**. Measured 2026-10-18 20:13:19Z:

```
.venv/bin/python .agents/slop/disagree/names.py --json
  graphs= 34   disagree= []   substituted= []   wire= None
```

So the sentence is FALSE and **a pin on an empty set is a claim that nothing disagrees** —
which is a perfectly good thing to record.

### Decision: **DELETE** both entries. `PIN = {}`.

Not refresh, not restate. Three independent reasons, each measured:

1. **The gate's own arithmetic forbids the alternative.** `len(PIN)` IS the
   `graphs-disagree` denominator (stated in this file's own docstring and enforced at
   `lane_pin`). A "must keep agreeing" regression row is **not representable** in this table
   and would break the arithmetic. There is no third option that keeps a per-graph row.
2. **The gate has already decided this question five times the same way.** `allred`, `cdiv`,
   `late`, `lin`, `loop` all LEFT this table when they stopped disagreeing, each with a
   recorded reason, and the file says in so many words: *"They are not pinned-and-agreeing;
   they left, which is why `len(PIN)` is what `graphs-disagree` reads."* `flip` and `unshard`
   are the sixth and seventh, by the same mechanism: a correctness fix.
3. **It is not re-pinning to hide a complaint.** The complaint was "these two graphs
   disagree". It was falsified by the port getting right, and `D0-run-summary.txt` now reads
   `graphs-disagree=0`.

### What replaces it — and it is NOT lost

`lane_pin` asserts the generator's own row directly: `graphs-disagree={len(PIN)}` must be in
`D0-run-summary.txt`, i.e. `graphs-disagree=0`.

**MEASURED 2026-10-18 20:13:05Z, and this corrected a claim I had written and was wrong about:**
`differ.PINS` has **NO `graphs-disagree` key** — its 17 keys are `byte-identical, census-rc,
conflations, controls, cross, expect-moved, graphs, graphs-agree, graphs-answered,
graphs-unset, not-comparable, oracle-selfcheck, plants-disagree, selfcheck, stable-differ,
stable-failed, stable-pairs`. **So that row is asserted in `disagree-gate.py` and NOWHERE
ELSE.** `PINS["graphs-agree"]="34"` over `PINS["graphs"]="34"` implies it only
ARITHMETICALLY, and only while nothing is REFUSED. That weaker claim is not what the lane
checks, and the comment in the file now says so instead of the flattering version.

### THE LANE STILL HAS FOUR TEETH WITH AN EMPTY PIN — PLANTED, NOT ASSERTED

Plant run 2026-10-18 20:13:50Z on a **throwaway copy** in `$TMPDIR` (0 paths under
`runs/graphcmp/D` modified, measured `git status --porcelain -- runs/graphcmp/D | wc -l` = 0):

```
CONTROL, unplanted copy      lane_pin -> []  (PASS)
PLANT: one byte in D2-canon-bend-lin.txt row 32, PLUS the run verdict line that declares it
        names.py disagree -> [('lin', None, [])]
        lane_pin   -> ["the disagreeing set moved: ['lin'], expected []",
                       'D0-run-summary.txt no longer reads graphs-disagree=0']
        lane_plant -> ["PLANT B did not move belt 1 (still None): it is not reading the
                        differ's diff record"]
```

`lane_pin` goes RED on one planted disagreement. `lane_plant` **runs** and discriminates
whenever it has a subject. **The gate is not turned off.**

---

## 3. `repro`: **NO — THE WITNESS WAS NOT TAKEN, AND IT CANNOT BE TAKEN FROM THIS GRANT**

### The file is BYTE-UNTOUCHED, and I did not write a byte into it

```
stat -f 'mtime=%Sm size=%z' -t '%Y-%m-%d %H:%M:%S' runs/graphcmp/D/D0-repro.txt
  mtime=2026-10-17 01:50:09 size=130
grep -c repro-substrate runs/graphcmp/D/D0-repro.txt
  0
shasum -a 256 runs/graphcmp/D/D0-repro.txt
  298f491939bc6e07fab3dfac300966c3…
```

**CAUTION ON `git status` AS PROOF: it is NOT proof here.** `git ls-files --error-unmatch
runs/graphcmp/D/D0-repro.txt` answers *"did not match any file(s) known to git"* and
`git check-ignore -v` answers `.gitignore:262:/runs/`. The path is **IGNORED, not clean**, so
an empty `git status` says nothing either way. The proof of byte-untouchedness is the
**mtime, unchanged at 2026-10-17 01:50:09 across the whole session**, the size, and the
content. (Recorded because AGENTS.md's own index census notes ~1057:1 ignored-to-untracked;
"ignored" and "unmodified" are not the same word.)

### WHY, WITH A MEASUREMENT

`cmd_repro` calls `clean_run()` twice, and `clean_run` will not proceed past a non-empty
`unhealthy()`. Measured 2026-10-18 20:13:05Z:

```
.venv/bin/python -c "import importlib.util; …; print(m.unhealthy())"
  2 complaints:
    graphs-agree=33 (expected 34)
    byte-identical=33 (expected 34)
```

Both trace to ONE graph. `D1-graph-loop.txt` is 1179 bytes, carries **`rc=2` and NO
`VERDICT:` line at all**, and says in its own text:

> `PORT LIMIT, NOT A PARTIAL FIXTURE: … 16 of them answer `?` in the dtype AND shape columns
> because `uop/fold.bend` did not settle them. The cause is ONE node type: an `AFTER` whose
> `src[0]` has NO SHAPE. … Fix belongs in `fold.bend` … This is stated here and NOT compared
> (exit 2, REFUSED, never a verdict): do not read this artifact as a disagreement about the port.`

**`clean_run` therefore cannot produce a healthy run, `cmd_repro` returns `REFUSED` (3), and
the artifact is never written. THE BLOCKER IS A DEFECT IN `tinybendygrad/uop/fold.bend`, WHICH
THE HARD RULES FORBID ME TOUCHING.** `dt_of` has 33 mentions in that file. This is not a
budget problem, not a timeout, and not a refusal to try.

### TWO INDEPENDENT CONFIRMATIONS THAT `cmd_repro` REFUSED, NOT A HAND-OFF

| window (local) | pids | outcome |
|---|---|---|
| 22:00:39 → 22:39:32 | 69980 `bounded.py` → 69982 `differ.py repro` → 70036 `differ.py run` | gone at 22:39:32; `D0-repro.txt` **mtime still 2026-10-17 01:50:09** |
| 22:40:00 → 23:12:57 | 21673 `bounded.py` → 21674 `differ.py repro` → 21692 `differ.py run` | gone at 23:12:57; `D0-repro.txt` **mtime still 2026-10-17 01:50:09** |

The second window shows `D0-run-summary.txt` advancing **9 times** (22:43:34, 22:47:44,
22:51:36, 22:55:00, 22:58:24, 23:01:46, 23:05:08, 23:08:27, 23:11:50) — `clean_run`'s
`wait=9` attempts, each ~3.3 min, each rejected by the same 2 complaints.

### WHY I DID NOT LAUNCH A COMPETING `repro` — MEASURED, NOT ASSUMED

The first window was **already a mixture before I touched anything**: `checks/differ.py` mtime
moved to **22:08:31** and again to **22:15:00** while `repro` was running (22:00:39–22:39:32).
That is exactly the failure the brief names, *"RUNS 1-3 ARE MIXTURES"*, and it is why that run
left `substrate-start=cfba180991f5` against `substrate-end=47066ce85b71`. **A second
`differ.py repro` would have (a) collided with the live one on the same `runs/graphcmp/D`, and
(b) been a mixture again by construction.** I did not start one.

**NO ROW WAS HAND-WRITTEN. `repro-substrate=` was never typed into that file by this unit.**

### `repro_bad()` — complaint count and every line, BEFORE and AFTER

Identical, because the file and the tree are unchanged by this unit:

```
2026-10-18T19:39:49Z  repro_bad(): 1 complaint
    repro-substrate ABSENT from D0-repro.txt -- a witness that names no bytes is a measurement
    with no subject, which is `substrate_bad()`'s own rule for a summary and applies here
    unchanged. RE-TAKE it with `checks/differ.py repro`; never hand-edit a value into it

2026-10-18T20:13:05Z  repro_bad(): 1 complaint   (identical text)
```

**The complaint is CORRECT and it is the instrument working.** It is the one thing standing
between a four-day-old file and a pin that reports success with no measurement behind it.

---

## 4. `unhealthy()` — complaint count and ALL its lines, BEFORE and AFTER

```
2026-10-18T19:39:49Z   4 complaints                                    [MIXTURE of two substrates]
    expect-moved=1 (expected 0)
    graphs-agree=33 (expected 34)
    byte-identical=33 (expected 34)
    substrate-start=cfba180991f5 but substrate-end=47066ce85b71 -- THE SUBSTRATE MOVED WHILE
      THE RUN WAS IN FLIGHT, so D/ holds a MIXTURE of two substrates and no artifact set here
      describes one thing

2026-10-18T20:13:05Z   2 complaints                                    [COHERENT run, c74f32ca…]
    graphs-agree=33 (expected 34)
    byte-identical=33 (expected 34)
```

The 2 that remain are ONE defect: `loop` is REFUSED, so 33 agree + 1 refused, not 34 agree.
`PINS` rows absent from the summary: **none** (measured: `[]`).

---

## 5. DID THE SUBSTRATE MOVE? NO — AND WHAT THE `33 / 5-of-5 / 7-of-7 / 5-of-5` FIGURES MEAN

**`substrate_digest()` did not move under this unit's edits, because `checks/disagree-gate.py`
is not a declared input.** The run the gate reads is coherent on its own terms:

```
substrate-start=c74f32ca629d4be90e342a19ec84454af45d2e91aca14211c31769396a0dea96
substrate-end  =c74f32ca629d4be90e342a19ec84454af45d2e91aca14211c31769396a0dea96
live substrate_digest() (20:13:05Z) = c74f32ca629d4be90e342a19ec84454af45d2e91aca14211c31769396a0dea96
```

**So no new baseline was taken and none was needed.** For the record, the figures on THIS
coherent run are `graphs=34 graphs-answered=34 graphs-unset=0 expect-moved=0 graphs-refused=1
graphs-agree=33 graphs-disagree=0 byte-identical=33 not-comparable=0 stable-pairs=5 of 5
stable-failed=0 of 5 stable-differ=0 of 5 plants-disagree=7 of 7 cross=1 of 1
conflations=4 of 4 controls=5 of 5 selfcheck=# SELFCHECK: OK oracle-selfcheck=# ORACLE
SELFCHECK: OK census-rc=rc=0`.

**THE BRIEF'S `graphs-agree=33, byte-identical=33, stable-pairs=5 of 5, stable-failed=0 of 5,
plants-disagree=7 of 7, controls=5 of 5` ARE NOT COMPARABLE TO A RUN THAT INCLUDES `loop`.**
They are, in fact, these numbers — but `33` here means **33 OF 34, WITH ONE REFUSED**, not
33-of-34-disagreeing. `loop` reached `VERDICT: DISAGREE` at 18:56Z on the mixture and `rc=2`
on the coherent run, so any figure quoted across that boundary is comparing two different
states of one graph. **A reader who takes `33` as "33 agree" without reading `graphs-refused=1`
is reading a number whose denominator moved underneath it.**

---

## 6. COST, `ps`, `fsck`, `show --stat`

- **Peak RSS 43 024 384 B (41 MiB), 0.40 s real / 0.31 s user / 0.06 s sys** —
  `/usr/bin/time -l .venv/bin/python checks/disagree-gate.py`, 2026-10-18 20:14:11Z.
- **This unit ran NO `bend` process, NO `differ.py run`, and NO `differ.py repro`.** Peak RSS
  957 MB / `graphcmp.bend` 370–701 MB never applied because nothing was launched.
- **`ps` before commit: NONE** (no `differ.py`, no `bounded.py`, no `bend2/main.ts`).
  Every artifact read in this report was taken after 23:12:57 local, when the last in-flight
  run had exited — checked with `ps`, never with a count that could match my own command line.
- `git fsck --no-progress` and `git show --stat`: **see the commit step below.**

---

## 7. FOUND AND NOT DONE

1. **`lane_pin` and `lane_plant` cannot see a disagreement the run did not declare.** Both read
   the population from `names.py`, which derives it from the **`VERDICT:` line in
   `D1-graph-*.txt`** — not by recomputing the comparison. Measured: planting one byte into
   `D2-canon-bend-lin.txt` row 32 in a throwaway copy changed **NOTHING**; `lane_pin` stayed
   `[]` and `lane_plant` stayed `REFUSED`, because `D1-graph-lin.txt` still said `AGREE`.
   Freshness is enforced separately by `checks/runs-artifacts.py` (`ARTIFACTS-FRESH … newest
   0.0 h old`). **Not fixed**: recomputing the verdict inside the gate would be a SECOND
   comparison implementation, which is how two parsers come to disagree. Reported.
2. **`PLANT A` has a duplicated comment block.** `lane_plant` carries two near-identical
   paragraphs ("PLANT A: make the bend canon agree…"), the second superseding the first. Not
   touched — it is not a defect and the brief is about two named ones.
3. **`check_oracle()` reads `D2-cmp-loop.txt` when `loop` has no verdict line at all.** Not
   investigated; `loop` being REFUSED is the finding that matters and it is recorded as a TODO
   in the PIN table.
4. **`loop`'s fix belongs to `fold.bend` and is outside this grant.** Recorded as
   `TODO(differ-corpus)` in `checks/disagree-gate.py`, where a reader of the pin lands.
5. **A second `differ.py repro` is required before `repro_bad()` can be green**, and it cannot
   succeed until `loop` answers a verdict, because `clean_run` gates on `unhealthy() == []`.
   **Whoever fixes `fold.bend` unblocks the witness too.** That ordering is the finding.