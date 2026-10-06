# SKIP IS NOT PASS, AND THE EXIT STATUS NOW SAYS SO

Unit `.agents/slop/skipexit/`. One job: `checks/e2e.py` said `SKIP IS NOT PASS` and then
exited 0 for PASS-with-SKIP. Owned files: `checks/e2e.py`, `checks/e2e.sh`,
`.agents/slop/e2epy/**`, this directory. Compiler Bend 2.0.34.

## 0. THE VERDICT LINE AND EXIT STATUS BEFORE AND AFTER, VERBATIM

Both from `.venv/bin/python checks/e2e.py` on this live tree, one before any byte was edited and
one after. Captured in `BEFORE.stdout`/`BEFORE.rc` and `AFTER2.stdout`/`AFTER2.rc`; the four
verdict lines are cut out verbatim into `BEFORE.verdict.rows` and `AFTER.verdict.rows`.

**BEFORE — `BEFORE.verdict.rows`:**

```
--- verdicts: 0 failed, 1 skipped ---
PASS WITH 1 SKIP(S) -- nothing failed, but 1 stage(s) measured NOTHING.
       PASS-WITH-SKIP IS NOT PASS. Read the skipped lines above.
rc=0
```

**AFTER — `AFTER.verdict.rows`, the same tree, the same seven stages, the same single skip:**

```
--- verdicts: 0 failed, 1 skipped ---
PASS WITH 1 SKIP(S) -- nothing failed, but 1 stage(s) measured NOTHING.
       PASS-WITH-SKIP IS NOT PASS, AND THE EXIT STATUS SAYS SO: 4, NOT 0. Read the
       skipped lines above. A caller that only reads `$?` can no longer mistake this
       for a clean pass; that was the defect.
rc=4
```

Stage 7 is the skip in both: `stage 7 f64 (double through the port, no Node): SKIP -- run-f64.sh
refused: its substrate is cold`. **The stages did not change, the tree did not change, and the
only thing that moved is the number a caller reads.**

**A NOTE ON A RUN IN BETWEEN.** One live run (`AFTER.stdout`, `rc=1`) came out `FAIL -- 1
stage(s) ran and failed` with stage 6 red, on a tree where the run before it had stage 6 green.
That is the **pre-existing** stage-6 non-reproducibility the brief names (measured: `run-port-mm`
twice on one tree, `rc 1` then `rc 0`), not a consequence of this change: `git diff HEAD --
.agents/slop/e2e_port/` is **empty**, stage 6's script was never touched, and the only edits are
the summary block and the docstring. It is recorded here rather than dropped because a run that
was quietly discarded is a run somebody will rediscover later.

## 1. WHY 0 WAS DEFENDED, AND WHY THE DEFENCE IS TRUE OF FAIL AND NOT OF SKIP

The old `:71` gave a reason, and it is not nonsense. A stage that RAN and FAILED does not
retract the stages that passed — that is CLAIM INDEPENDENCE, and it is correct. But a stage
that measured **NOTHING** retracts every claim that depends on it, including the passing
ones' claim to be *evidence about this tree*. "A passing stage does not retract the others"
presupposes the passing stage measured something. A skipped stage retracts even that.

**THE DEFECT IN ONE LINE: THE EXIT STATUS HAD THREE STATES AND TWO NUMBERS.** A caller that
reads only `$?` — which is all most CI runners read — cannot tell

| what actually happened                     | status before | status now |
| ----------------------------------------- | ------------- | ---------- |
| every stage ran, every stage agreed        | 0             | 0          |
| a stage ran and got the wrong answer       | 1             | 1          |
| a stage measured nothing at all            | **0**         | **4**      |

so it is trusted for a run in which the port was never judged on the f64 lane at all. A gate
that exits 0 having done nothing is worse than no gate, because it is trusted.

## 2. THE OPTION MEASUREMENT

Three options were on the table. The measurement that settled it is that the three states in
the table above are three distinct calls a caller can legitimately make, and the SKIP one was
folded into PASS.

**Option 1, SKIP ⇒ non-zero.** Rejected: the only non-zero it could reach that is not already
spoken for is 1 or 2, and both are taken by *this* script (`1` = a stage RAN and failed,
`2` = eight fruitless `bend` attempts). Collapsing SKIP into 1 destroys the distinction the
three-outcome design exists for — "the port is broken" versus "this machine cannot judge" —
and moves it from stdout, where it is legible, into `$?`, where it is not. It also falsifies
the failure prose: `FAIL -- N stage(s) ran and failed` would be printed for a run in which no
stage failed at all.

**Option 3, MAKE NOTHING SKIP.** Rejected BY MEASUREMENT, not by taste. Stage 7's refusal was
traced to its cause (`runs/e2e/e2e-f64.txt`, and the `repair.txt` it names):

```
     removed 33 adjacent identical block(s):
     duplicate `def` names remaining: none
     ./bin/bend -> rc=0  rows=227          <-- THE PORT'S ROWS *WERE* REPRODUCED
   /…/.agents/slop/cstyle-live/port.txt is absent -- rows vs the recorded good run CANNOT be checked
```

`repair-dupes.py:97-99` exits 2 because its **independent** cross-check file
`.agents/slop/cstyle-live/port.txt` does not exist. So:

- **NOT a retry.** Retry is for a transient condition. `port.txt` does not exist and
  `git log --all -- .agents/slop/cstyle-live/port.txt` shows it was never committed at that
  path (`git cat-file -t 0c6bb8889:.agents/slop/cstyle-live/port.txt` → *does not exist*). No
  number of attempts creates a file that has no source.
- **NOT a fixture fix I may make.** The fixture's entire value is that it was recorded
  INDEPENDENTLY, before the run. Regenerating it from the repaired copy makes the check
  `X == X` — a check that CANNOT FAIL, which is the "a plant that cannot move is a plant that
  passes" defect one level down. It would also launder another unit's live damage (33
  duplicated blocks in `renderer/cstyle.bend`, which the script's own header attributes to a
  mutation script that never asserted `end > start`) into a "known good" baseline.
- **A REAL SKIP**, until whoever owns `cstyle-live/` restores the recorded good run. Not this
  unit's file to write.

And option 3 would not even remove the contradiction on this machine: stage 3 SKIPs when there
is no `node` on PATH and stage 7 SKIPs on `rc 127` when there is no `zsh`. Those are real
skips no fixture can eliminate. Option 3 hides today's instance and leaves the defect.

**Option 2, A DISTINCT EXIT STATUS. CHOSEN.** The precedent is two units old and in the tree:
`bounded.py` added `5 NOT-STARTED` and `6 NO-VERDICT` for exactly this reason, and its own
header records the cost of not doing it — "a coarse summary where 3 cannot mean one thing …
A unit lost 425 rows by believing the status instead of the token." `e2e.py:79` already
refuses to route stages through it precisely because `3` there is ambiguous between a correct
refusal and a memory kill. The same lesson, applied here, in the only direction that survives:
**make the status mean one thing.**

`4` is free. `0` PASS, `1` a stage ran and failed, `2` eight fruitless attempts, `3` ORACLE
DRIFT (this file's own addition), and nothing in `e2e.sh`, `run-f64.sh` or `run-port-mm.sh`
emits `4` — those use `3` for their own refusals, which are a *different namespace* read at
`e2e.py:366` before the summary is reached.

## 3. FIDELITY: WHY THE SHELL BODY MOVED TOO

`checks/e2e.py` is a port, and the rule is that it reproduces the shell's verdict on EVERY
INPUT or it does not move — `.agents/slop/e2epy/diff.py:115` prints
`*** EXIT STATUS DIFFERS ***` when the two disagree. Changing only the Python would have made
the port diverge from the frozen oracle on the one input the whole defect lives on. So the
shell body carries the same change, and the oracle is re-frozen from it and BOTH pins move in
the same commit. That is the stage-8 retirement's precedent, named in the brief.

**MEASURED, ALL EIGHT PLANTS, AFTER THE CHANGE — `0 of 8 set(s) disagree`:**

| plant | reaches | exit (both sides) | stdout |
|---|---|---|---|
| `plant-pass` | 1 stage failed (stage 3, see §5) | 1 | IDENTICAL |
| `plant-passskip` | 1 failed + 1 SKIP | 1 | IDENTICAL |
| `plant-refuse` | 3 failed + 1 SKIP | 1 | IDENTICAL |
| `plant-no-node` | **stage 3 SKIP, nothing failed** | **4** | IDENTICAL |
| `plant-no-zsh` | 2 failed + 1 SKIP | 1 | IDENTICAL |
| `plant-thin` | stage 2 abort, `set -e` shape | 2 | IDENTICAL |
| `plant-deadbend` | stage 2 abort, `set -e` shape | 2 | IDENTICAL |
| `plant-stage1red` | stage 1 abort | 3 | IDENTICAL |

`plant-no-node` is the only plant that reaches the SKIP summary with **no** failure anywhere, so
it is the one that exercises the new status: both sides exit **4**. Status 0 is now reached only
by `plant-pass`'s own branch, and 4 is a distinct, observed, both-sides-agree outcome.

### 3a. THE PIN, BEFORE AND AFTER

| | ORACLE_SHA | BODY_SHA |
|---|---|---|
| before | `9ee46f84ca41453a4f3422f4636e12ab37e85d6517b0adc09d87c924b628b5d3` | `e75c9e38e22ff7297300735381373ab60617cf9fe7ed1645a35405ff2fa3a217` |
| after | `6a198bbf8fe1fcb1949009661b25a35d44ef765221bc4c2c8e35cfee0fc620be` | `24d7fbf196661779c6820622447454d42f0cd044bf11db12bde0f7d5de58d1bc` |

**MOVED WITH THE CHANGE, IN THE SAME EDIT — as they must.** A pin guards a file; an edit to that
file that leaves the pin behind turns the gate into a gate reporting drift about a repair.
`oracle_drift()` returns `[]` on the new pair, so the pin is not merely updated but **accepted**,
and the one-documented-edit invariant is re-proved by re-substitution rather than asserted in a
comment:

```
frozen.replace(new, old) == body   ->   True
```

### 3b. A HAZARD THE FIDELITY RUN CAUGHT, WHICH NO AMOUNT OF READING WOULD HAVE

The first frozen oracle carried the line ``a caller that only reads `$?` ``. In `sh` an
unescaped backtick pair is **command substitution**, so the shell ran `0` as a command and wrote
`line 314: 0: command not found` to the gate's own stderr. It surfaced as exactly one failing
input —

```
## plant-no-node    stdout: DIFFERS (1362 vs 1366 bytes)
  stderr: DIFFERS (118 vs 0 bytes)     <-- 0: command not found
```

— and only there, because `plant-no-node` is the one plant whose `PATH` is short enough for the
subshell to reach. **A hazard that only one of eight inputs can see is exactly the kind that
survives a review**, and it is why the frozen shell is run rather than read. The backticks are now
escaped, which makes the two sides emit the same bytes; the reasoning is in `checks/e2e.sh` beside
the line.

## 4. WHAT I COULD NOT SETTLE

- Whether `4` should be `2`, given `2` currently means "eight fruitless attempts" and that
  condition is also a stage that measured nothing. They are kept apart because `2` is reached
  under `set -e` BEFORE any stage ran, so the two runs have no per-stage verdicts to read at
  all, whereas PASS-with-SKIP prints them. That is a judgement, not a measurement.
- Stage 7 stays a skip until `cstyle-live/port.txt` is restored. That file is not this unit's.
- I did not re-run the whole diff over `--sets live`, which executes the real compiler, browser
  and GPU lanes. The live comparison is the `AFTER2` run above plus the eight plants; `live` is
  the one input set that needs the machine to itself, and its stage 6 is documented as
  not-reproducible run-to-run.

## 7. STAGE 7'S REFUSAL, STATED PLAINLY, BECAUSE "COLD SUBSTRATE" IS NOT WHAT IT IS

The gate prints `run-f64.sh refused: its substrate is cold`. **That sentence is the thing that
made this look like a memory problem, and it is not one.** Traced to its cause:

```
runs/e2e/e2e-f64.txt
     removed 33 adjacent identical block(s):
     duplicate `def` names remaining: none
     ./bin/bend -> rc=0  rows=227          <-- THE PORT'S ROWS *WERE* REPRODUCED
   …/.agents/slop/cstyle-live/port.txt is absent -- rows vs the recorded good run CANNOT be checked
```

`run-f64.sh:123-130` maps `repair-dupes.py`'s non-zero to `REFUSED, EXIT 3`, and
`repair-dupes.py:97-99` is:

```python
if not GOOD.exists():
    print(f"  {GOOD} is absent -- rows vs the recorded good run CANNOT be checked")
    sys.exit(2)
```

So the refusal is **`rc 2` from a MISSING FIXTURE**, on a substrate that was demonstrably warm —
`bend` compiled the repaired copy and emitted all 227 rows. No `bounded.py` bound is in this path
at all (`e2e.py:79` refuses to route stages through it), so no memory or time bound fired; the
`rc 3` is `run-f64.sh`'s own refusal code, in its own namespace.

**RETRY, FIXTURE FIX, OR REAL SKIP?**

- **NOT a retry.** Retry is for a transient condition. `port.txt` is not intermittent — it is
  absent, and `git cat-file -t 0c6bb8889:.agents/slop/cstyle-live/port.txt` answers *does not
  exist*. No number of attempts creates a file with no source.
- **NOT a fixture fix this unit may make.** `port.txt`'s entire value is that it was recorded
  **independently, before the run** — that is what makes it a control rather than a mirror.
  Regenerating it from the repaired copy turns the check into `X == X`, a check that cannot fail,
  which is the `A PLANT THAT CANNOT MOVE IS A PLANT THAT PASSES` defect one level down. It would
  also launder another unit's live damage — 33 duplicated blocks in `renderer/cstyle.bend`, which
  `repair-dupes.py:6-23` attributes to a mutation script that never asserted `end > start` — into
  a "known good" baseline.
- **A REAL SKIP**, pending whoever owns `.agents/slop/cstyle-live/` restoring the recorded good
  run from the run that produced it. It is not this unit's file to write, and guessing its
  contents would be worse than the skip.

**AND OPTION 3 WOULD NOT HAVE FIXED THE GATE ANYWAY.** Stage 3 SKIPs when there is no `node` on
`PATH` and stage 7 SKIPs on `rc 127` when there is no `zsh`. Those are real skips no fixture can
eliminate — `plant-no-node` reaches the summary with **no failure anywhere** and exits 4 on both
sides. Option 3 would have removed today's instance and left the defect, which is the exact shape
of the thing being fixed.

## 5. ONE THING THE PLANTS GOT WRONG, AND IT IS MEASURED NOT GUESSED

`diff.py`'s builder never created `e2e_mm_run.mjs`, so **stage 3 ran real `node` on a missing file
and FAILed `rc=1` in every plant**. The committed artifacts say so:

```
## plant-pass   ...   stage 3 gpu (node): FAIL (rc=1)
                     --- verdicts: 1 failed, 0 skipped ---
```

So `plant-pass` was never a green column — it was a one-failure column with a misleading name, and
`plant-passskip` reached its SKIP with a FAIL beside it, which would have driven the exit to 1 on
both gates and made the SKIP column non-discriminating for the wrong reason. `.agents/slop/
skipexit/repro.py` supplies a **three-line** stage-3 stub. It is a stub and not a copy of the real
script, because a plant that copies the thing it is meant to displace cannot prove anything.

**I did NOT fix `diff.py`'s builder**, which still lacks the stub: it belongs to the already
validated pair and changing it would invalidate the artifacts other units are reading. It is a
real finding and it is reported, not silently patched.

## 6. THE REPRO'S OWN TWO BUGS, CAUGHT BY ITS OWN VACUITY REFUSALS

Worth recording because both were caught by the belt, not by reading:

1. The first cut looked for the plant's stub marker in **stdout**. Stage 7 is captured with
   `> FILE 2>&1` and only its GREPED lines reach stdout, so a SKIP column's marker never appears
   there — and the repro correctly reported `the plant DID NOT MOVE` rather than passing.
2. The vacuity check itself was miswritten as an empty `for … pass` loop, which asserted nothing.

The gate's real assertion is that **a plant that cannot move must not be able to pass**: every
column checks that its intended verdict line appears exactly once, that the status is the expected
one, that the plant's own stubs ran, and that the artifact is non-empty — and the SKIP column adds
its own, which is that **the two gates must DISAGREE**. Reverting `return 4` to `return 0` in
place makes the repro exit 1 with `THIS REPRO IS LYING`, which is the required direction of
failure.

## 4. WHAT I COULD NOT SETTLE

- Whether `4` should be `2`, given `2` currently means "eight fruitless attempts" and that
  condition is also a stage that measured nothing. They are kept apart because `2` is reached
  under `set -e` BEFORE any stage ran, so the two runs have no per-stage verdicts to read at
  all, whereas PASS-with-SKIP prints them. That is a judgement, not a measurement.
- Stage 7 stays a skip until `cstyle-live/port.txt` is restored. That file is not this unit's.