#!/usr/bin/env python3
"""Plant and disarm for the fifth verdict. Nothing here touches a production file.

    usage: .venv/bin/python .agents/slop/unknowns/plant-unknown.py            # expect exit 0
           .venv/bin/python .agents/slop/unknowns/plant-unknown.py --disarm NAME
           NAME in commit-or-drop, commit-the-report, belts, residue-internal-citer

THE EXPECTATIONS ARE LITERALS. Nothing computes them, and the temp tree is built fresh and `rmtree`d
by the context manager, because one repro in this project read `LEFT=NOTHING` ON BOTH SIDES -- it
destroyed the state under test between beats.

THE TEMP TREE IS `git init`ed AND COMMITTED, not just `git add`ed, because two of the four resolvers
read git rather than the filesystem: `tracked_files()` runs `git ls-files` and the citation corpus is
read with `git show HEAD:`. An uncommitted tree would make both resolvers silently vacuous and the
plant would pass on a stand-in that shares the production assumptions -- the exact failure this
project has already paid for twice.

A DISARM REMOVES THE EVIDENCE A RESOLVER READS AND REQUIRES THE ROW TO MOVE. It is not a flag in
`verdict_for`, because a flag is test scaffolding in the load-bearing classifier and a scaffolding
hook is a second way for the production path to be wrong. Disarming by mutating the INPUT proves the
stronger thing: the verdict depends on the measurement, not on the code path happening to run.

    UNKNOWN IN, ONCE PER PATH. `tool/no-report.py` is a TOOL whose directory has no committed report;
    `explained/probe.py` is the SAME ROW WITH THE REPORT COMMITTED, and it is `DELETE`. One flag
    separates them, and the flag is a fact about the tree rather than about the classifier -- which is
    the property `LIVE_UNITS` and `PROTECTED` do not have.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
import time
import importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SWEEP = os.path.join(ROOT, "checks/sweep.py")

# The corpus: ONE committed report outside the residue, and ONE committed report inside it. The
# second exists because a citation from inside the residue is not a citation (`NAMED_BY`'s
# `:(glob).agents/slop/*.md` puts it there, which is how this project's own reports name their files).
CORPUS_OUT = "checks/report.md"
CORPUS_IN = ".agents/slop/NOTES.md"

# (relpath, content, expected verdict). The expectation is the WHOLE verdict, tag included, so a row
# cannot pass by landing in `UNKNOWN` for the wrong reason.
CASES = [
    (CORPUS_OUT, "kept by the outside corpus: keep/kept.rows mm-*-gate.sh\n", "-"),
    (CORPUS_IN, "named only from inside the residue: onlyres/named.py\n", "-"),
    ("runs/keep/kept.rows", "a\n1\n", "ORACLE"),
    ("runs/graphcmp/D/ARTIFACT.txt", "rendered by an authority\n", "AUTHORED"),
    (".agents/slop/w/gate.sh", "#!/bin/sh\n", "UNKNOWN:belts-disagree"),
    (".agents/slop/onlyres/named.py", "print(1)\n", "UNKNOWN:residue-internal-citer"),
    (".agents/slop/tool/no-report.py", "print(1)\n", "UNKNOWN:commit-the-report-that-explains-it"),
    (".agents/slop/explained/REPORT.md", "what explained/probe.py is for\n", "DOC"),
    (".agents/slop/explained/probe.py", "print(1)\n", "DELETE"),
]

# The row each resolver decides, and what that row becomes once the resolver cannot see its evidence.
DISARMS = {
    "commit-or-drop": (".agents/slop/new/out.tsv", "UNKNOWN:commit-or-drop", "DELETE"),
    "commit-the-report": (".agents/slop/tool/no-report.py",
                          "UNKNOWN:commit-the-report-that-explains-it", "DELETE"),
    "belts": (".agents/slop/w/gate.sh", "UNKNOWN:belts-disagree", "KEEP-CITED"),
    "residue-internal-citer": (".agents/slop/onlyres/named.py",
                               "UNKNOWN:residue-internal-citer", "KEEP-CITED"),
}


def sweep_module():
    spec = importlib.util.spec_from_file_location("sweep_plant", SWEEP)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def git(tmp: str, *args: str) -> None:
    subprocess.run(["git", *args], cwd=tmp, capture_output=True, text=True, check=True)


def build(tmp: str, sweep) -> list[tuple[str, str, str]]:
    """The temp tree, with the AUTHORED row named by the REAL `differ.declared()`.

    The authority is imported, not stood in for: if `differ.declared()` cannot be asked, the plant
    FAILS rather than passing on a name it made up, because a carve-out that cannot be computed must
    never become a blanket exemption.
    """
    declared = sorted(sweep.declared_names())
    if not declared:
        raise SystemExit("plant: `differ.declared()` is empty -- the AUTHORED row cannot be planted")
    cases = [(p, c, e) for p, c, e in CASES]
    # `runs/graphcmp/D/<rendered name>` is the shape the real artifacts have.
    cases = [(p.replace("ARTIFACT.txt", os.path.basename(declared[0])),
              c, e) for p, c, e in cases]
    cases.append((".agents/slop/new/out.tsv", "a\tb\n", "UNKNOWN:commit-or-drop"))
    for rel, content, _e in cases:
        p = os.path.join(tmp, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as fh:
            fh.write(content)
    git(tmp, "init", "-q")
    git(tmp, "add", "-A")
    git(tmp, "-c", "user.email=plant@example.invalid", "-c", "user.name=plant",
        "commit", "-q", "-m", "plant")
    git(tmp, "rm", "-q", "--cached", ".agents/slop/new/out.tsv")
    # 30 days old, so nothing here can pass by being inside a liveness window.
    ts = time.time() - 30 * 86400
    for dirpath, _dn, fn in os.walk(tmp):
        for n in fn:
            if n != ".git":
                os.utime(os.path.join(dirpath, n), (ts, ts))
    return cases


def classify(tmp: str, sweep, cases) -> dict[str, str]:
    """Run `checks/sweep.py`'s own `verdict_for` against the temp tree, with ROOT repointed.

    ONLY `ROOT` MOVES. `declared_names()` reads `CHECKS`, so the AUTHORED row is decided by the real
    differ's real declaration -- a plant that renamed the authority would be planting the harness.
    """
    real_root, real_facts = sweep.ROOT, sweep.facts
    try:
        sweep.ROOT = tmp
        sweep.facts.cache_clear()
        f = sweep.facts()
        # `tag()` EXISTED AND WAS NEVER CALLED, SO THE PLANT COMPARED THE WHOLE SENTENCE AGAINST A
        # SHORT VERDICT AND WENT RED ON **ALL FOUR** ROWS -- A PLANT THAT CANNOT GO GREEN IS NOT A
        # PLANT. THE DOCSTRING AT `tag()` SAYS WHY THE PROSE MUST NOT BE ASSERTED; THE CALL THAT HONOURS
        # IT WAS MISSING.
        return {rel: tag(sweep.verdict_for(rel, f.mentioned, f)) for rel, _c, _e in cases}
    finally:
        sweep.ROOT, sweep.facts = real_root, real_facts
        sweep.facts.cache_clear()


def tag(verdict: str) -> str:
    """The machine-readable half: `UNKNOWN:belts-disagree (prose)` -> `UNKNOWN:belts-disagree`.

    The parenthetical is evidence FOR A HUMAN and is deliberately not asserted, because the tag is the
    part a caller can act on. **AN EXPECTATION THAT CHECKS A SENTENCE CHECKS THE AUTHOR'S MOOD.**
    """
    return verdict.split(" (")[0]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--disarm", metavar="NAME", choices=sorted(DISARMS))
    args = ap.parse_args()

    sweep = sweep_module()
    with tempfile.TemporaryDirectory() as tmp:
        cases = build(tmp, sweep)
        bad = []
        for rel, _c, expect in cases:
            if expect == "-":
                continue
            got = classify(tmp, sweep, cases)[rel]
            if got != expect:
                bad.append(f"    {rel}: want {expect!r}, got {got!r}")

        disarmed, moved = None, False
        if args.disarm:
            disarmed, armed_verdict, disarmed_verdict = DISARMS[args.disarm]
            if args.disarm == "commit-or-drop":
                git(tmp, "add", ".agents/slop/new/out.tsv")
            elif args.disarm == "commit-the-report":
                p = os.path.join(tmp, ".agents/slop/tool/REPORT.md")
                with open(p, "w") as fh:
                    fh.write("what tool/no-report.py was for\n")
                git(tmp, "add", "-A")
                git(tmp, "-c", "user.email=plant@example.invalid", "-c", "user.name=plant",
                    "commit", "-q", "-m", "the report")
            elif args.disarm == "belts":
                p = os.path.join(tmp, CORPUS_OUT)
                with open(p, "w") as fh:
                    fh.write("kept by the outside corpus: keep/kept.rows gate.sh\n")
                git(tmp, "add", "-A")
                git(tmp, "-c", "user.email=plant@example.invalid", "-c", "user.name=plant",
                    "commit", "-q", "-m", "a name both tokenizers can see")
            elif args.disarm == "residue-internal-citer":
                p = os.path.join(tmp, CORPUS_OUT)
                with open(p, "a") as fh:
                    fh.write("and from outside: .agents/slop/onlyres/named.py\n")
                git(tmp, "add", "-A")
                git(tmp, "-c", "user.email=plant@example.invalid", "-c", "user.name=plant",
                    "commit", "-q", "-m", "a citer outside the residue")
            got = classify(tmp, sweep, cases)[disarmed]
            moved = got != armed_verdict
            print(f"# disarmed {args.disarm}: {disarmed} was {armed_verdict!r}, now {got!r}"
                  f" (want {disarmed_verdict!r})")
            if got != disarmed_verdict:
                bad.append(f"    disarmed {disarmed}: want {disarmed_verdict!r}, got {got!r}")

        print(f"# plant: {'armed' if not args.disarm else 'disarmed ' + args.disarm}: "
              f"{'FAIL' if bad else 'PASS'}")
        for b in bad:
            print(b)
        if args.disarm and not moved:
            print("# THE ROW DID NOT MOVE. A resolver that cannot move a row is not being computed, and\n"
                  "# this harness would rather say that than report a confident wrong answer.")
            return 3
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
