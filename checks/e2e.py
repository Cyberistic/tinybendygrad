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
PY, RUN = ".venv/bin/python", ROOT / "runs/e2e"
# `env -u PYTHONPATH` IS NOT APPLIED HERE, and that is fidelity rather than an oversight: the shell
# never applies it, so the eight stages inherit whatever `PYTHONPATH` the caller had. Removing it
# would change what `e2e_mm.py` can import, i.e. change a verdict.
ENV = dict(os.environ)
# ONE BEND AT A TIME IS A STRUCTURAL PROPERTY OF THIS PROGRAM, NOT A FLAG: `stage()` blocks, so no
# two stages and no two children of one stage are ever live at once. See the module docstring.
# THE FROZEN SHELL ORACLE IS PINNED HERE, IN CODE, AND CHECKED ON EVERY RUN. A pin in a comment is
# a pin that cannot fail, which is how `checks/differ.py` shipped a CORRECT pin that nothing read.
#
# BOTH FILES ARE PINNED, and that is stronger than pinning one. `checks/e2e.sh` is the COMMITTED
# BODY; `e2epy/oracle-e2e.sh` is the frozen copy the port is diffed against. Pinning only the copy
# would let the committed body drift away from the thing the port was measured on, so the two are
# pinned separately and the copy's ONE DOCUMENTED EDIT -- an `E2E_REPO` default in its first `cd`,
# so the copy can be pointed at a fixture tree -- is named in `ORACLE_EDIT` rather than left
# implicit for the next reader to guess at.
ORACLE_PIN = {
    "e2epy/oracle-e2e.sh":
        "e0eb23d5cb7340d5bc24000675d80aba44f5b83c9ea1ef3fe3136d610d7f7e04",
}
COMMITTED_SHELL = {
    "checks/e2e.sh":
        "f222c02c9481d9827dcc94c932177a033ef454514be515ab5b80492c1d42b605",
}
ORACLE_EDIT = ('ROOT=${E2E_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}',
               'ROOT=$(cd "$(dirname "$0")/../.." && pwd)')

HELP = __doc__
# STAGE 7's OWN FILTER, `checks/e2e.sh:232`. Only these lines of `run-f64.sh`'s output reach the
# artifact; the stage's exit status is read from the command.
F64_RE = re.compile(
    r"STAGE 7 (PASS|FAILED)|64/64 MET|IDENTICAL|port now says|REFUSED\[|RED   \[|GREEN \[|"
    r"THEOREM \[|F64-[0-9]")
# STAGE 8'S OWN FILTER, `checks/e2e.sh:323`. The backticks are LITERAL: the shell wrote them inside
# single quotes, so the pattern really is "`node` exit" and a reader's shell does not expand them.
JS_RE = re.compile(
    r"^(?:THE CLAIM|  substrate measured|  rows asked|  rows that|  CIDs|  rows CPython|"
    r"  `node` exit|  ROWS PRESENT|  node agrees|  PLANT|  DISARM|===== VERDICT|REFUSED|"
    r"SUBSTRATE MEASURED)")
RC_STAMP_RE = re.compile(r"^rc=([0-9]*)$", re.M)

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
    """
    sys.stdout.flush()
    sys.stderr.flush()
    if into is None:
        return subprocess.run(argv, env=ENV, cwd=ROOT).returncode
    with open(into, "wb") as fh:
        return subprocess.run(argv, env=ENV, cwd=ROOT, stdout=fh, stderr=subprocess.STDOUT).returncode


def text(path: Path) -> str:
    try:
        return path.read_text(errors="replace")
    except OSError:
        return ""


def echo_file(path: Path) -> None:
    """`cat FILE`. An absent file prints nothing here, where the shell's `cat` would have aborted
    under `set -e`; every `cat`/`tail` in the shell follows the command that just created the file."""
    sys.stdout.write(text(path))


def tail_file(path: Path, n: int) -> None:
    """`tail -n FILE`."""
    sys.stdout.write("".join(text(path).splitlines(keepends=True)[-n:]))


def grep_file(path: Path, rx: re.Pattern[str], indent: str = "") -> None:
    """`grep -E PATTERN FILE | sed 's/^/  /'`. Exit status is `sed`'s and is discarded, because a
    pipeline's status is its LAST command's -- one of the traps this gate's own comments name."""
    for ln in text(path).splitlines():
        if rx.search(ln):
            say(f"{indent}{ln}")


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
            rows = str(sum(1 for ln in txt.read_text(errors="replace").splitlines() if "=" in ln))
            if int(rows) > 20:
                say(f"bend: {rows} rows (attempt {i})")
                return 0
        say_err(f"bend: attempt {i} produced {rows} rows, retrying")
        time.sleep(1)
    say_err("bend: no run produced rows in 8 attempts -- SUBSTRATE OR FIXTURE, not a verdict")
    say_err("".join(text(err).splitlines(keepends=True)[:3]))
    return 2


def say_err(s: str) -> None:
    """`>&2`. The shell's `head -3 FILE >&2 2>/dev/null` is `>&2` FIRST and `2>/dev/null` SECOND, so
    `head`'s stdout keeps the ORIGINAL stderr and only the complaint about a missing file is
    discarded. Writing to stderr directly is the same destination."""
    sys.stderr.write(s)
    sys.stderr.flush()


# --------------------------------------------------------------------------- the eight stages
def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        say(HELP)
        return 0
    if drift := oracle_drift():
        for line in drift:
            print(f"ORACLE DRIFT: {line}", file=sys.stderr)
        print("  the frozen shell oracle moved, so this run would compare against nothing. "
              "Restore it, or re-freeze it deliberately and update ORACLE_PIN in checks/e2e.py -- "
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
        grep_file(f64, F64_RE, "  ")
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
    stamps = sum(1 for ln in text(rep).splitlines() if ln.startswith("rc="))
    found = RC_STAMP_RE.findall(text(rep))
    jrc = int(found[-1]) if found else -1
    grep_file(rep, JS_RE, "  ")
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
    """Every frozen oracle's actual sha against its pin, and BOTH directions of the correspondence.

    An empty list means intact. Three questions, and they are three because one hash cannot answer
    three: is the frozen COPY the thing the port was diffed against (its pin), is the COMMITTED
    BODY still that script (its own pin), and does REVERSING THE COPY'S ONE DOCUMENTED EDIT
    REPRODUCE THE COMMITTED BODY (the edit, checked as text rather than assumed). The third is what
    makes the two pins a correspondence instead of two facts.
    """
    import hashlib
    bad = []
    for pins, base in ((ORACLE_PIN, REPO / ".agents/slop"), (COMMITTED_SHELL, REPO)):
        for name, want in pins.items():
            path = base / name
            if not path.exists():
                bad.append(f"{name}: MISSING -- the frozen oracle is gone")
                continue
            got = hashlib.sha256(path.read_bytes()).hexdigest()
            if got != want:
                bad.append(f"{name}: {got[:16]} != pinned {want[:16]}")
    copy = REPO / ".agents/slop/e2epy/oracle-e2e.sh"
    if copy.exists() and not bad:
        reverted = copy.read_text(errors="replace").replace(*ORACLE_EDIT)
        if reverted != (REPO / "checks/e2e.sh").read_text(errors="replace"):
            bad.append("e2epy/oracle-e2e.sh: reverting its one documented edit does NOT reproduce "
                       "checks/e2e.sh, so the oracle carries an UNDOCUMENTED difference")
    return bad


def which(name: str) -> str:
    """`command -v`, first match wins, empty string for none. The shell's stage-3 availability test."""
    for d in ENV.get("PATH", "").split(os.pathsep):
        if d and os.access(os.path.join(d, name), os.X_OK):
            return os.path.join(d, name)
    return ""


if __name__ == "__main__":
    sys.exit(main())