#!/usr/bin/env python3
"""THE SEVEN-STAGE END-TO-END GATE. The Python successor of `checks/e2e.sh`.

`.venv/bin/python checks/e2e.py --help` says what it gates and each verdict's DENOMINATOR.
`checks/e2e.sh` is the shell body this port replaces, and it is still runnable: its root is ASSERTED
(`pyproject.toml` + `tinybendygrad/`) rather than computed by `../..`, which was correct at
`.agents/slop/` and resolved to the repo's PARENT from `checks/`. The shell's body is frozen at
`.agents/slop/e2epy/oracle-e2e.sh` as the ORACLE this port is diffed against, because the rule this
project wrote for itself is that the Python reproduces the shell's verdict on EVERY INPUT or it does
not move. That oracle differs from `checks/e2e.sh` by exactly the edits `ORACLE_EDITS` declares --
one pair per call site, applied in order, the FIRST of which is the `ROOT` preamble, because a fixture
tree has no `pyproject.toml` for the assertion to find -- and both shas are pinned in `ORACLE_SHA` and
`BODY_SHA`, CHECKED IN CODE on every run, refusing with exit 3 on drift. A pin in a comment is a pin
that cannot fail, and `checks/differ.py` measured that lesson the hard way.

**THE NUMBER OF PAIRS IS NOT WRITTEN HERE, AND THE REASON IS THIS PARAGRAPH.** It used to read
`exactly ONE documented edit -- ORACLE_EDIT` on a tree whose `ORACLE_EDITS` held 9 pairs, and that
was a governing-document claim about this file's OWN MECHANISM that was false for as long as it
stood (MEASURED 2026-10-19, `.venv/bin/python` over a `module_from_spec` load of this file:
`oracle_drift() == []` and `revert(oracle) == checks/e2e.sh` byte for byte at 19894 B each, so the
mechanism was SOUND and only its description had gone stale -- which is the same failure `BODY_SHA`
itself went stale on, in prose, one level up). So the number is now DERIVED WHERE IT IS USED:
`--help` prints `len(ORACLE_EDITS)`, and `oracle_drift()`'s own message carries it. **A COUNT
TRANSCRIBED IN PROSE ABOUT ITS OWN INSTRUMENT IS A COUNT NOBODY CAN CHECK.**

WHAT IT GATES, IN ORDER, AND THE ORDER IS THE ORDER THE CLAIMS COME IN:

  1  oracle      `e2e_mm.py` traces a real `(A @ B) @ C` out of CPython tinygrad on DEV=CPU,
                 takes tinygrad's own WGSL for each of the two launches, and writes
                 `checks/e2e-mm-oracle.json` plus the `.bend` that will be run.
                 (The oracle moved OUT of the ignored `runs/`; `checks/e2e.py:20`
                 named the conflict and `.agents/slop/runsgate/REPORT.md` landed it.)
                 DENOMINATOR: none of its own -- it is the fixture every later stage is measured
                 against. Under `set -e`, so a failure here ABORTS the gate with its own status
                 and NO verdict line is ever printed.
  2  port        `./bin/bend .agents/slop/e2e_mm.bend` runs the pure half. No GPU.
                 DENOMINATOR: **> 20 `name=value` rows**, retried up to 8 times, because bend
                 stack-overflows on roughly one run in twenty and prints NOTHING. A run with 20 or
                 fewer rows is NOT a pass and NOT a fail: it is retried. Under `set -e`, so 8 fruitless
                 attempts abort the gate with status 2.
  3  gpu         `node .agents/slop/e2e_mm_run.mjs` compiles the same `.bend` with `bend -o`, serves
                 it with a byte copy of `tinybendygrad/runtime/webgpu_call.js`, and walks it on a
                 real WebGPU adapter in headless Chrome.
                 DENOMINATOR: node's exit status, and nothing else -- the stage reads the STATUS
                 because a plausible-looking row on stdout is what a dead lane prints. No `node` on
                 PATH is SKIP, never PASS.
  4  gate        `e2e_mm_gate.py` diffs whole `name=value` rows against stage 1's CPython trace.
                 DENOMINATOR: the row count inside the gate's own text, which is `cat`-ed whole.
                 The status is the GATE'S, read from the command and never from a pipeline.
  5  ops_bend    `opsbend-milestone.sh` runs the port's OWN `ops_bend` runtime: three buffers, one
                 elementwise add over three f32 scalars, PACKET.out compared against the fixture
                 whose stem is `ops_bend-milestone-expected`, declared ONCE in
                 `.agents/slop/opsbend_milestone_gate.py` as `_EXPECTED_STEM` and resolved by
                 discovery. No stage names its EXTENSION: a rename moved it once and this stage died
                 at `FileNotFoundError`, which is a FIXTURE MOVED and a gate reading a hand list.
                 The expectation was written down BEFORE any run.
                 DENOMINATOR: that expectation file, and it is printed as the milestone's own last
                 three lines. No Node, no browser, no adapter, no tinygrad scheduler.
  6  port mm     `run-port-mm.sh` runs the SAME `(A @ B) @ Cm` with NO Node, NO browser, NO
                 `navigator.gpu` and NO tinygrad Python scheduler: `cstyle.bend`'s `render_kernel`
                 emits C, `cc` compiles it, BEND allocates, fills, LAUNCHES BY POINTER, reads 64
                 words back. RED AND NOT MINE: see the stage's own text, and do not read it as
                 this gate's opinion.
                 DENOMINATOR: 64 words read back against CPython's 64, plus the coverage table the
                 stage prints, which is what stops the artifact being quoted as stronger than one
                 of the port's gate rows being executed.
  7  f64         `run-f64.sh` runs the SAME kernel one dtype wider, `double`, through the same
                 committed harness on a copy. Its DENOMINATOR is why it is its own stage:
                 the port's `renderer/cstyle.bend` dtype driver (`rd_row`) covered exactly seven
                 dtypes -- f32, f16, bf16, bool, u8, fp8e4m3, i32 -- so all 227 rows are silent
                 about `double*`. (`rd_row` and its seven-dtype dispatch were DELETED by
                 `e51904b04`, which cut 1061 lines from `cstyle.bend`; the expected rows survive
                 as data in `gates/cstyle-live.rows`.)
                 **EXIT 3 FROM `run-f64.sh` IS A VERDICT, NOT A FAILURE TO REPRODUCE:** it refuses
                 without running a lane when its substrate is cold, and refusing is a third
                 outcome alongside PASS and FAIL. So is rc 127: no `zsh`, nothing measured.
  8  js lane     **RETIRED, AND NOT RE-POINTED: ITS DENOMINATOR IS 0.** It was `jstage.py`
                 running `runtime/dtype.js` through `bend -o` under node over 20 rows.
                 `dtype.bend` declares 0 `IO(` laws, so `rows that REACH dtype.js` is **0**,
                 the other 20 are pure `dtype.bend` arithmetic, and `runtime/dtype.js` is not
                 one byte of the emitted bundle. ITS OWN REPORT SAID SO OUT LOUD: `FAIL  the
                 plant moved 0 rows, so this stage CANNOT fail on the bug it exists for`.
                 **A GATE WHOSE DENOMINATOR IS ZERO IS NOT A GATE -- it can never fail, so it can
                 never pass either, and it makes the seven around it look like a suite.** What
                 replaces it is a CITATION, not a stage: `.agents/slop/lastlaw/run.py` measures
                 the same pure arithmetic at **1330/1330** (102 i64 + 1228 fp8) against the same
                 CPython callables, so stage 8 was a 19-row echo of a 1330-row gate. Re-point it
                 only if a `Dt.*` law becomes a seam again; evidence `.agents/slop/deadreg/
                 REPORT.md` §2. `.agents/slop/e2estage8/verdicts.py` is the census that keeps it
                 gone: it exits 1 on any emitted stage whose denominator counts 0.

THE THREE OUTCOMES, NOT TWO. `PASS` / `FAIL` / `SKIP`, and `SKIP IS NOT PASS`: a stage that could
not run has measured nothing, and reporting that as a pass is the same defect one level up. **AND
THE EXIT STATUS NOW SAYS SO, WHICH IS THE WHOLE POINT OF A THREE-OUTCOME VERDICT.**

THE OLD 0 WAS DEFENDED AND THE DEFENCE WAS TRUE OF FAIL AND NOT OF SKIP. It said: *a passing stage
does not retract the others' claims; a stage that RAN and FAILED is what makes the gate exit 1.*
That is CLAIM INDEPENDENCE and it is correct -- stage 6 failing must not retract "stage 4's matmul
is green". But it presupposes the passing stage measured something. A SKIPPED stage measured
**NOTHING**, and a stage that measured nothing retracts every claim resting on it, INCLUDING the
passing stages' claim to be evidence about this tree. So the rule that made `FAIL` non-zero does
not transfer, and the three states came out of the exit status as TWO NUMBERS:

| what happened                                | before | now |
| -------------------------------------------- | ------ | --- |
| every stage ran, every stage agreed           | 0      | 0   |
| a stage RAN and got the wrong answer          | 1      | 1   |
| a stage measured nothing at all               | **0**  | **4** |

**A GATE THAT EXITS 0 HAVING DONE NOTHING IS WORSE THAN NO GATE, BECAUSE IT IS TRUSTED**, so
PASS-with-SKIP is now `4` and `4` MEANS EXACTLY THAT AND NOTHING ELSE. Collapsing it into `1`
was rejected: it would print `FAIL -- N stage(s) ran and failed` for a run in which no stage
failed, and would lose the difference between *the port is broken* and *this machine cannot
judge* -- a distinction the three outcomes were built to keep. The precedent is two units old
and in the tree: `checks/bounded.py` added `5 NOT-STARTED` and `6 NO-VERDICT` for this reason and
its own header records the cost of a status that cannot mean one thing ("a unit lost 425 rows by
believing the status instead of the token"). Evidence `.agents/slop/skipexit/FINDINGS.md` §2,
which also disposes of the third option by measurement: stage 7's refusal is a COLD
SUBSTRATE; the separate deleted-fixture defect at `repair-dupes.py:97`
(`cstyle-live/port.txt` under the swept tree) is REPAIRED as of this unit — the recorded
good run is recovered from git and lives at `gates/cstyle-live.rows`, a TRACKED path. **NOT
under `gates/artifacts/`: that directory is `.gitignore`d AND is where gate runs write, so a
`rm -rf gates/artifacts` deletes anything kept there — which is how the first restore of this
fixture vanished. A gate's INPUT has to be in git or it is one cleanup away from gone.**

ONE `bend` PROCESS AT A TIME, ALWAYS, AND THE SHELL HAS NO CONCERN ABOUT IT. Measured 2026-10-05:
`ulimit` appears ZERO times in `e2e.sh`, and two `bend` processes took this machine's memory to
zero (`PEAKRSS.md`: 1,152 MB + 1,108 MB). The shell runs every stage strictly sequentially -- no `&`,
no `wait`, no `xargs -P`, in this file or in any of the four stage scripts it calls -- and so does
this port, stage for stage in the same order. **NO MEMORY BOUND IS ADDED HERE, and that is a
deliberate refusal, not an oversight:** routing a stage through `checks/bounded.py` would report a
kill as exit 3 or a timeout as exit 4, and stage 7 READS 3 AS A VERDICT. A bound that changes a
verdict is a change to the artifact, and the migration rule is fidelity. The gap is reported by
`.agents/slop/e2epy/report.md` instead.

EXIT STATUS, and the shell's, because the shell body carries this change too -- a port that
disagreed with its oracle on the very input the defect lives on would not be a port:

  0  every stage ran and every stage agreed
  1  one or more stages RAN and FAILED
  2  eight `bend` attempts produced no rows -- `set -e`, aborted inside stage 2, BEFORE any
     per-stage verdict exists to read
  3  THE FROZEN ORACLE MOVED (this file's own addition, and the shell's too): there is nothing
     to be a port of, so nothing was compared
  4  NOTHING FAILED BUT SOMETHING MEASURED NOTHING. Distinct from 0 so a caller reading only `$?`
     -- which is all most CI runners read -- can tell a clean pass from a partial one.

Plus the shell's `set -e` passthrough: stage 1's own status if `e2e_mm.py` fails. `4` is free --
nothing in `e2e.sh`, `run-f64.sh` or `run-port-mm.sh` emits it, and their `3`s are a DIFFERENT
namespace, read at `e2e.py:380` before the summary is reached.

ARGUMENTS: THE SHELL READS NONE, AND NEITHER DOES THIS, EXCEPT `-h`/`--help`. `e2e.sh foo bar baz`
runs all seven stages and ignores every word, so `checks/e2e.py foo bar baz` does the same rather
than failing on an argument the shell would have ignored. `--help` IS THE ONE DELIBERATE ADDITION
and it is not a verdict.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(os.environ["E2E_ROOT"] if os.environ.get("E2E_ROOT") else Path(__file__).resolve().parents[1])
# THE TREE BEING JUDGED IS NOT ALWAYS THE TREE THAT SHIPS THIS FILE, and the pins must belong to the
# second one. `E2E_ROOT` points the seven stages at a FIXTURE tree so every branch is reachable
# without a compiler, a browser or a GPU; a pin resolved against `ROOT` would then look for the
# oracle inside the fixture and report DRIFT on a tree that is perfectly intact -- which is the
# first run of this driver's answer, and it refused to compare anything at all.
REPO = Path(__file__).resolve().parents[1]
# `$PY` IS ABSOLUTE, like the shell's `PY="$ROOT/.venv/bin/python"`. It does not change any status,
# but it makes each stage's ARGV byte-identical to the shell's, which is how `.agents/slop/e2epy/
# diff.py` compares a stage's whole command line without the two sides differing in spelling.
PY, RUN = str(ROOT / ".venv/bin/python"), ROOT / "runs/e2e"
# `env -u PYTHONPATH` IS NOT APPLIED HERE, and that is fidelity rather than an oversight: the shell
# never applies it, so the seven stages inherit whatever `PYTHONPATH` the caller had. Removing it
# would change what `e2e_mm.py` can import, i.e. change a verdict.
ENV = dict(os.environ)
# ONE BEND AT A TIME IS A STRUCTURAL PROPERTY OF THIS PROGRAM, NOT A FLAG: `stage()` blocks, so no
# two stages and no two children of one stage are ever live at once. See the module docstring.
# THE FROZEN SHELL ORACLE IS PINNED HERE, IN CODE, AND CHECKED ON EVERY RUN. A pin in a comment is
# a pin that cannot fail, which is how `checks/differ.py` shipped a CORRECT pin that nothing read.
#
# TWO HASHES, AND THE SECOND ONE IS THE POINT. `ORACLE_SHA` is the frozen copy the port is diffed
# against. `BODY_SHA` is the shell body that copy was frozen FROM, and it is checked against the copy
# WITH ITS DOCUMENTED EDITS REVERSED -- so the correspondence is proved from the ONE FILE THAT
# SURVIVES rather than from a second file that must also survive.
#
# MEASURED 2026-10-05, AND IT IS WHY: the live cleanup unit `qmyqvmnpsloz` ("THE POLICY IS PYTHON
# ONLY ... 103 ONE-OFF `.sh` DELETED") DELETED `checks/e2e.sh` from the working tree WHILE THIS PORT
# WAS BEING WRITTEN, minutes after it had been read and copied. `checks/e2e.sh` is checked as well,
# but ONLY IF IT IS STILL THERE: a pin on a file another unit is entitled to delete becomes a gate
# reporting drift about a deletion instead of about a change. THE ORACLE IS THE SURVIVOR, which is
# the entire reason the migration rule freezes one.
# THE PIN MOVED FOUR TIMES AND EVERY MOVE IS THE PIN WORKING, AND THE FOURTH IS THE ONE THAT
# SETTLES WHETHER IT COULD BE DELETED. Once when stage 8 was retired, once when a TODO comment was
# added to stage 5 -- the second time it is the proof that this pin is read, because `checks/e2e.py`
# refused to start a single stage and exited 3 on a change that moved no code at all -- once on
# 2026-10-06 when PASS-with-SKIP became exit 4, which moved the shell body too because a port that
# disagreed with its oracle on the one input the defect lives on would not be a port, and once on
# 2026-10-06 when `checks/e2e.sh`'s root was ASSERTED rather than computed (`.agents/slop/e2esh/`).
#
# **THE FOURTH MOVE WAS MEASURED BEFORE IT WAS PAID, AND IT IS WHY (3) IS STILL HERE.** Three commits
# touched `checks/e2e.sh` and zero of them left the pin behind (`.agents/slop/e2esh/history.py`), which
# is a fact about DISCIPLINE and not about the pin's ability to see. So the pin was planted two
# changes and asked (`.agents/slop/e2esh/plant.py`): appending ONE COMMENT LINE, and the root fix
# itself. Both gave `oracle_drift() -> ['checks/e2e.sh: <sha> != 24d7fbf1…']` and
# `checks/e2e.py -> rc=3` with `== 1/4 oracle` never printed. **A CHANGE TO `checks/e2e.sh` FAILS
# SOMETHING, AND THAT SOMETHING IS THIS GATE, SO DELETING (3) WOULD DELETE THE ONLY THING THAT
# NOTICES.** The sibling unit's conclusion -- that deleting `checks/e2e.sh` is the clean unblock --
# rests on the pin's own comment, not on a measurement, and the measurement does not support it.
#
# THE THING THAT WAS BELIEVED INSTEAD, AND MEASURED FALSE: that stdout fidelity already covers the
# live shell, so the text pin is redundant with it. `diff.py` compares `checks/e2e.py` against the
# FROZEN ORACLE and never reads `checks/e2e.sh`, and under both plants it reported
# `1 of 1 set(s) disagree` with the entire disagreement being the port's own refusal --
# `.agents/slop/e2epy/artifacts/plant-no-node.port.err` held two lines, both of them `ORACLE DRIFT`,
# and `plant-no-node.port.out` was EMPTY. **THE PIN IS INSIDE THE MEASUREMENT, SO THE MEASUREMENT
# CANNOT SEE PAST IT.** There is no stdout-level observer of the live shell to move the pin down to,
# and `checks/e2e.sh` asserting its own root is what makes its bytes worth asserting at all.
#
# **A PIN GUARDS A FILE, AND ANY EDIT TO THAT FILE MUST MOVE THE PIN IN THE SAME COMMIT**, and a pin
# that has never fired is a pin in a comment, and `checks/differ.py` shipped one (`RECOVERED.md` §6).
#
# **`BODY_SHA` IS A CONTENT PIN, NOT A BEHAVIOUR CLAIM, AND THE DISTINCTION IS WRITTEN DOWN HERE
# BECAUSE A HASH OF A WHOLE FILE CANNOT TELL A COMMENT FROM CODE.** What is pinned is the BYTES of
# `checks/e2e.sh`, so the question it answers is "is the live body still the body the frozen oracle
# was taken from", and its remedy is the rule above: move the pin in the same commit. A comment-only
# edit is an edit; it is not a *smaller* one, and a check that pretended otherwise would be comparing
# something other than what it declares. MEASURED 2026-10-18 19:11Z, `difflib` over
# `revert(oracle)` and the live body: 6 changed lines, 2 replaced by 4, and EVERY ONE BEGINS WITH `#`;
# the 108 non-comment lines compare EQUAL and `sh -n` accepts both files. It moved because
# `813bbec3e` restored `checks/e2e.sh` and `ce4bd59c49:checks/e2e.sh` hashes to `aaea6add…` -- the
# PINNED value -- while the blob that restore wrote is `fcf647cd…`. So the pin was RIGHT and the
# shell moved, and the correct act is to re-freeze it WHILE NAMING THE DELTA in `ORACLE_EDITS`, not
# to delete the pin and not to teach the hash about comments.
# **RE-FREEZING `BODY_SHA` ALONE IS MEASURED INSUFFICIENT.** `.venv/bin/python` over a scratch copy
# of these three files with only that one line changed returns a NON-EMPTY `oracle_drift()` -- and
# the surviving complaint is #2 ("reverting its documented edits gives …"), not #3 -- because "the
# oracle differs from the body by exactly these edits" is a claim about the ORACLE too. The delta is
# therefore declared, and the byte identity `revert(oracle) == checks/e2e.sh` still has to hold, so
# any UNdeclared difference in either file still stops the gate.
#
# Current pair below; the pair before this one was
# ORACLE_SHA 05d7cfea… / BODY_SHA fcf647cd… (`6ed4e1c1e`), the pair before that was
# ORACLE_SHA 05d7cfea… / BODY_SHA aaea6add… (`5ed3ad771`, whose `checks/e2e.sh` hashes to it), the
# pair before the root fix was
# ORACLE_SHA 6a198bbf… / BODY_SHA 24d7fbf1…, the pair before the exit-status change was
# ORACLE_SHA 9ee46f84… / BODY_SHA e75c9e38…, the stage-8-only pair was
# ORACLE_SHA 245a10db… / BODY_SHA 558554c8…, and the pair before the retirement was
# e0eb23d5cb7340d5 / f222c02c9481d982.
# THE PIN MOVED A SIXTH TIME, AND IT MOVED BECAUSE THE BODY MOVED: `checks/e2e.sh` gained two
# `#` comment lines' worth of corrections to two citations of the stage-5 fixture, so its bytes
# changed and the pin that names those bytes had to change with them IN THE SAME COMMIT. That is the
# rule `BODY_SHA`'s own comment records ("any edit to that file must move the pin in the same
# commit"), and following it is what keeps the comment-only-edit refusal honest: a pin that only
# fired for code would have been a pin with a hole in the one place this gate has been bitten twice.
# MEASURED, and the delta is the WHOLE story, not a re-freeze:
#   `BODY_SHA` was `69d7cfcd…`, is now `2ef51412…`;
#   `len(ORACLE_EDITS)` is 11 pairs;
#   `revert_oracle()` over all 11 and `checks/e2e.sh` are both 20388 bytes and both `2ef51412…`;
#   `oracle_drift() == []`.
# **AND `sh -n` ACCEPTS BOTH SIDES**, which is the check that a comment edit cannot be a code edit.
# The pair before this one was `69d7cfcd…`, the pair before that was `bdbf6f6c…`, and before that
# `fcf647cd…`.
ORACLE_SHA = "05d7cfea0aea9c8523649ad1e277cb03890214cb9c7996807c1b0295207f8696"
BODY_SHA = "2ef51412c74428b8545a133ebedeb763407ec9b3c78bf58fdf726e10a15cd3bb"
# THE DOCUMENTED EDITS, IN ORDER, AS `(ORACLE_SIDE, SHELL_SIDE)`: applying every one of them to the
# frozen copy must yield the live body, byte for byte. So the ORACLE's text is the FIRST element of
# each pair. `ORACLE_EDIT` IS STILL THE NAME OF THE FIRST PAIR AND IT IS NO LONGER THE ONLY ONE --
# **it is not read alone by anything any more**, which is the repair, measured 2026-10-19:
# `.agents/slop/e2esh/refreeze.py` applied `ORACLE_EDIT` and nothing else, so its question (2)
# reported a byte difference that is really 1 of the declared pairs. It now calls `revert_oracle()`
# below, the SAME function `oracle_drift()` uses, so two readers of this mechanism cannot drift
# apart -- one transform, two callers, `AGENTS.md`'s "shareable logic should be reused".
ORACLE_EDIT = ('ROOT=${E2E_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}\n', """# ROOT IS ASSERTED, NOT COMPUTED. `../..` is `dirname "$0"` up two, which was correct while this
# file lived at `.agents/slop/` and is WRONG here: `checks/` is one level shallower, so it resolved
# to `/Users/cyberistic/src/tries` -- the repo's PARENT, a directory that exists, so `cd "$ROOT"`
# succeeded and every stage then ran against a tree that is not the repository.
# `.agents/slop/shells/README.md` holds the census; this was the seventeenth of seventeen.
# `${0%/*}` is POSIX and spawns no `dirname`, and the `case` arm is the `$0` that carries no slash.
_d=${0%/*}; case $_d in "$0") _d=.;; esac
ROOT=$(cd "$_d/.." && pwd)
[ -f "$ROOT/pyproject.toml" ] && [ -d "$ROOT/tinybendygrad" ] ||
  { echo "$0: not at the repo root (pwd $ROOT)" >&2; exit 2; }
""")
# THE SECOND DIFFERENCE, AND IT IS COMMENT TEXT IN A STAGE-7 HEADER. It arrived with `813bbec3e`'s
# restore and was never declared, which is the whole reason this gate was dark: 6 lines, every one a
# `#` comment, and the shell's 108 non-comment lines identical on both sides (measured, above). It is
# TWO pairs, not one, because one unchanged line separates the two regions and `str.replace` takes
# one region at a time -- so "one pair per call site", not "one pair per commit".
# THE THIRD DIFFERENCE, AND IT IS FOUR STAGE HEADERS. STAGES 5, 6 AND 7 WERE "ADDED, NOT
# SUBSTITUTED" (this file's stage-5/6/7 blocks, and the shell's) AND EACH WROTE ITS OWN DENOMINATOR
# -- `5/5`, `6/6`, `7/7` -- WHILE THE FOUR THAT EXISTED SAID `1/4 2/4 3/4 4/4`. So the gate emitted a
# SEVEN-STAGE ARTIFACT THAT SAYS FOUR TIMES THAT IT IS FOUR STAGES LONG. A DENOMINATOR IS THE COUNT
# OF A POPULATION, AND ONE TRANSCRIBED INSTEAD OF DERIVED IS A TRANSCRIPTION THAT DECAYS THE MOMENT A
# STAGE IS ADDED: this is why the number was wrong for 4 of 7 and nobody noticed, because a reader
# compares `n/` against the `n` on the same line, and `1/4` is internally CONSISTENT. It is also a
# PARSER INPUT and not only a printed number -- `.agents/slop/e2estage8/verdicts.py:30` splits
# stages on `^== (\d+)/\d+`, so whatever is on the right of the slash is what the census inherits.
#
# **THE DENOMINATOR IS STILL WRITTEN OUT, AND THAT IS A NAMED REFUSAL, NOT AN OMISSION.** The right
# fix is to DERIVE it from the seven `say("== n/...")` call sites, so stage 8's retirement cannot make
# it stale again. It is not done here because `.agents/slop/e2estage8/verdicts.py:49` discovers the
# emitted stage set with `CODE = re.compile(r'say\("== (\d+)')` -- it READS THE POPULATION OUT OF
# THESE LITERALS, so a derived header would make the census report `PROSE names [...] the CODE does
# not emit` and go DARK. That trade, an honest number bought with a dead instrument, is refused.
#
# **AND TWO OF THE SEVEN WERE WRONG ANYWAY, MEASURED 2026-10-19T15:41Z BY A CENSUS, NOT BY A READER.**
# The fix above took `1/4`..`4/4` to `/7` and DID NOT TOUCH THE TWO STAGES THAT HAD BEEN ADDED: `5/5`
# and `6/6`, each written by the author of that stage and each internally CONSISTENT, so every reader
# compared `n/` against the `n` on the same line and saw nothing. `.agents/slop/e2estage8/verdicts.py`
# counted the call sites itself (`census FOUND 7 stage call site(s) in e2e.py`) and compared them:
#     gate SAYS 7 denominator(s), from the gate source: 1->7 2->7 3->7 4->7 5->5 6->6 7->7
#     DENOMINATOR FAIL: stage 5: the gate's own banner says `== 5/5` and the gate emits 7 stage(s)
#     DENOMINATOR FAIL: stage 6: the gate's own banner says `== 6/6` and the gate emits 7 stage(s)
# THE LESSON IS THE ONE THE FIX ABOVE ALREADY TAUGHT AND DID NOT APPLY TO ITSELF: **A PARTIAL FIX IS A
# PARTIAL FIX, AND A GATE THAT PASSES IS NOT EVIDENCE THAT IT IS FINISHED.** Both banners are now `n/7`
# and both sides of the port moved in this commit.
#
# THE PIN MOVED A FIFTH TIME, AND `BODY_SHA` MOVED WITH THE SHELL BY ONE BYTE-FOR-BYTE PROOF, not by a
# comment: `revert(oracle)` over the nine pairs and `checks/e2e.sh` are both 19894 bytes and both
# `69d7cfcd7fb71b7f`, so the two pairs above are the WHOLE delta and no undeclared difference rode in
# with them. The pair before this one was `bdbf6f6c…`, and the pair before that was `fcf647cd…`.
#
# BOTH SIDES MOVED IN ONE COMMIT, because a port that disagreed with its shell on the very lines it
# emits is not a port (`checks/e2e.py:126`). THE ORACLE IS FROZEN AND NOT EDITED, so it still says
# `/4` for stages 1-4 and `5/5`/`6/6` for the two stages that were added rather than substituted, and
# these nine pairs are what keeps `revert(oracle) == checks/e2e.sh` byte for byte: the delta is
# NAMED rather than removed, which is the whole difference between a pin and a hash.
#
# THE COST THAT EXISTED, MEASURED, AND REPAIRED IN THE SAME COMMIT THIS DELTA LANDED:
# `.agents/slop/e2esh/refreeze.py` applied `ORACLE_EDIT` alone, so it answered its own question (2)
# wrongly for 1 of the 9 declared pairs rather than for the delta, and it KNEWED -- its own comment
# said so. Its questions (1) and (3) were always sound. One call to `revert_oracle()` is the fix, and
# that function is the one `oracle_drift()` uses, so the reader cannot become wrong again by being
# corrected in one place only.
ORACLE_EDITS = (
    ORACLE_EDIT,
    ("# HAS NO `f64` GATE ROW.  `renderer/cstyle.bend:2984-3015` calls `rd_row` for exactly\n",
     "# HAS NO `f64` GATE ROW.  The port's cstyle dtype driver (`rd_row`) called exactly\n"),
    ("# f64 is not among them, so all 227 rows are silent about `double*`.  `tmap CLANG`\n",
     "# f64 is not among them, so all 227 rows are silent about `double*`.  (`rd_row` and its\n"
     "# seven-dtype dispatch were DELETED by `e51904b04`; the rows survive as data in\n"
     "# `gates/cstyle-live.rows`.)  `tmap CLANG`\n"),
    ('echo "== 1/4 oracle (CPython tinygrad, DEV=CPU)"\n',
     'echo "== 1/7 oracle (CPython tinygrad, DEV=CPU)"\n'),
    ('echo "== 2/4 port (pure bend, no GPU)"\n',
     'echo "== 2/7 port (pure bend, no GPU)"\n'),
    ('echo "== 3/4 gpu (real WebGPU adapter, headless Chrome)"\n',
     'echo "== 3/7 gpu (real WebGPU adapter, headless Chrome)"\n'),
    ('echo "== 4/4 gate"\n', 'echo "== 4/7 gate"\n'),
    ('echo "== 5/5 port\'s own device (the port\'s ops_bend runtime executes)"\n',
     'echo "== 5/7 port\'s own device (the port\'s ops_bend runtime executes)"\n'),
    ('echo "== 6/6 the matmul THROUGH THE PORT (no Node, no browser, no navigator.gpu)"\n',
     'echo "== 6/7 the matmul THROUGH THE PORT (no Node, no browser, no navigator.gpu)"\n'),
    # TWO MORE, AND THEY ARE THE ONES THIS COMMIT IS ABOUT. Both are `#` comment lines in
    # `checks/e2e.sh` naming `ops_bend-milestone-expected.txt`, a path that has not existed since the
    # fixture was renamed to `.md`. **A COMMENT LINE IS NOT A STRING THE SHELL READS** -- `/bin/sh`
    # discards it before execution, `grep -v '^[[:space:]]*#' checks/e2e.sh | grep -c
    # 'ops_bend-milestone-expected'` is `0` and `grep -c '<<' checks/e2e.sh` is `0`, so no heredoc
    # body mentions it either -- which is why this could sit here falsified and run. It was load-bearing
    # all the same: it is the citation a reader would follow to the fixture.
    # THE FIRST IS A LIVE POINTER, so it now names the STEM the loader actually resolves
    # (`_EXPECTED_STEM` in `opsbend_milestone_gate.py`, by discovery), which is the same lesson the
    # stage-5 header in this file records in prose.
    # THE SECOND IS A MEASUREMENT -- `FileNotFoundError: .agents/slop/ops_bend-milestone-expected.txt`
    # is what the fixture did on 2026-10-05 -- so the quote is KEPT VERBATIM and the correction is set
    # BESIDE it, explicitly labelled a record. **A MEASUREMENT IS NOT A PATH AND MUST NOT BE REWRITTEN
    # TO LOOK LIKE A CURRENT ONE.** Rewriting it to say `.md` would have made the sentence true and the
    # evidence false.
    ('# (`.agents/slop/ops_bend-milestone-expected.txt`). No Node, no browser, no adapter,\n',
     '# (`.agents/slop/ops_bend-milestone-expected.*` -- BY STEM, NEVER BY EXTENSION: the loader resolves\n'
     '# `_EXPECTED_STEM` in `opsbend_milestone_gate.py` by discovery, so the `.txt` -> `.md` rename that\n'
     '# this pointer used to transcribe moved it once and the stage died on a `FileNotFoundError`). No Node,\n'
     '# no browser, no adapter,\n'),
    ('# artifact unable to say what it would have measured. NOT FIXED HERE, DELIBERATELY: changing what\n',
     '# artifact unable to say what it would have measured. THE `.txt` IN THAT QUOTE IS A RECORD, NOT A\n'
     '# PATH: it is the extension the fixture carried on 2026-10-05, and nothing resolves it now -- the\n'
     '# loader takes `_EXPECTED_STEM` by discovery, so this citation cannot go stale the way a live\n'
     '# pointer did. NOT FIXED HERE, DELIBERATELY: changing what\n'),
)

HELP = __doc__
# STAGE 7's OWN FILTER, `checks/e2e.sh:256`. Only these lines of `run-f64.sh`'s output reach the
# artifact; the stage's exit status is read from the command.
F64_RE = re.compile(
    rb"STAGE 7 (PASS|FAILED)|64/64 MET|IDENTICAL|port now says|REFUSED\[|RED   \[|GREEN \[|"
    rb"THEOREM \[|F64-[0-9]")

FAILS = SKIPS = 0  # THE VERDICT ACCUMULATOR. See `checks/e2e.sh:91-100`, added after a measured defect.


def say(line: str = "") -> None:
    """`echo`, and flushed: a child that inherits this fd must not overtake it."""
    print(line, flush=True)


def stage(argv: list[str], into: Path | None = None) -> int:
    """ONE STAGE'S COMMAND, and the only place a process is ever started.

    `into=None` means the shell let the child write to the gate's own stdout/stderr -- stages 1 and
    3 -- so this inherits and the interleaving with our own lines is the shell's. `into=Path` is
    `> FILE 2>&1`, so the child's whole stream is captured and printed later by `tail`/`cat`/`grep`
    exactly where the shell printed it. NEVER parallel: a second `stage()` before the first returns
    is what took this machine down on 2026-10-05, and this function makes it impossible to write.

    **A COMMAND THAT DOES NOT EXIST IS STATUS 127, NOT A TRACEBACK.** The shell runs `zsh` by name
    at stage 6 and `node` by name at stage 3; when the tool is absent `sh` prints `zsh: command not
    found` and continues, and stage 7 has a whole SKIP branch for `rc -eq 127` that is unreachable if
    the gate dies first. MEASURED by `plant-no-zsh`: the first cut raised `FileNotFoundError` out of
    stage 6, so stages 7 and 8 never ran, the summary never printed, and the gate exited 1 by
    crashing instead of by deciding. `PermissionError` is 126 for the same reason -- a non-executable
    `opsbend-milestone.sh` is a stage-5 FAIL in the shell, not a dead gate.
    """
    sys.stdout.flush()
    sys.stderr.flush()
    try:
        if into is None:
            return subprocess.run(argv, env=ENV, cwd=ROOT).returncode
        with open(into, "wb") as fh:
            return subprocess.run(argv, env=ENV, cwd=ROOT,
                                  stdout=fh, stderr=subprocess.STDOUT).returncode
    except (FileNotFoundError, PermissionError) as exc:
        # THE SHELL'S OWN COMPLAINT, IN ITS OWN WORDS, AND TO THE STREAM THE STAGE CAPTURES INTO --
        # `zsh: command not found` inside `$RUN/e2e-port-mm.out`, which stage 6 then `cat`s, exactly
        # where the shell put it. Writing it to the gate's stderr instead would be invisible in the
        # artifact the reader is shown.
        #
        # **THE LINE PREFIX IS THE SHELL'S, NOT OURS, AND IT NAMES THE SCRIPT.** `sh` reports the
        # location with its own `$0`, so the oracle's line is
        # `…/oracle-e2e.sh: line 185: zsh: command not found` and a bare `zsh: command not found`
        # diffed against it. `checks/e2e.py` has no line 185 to name, so it prints the prefix a
        # reader needs -- WHICH PROGRAM COULD NOT BE FOUND -- and the driver normalises the shell's
        # location prefix away, because the two are answering the same question with the only
        # difference being which file asked it.
        status = 127 if isinstance(exc, FileNotFoundError) else 126
        note = (f"{argv[0]}: {'command not found' if status == 127 else 'Permission denied'}\n")
        if into is None:
            sys.stderr.write(note)
            sys.stderr.flush()
        else:
            with open(into, "ab") as fh:
                fh.write(note.encode())
        return status


def raw(path: Path) -> bytes:
    """BYTES, NEVER TEXT. `cat`, `tail` and `grep` are byte-transparent, so a stage that printed one
    non-UTF-8 byte must reach the artifact unchanged; `read_text(errors="replace")` would substitute
    U+FFFD and the artifact would differ from the shell's on a byte the reader cannot see. An absent
    file reads as empty, which is what the shell's `cat` under `set -e` never got to print."""
    try:
        return path.read_bytes()
    except OSError:
        return b""


def emit(data: bytes) -> None:
    """Write to the artifact's own stdout, unbuffered against the children that inherit it."""
    sys.stdout.flush()
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def echo_file(path: Path) -> None:
    """`cat FILE`."""
    emit(raw(path))


def tail_file(path: Path, n: int) -> None:
    """`tail -n FILE`: the last `n` lines, and a last line with NO trailing newline stays that way."""
    emit(b"".join(raw(path).splitlines(keepends=True)[-n:]))


def grep_file(path: Path, rx: re.Pattern[bytes]) -> None:
    """`grep -E PATTERN FILE | sed 's/^/  /'`. Exit status is `sed`'s and is discarded, because a
    pipeline's status is its LAST command's -- one of the traps this gate's own comments name."""
    emit(b"".join(b"  " + ln + b"\n" for ln in raw(path).splitlines() if rx.search(ln)))


def verdict(name: str, rc: int) -> None:
    """`checks/e2e.sh:93`. PASS / FAIL, and FAIL is what reaches the exit status."""
    global FAILS
    if rc == 0:
        say(f"  {name}: PASS")
    else:
        say(f"  {name}: FAIL (rc={rc})")
        FAILS += 1


def skip(name: str, why: str) -> None:
    """`checks/e2e.sh:97`. THE THIRD OUTCOME. Measured nothing; not a pass."""
    global SKIPS
    say(f"  {name}: SKIP -- {why}")
    SKIPS += 1


# --------------------------------------------------------------------------- stage 2's retry
def bend_run() -> int:
    """`bend_run`, `checks/e2e.sh:51-68`. THE DENOMINATOR IS > 20 ROWS, NOT THE EXIT STATUS.

    bend stack-overflows on roughly one run in twenty and prints NOTHING, and a zero-row result is
    indistinguishable from "not started", so the run is RETRIED and the ROW COUNT is checked. This
    is the shell's `set -e` abort path: eight fruitless attempts return 2 and the gate stops there.

    `rows` STARTS EMPTY, NOT ZERO, and that is the shell's shape: it is assigned only inside the
    success branch, so a bend that FAILS on attempt 1 prints `attempt 1 produced  rows` with
    nothing between the two words. Tidy that into `0` and the artifact changes.

    THREE RETURNS, AND THE THIRD IS NOT A ROW COUNT. `0` is > 20 rows, `2` is eight fruitless
    attempts, and `127`/`126` is `./bin/bend` absent / not executable -- the status the SHELL would
    have exited with, which is why they are passed on rather than invented. `main()` reads `127`
    as SKIP, because that is what this gate already does for the identical question at stage 3 (no
    `node` on PATH) and at stage 7 (no `zsh`): a stage that measured nothing is not a stage that
    got the wrong answer, and one tool being absent is not evidence about the port.
    """
    txt, err = RUN / "e2e-mm-bend.out", RUN / "e2e-mm-bend.err"
    rows = ""
    for i in range(1, 9):
        # `> TXT 2> ERR` ARE TWO SEPARATE STREAMS, and the row count is read from the FIRST one
        # only. `stage()` has one capture, so the two redirections are spelled out here.
        #
        # **THE 127 BRANCH IS `stage()`'s, ONE FUNCTION OVER, AND IT WAS MEASURED MISSING.** The
        # sibling handles an absent command in two lines and this one raised `FileNotFoundError` out
        # of `main()`, so a tree with no `./bin/bend` produced a traceback, no verdict line and no
        # summary -- a CRASH, which is neither of this gate's five outcomes and is the defect the
        # whole SKIP column exists to prevent. `except` is INSIDE the `with`, so the two artifacts
        # are already open and `fail` can carry the complaint into the file `head -3` prints below:
        # the same words `stage()` writes, to the same stream, for the same reason.
        with open(txt, "wb") as out, open(err, "wb") as fail:
            sys.stdout.flush()
            try:
                rc = subprocess.run(["./bin/bend", ".agents/slop/e2e_mm.bend"], env=ENV, cwd=ROOT,
                                    stdout=out, stderr=fail).returncode
            except (FileNotFoundError, PermissionError) as exc:
                status = 127 if isinstance(exc, FileNotFoundError) else 126
                fail.write(f"./bin/bend: {'command not found' if status == 127 else 'Permission denied'}\n"
                           .encode())
                return status
        if rc == 0:
            rows = str(sum(1 for ln in raw(txt).splitlines() if b"=" in ln))
            if int(rows) > 20:
                say(f"bend: {rows} rows (attempt {i})")
                return 0
        # `echo ... >&2` IS AN ECHO, SO THE NEWLINE IS PART OF THE LINE AND IS NOT OPTIONAL. An
        # earlier cut wrote these without one and `plant-thin` diffed 9 stderr lines against 1.
        say_err(f"bend: attempt {i} produced {rows} rows, retrying\n".encode())
        time.sleep(1)
    say_err(b"bend: no run produced rows in 8 attempts -- SUBSTRATE OR FIXTURE, not a verdict\n")
    say_err(b"".join(raw(err).splitlines(keepends=True)[:3]))   # `head -3`, unmodified
    return 2


def say_err(s: bytes) -> None:
    """`>&2`, BYTES. The shell's `head -3 FILE >&2 2>/dev/null` applies `>&2` FIRST and
    `2>/dev/null` SECOND, so `head`'s stdout keeps the ORIGINAL stderr and only the complaint about a
    missing file is discarded; writing to stderr is the same destination. NO NEWLINE IS ADDED, and
    that is measured rather than tidy: the caller passes `b"...\\n"` for an `echo >&2` and passes
    `head`'s own lines unmodified, because a file whose last line has no newline must not gain one."""
    sys.stderr.flush()
    sys.stderr.buffer.write(s)
    sys.stderr.buffer.flush()


# --------------------------------------------------------------------------- the seven stages
def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        say(HELP)
        # THE PINS, DERIVED. The docstring deliberately does NOT transcribe how many pairs
        # `ORACLE_EDITS` holds -- it is the reader that used to be wrong about its own mechanism --
        # so the number is printed here from the tuple, and `--help` is the one command that can
        # falsify the docstring's claim that there are "exactly the edits `ORACLE_EDITS` declares".
        say(f"\nDECLARED EDITS: {len(ORACLE_EDITS)} pair(s) in `ORACLE_EDITS`, applied in order "
            f"by `revert_oracle()`")
        say(f"PINS: ORACLE_SHA {ORACLE_SHA[:16]}…  BODY_SHA {BODY_SHA[:16]}…  "
            f"revert(oracle) == checks/e2e.sh is checked by `oracle_drift()` on every run")
        return 0
    if drift := oracle_drift():
        for line in drift:
            print(f"ORACLE DRIFT: {line}", file=sys.stderr)
        print("  the frozen shell oracle moved, so this run would compare against nothing. "
              "Restore it, or re-freeze it deliberately and update ORACLE_SHA in checks/e2e.py -- "
              "do not delete the pin: it is the only thing that notices a change to "
              "`checks/e2e.sh` at all (`.agents/slop/e2esh/plant.py`).", file=sys.stderr)
        return 3
    os.chdir(ROOT)   # the shell's `cd "$(dirname "$0")/../.."`
    RUN.mkdir(parents=True, exist_ok=True)   # `mkdir -p`, under `set -e`

    say("== 1/7 oracle (CPython tinygrad, DEV=CPU)")
    if rc := stage([PY, ".agents/slop/e2e_mm.py"]):
        return rc          # `set -e`: aborts HERE, with no verdict line and no summary.

    say("== 2/7 port (pure bend, no GPU)")
    rc = bend_run()
    if rc == 127:
        # SKIP, NOT FAIL, AND NOT A CRASH. The five outcomes are PASS/FAIL/REFUSED/SKIP/DEAD and an
        # ABSENT COMPILER is SKIP, for the reason this file already skipped stage 3 and stage 7: the
        # stage measured nothing, and reporting a missing tool as a wrong answer would put "the port
        # is broken" in the exit status when nothing about the port was measured. `126` (bend present
        # and not executable) is deliberately NOT here: that is a broken install, and `set -e` stops
        # on it below, exactly as the shell stops.
        skip("stage 2 port (pure bend, no GPU)",
             "`./bin/bend` is not available; stage 2 measured NOTHING")
    elif rc:
        return rc          # `set -e`, same shape: 8 fruitless attempts stop the gate.

    say("== 3/7 gpu (real WebGPU adapter, headless Chrome)")
    if which("node"):
        verdict("stage 3 gpu (node)", stage(["node", ".agents/slop/e2e_mm_run.mjs"]))
    else:
        skip("stage 3 gpu (node)", "no `node` on PATH; stage 3 measured nothing")

    say("== 4/7 gate")
    # THE EXIT STATUS IS THE GATE'S, NOT A PIPELINE'S. `checks/e2e.sh:120-125` names the trap this
    # repo keeps paying for: `"$PY" gate.py | tee out` makes `$?` the status of `tee`, so a gate that
    # CRASHED printed `PASS`. POSIX sh has no PIPESTATUS.
    gate = RUN / "e2e-mm-gate.out"
    rc = stage([PY, ".agents/slop/e2e_mm_gate.py", str(RUN / "e2e-mm-bend.out")], gate)
    echo_file(gate)
    verdict("stage 4 gate (matmul vs CPython, via WebGPU)", rc)

    say("== 5/7 port's own device (the port's ops_bend runtime executes)")
    ops = RUN / "e2e-opsbend.out"
    rc = stage(["./.agents/slop/opsbend-milestone.sh"], ops)
    tail_file(ops, 3)      # THE DENOMINATOR: the milestone's own last three lines.
    # TODO(stage-5-denominator): `tail -3` IS THE DENOMINATOR AND IT IS ALSO WHAT A CRASH REPLACES,
    # so a stage that ran and printed NOTHING COUNTABLE leaves the artifact unable to say what it
    # would have measured. NOT FIXED HERE, DELIBERATELY, and for the same reason the shell's copy says
    # so: changing what this stage prints is a change to the artifact on BOTH sides of the porting
    # rule, and the oracle is frozen so such a change is a separate deliberate act rather than a side
    # effect of retiring stage 8. `e2estage8/verdicts.py` reports it as `DENOMINATOR None` until then.
    verdict("stage 5 ops_bend (kernel executes in Bend)", rc)

    say("== 6/7 the matmul THROUGH THE PORT (no Node, no browser, no navigator.gpu)")
    pmm = RUN / "e2e-port-mm.out"
    rc = stage(["zsh", ".agents/slop/e2e_port/run-port-mm.sh"], pmm)
    echo_file(pmm)
    verdict("stage 6 port (matmul THROUGH the port, no Node)", rc)

    say("== 7/7 the SAME kernel in f64 THROUGH THE PORT (no Node, no browser, no adapter)")
    f64 = RUN / "e2e-f64.out"
    rc = stage(["zsh", ".agents/slop/f64/run-f64.sh"], f64)
    if rc == 3:
        skip("stage 7 f64 (double through the port, no Node)",
             f"run-f64.sh refused: its substrate is cold; see {RUN}/e2e-f64.out")
    elif rc == 127:
        skip("stage 7 f64 (double through the port, no Node)",
             "`zsh` is not available; stage 7 measured NOTHING")
    else:
        grep_file(f64, F64_RE)
        verdict("stage 7 f64 (double through the port, no Node)", rc)

# ---------------------------------------------------------------------------
    # STAGE 8, THE JAVASCRIPT LANE. RETIRED, NOT RE-POINTED, BECAUSE ITS DENOMINATOR IS 0.
    # Its prose went with its code on purpose: an essay about a stage that no longer runs is how a
    # reader is told a stage exists when it does not, and the docstring is the one a reader trusts.
    # THAT DISAGREEMENT IS THE DEFECT THIS BLOCK WAS FOUND BY, and it is why the census below is
    # part of the fix rather than a report about it.
    #
    # WHAT IT WAS. `jstage.py` ran `runtime/dtype.js` through `bend -o` under node over 20 rows.
    #
    # WHY 0, IN THE STAGE'S OWN WORDS, because it printed the denominator every run and then said
    # the rest out loud:
    #     rows that REACH `dtype.js`      0
    #     rows that are pure `dtype.bend` 20   (NOT the JS lane)
    #     FAIL  the plant moved 0 rows, so this stage CANNOT fail on the bug it exists for
    # `dtype.bend` declares 0 `IO(` laws, 0 of 137+ `.bend` files import `runtime/dtype.{c,js}`,
    # and `runtime/dtype.js` is not one byte of the emitted bundle. A GATE WHOSE DENOMINATOR IS
    # ZERO IS NOT A GATE: it can never fail, so it can never pass either, and it makes the seven
    # around it look like a suite.
    #
    # WHAT REPLACES IT IS A CITATION, NOT A STAGE. `.agents/slop/lastlaw/run.py` measures the same
    # pure `dtype.bend` arithmetic at 1330/1330 (102 i64 + 1228 fp8) against the same CPython
    # callables, so stage 8's 19 rows were a 19-row echo of a 1330-row gate. Evidence:
    # `.agents/slop/deadreg/REPORT.md` §2. Re-point this stage ONLY if a `Dt.*` law becomes a seam
    # again -- the one change that would make the denominator non-zero, and the one
    # `.agents/slop/LASTLAW.md` undid. A row count is not a reason to undo it.
    #
    # THE CENSUS THAT KEEPS IT GONE IS `.agents/slop/e2estage8/verdicts.py`: it counts every
    # emitted stage's denominator out of a run's artifact and exits 1 on any stage emitted with 0,
    # and on any disagreement between the stage names in this docstring, the headers this code
    # emits, and the headers in the transcript. A retirement nobody can check is a comment.
    # ---------------------------------------------------------------------------
    # THE SUMMARY, AND THE THREE RETURNS BELOW ARE THE WHOLE OF THE VERDICT. `return 4` IS THE
    # FIX, and `4` is quoted in the docstring's exit-status table rather than derived from here, so
    # a reader who greps for `return 4` finds the claim and the prose that justifies it together.
    say(f"--- verdicts: {FAILS} failed, {SKIPS} skipped ---")
    if FAILS:
        say(f"FAIL -- {FAILS} stage(s) ran and failed. The per-stage verdicts above stand on "
            f"their own:")
        say("       a failing stage does not retract the others' claims, and this script now says "
            "so in")
        say("       its exit status, which it did not before.")
        return 1
    if SKIPS:
        say(f"PASS WITH {SKIPS} SKIP(S) -- nothing failed, but {SKIPS} stage(s) measured NOTHING.")
        say("       PASS-WITH-SKIP IS NOT PASS, AND THE EXIT STATUS SAYS SO: 4, NOT 0. Read the")
        say("       skipped lines above. A caller that only reads `$?` can no longer mistake this")
        say("       for a clean pass; that was the defect.")
        return 4
    say("PASS -- every stage ran and every stage agreed.")
    return 0


def revert_oracle(raw: str) -> str:
    """`raw` (the frozen oracle's text) with EVERY declared edit applied, in order.

    **THE ONE DEFINITION OF THE TRANSFORM, AND THE REASON IT IS A FUNCTION.** `oracle_drift()` and
    `.agents/slop/e2esh/refreeze.py` both need "the oracle as the body would have to be", and the
    second one grew its own inline loop that applied only `ORACLE_EDIT` -- so its question (2)
    answered a ninth of the delta and reported the rest as a byte difference (MEASURED 2026-10-19,
    before this commit). Two loops over one table is two witnesses with no generator between them,
    which is `checks/sweep.py`'s removed `LIVE_UNITS` one level in. `str.replace` that matches
    NOTHING is silent, so an edit that stopped being present surfaces as the hash mismatch in
    `oracle_drift()`, whose message names that possibility; there is deliberately no second "is each
    ORACLE_SIDE still there" check, because the byte identity already is that check.
    """
    for oracle_side, shell_side in ORACLE_EDITS:
        raw = raw.replace(oracle_side, shell_side)
    return raw


def oracle_drift() -> list[str]:
    """Is the frozen oracle still the thing this port was diffed against? An empty list means yes.

    THREE QUESTIONS, AND ONE HASH CANNOT ANSWER THREE. (1) Does the frozen COPY on disk hash to
    `ORACLE_SHA`? (2) Does that copy WITH ITS DOCUMENTED EDITS REVERSED hash to `BODY_SHA`, the
    shell body this port was measured on -- i.e. is every difference between them one this file names?
    (3) IF `checks/e2e.sh` is still on disk -- the live cleanup unit deleted it mid-port, see the
    pin's comment -- does it also hash to `BODY_SHA`? (3) is deliberately NOT a failure when the file
    is absent: a pin another unit is entitled to remove would report drift about a deletion, and the
    oracle already answers (1) and (2) from the one file that survives.

    (2) APPLIES EVERY PAIR IN `ORACLE_EDITS` IN ORDER, through `revert_oracle()`, which is also what
    `.agents/slop/e2esh/refreeze.py` calls -- one transform, two callers, and no second copy of the
    loop to fall behind the table.
    """
    import hashlib
    bad = []
    copy = REPO / ".agents/slop/e2epy/oracle-e2e.sh"
    if not copy.exists():
        return ["e2epy/oracle-e2e.sh: MISSING -- the frozen oracle is gone"]
    raw = copy.read_bytes()
    if hashlib.sha256(raw).hexdigest() != ORACLE_SHA:
        bad.append(f"e2epy/oracle-e2e.sh: {hashlib.sha256(raw).hexdigest()[:16]} != oracle "
                   f"{ORACLE_SHA[:16]}")
    reverted = revert_oracle(raw.decode(errors="replace")).encode()
    if hashlib.sha256(reverted).hexdigest() != BODY_SHA:
        bad.append(f"e2epy/oracle-e2e.sh: reverting its {len(ORACLE_EDITS)} documented edits gives "
                   f"{hashlib.sha256(reverted).hexdigest()[:16]}, not the shell body "
                   f"{BODY_SHA[:16]} this port was diffed against -- so the oracle carries an "
                   f"UNDOCUMENTED difference, or a declared edit changed")
    body = REPO / "checks/e2e.sh"
    if body.exists() and hashlib.sha256(body.read_bytes()).hexdigest() != BODY_SHA:
        bad.append(f"checks/e2e.sh: {hashlib.sha256(body.read_bytes()).hexdigest()[:16]} != "
                   f"{BODY_SHA[:16]} -- the live shell body no longer matches the frozen oracle")
    return bad


def which(name: str) -> str:
    """`command -v`, first match wins, empty string for none. The shell's stage-3 availability test."""
    for d in ENV.get("PATH", "").split(os.pathsep):
        if d and os.access(os.path.join(d, name), os.X_OK):
            return os.path.join(d, name)
    return ""


if __name__ == "__main__":
    sys.exit(main())