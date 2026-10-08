#!/usr/bin/env python3
"""RUN the gate-shaped population, sequentially, under BOTH bounds. MEASURE ONLY.

    .venv/bin/python .agents/slop/gatecensus/run.py --dry-run
    .venv/bin/python .agents/slop/gatecensus/run.py                 # every candidate
    .venv/bin/python .agents/slop/gatecensus/run.py ops-gate.sh e2e.sh   # named subset

WHY THIS FILE EXISTS AND WHAT IT REPLACES
-----------------------------------------
`census.py` already ran 925 gates at `-j 10` with NO memory bound. Its own tripwire recorded 29
files modified and 4 created under `tinybendygrad/` during those runs. That evidence is void twice
over: ten-at-a-time is the workload that filled the machine, and an instrument whose side effects it
measured only after the fact is not a measuring instrument. This file is SEQUENTIAL by construction
-- one `subprocess.run` at a time, no executor, no thread pool -- and every run is inside
`checks/bounded.py`, which is the only bound in this repo that has actually been shown to fire.

    NEVER `subprocess.run(cmd)` directly.  Every run is `bounded.py --seconds N --mb 1024 -- cmd`.

THE VERDICT RULES, AND WHY EACH IS STRICTER THAN THE EXIT STATUS
---------------------------------------------------------------
`substrate-check.sh` printed `SUBSTRATE CLEAN: 0 file(s)` with no arguments for the life of the
project. An instrument that examines nothing and reports all-clear is the failure this whole file
exists to prevent. So:

  PASS      rc==0 AND both-bound exit==0 AND output on at least one stream AND a verdict token seen
  FAIL      the gate ran and said no
  NOT-RUN   our bound fired (exit 3 memory / 4 time / 124 / 142), or ZERO bytes on both streams,
            or rc==0 with output but NO verdict token. Never reported as green.
  SKIP      the gate printed usage. Bare is a DIFFERENT instrument from "run with its population".
  UNSAFE    not run BY NAME: running it would edit a tree six units are writing into.

EXIT-CODE ARITHMETIC, STATED BECAUSE IT WAS GOT WRONG TWICE TODAY.
  `checks/bounded.py` exits 0/3/4 and PRINTS the child's own rc on its own line as `rc=N`.
  `$?` after a pipe is the LAST command's status, so `bounded.py ... | tee` does not report the
  child's rc. The rc is read from the child's own stream, never from `$?`, and the two are stored
  separately because they answer different questions: "did the bound fire" and "what did the gate say".
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
SLOP = os.path.join(ROOT, ".agents/slop")
OUT = os.path.join(SLOP, "gatecensus")
RUNS = os.path.join(OUT, "runs")
BOUNDED = os.path.join(ROOT, "checks/bounded.py")
PY = os.path.join(ROOT, ".venv/bin/python")

# Shadow trees are copies OF the repo: a directory holding its own `.agents/`. Running a gate out
# of one measures the copy, and counting the copy inflates the denominator. DETECTED BY MARKER, not
# by a list of names -- `differverdict/` has grown seven sub-trees since this file was written
# (`root`, `warm`, `pristine`, `out`, `py-D`, `shell-D`, `oracle-D`, `python-D`) and a hand-kept
# list would have silently counted the new ones as gates. `.agents/` inside the tree is the marker
# every one of them shares and it cannot appear in a real gate population.
def _shadow_dir(path: str) -> bool:
    """Is this DIRECTORY a copy of the repo? The marker is a nested `.agents/` or a checked-out
    `tinygrad/` -- a property of the directory, so it can prune the walk."""
    return (os.path.isdir(os.path.join(path, ".agents"))
            or os.path.isdir(os.path.join(path, "tinygrad")))


def _shadow(rel: str) -> bool:
    r = rel[len(".agents/slop/"):] if rel.startswith(".agents/slop/") else rel
    p = os.path.join(ROOT, ".agents/slop", r)
    return _shadow_dir(p) or _shadow_dir(os.path.dirname(p))
NEVER = ("_cleanup", "gatecensus", "__pycache__", "references")

# Gate-shaped: the NAME says this thing decides something, compares two things, or sweeps a tree.
GATESHAPED = re.compile(r"(gate|check|census|sweep|verify|audit|diff|compare|rows|prove|"
                        r"substrate|e2e|graphcmp|liveness|reach|verdict|oracle)", re.I)

# NOT RUN BY NAME. These WRITE to the port, or MUTATE a baseline to prove a mutation moves rows.
# Decided before running, because it has to be, and counted beside the attempted total -- never
# green. A name is the only thing decidable without executing, so for SAFETY this is name-based,
# deliberately, and every exclusion is listed in the log.
UNSAFE = re.compile(r"(fix|patch|hoist|emit|gen|writer|mirror|plumb|splice|rewrite|stamp|"
                    r"plant|inject|corrupt|break|repair|apply|autogen|build|stage|mut)", re.I)

ENTRY = {"substrate-check.sh", "e2e.sh", "graphcmp-run.sh", "graphcmp-repro.sh",
         "tree-verdict.py", "graphcmp.py"}

# A verdict token is a WORD that says a decision was made. `\b`-anchored on BOTH sides: an
# unbounded `FAIL` matches `FAILSAFE`, and `MATCH` matches inside `MISMATCH` and inside paths --
# which is how an unanchored list mints PASSes out of prose.
#
# WIDENED AFTER A MEASURED FALSE NEGATIVE, NOT ON THEORY. `arena-census.py` prints
#   `SAFE 172  LATENT 1061  DEFECT 0`
# and rc 0, and the original list had no token for it, so a gate that ran to completion and
# reported a three-way census came back NOT-RUN. That is the safe direction to fail in, but it is
# still a false negative in a census whose only job is to tell a green from a silence, and the
# fix is the census's own vocabulary: `DEFECT <n>` and `SAFE <n>` ARE verdicts.
VERDICT = re.compile(
    r"\b(PASS|PASSED|FAIL|FAILED|ERROR|ERR|WARM|COLD|CLEAN|DIRTY|MATCH|MISMATCH|"
    r"AGREE|DISAGREE|UNRESOLVED|UNJUDGED|OK|BAD|VERDICT|RED|GREEN|MATCHED|"
    r"SAFE|LATENT|DEFECT|DEFECTS|REGRESS|OKAY|NO-OP|NOOP|DRIFT|SKEW)\b"
    r"|\b\d+\s+rows?\b"
    r"|\b\d+\s+(?:call sites?|sites?|defs?|checks?|tests?)\b"
    r"|^\s*total\b", re.I | re.M)

# `bounded.py` prints the child's own rc. This is where it is read from, because `$?` after a pipe
# is the LAST command in the pipeline and not this one.
BOUNDED_RC = re.compile(r"^rc=(\d+)", re.M)

# EXIT 3 IS AMBIGUOUS AND THE EXIT CODE ALONE MISLEADS. `checks/bounded.py:152` ends with
#     return rc if rc else 0
# so a WITHIN-LIMITS run whose CHILD exited 3 leaves bounded.py exiting 3 -- byte-identical to the
# KILLED-ON-MEMORY return at line 147. MEASURED HERE: `substrate-check.sh` refuses an empty
# population with exit 3 and peak-RSS 2 MB, i.e. it is a refusal, and the bound never fired.
# A runner that reads `exit == 3` as "killed on memory" therefore reports a GATE THAT CORRECTLY
# REFUSED as a machine that almost died, and -- the direction that matters -- cannot tell the two
# apart at all. The verdict TOKEN is the only thing that distinguishes them, so the token is
# parsed and the exit code is recorded beside it, never substituted for it.
BOUNDED_VERDICT = re.compile(r"^\[bounded\]\s+(WITHIN-LIMITS|KILLED-ON-MEMORY|TIMED-OUT)"
                             r"\s+rc=(-?\d+)\s+peak-RSS=(\d+)\s+MB", re.M)


def candidates(only: list[str] | None = None) -> list[str]:
    out = []
    for dirpath, dirs, files in os.walk(SLOP):
        # PRUNE THE SHADOW TREES AT THE WALK, not per-file. Marking a file shadow and then
        # `continue`-ing it still pays for reading and stat-ing every one of the ~4,600 scripts
        # inside them, and -- the bug this replaced -- a per-file test on the FILE cannot see a
        # shadow tree, because the marker (`.agents/`, `tinygrad/`) is a property of the DIRECTORY.
        dirs[:] = [d for d in dirs if d not in NEVER and not _shadow_dir(os.path.join(SLOP, d))
                   and not _shadow_dir(os.path.join(dirpath, d))]
        for name in sorted(files):
            if not name.endswith((".sh", ".py")):
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), ROOT)
            if _shadow(rel):
                continue
            # Gate-shaped BY NAME, not "or executable". An executable with no gate in its name is a
            # one-shot instrument from a finished unit (`bend_fix.py`, `afloat-patch.py`,
            # `ag-order.py`) and running it measures nothing that a report does not already record.
            # Widening the population to "everything executable" is what made the earlier attempt
            # 527 rows and 11 hours, and it is the same error as moving probes into `checks/`.
            if not GATESHAPED.search(name):
                continue
            out.append(rel)
    out.sort()
    if only:
        want = set(only)
        out = [r for r in out if r.rsplit("/", 1)[-1] in want]
    return out


def env() -> dict:
    # `env -u PYTHONPATH`: a PYTHONPATH pointing at another checkout makes a row about THIS tree
    # out of a library that is not this tree. The venv is verified to resolve to this repo's
    # tinygrad in README.md; a `.venv` copied out of the tree points at the ORIGINAL.
    return {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {"NO_COLOR": "1"}


def command_for(rel: str) -> tuple[list[str], str]:
    """A `.sh` gate's shebang may be `#!/bin/zsh` while `sh -n` fails on it -- that cost a unit
    its own verification. So: executable `.sh` runs AS AN EXECUTABLE (the kernel honours the
    shebang), a non-executable `.sh` goes through `zsh`, and `.py` goes through the venv.
    Recorded per row as `how`, so no reader has to guess."""
    path = os.path.join(ROOT, rel)
    base = rel.rsplit("/", 1)[-1]
    if base.endswith(".sh"):
        if os.access(path, os.X_OK):
            return [os.path.join(".", rel)], "./x (shebang honoured)"
        return ["zsh", path], "zsh (no exec bit)"
    return [PY, path], "venv-py"


# THE TWO-PASS LEASH, AND WHY 458 SEQUENTIAL RUNS FINISH IN AN HOUR INSTEAD OF ELEVEN.
# A gate that finishes in 3 seconds pays 3 seconds whatever the leash is; the leash only decides how
# long a HANG is allowed to hold the single slot. So pass 1 runs everything at a short leash, and
# pass 2 re-runs ONLY the rows pass 1 could not resolve, at a long leash. Sequential either way --
# there is exactly one live gate at a time in this file, and that is the property that keeps two
# `bend` processes from filling the machine. A NOT-RUN that survives pass 2 is reported NOT-RUN.
PASS1 = 25
PASS2 = 180


def leash(rel: str, long: bool = False) -> int:
    base = rel.rsplit("/", 1)[-1]
    if long:
        return 600 if base in ENTRY else PASS2
    return 300 if base in ENTRY else PASS1


def run_one(rel: str, mb: int = 1024, long: bool = False) -> dict:
    secs = leash(rel, long)
    inner, how = command_for(rel)
    cmd = [PY, BOUNDED, "--seconds", str(secs), "--mb", str(mb), "--"] + inner
    t0 = time.time()
    p = subprocess.run(cmd, cwd=ROOT, env=env(), capture_output=True, text=True,
                       errors="replace", timeout=secs + 45)
    wall = round(time.time() - t0, 2)
    blob = p.stdout + "\n" + p.stderr
    bv = BOUNDED_VERDICT.search(blob)
    if bv:
        bound, child_rc, peak = bv.group(1), int(bv.group(2)), int(bv.group(3))
    else:
        bound, child_rc, peak = "NO-BOUNDED-LINE", None, -1
    row = {"rel": rel, "how": how, "leash_s": secs, "mb": mb, "wall_s": wall,
           "bounded_exit": p.returncode, "bound": bound, "child_rc": child_rc,
           "peak_mb": peak, "stdout": p.stdout, "stderr": p.stderr}

    # THE BOUND, read from the token. Nothing below this line may consult the exit code to decide
    # whether a bound fired.
    if bound == "KILLED-ON-MEMORY":
        row.update(status="NOT-RUN", verdict="",
                   why=f"KILLED ON MEMORY at {mb}MB ceiling, peak {peak}MB")
        return row
    if bound == "TIMED-OUT":
        row.update(status="NOT-RUN", verdict="", why=f"TIMED OUT at {secs}s")
        return row
    if bound == "NO-BOUNDED-LINE":
        row.update(status="NOT-RUN", verdict="",
                   why="bounded.py produced no verdict line -- the bound is unproven")
        return row
    if p.returncode == 5:
        row.update(status="NOT-RUN", verdict="", why="bounded.py could not start the child")
        return row

    # Within both bounds. Now the child's own output decides.
    # THE BODY IS THE CHILD'S OUTPUT, VERBATIM, AND IT IS THE ONLY OUTPUT.
    # `bounded.py` runs the child with `stdout=PIPE, stderr=STDOUT`, so the child's streams are
    # already interleaved into what it prints; everything before its own summary line is the gate.
    # NOT its stderr and NOT `$?`. An earlier version of this file classified on the child's rc and
    # kept no text, which is how 425 rows came back FAIL with **no quoted reason at all** -- 404 of
    # them could not even name what they were failing on. A red you cannot quote is not a finding.
    body = blob[:bv.start()] if bv else blob
    if not body.strip():
        row.update(status="NOT-RUN", verdict="", why="ZERO bytes on both streams -- a refusal")
        return row
    line = first_verdict(body)
    row["verdict"] = line
    # A usage/refusal line is checked BEFORE the rc, because a gate that prints usage and exits
    # non-zero is not red -- it refused to run without its population.
    if re.search(r"^\s*usage\b|^\s*\S+:\s+usage|\busage:\s|^usage:|^\s*REFUSED", body, re.I | re.M):
        row.update(status="SKIP", verdict="",
                   why="printed usage/REFUSED; bare is a different instrument")
        return row
    if child_rc == 127:
        row.update(status="NOT-RUN", verdict="", why="rc=127 -- the command was not found")
        return row
    if child_rc not in (0, None):
        row.update(status="FAIL", why=f"child rc={child_rc} within both bounds")
        return row
    if line:
        row.update(status="PASS", why="rc=0 under both bounds, output present, verdict token seen")
        return row
    row.update(status="NOT-RUN", verdict="", why="rc=0 with output but NO verdict token")
    return row


# THE CAUSE LINE. A python traceback's last line names the defect; a bend error names the symbol.
# Capturing the LAST line of a traceback rather than the first verdict token is the difference
# between a red you can act on and a red you have to re-run by hand.
CAUSE_LINE = re.compile(
    r"^(?:\w*Error|\w*Exception|RuntimeError|AssertionError|SystemError)\b"
    r"|^expected\s*:.*observed\s*:"
    r"|\bundefined symbol\b|\bNo such file\b|\bnot found\b"
    r"|^bend:|^Duplicate declaration", re.I)


def first_verdict(text: str) -> str:
    """The most informative single line. A traceback's cause beats a verdict token: `PASS 0 rows`
    appears in a traceback that is about to die, and quoting it would report a green."""
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    for s in reversed(lines):
        if CAUSE_LINE.search(s) and not re.match(r"^\[bounded\]", s):
            return s[:180]
    for s in lines:
        if VERDICT.search(s) and not re.match(r"^(peak|rc=|elapsed|max |\[bounded\])", s, re.I):
            return s[:180]
    return ""


def main() -> int:
    only = [a for a in sys.argv[1:] if not a.startswith("-")]
    mb = int(next((a.split("=")[1] for a in sys.argv if a.startswith("--mb=")), 1024))
    cands = candidates(only or None)
    os.makedirs(RUNS, exist_ok=True)

    unsafe = [r for r in cands if UNSAFE.search(r.rsplit("/", 1)[-1].rsplit(".", 1)[0])]
    safe = [r for r in cands if r not in unsafe]

    print(f"# DENOMINATOR  gate-shaped BY NAME, outside shadow trees        {len(cands)}")
    print(f"#   excluded BY NAME (would write the port / plant a mutation) {len(unsafe)}")
    print(f"#   ATTEMPTED, SEQUENTIALLY, each under --seconds+--mb          {len(safe)}")
    print(f"#   bounds: {mb}MB, leash {leash('x.sh')}s default / 300s for the 6 entry points")
    if "--dry-run" in sys.argv:
        for r in unsafe:
            print(f"  UNSAFE  {r}")
        for r in safe:
            print(f"  run     {r}  [{command_for(r)[1]}, {leash(r)}s]")
        return 0

    rows: list[dict] = []
    t0 = time.time()
    for i, rel in enumerate(safe, 1):
        try:
            row = run_one(rel, mb, long=False)
        except Exception as e:                       # a gate that cannot be exec'd is NOT-RUN
            row = {"rel": rel, "status": "NOT-RUN", "why": f"harness error: {e}",
                   "verdict": "", "child_rc": None, "bounded_exit": None}
        rows.append(row)
        print(f"[p1 {i:4d}/{len(safe)}] {row['status']:8s} {row.get('bound','')[:13]:13s} "
              f"rc={str(row.get('child_rc')):>4s} {row.get('wall_s', 0):7.1f}s  {rel}\n"
              f"               :: {(row.get('verdict') or row.get('why',''))[:150]}", flush=True)

    # PASS 2. Only what pass 1 could not resolve, at the long leash. A SKIP is RESOLVED -- the gate
    # told us it needs arguments -- so it is not re-run. Only NOT-RUN is, because NOT-RUN is a
    # statement about the leash, and the only way to improve on it is a longer leash.
    stuck = [r["rel"] for r in rows if r["status"] == "NOT-RUN"]
    print(f"\n# PASS 2: {len(stuck)} NOT-RUN row(s) re-run at {PASS2}s/{mb}MB, still one at a time")
    for i, rel in enumerate(stuck, 1):
        try:
            row = run_one(rel, mb, long=True)
        except Exception as e:
            row = {"rel": rel, "status": "NOT-RUN", "why": f"harness error: {e}",
                   "verdict": "", "child_rc": None, "bounded_exit": None}
        row["pass"] = 2
        rows[next(k for k, r in enumerate(rows) if r["rel"] == rel)] = row
        print(f"[p2 {i:4d}/{len(stuck)}] {row['status']:8s} {row.get('bound','')[:13]:13s} "
              f"rc={str(row.get('child_rc')):>4s} {row.get('wall_s', 0):7.1f}s  {rel}\n"
              f"               :: {(row.get('verdict') or row.get('why',''))[:150]}", flush=True)

    tally: dict[str, int] = {}
    for r in rows:
        tally[r["status"]] = tally.get(r["status"], 0) + 1
    notrun = tally.get("NOT-RUN", 0)
    print(f"\n# VERDICTS over {len(rows)} ATTEMPTED  ({time.time()-t0:.0f}s wall)")
    for k, v in sorted(tally.items(), key=lambda kv: -kv[1]):
        print(f"#   {k:8s} {v:4d} / {len(rows)}")
    print(f"#   PASS {tally.get('PASS',0)}   NOT-RUN {notrun}   "
          f"UNSAFE(excluded) {len(unsafe)}   DENOMINATOR {len(cands)}")
    print(f"#   I COULD NOT RUN {notrun + len(unsafe)} of {len(cands)}. Every one of them is a "
          f"NOT-RUN or an exclusion. None is green.")

    json.dump({"denominator": len(cands), "attempted": len(safe), "unsafe": unsafe,
               "rows": rows, "tally": tally, "bounds_mb": mb},
              open(os.path.join(OUT, "results.json"), "w"), indent=1)
    for r in rows:
        json.dump(r, open(os.path.join(RUNS, r["rel"].replace("/", "%") + ".json"), "w"), indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())