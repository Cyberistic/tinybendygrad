#!/usr/bin/env python3
"""THE EIGHT-STAGE END-TO-END GATE. The Python successor of `checks/e2e.sh`.

`.venv/bin/python checks/e2e.py --help` says what it gates and each verdict's DENOMINATOR.
`.agents/slop/e2e.sh` is a short `exec` shim, and the shell's body is frozen at
`.agents/slop/e2epy/oracle-e2e.sh` as the ORACLE this port is diffed against, because the rule this
project wrote for itself is that the Python reproduces the shell's verdict on EVERY INPUT or it does
not move. That oracle is BYTE-IDENTICAL to `checks/e2e.sh` -- sha256 in `ORACLE_PIN`, checked IN
CODE on every run, refusing with exit 3 on drift. A pin in a comment is a pin that cannot fail, and
`checks/differ.py` measured that lesson the hard way.

WHAT IT GATES, IN ORDER, AND THE ORDER IS THE ORDER THE CLAIMS COME IN:

  1  oracle      `e2e_mm.py` traces a real `(A @ B) @ C` out of CPython tinygrad on DEV=CPU,
                 takes tinygrad's own WGSL for each of the two launches, and writes
                 `runs/e2e/e2e-mm-oracle.json` plus the `.bend` that will be run.
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
                 elementwise add over three f32 scalars, PACKET.out compared against
                 `ops_bend-milestone-expected.txt`, which was written down BEFORE any run.
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
                 `renderer/cstyle.bend:2984-3015` calls `rd_row` for exactly seven dtypes -- f32,
                 f16, bf16, bool, u8, fp8e4m3, i32 -- so all 227 rows are silent about `double*`.
                 **EXIT 3 FROM `run-f64.sh` IS A VERDICT, NOT A FAILURE TO REPRODUCE:** it refuses
                 without running a lane when its substrate is cold, and refusing is a third
                 outcome alongside PASS and FAIL. So is rc 127: no `zsh`, nothing measured.
  8  js lane     `jstage.py` runs `runtime/dtype.js` through `bend -o` under node.
                 DENOMINATOR, and this is the whole of the claim: **20 rows asked, of which 12 REACH
                 `dtype.js` and 8 are pure `dtype.bend`, and 19 of the 20 are ones CPython can
                 answer.** `ceildiv(x, 0)` answers 0 in both lanes where CPython raises, so that row
                 counts `diverge` and is in NEITHER pass nor fail. The gate derives the 12/8 split from
                 the substrate's own declarations on every run, so a tree that moves back is counted
                 correctly without an edit here. RED AND NOT MINE: the unit that owns it measured
                 the true denominator as **0** and the stage's own answer is that it should be
                 RETIRED rather than re-pointed.
                 rc 3 is REFUSAL (its substrate would not compile) and is SKIP, never PASS.

THE THREE OUTCOMES, NOT TWO. `PASS` / `FAIL` / `SKIP`, and `SKIP IS NOT PASS`: a stage that could
not run has measured nothing, and reporting that as a pass is the same defect one level up. The
summary says so and then still EXITS 0 for PASS-with-SKIP, because a passing stage does not retract
the others' claims -- a stage that RAN and FAILED is what makes the gate exit 1.

ONE `bend` PROCESS AT A TIME, ALWAYS, AND THE SHELL HAS NO CONCERN ABOUT IT. Measured 2026-10-05:
`ulimit` appears ZERO times in `e2e.sh`, and two `bend` processes took this machine's memory to
zero (`PEAKRSS.md`: 1,152 MB + 1,108 MB). The shell runs every stage strictly sequentially -- no `&`,
no `wait`, no `xargs -P`, in this file or in any of the four stage scripts it calls -- and so does
this port, stage for stage in the same order. **NO MEMORY BOUND IS ADDED HERE, and that is a
deliberate refusal, not an oversight:** routing a stage through `checks/bounded.py` would report a
kill as exit 3 or a timeout as exit 4, and stage 7 READS 3 AS A VERDICT. A bound that changes a
verdict is a change to the artifact, and the migration rule is fidelity. The gap is reported by
`.agents/slop/e2epy/report.md` instead.

EXIT STATUS, exactly the shell's: 0 PASS, 0 PASS-with-SKIP, 1 one or more stages RAN and FAILED,
and the two statuses the shell reaches by ABORTING under `set -e` -- stage 1's own status if
`e2e_mm.py` fails, and 2 if eight bend attempts produced no rows. 3 is this file's own addition:
the frozen oracle moved, so there is nothing to be a port of.

ARGUMENTS: THE SHELL READS NONE, AND NEITHER DOES THIS, EXCEPT `-h`/`--help`. `e2e.sh foo bar baz`
runs all eight stages and ignores every word, so `checks/e2e.py foo bar baz` does the same rather
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
# second one. `E2E_ROOT` points the eight stages at a FIXTURE tree so every branch is reachable
# without a compiler, a browser or a GPU; a pin resolved against `ROOT` would then look for the
# oracle inside the fixture and report DRIFT on a tree that is perfectly intact -- which is the
# first run of this driver's answer, and it refused to compare anything at all.
REPO = Path(__file__).resolve().parents[1]
# `$PY` IS ABSOLUTE, like the shell's `PY="$ROOT/.venv/bin/python"`. It does not change any status,
# but it makes each stage's ARGV byte-identical to the shell's, and a stage that prints its own
# arguments -- `jsstage.py` prints the substrate path it measured -- is then diffable on argv alone.
PY, RUN = str(ROOT / ".venv/bin/python"), ROOT / "runs/e2e"
# `env -u PYTHONPATH` IS NOT APPLIED HERE, and that is fidelity rather than an oversight: the shell
# never applies it, so the eight stages inherit whatever `PYTHONPATH` the caller had. Removing it
# would change what `e2e_mm.py` can import, i.e. change a verdict.
ENV = dict(os.environ)
# ONE BEND AT A TIME IS A STRUCTURAL PROPERTY OF THIS PROGRAM, NOT A FLAG: `stage()` blocks, so no
# two stages and no two children of one stage are ever live at once. See the module docstring.
# THE FROZEN SHELL ORACLE IS PINNED HERE, IN CODE, AND CHECKED ON EVERY RUN. A pin in a comment is
# a pin that cannot fail, which is how `checks/differ.py` shipped a CORRECT pin that nothing read.
#
# TWO HASHES, AND THE SECOND ONE IS THE POINT. `ORACLE_SHA` is the frozen copy the port is diffed
# against. `BODY_SHA` is the shell body that copy was frozen FROM, and it is checked against the copy
# WITH ITS ONE DOCUMENTED EDIT REVERSED -- so the correspondence is proved from the ONE FILE THAT
# SURVIVES rather than from a second file that must also survive.
#
# MEASURED 2026-10-05, AND IT IS WHY: the live cleanup unit `qmyqvmnpsloz` ("THE POLICY IS PYTHON
# ONLY ... 103 ONE-OFF `.sh` DELETED") DELETED `checks/e2e.sh` from the working tree WHILE THIS PORT
# WAS BEING WRITTEN, minutes after it had been read and copied. `checks/e2e.sh` is checked as well,
# but ONLY IF IT IS STILL THERE: a pin on a file another unit is entitled to delete becomes a gate
# reporting drift about a deletion instead of about a change. THE ORACLE IS THE SURVIVOR, which is
# the entire reason the migration rule freezes one.
ORACLE_SHA = "e0eb23d5cb7340d5bc24000675d80aba44f5b83c9ea1ef3fe3136d610d7f7e04"
BODY_SHA = "f222c02c9481d9827dcc94c932177a033ef454514be515ab5b80492c1d42b605"
ORACLE_EDIT = ('ROOT=${E2E_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}',
               'ROOT=$(cd "$(dirname "$0")/../.." && pwd)')

HELP = __doc__
# STAGE 7's OWN FILTER, `checks/e2e.sh:232`. Only these lines of `run-f64.sh`'s output reach the
# artifact; the stage's exit status is read from the command.
F64_RE = re.compile(
    rb"STAGE 7 (PASS|FAILED)|64/64 MET|IDENTICAL|port now says|REFUSED\[|RED   \[|GREEN \[|"
    rb"THEOREM \[|F64-[0-9]")
# STAGE 8'S OWN FILTER, `checks/e2e.sh:323`. The backticks are LITERAL: the shell wrote them inside
# single quotes, so the pattern really is "`node` exit" and a reader's shell does not expand them.
JS_RE = re.compile(
    rb"^(?:THE CLAIM|  substrate measured|  rows asked|  rows that|  CIDs|  rows CPython|"
    rb"  `node` exit|  ROWS PRESENT|  node agrees|  PLANT|  DISARM|===== VERDICT|REFUSED|"
    rb"SUBSTRATE MEASURED)")
RC_STAMP_RE = re.compile(rb"^rc=([0-9]*)$", re.M)

FAILS = SKIPS = 0  # THE VERDICT ACCUMULATOR. See `checks/e2e.sh:75-83`, added after a measured defect.


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
        # `zsh: command not found` inside `$RUN/e2e-port-mm.txt`, which stage 6 then `cat`s, exactly
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
    """`checks/e2e.sh:77`. PASS / FAIL, and FAIL is what reaches the exit status."""
    global FAILS
    if rc == 0:
        say(f"  {name}: PASS")
    else:
        say(f"  {name}: FAIL (rc={rc})")
        FAILS += 1


def skip(name: str, why: str) -> None:
    """`checks/e2e.sh:81`. THE THIRD OUTCOME. Measured nothing; not a pass."""
    global SKIPS
    say(f"  {name}: SKIP -- {why}")
    SKIPS += 1


# --------------------------------------------------------------------------- stage 2's retry
def bend_run() -> int:
    """`bend_run`, `checks/e2e.sh:39-56`. THE DENOMINATOR IS > 20 ROWS, NOT THE EXIT STATUS.

    bend stack-overflows on roughly one run in twenty and prints NOTHING, and a zero-row result is
    indistinguishable from "not started", so the run is RETRIED and the ROW COUNT is checked. This
    is the shell's `set -e` abort path: eight fruitless attempts return 2 and the gate stops there.

    `rows` STARTS EMPTY, NOT ZERO, and that is the shell's shape: it is assigned only inside the
    success branch, so a bend that FAILS on attempt 1 prints `attempt 1 produced  rows` with
    nothing between the two words. Tidy that into `0` and the artifact changes.
    """
    txt, err = RUN / "e2e-mm-bend.txt", RUN / "e2e-mm-bend.err"
    rows = ""
    for i in range(1, 9):
        # `> TXT 2> ERR` ARE TWO SEPARATE STREAMS, and the row count is read from the FIRST one
        # only. `stage()` has one capture, so the two redirections are spelled out here.
        with open(txt, "wb") as out, open(err, "wb") as fail:
            sys.stdout.flush()
            rc = subprocess.run(["./bin/bend", ".agents/slop/e2e_mm.bend"], env=ENV, cwd=ROOT,
                                stdout=out, stderr=fail).returncode
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


# --------------------------------------------------------------------------- the eight stages
def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        say(HELP)
        return 0
    if drift := oracle_drift():
        for line in drift:
            print(f"ORACLE DRIFT: {line}", file=sys.stderr)
        print("  the frozen shell oracle moved, so this run would compare against nothing. "
              "Restore it, or re-freeze it deliberately and update ORACLE_SHA in checks/e2e.py -- "
              "do not delete the pin.", file=sys.stderr)
        return 3
    os.chdir(ROOT)   # the shell's `cd "$(dirname "$0")/../.."`
    RUN.mkdir(parents=True, exist_ok=True)   # `mkdir -p`, under `set -e`

    say("== 1/4 oracle (CPython tinygrad, DEV=CPU)")
    if rc := stage([PY, ".agents/slop/e2e_mm.py"]):
        return rc          # `set -e`: aborts HERE, with no verdict line and no summary.

    say("== 2/4 port (pure bend, no GPU)")
    if rc := bend_run():
        return rc          # `set -e`, same shape: 8 fruitless attempts stop the gate.

    say("== 3/4 gpu (real WebGPU adapter, headless Chrome)")
    if which("node"):
        verdict("stage 3 gpu (node)", stage(["node", ".agents/slop/e2e_mm_run.mjs"]))
    else:
        skip("stage 3 gpu (node)", "no `node` on PATH; stage 3 measured nothing")

    say("== 4/4 gate")
    # THE EXIT STATUS IS THE GATE'S, NOT A PIPELINE'S. `checks/e2e.sh:104-112` names the trap this
    # repo keeps paying for: `"$PY" gate.py | tee out` makes `$?` the status of `tee`, so a gate that
    # CRASHED printed `PASS`. POSIX sh has no PIPESTATUS.
    gate = RUN / "e2e-mm-gate.txt"
    rc = stage([PY, ".agents/slop/e2e_mm_gate.py", str(RUN / "e2e-mm-bend.txt")], gate)
    echo_file(gate)
    verdict("stage 4 gate (matmul vs CPython, via WebGPU)", rc)

    say("== 5/5 port's own device (the port's ops_bend runtime executes)")
    ops = RUN / "e2e-opsbend.txt"
    rc = stage(["./.agents/slop/opsbend-milestone.sh"], ops)
    tail_file(ops, 3)      # THE DENOMINATOR: the milestone's own last three lines.
    verdict("stage 5 ops_bend (kernel executes in Bend)", rc)

    say("== 6/6 the matmul THROUGH THE PORT (no Node, no browser, no navigator.gpu)")
    pmm = RUN / "e2e-port-mm.txt"
    rc = stage(["zsh", ".agents/slop/e2e_port/run-port-mm.sh"], pmm)
    echo_file(pmm)
    verdict("stage 6 port (matmul THROUGH the port, no Node)", rc)

    say("== 7/7 the SAME kernel in f64 THROUGH THE PORT (no Node, no browser, no adapter)")
    f64 = RUN / "e2e-f64.txt"
    rc = stage(["zsh", ".agents/slop/f64/run-f64.sh"], f64)
    if rc == 3:
        skip("stage 7 f64 (double through the port, no Node)",
             f"run-f64.sh refused: its substrate is cold; see {RUN}/e2e-f64.txt")
    elif rc == 127:
        skip("stage 7 f64 (double through the port, no Node)",
             "`zsh` is not available; stage 7 measured NOTHING")
    else:
        grep_file(f64, F64_RE)
        verdict("stage 7 f64 (double through the port, no Node)", rc)

    say("== 8/8 the JS dtype LANE under node (bend -o emits JS; node is what runs it)")
    # ONE TEMP, ONE WRITE, ONE ATOMIC MOVE (`checks/e2e.sh:309-313`). The version that appended
    # `rc=$?` to the SAME file the child had just written left a window between the two, and a run
    # killed in it produced a report MISSING its last line and with no `rc=` stamp -- which the
    # stability step then reported as a reproducibility difference.
    tmp, rep = RUN / ".tmp.e2e-jsstage.txt", RUN / "e2e-jsstage.txt"
    tmp.unlink(missing_ok=True)
    jrc = stage([PY, ".agents/slop/jstage/jsstage.py"], tmp)
    with open(tmp, "a") as fh:
        fh.write(f"rc={jrc}\n")
    try:
        os.replace(tmp, rep)
        jsrc = 0
    except OSError:
        jsrc = 1
    # `jsrc` IS `mv`'s AND THE GATE'S STATUS IS THE LAST `rc=` LINE. It is read with `sed` and not
    # with a pipeline, for the same reason stage 4 does not pipe its gate into `tee`.
    # `grep -c '^rc='` COUNTS LINES, NOT OCCURRENCES, so a report containing `rc=` mid-line does not
    # satisfy it. `: "${jsstage_rc:=-1}"` IS AN EMPTY-STRING TEST: no stamp at all is `-1`, and a
    # stamp that is not a number never reaches here because the `sed` did not match it.
    body = raw(rep)
    stamps = sum(1 for ln in body.splitlines() if ln.startswith(b"rc="))
    found = RC_STAMP_RE.findall(body)
    jrc = int(found[-1]) if found else -1
    grep_file(rep, JS_RE)
    if jsrc != 0 or stamps != 1:
        # THE STAGE ITSELF DID NOT RUN. Nothing measured, so SKIP and not FAIL -- but not PASS
        # either, and it says which of the two went wrong.
        skip("stage 8 js lane (node on runtime/dtype.js)",
             f"the gate did not complete: mv rc={jsrc}, rc= stamps={stamps} (want 1/1); "
             f"see {RUN}/e2e-jsstage.txt")
    elif jrc == 3:
        skip("stage 8 js lane (node on runtime/dtype.js)",
             f"jsstage.py REFUSED (rc 3): its substrate would not compile; "
             f"see {RUN}/e2e-jsstage.txt")
    else:
        verdict("stage 8 js lane (node on runtime/dtype.js, 20 rows vs CPython)", jrc)

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
        say("       PASS-WITH-SKIP IS NOT PASS. Read the skipped lines above.")
        return 0
    say("PASS -- every stage ran and every stage agreed.")
    return 0


def oracle_drift() -> list[str]:
    """Is the frozen oracle still the thing this port was diffed against? An empty list means yes.

    THREE QUESTIONS, AND ONE HASH CANNOT ANSWER THREE. (1) Does the frozen COPY on disk hash to
    `ORACLE_SHA`? (2) Does that copy WITH ITS ONE DOCUMENTED EDIT REVERSED hash to `BODY_SHA`, the
    shell body this port was measured on -- i.e. is the edit still the ONLY difference? (3) IF
    `checks/e2e.sh` is still on disk -- the live cleanup unit deleted it mid-port, see the pin's
    comment -- does it also hash to `BODY_SHA`? (3) is deliberately NOT a failure when the file is
    absent: a pin another unit is entitled to remove would report drift about a deletion, and the
    oracle already answers (1) and (2) from the one file that survives.
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
    reverted = raw.decode(errors="replace").replace(*ORACLE_EDIT).encode()
    if hashlib.sha256(reverted).hexdigest() != BODY_SHA:
        bad.append(f"e2epy/oracle-e2e.sh: reverting its one documented edit gives "
                   f"{hashlib.sha256(reverted).hexdigest()[:16]}, not the shell body "
                   f"{BODY_SHA[:16]} this port was diffed against -- so the oracle carries an "
                   f"UNDOCUMENTED difference, or its edit changed")
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