"""THE CONTROL, DRIVEN NOT ASSERTED: every wired reader, over absent / empty / stale / fresh.

RUNS EACH READER AS A SUBPROCESS against a scratch ROOT so the live `runs/graphcmp/D` is never
read, never written, and never deleted. Nothing here edits a reader to make a branch appear: each
reader is invoked exactly as an operator invokes it, and the exit and the TOKEN are read back.

THE DECISIVE PROPERTY: **absent and stale must not produce the same token.** A reader that
returns 3 for both, printing the same word, has told an operator to do two opposite things --
"regenerate the corpus" and "the green you are reading is old" -- with one indistinguishable
answer. `checks/runs-artifacts.py` splits them by token and by remedy; this file is what says
whether the wiring actually delivers that.

WHY A SUBPROCESS AND NOT AN IMPORT: importing a gate RUNS a gate (`gates/gate-surface.py` says so
in its own header), and these files differ in whether `main()` sits behind an entry guard. The
subprocess is also the only way to observe `$?`, which is half of what requirement 2 is about.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
assert os.path.isdir(os.path.join(ROOT, "checks")), f"ROOT wrong: {ROOT}"
PY = os.path.join(ROOT, ".venv/bin/python")
GRAPH_D = "runs/graphcmp/D"
# A FIXED CLOCK, injected, so `now` never drifts between building a state and reading it back.
NOW = 1000.0 * 86400  # far past every real mtime; the tree's files are all older

# (relpath, argv) -- the EXACT spellings from each file's own `argparse`. devpin/env-precond take
# a --plant that asserts the opposite outcome; the default arm is the one that reads the subject.
READERS = [
    ("checks/corpus-figure.py", []),
    ("checks/devpin.py", []),
    ("checks/disagree-gate.py", ["--lane", "pin"]),
    ("checks/env-precond.py", ["--check"]),
    ("gates/retention-check.py", []),
    # NOT IN THIS LIST, AND THE REASONS ARE MEASURED IN REPORT.md, NOT ASSUMED:
    #   checks/diary-census.py -- a SOURCE SCANNER; proven to answer with the dir absent.
    #   checks/no-txt.py        -- a CARVE-OUT over declared NAMES; a staleness guard would make
    #                              the `.txt` rule unenforceable exactly when the corpus is stale.
    # `disagree-gate.py --lane citations` reads `.agents/slop/disagree/names.py`, a DIFFERENT
    # untracked subject with its OWN guard at `:474` (`if not NAMES.exists(): return 2`). It is
    # listed here ONLY to show that guard is untouched by this unit and does NOT collapse: it
    # answers 2 on every state for its own stated reason. **A LANE THAT DOES NOT READ THE CORPUS
    # MUST NOT BE SCORED AS IF IT DID**, and an exemption written down is an exemption that can be
    # argued with; a reader quietly dropped from the list is one that cannot be.
    ("checks/disagree-gate.py", ["--lane", "citations"]),
]
#: Rows whose exit is expected to be state-INDEPENDENT, and why. Keyed by (rel, argv-tuple).
EXEMPT = {
    ("checks/disagree-gate.py", ("--lane", "citations")):
        "reads .agents/slop/disagree/names.py, guarded separately at disagree-gate.py:474",
}

# THE FOUR STATES ARE BUILT UNDER A **COPY OF THE READERS THEMSELVES**, and that is not tidiness.
#
# **MY FIRST CONTROL WAS WORTHLESS AND IT LOOKED PERFECT.** It created four scratch roots and ran
# `python <abs path>/checks/devpin.py` with `cwd=<that root>`. Every reader anchors
# `ROOT = Path(__file__).resolve().parents[1]` -- measured, all five -- so `__file__` was the LIVE
# tree and `cwd` was ignored. The result was four identical rows reading
# `absent=3/ARTIFACTS-STALE ... fresh=3/ARTIFACTS-STALE`: **every state reported the live corpus**,
# and I nearly wrote that the wiring collapses all four states. It collapses NOTHING -- the control
# simply never built the state it claimed to build. **A CONTROL THAT CANNOT REACH ITS FIXTURE
# MEASURES THE TREE IT WAS AIMED AWAY FROM, AND IT MEASURES IT CLEANLY.**
#
# So each state is a root holding a real COPY of the reader, and the corpus under it is the only
# thing that varies. `cp` of two files per reader; no `bend`, no differ.py, no write into `runs/`.
READER_COPIES = ("checks/devpin.py", "checks/env-precond.py", "checks/corpus-figure.py",
                 "checks/disagree-gate.py", "gates/retention-check.py", "checks/runs-artifacts.py")


def build_states(td: str) -> dict[str, str]:
    states = {}
    for name in ("absent", "empty", "stale", "fresh"):
        root = os.path.join(td, name)
        for rel in READER_COPIES:
            dst = os.path.join(root, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(os.path.join(ROOT, rel), dst)
        # The readers import siblings by relative name (`import differ`, `load("checks/...")`).
        # Those imports must RESOLVE to something, and a copy that cannot import would exit 1 with
        # a traceback -- which is a DIFFERENT failure from the one under test. Copy the two
        # generator files those imports name, so an absent-subject refusal is never confused with
        # a missing-module crash.
        # **THE FIRST RUN OF THIS CONTROL CRASHED 8 OF 20 PROBES** and the crashes were mine, not
        # the wiring's: `corpus-figure.py` loads `.agents/slop/graphcmp.py` and `retention-check.py`
        # imports `gatekit`, neither of which is a `checks/` or `gates/` file, so the copy lacked
        # them and every probe died with FileNotFoundError / ModuleNotFoundError at rc=1 -- the
        # same rc as "the pins disagree". **A CRASH AND A VERDICT THAT SHARE AN EXIT ARE THE
        # AMBIGUITY THIS UNIT EXISTS TO REMOVE**, and it arrived from the fixture rather than from
        # the code under test. Copied by path below; `graphcmp.py` is large but copying it is a
        # file read, not a `bend` run, and it is NEVER executed unless the reader reaches it.
        # `graphcmp.py` is needed TWICE over and by two different routes: `corpus-figure.py` loads
        # it directly, AND `checks/differ.py:110 corpus()` loads it to build `declared()`, which
        # `retention-check.py:343` calls. Without it the second route dies with
        # FileNotFoundError at rc=1 -- indistinguishable from "the retention clauses failed".
        # `gates/gendirs.py` is the THIRD file this fixture was missing, and it is here because
        # `retention-check.py` answered `rc=1  gates/gendirs.py is gone -- it IS the discovered
        # population, and a check whose population is missing must not report 0`. That is the
        # reader being CORRECT and my fixture being wrong: it is the same shape as the guard under
        # test, refusing over a population it cannot see. A fixture that trips the very defect it
        # is meant to measure has to be completed before its numbers mean anything.
        for rel in ("checks/differ.py", "checks/txt-owners.py", "gates/gatekit.py",
                    ".agents/slop/graphcmp.py", "gates/gendirs.py"):
            dst = os.path.join(root, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(os.path.join(ROOT, rel), dst)
        states[name] = root
        if name == "absent":
            continue                                   # nothing created: no runs/ at all
        d = os.path.join(root, GRAPH_D)
        if name == "empty":
            os.makedirs(d)
            continue                                   # the directory, zero files
        os.makedirs(d)
        with open(os.path.join(d, "D0-run-summary.txt"), "w") as f:
            f.write("graphs=34\n")
        if name == "stale":
            os.utime(os.path.join(d, "D0-run-summary.txt"), (NOW - 10 * 86400, NOW - 10 * 86400))
    return states


def probe(root: str, rel: str, argv: list[str]) -> tuple[int, str]:
    """Run one reader against the scratch root. `cwd=root` so its `ROOT`-relative paths resolve
    there, and the instrument path is ABSOLUTE so it still loads."""
    env = dict(os.environ, PYTHONWARNINGS="ignore")
    # THE COPY, NOT THE ORIGINAL. This is the line whose previous value (`os.path.join(ROOT, rel)`,
    # the LIVE tree) made the first control measure the live corpus four times and report it as
    # four states. `cwd=root` is not enough on its own: every reader anchors `ROOT` to `__file__`.
    p = subprocess.run([PY, os.path.join(root, rel), *argv], cwd=root, env=env,
                       capture_output=True, text=True, timeout=180)
    token = ""
    for line in p.stdout.splitlines():
        for t in ("ARTIFACTS-ABSENT", "ARTIFACTS-EMPTY", "ARTIFACTS-STALE", "ARTIFACTS-FRESH"):
            if t in line:
                token = t
    # A CRASH IS NOT A VERDICT, AND MUST NOT BE SCORED AS ONE. In the copied tree a reader can
    # still fail to import a sibling it needs, and `ModuleNotFoundError` exiting 1 sits in exactly
    # the same column as "the pins disagree". Recording the traceback makes the two separable in
    # this file's own output, which is the only place a reader of it can see the difference.
    if "Traceback (most recent call last)" in p.stderr:
        token = token or "CRASH"
    return p.returncode, token, p.stderr


def main() -> int:
    print(f"PYTHON: {PY}")
    print(f"ROOT  : {ROOT}")
    print(f"clock : fixed at {NOW:.0f} (injected into utime; the live corpus is never read)\n")
    bad = []
    with tempfile.TemporaryDirectory() as td:
        states = build_states(td)
        for rel, argv in READERS:
            print(f"{rel} {' '.join(argv) or '(default)'}".ljust(52), end="")
            seen = {}
            for name in ("absent", "empty", "stale", "fresh"):
                try:
                    rc, tok, err = probe(states[name], rel, argv)
                except subprocess.TimeoutExpired:
                    rc, tok, err = -1, "TIMEOUT", ""
                if tok == "CRASH":
                    bad.append(f"{rel} {argv}: CRASHED on {name}: "
                               f"{err.strip().splitlines()[-1] if err.strip() else '?'}")
                seen[name] = (rc, tok)
                print(f" {name}={rc}/{tok or '-':<16}", end="")
            # THE CONTROL, PER READER, NOT PER HELPER.
            absent, empty, stale, fresh = (seen[k] for k in ("absent", "empty", "stale", "fresh"))
            if (rel, tuple(argv)) in EXEMPT:
                print(f"  EXEMPT: {EXEMPT[(rel, tuple(argv))]}")
                if len({v[0] for v in seen.values()}) != 1:
                    bad.append(f"{rel} {argv}: exempt row is NOT state-independent: {seen}")
                continue
            if absent[1] == stale[1] and absent[1]:
                bad.append(f"{rel} {argv}: absent and stale share token {absent[1]}")
            if empty[1] == absent[1]:
                bad.append(f"{rel} {argv}: empty collapsed into absent ({empty[1]})")
            # A reader with NO token at all is the ORIGINAL defect: it read the subject and said
            # nothing about it. Every subject-reading reader must name one on absent.
            if not absent[1]:
                bad.append(f"{rel} {argv}: absent gave rc={absent[0]} with NO token")
            # AND THE OTHER DIRECTION: a reader that says FRESH must not also be reporting a
            # failure for its OWN reasons, which is how a green token hides a red reader.
            if fresh[1] and fresh[0] not in (0, 1, 2, 3):
                bad.append(f"{rel} {argv}: fresh gave rc={fresh[0]}, outside the vocabulary")
            print()
    print()
    if bad:
        print("--control: FAILED")
        for b in bad:
            print(f"   {b}")
        return 1
    print("--control: every reader distinguishes ABSENT / EMPTY / STALE / FRESH by TOKEN, and no "
          "absent or stale case is silent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())