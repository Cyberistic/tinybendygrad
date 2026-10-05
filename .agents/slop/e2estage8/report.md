# STAGE 8 IS RETIRED. Its denominator was 0, and a gate with a denominator of 0 is not a gate.

`.agents/slop/e2estage8/`. Owns `checks/e2e.py`, `checks/e2e.sh`, `.agents/slop/e2epy/**` and this
directory. **NOT COMMITTED.** Compiler Bend 2.0.34, one `bend` at a time throughout.

## 1. THE EIGHT STAGE VERDICTS, WITH EACH DENOMINATOR, BEFORE THE RETIREMENT

`checks/e2e.py` on the live tree, `artifacts/pre.port.out`, all eight stages ran:

| n | verdict | denominator, counted out of the block |
|---|---|---|
| 1 | **no verdict line** — under `set -e` it aborts, so its status IS the gate's | **1**, the oracle's own exit status |
| 2 | **no verdict line** — same abort shape; `bend: 22 rows (attempt 1)` | **22** `name=value` rows, want > 20 |
| 3 | FAIL rc=1 | **1**, node's exit status |
| 4 | PASS | **38** `mm_e2e_*` rows against CPython |
| 5 | FAIL rc=1 | **None** — it died before printing any count |
| 6 | PASS | **64** u32 words against CPython's 64 |
| 7 | SKIP (rc 3, substrate cold) | **None** — it measured nothing, so nothing is knowable |
| 8 | FAIL rc=1 | **0** — `rows that REACH \`dtype.js\`` |

**Denominator 0 is not a smaller stage, it is the absence of one.** The stage said so itself:

```
rows that REACH `dtype.js`      0
rows that are pure `dtype.bend` 20   (NOT the JS lane)
FAIL  the plant moved 0 rows, so this stage CANNOT fail on the bug it exists for
```

A stage that cannot fail on the bug it exists for cannot pass either, and its presence makes the
seven around it look like a suite. The arithmetic it duplicated is measured at **1330/1330**
(102 i64 + 1228 fp8) by `.agents/slop/lastlaw/run.py`, so stage 8 was a 19-row echo of a 1330-row
gate. Re-declaring a `Dt.*` law as a seam would make the count non-zero and would undo `LASTLAW`,
so **retire, do not re-point.**

## 2. WHAT LANDED, AND WHERE

| file | change |
|---|---|
| `checks/e2e.sh` | stage 8's 39 lines of code and 63 lines of prose replaced by a 27-line retirement record; the header's stale `FOUR STAGES` → `SEVEN STAGES`; a `TODO(stage-5-denominator)` on `tail -3` |
| `.agents/slop/e2epy/oracle-e2e.sh` | re-frozen by replacing the ONE line `ORACLE_EDIT` names, so the two still differ by exactly that line |
| `checks/e2e.py` | stage 8's 37 lines of code deleted at the old `:402`; `JS_RE` and `RC_STAMP_RE` deleted with it; `EIGHT-STAGE` → `SEVEN-STAGE`; the docstring's stage-8 row is now `**RETIRED**`; the same TODO |
| `checks/e2e.py` pins | `ORACLE_SHA` `9ee46f84ca41453a…`, `BODY_SHA` `e75c9e38e22ff729…`. Old pair `e0eb23d5cb7340d5` / `f222c02c9481d982`. `oracle_drift()` returns empty |
| `.agents/slop/e2epy/diff.py` | `plant-stage8red` DELETED — a plant for a retired stage is the residue the retirement exists to remove; `codes` lost its dead 6th entry; the stubs now print the denominator their real counterparts print, so a plant transcript can be counted |
| `.agents/slop/e2epy/fixtures/plant-stage8red/` | removed, generated debris for a plant that no longer exists |
| `AGENTS.md` | the `e2e.py` clause rewritten: seven stages, the two still-deleted fixtures named, stage 6's non-reproducibility, and the retirement with its census |

**BOTH SIDES OF THE DISAGREEMENT ARE NOW GONE.** `checks/e2e.py:62`'s `RETIRED` was prose-only while
`:402` still emitted the stage — the docstring a reader trusts and the program that runs disagreed,
and `--help` could not tell a reader which was true. The prose now says RETIRED and the code does not
emit it, and **`e2estage8/verdicts.py` fails on that disagreement in either direction.**

## 3. THE PIN, AND THE PROOF THAT IT IS READ

`ORACLE_SHA` and `BODY_SHA` are checked in code on every run and refuse with exit 3. It moved twice,
and the second move is the interesting one: a **TODO comment** added to stage 5 of `checks/e2e.sh`
changed no code and the gate refused to start a single stage —

```
ORACLE DRIFT: checks/e2e.sh: e75c9e38e22ff729 != 558554c8ba676be4 -- the live shell body no longer
              matches the frozen oracle
rc=3
```

**A PIN THAT HAS NEVER FIRED IS A PIN IN A COMMENT**, and `checks/differ.py` shipped one
(`RECOVERED.md` §6). The pin is also planted directly in `plant.py`, by running a copy of the gate
in a tree with no frozen oracle: rc 3 before any stage runs.

## 4. DID THE SHELL AND THE PYTHON STILL AGREE? THE VERDICT DIFF, NOT A CLAIM

`e2epy/diff.py` runs the frozen shell and `checks/e2e.py` from the same cwd with one variable
apart, and compares **per stage**: verdict line, whole stage block, stdout, stderr, exit status.

**8 of 8 plants: 0 disagree.** Every verdict equal on both sides, exit statuses equal
(`0/0`, `1/1`, `2/2`, `3/3`), stdout byte-identical on 7 of 8. `plant-no-zsh`'s stdout is 1253 vs
1156 bytes and reports IDENTICAL: the 97 bytes are the shell's own `…: line N: ` prefix, which
`diff.py` strips from **both** sides as its one documented normalisation.

**The live tree, run twice, 90 minutes apart** (`artifacts/diff.live.txt`, `diff.live2.txt`):

| | run 1 | run 2 |
|---|---|---|
| exit status | oracle 1, port 1 — **agree** | oracle 1, port 1 — **agree** |
| stage blocks | 19 both sides, none lost | 19 both sides, none lost |
| stage 3 / 4 / 5 / 7 verdicts | **agree** | **agree** |
| stage 6 | FAIL / FAIL | PASS / **FAIL — `*** DIFFERS ***`** |
| stderr | 1168 = 1168 bytes | 1168 = 1168 bytes |
| differing blocks | 12, and one more | **12, 15, 17, 18** — the 17/18 differ only because stage 6's verdict did |

**THE DIFFERING BLOCKS MOVED BETWEEN TWO RUNS OF THE SAME PAIR**, and the disagreement is entirely
inside stage 6's own lane text. The direct measurement, same script, same tree, twice:

```
$ zsh .agents/slop/e2e_port/run-port-mm.sh ; echo $?   # -> 1
$ zsh .agents/slop/e2e_port/run-port-mm.sh ; echo $?   # -> 0
    *** RED BUT NOT SEMANTIC [C2 a single matmul A@C is not (A@B)@C] -- it fell over
    RED   [C2 a single matmul A@C is not (A@B)@C]
```

**STAGE 6'S LANE IS NOT REPRODUCIBLE RUN-TO-RUN**, so the live diff was comparing two runs of a
nondeterministic lane rather than two implementations. It is not caused by this change: the edit
removed stage 8 and nothing else, and stage 6's own text moved. `run-port-mm.sh:41` also uses a
FIXED work dir `${TMPDIR}/e2e-port-mm` with no `mktemp -d`, so consecutive runs share it.

**Therefore: the porting rule holds on everything structural and on every verdict except stage 6,
whose substrate cannot be compared to itself.** That is the honest reading, and it is a finding
about the substrate, not a licence.

## 5. PLANT AND DISARM FOR THE RETIREMENT — 6 of 6, `.agents/slop/e2estage8/plant.py`

No `bend`, `node` or `cc`: every arm is a text edit into a **copy** and a census over a stored
transcript. The shipped `checks/e2e.py` is only ever read.

| arm | planted | census |
|---|---|---|
| shipped, against an 8-stage transcript | — | rc 1: `CODE emits [] this transcript does not contain, and [8]` |
| **PLANT** prose RETIRED + code emits stage 8 | the one deleted `say("== 8/8 …")` line, re-inserted | rc 1: `PROSE says [8] is RETIRED and this transcript contains it` |
| **PLANT** prose LIVE + code retired | `**RETIRED` → `**LIVE, AND RE-POINTED AT` | rc 1: `PROSE names [8] the CODE does not emit, and [] the CODE emits and the PROSE does not name` |
| **DISARM** reworded retirement record | one comment's wording | rc 1, and the line is still `stage 8: DENOMINATOR 0` — the verdict did not move |
| **CONTROL** `plant-pass.port.out` | — | **rc 0**: `7 stage(s) emitted, 1 retired`, three readers agree |
| **PLANT** the frozen oracle gone | a copy of the gate in a tree with no oracle | **rc 3** before any stage runs |

**The control is what makes the other five mean anything:** a census that can only exit 1 cannot tell
a retirement from an outage. And its transcript is a plant's real run, not text I typed.

**MY OWN HARNESS HAD THE EXACT DEFECT THIS PROJECT KEEPS PAYING FOR.** The first cut of
`planted()` wrote back the *unmutated* text, so all three plants were no-ops and "passed" for the
wrong reason — the shipped gate against the same transcript already prints each expected string.
`RECOVERED.md` §7: *a positive control that patched nothing is the one failure this gate cannot
have*. `planted()` now asserts `after != before`.

## 6. WHAT I COULD NOT SETTLE

1. **THE GATE IS RED FOR THREE DELETED FIXTURES, NOT FOR STAGE 8.** stage 3 needs
   `.agents/slop/xd2/cdp.mjs` (`ERR_MODULE_NOT_FOUND`, node exits 1) and stage 5 needs
   `.agents/slop/ops_bend-milestone-expected.txt` (`FileNotFoundError`). **Both were deleted by the
   sweep while the gate still named them** — the same shape as the `e2e_mm.py` deletion the brief
   records: **a gate's own required input was deletable while the gate still named it.** Neither file
   is in my ownership (`.agents/slop/opsbend-milestone.sh` is a stage script, not `checks/e2e.sh`), so
   both are reported, not restored.
2. **STAGE 5's DENOMINATOR IS `None` AND THAT IS A GATE DEFECT I CHOSE NOT TO FIX.**
   `checks/e2e.sh` prints `tail -3` of the milestone, and `tail -3` is also what a crash replaces, so
   a stage that ran and printed nothing countable leaves the artifact unable to say what it would
   have measured. Fixing it changes what the gate prints **on both sides of the porting rule**, and
   the oracle is frozen precisely so such a change is a separate deliberate act rather than a side
   effect of retiring stage 8. Carried as `TODO(stage-5-denominator)` in both files.
3. **STAGE 6'S LANE IS NOT REPRODUCIBLE** (§4) and is not mine: `.agents/slop/e2e_port/`.
4. **`run-port-mm.sh` PRINTS A SENTENCE THE GATE CONTRADICTS** — `STAGE 6 FAILED -- … the script's
   exit status is STILL stage 4's and is unaffected by this line` — while the gate's own accumulator
   made that untrue. Prose inside a lane I do not own.
5. **`runs/e2e/e2e-jsstage.txt` IS NOW A RESIDUE.** The retired stage wrote it and the retired gate
   no longer declares it, so `runskeep` clause I (one directory, exactly its generator's declared
   set) fires. `runs/**` is not mine.
6. **THE LIVE CENSUS CANNOT GO GREEN ON THIS TREE**, and the only reason is 1 and 2. The green path
   is demonstrated on `plant-pass.port.out` instead.
7. **`checks/sweep.py`'s `NAMED_BY` IS NOT RE-CHECKED BY ME.** The brief records the citation set
   going 3,315 → 4,864 after it stopped excluding `checks/*.py`; `sweep.py` is not in my ownership.