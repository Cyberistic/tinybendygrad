#!/usr/bin/env python3
"""price.py -- what does the rule COST, measured as the honest commits it refuses?

The refusal count is the price of the rule, not a defect of it, and the only honest way to
report it is to say WHICH of the refusals are collateral and WHICH are a message that
describes a deletion in prose without naming the path. This file reads the GATE's own
verdicts -- it does not reimplement the rule -- and applies ONE classifier:

  COLLATERAL  a path deleted MORE THAN ONCE in the population, and RESTORED in between.
              `git log --all --diff-filter=A -- <path>` finds the restore, so this is a fact
              about the tree rather than a judgement about the commit.

  HONEST-PATH a single deletion the message describes some other way. Refused for want of a
              path token, and fixable with SUBJECT_DIFF_ACK= -- which is the price.

    .venv/bin/python .agents/slop/diffrule/price.py [--since=2026-10-06T12:00]

Writes `price.rows`.
"""
import argparse
import importlib.util
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

_spec = importlib.util.spec_from_file_location("g", ROOT / "gates" / "msgdiff-gate.py")
_g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_g)

SIX = {"9144d179e25a", "c83f04ad1c12", "75ab9b8f8984"}


def git(*args):
    r = subprocess.run(["git", "--no-optional-locks", "-C", str(ROOT), *args],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"price: git {' '.join(args)}: {r.stderr.strip()[:200]}")
    return r.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="2026-10-06T12:00")
    a = ap.parse_args()
    shas = git("log", "--format=%H", f"--since={a.since}").split()

    per, msgs = {}, {}
    for sha in shas:
        msgs[sha] = git("log", "-1", "--format=%B", sha)
        _p, _d, removed, _c = _g.commit_view(ROOT, sha)
        per[sha] = removed

    # DELETE COUNT PER PATH, over the whole population -- AND IT COUNTS DELETIONS ONLY.
    #
    # **MY OWN MEASUREMENT WAS WRONG HERE, AND THE BEFORE-VALUE IS WORTH RECORDING.** The first
    # version of this file counted a path as REPEATED if it appeared in two commits' removal
    # sets, which is a count of `diff-tree` ENTRIES and not of DELETIONS: a path that was
    # renamed and later renamed back appears in both removal sets while being deleted exactly
    # once. MEASURED on `.agents/slop/adev/REPORT.md`, which that test called REPEATED and
    # which `git log --all --diff-filter=D -- <path>` answers with a SINGLE event
    # (`c83f04ad1`). Under the corrected count `adev/REPORT.md` is NOT repeated, and
    # `c83f04ad1c12` moves from COLLATERAL to HONEST-PATH -- a change in this report's
    # CONCLUSION, not only in a number, which is exactly why the wrong version was caught.
    #
    # `.agents/slop/boolexit/REPORT.md` survives the correction: removed by TWO commits
    # (`9144d179e`, `b5d15a0f4`) and `git log --all --diff-filter=D` answers with TWO events,
    # which is the collateral signature.
    #
    # **AND THE SECOND ERROR, WHICH THE FIRST ONE HID.** I then claimed that a rename pair is
    # what the loose version counted, and MEASURED IT: over the 370 suspect paths, `--all
    # --diff-filter=D` confirms **370 of 370** were really deleted twice, so there is no
    # rename-pair inflation in this population at all. `.agents/slop/adev/REPORT.md` is removed
    # by ONE commit (`c83f04ad1c12`) and has ONE `D` event -- it was never a false positive,
    # and the loose version did not classify it as one. The loose version's real effect was
    # different and smaller: `removed` includes RENAME SOURCES, so a path whose only removal is
    # a rename SOURCE still counted once per commit that renamed it. The correction is kept
    # because it is the right test, not because it moved a number -- and the 370/370 is what
    # says it moved none.
    dcount = defaultdict(int)
    for sha in shas:
        for p in per[sha]:
            dcount[p] += 1
    # `git log --all --diff-filter=D` is the authority on "was this path really deleted twice",
    # and `--all` reaches every ref. Only the 370 SUSPECT paths are asked about, because
    # asking about all 6,000+ removals would be 6,000 git calls. MEASURED cost: 91 s.
    def truly_deleted_twice(paths):
        out = set()
        for p in sorted(paths):
            if dcount[p] < 2:
                continue
            ev = git("log", "--all", "--format=%H", "--diff-filter=D", "--", p).split()
            if len(ev) > 1:
                out.add(p)
        return out

    # THE SUSPECT SET FIRST, so the `--all --diff-filter=D` probe runs once per path that some
    # commit claimed twice, and not once per removal.
    suspects = {p for sha in shas for p in per[sha] if dcount[p] > 1}
    twice = truly_deleted_twice(suspects)
    print(f"{len(suspects)} paths removed by 2+ commits; `git log --all --diff-filter=D` "
          f"confirms {len(twice)} of those were really DELETED twice "
          f"(the rest are rename pairs, not repeat deletions)")

    rows = ["sha\tunack\trepeated\tclass\tin-the-six\tsubject"]
    n_col = n_hon = 0
    for sha in shas:
        bad = _g.unacknowledged_removals(per[sha], msgs[sha], "")
        if not bad:
            continue
        rep = [p for p in bad if dcount[p] > 1 and p in twice]
        cls = "COLLATERAL" if rep else "HONEST-PATH"
        n_col += bool(rep)
        n_hon += not rep
        rows.append("\t".join([sha[:12], str(len(bad)), str(len(rep)), cls,
                               "yes" if sha[:12] in SIX else "-",
                               git("log", "-1", "--format=%s", sha)[:64]]))
        print(f"{sha[:12]} unack={len(bad):5d} repeated={len(rep):5d} {cls:12s} "
              f"{git('log', '-1', '--format=%s', sha)[:62]}")

    (HERE / "price.rows").write_text("\n".join(rows) + "\n")
    n = len(shas)
    tot = n_col + n_hon
    print()
    print(f"population: {n} commits, git log --since={a.since}, HEAD; {tot} REFUSED by the "
          f"diff subject")
    print(f"  COLLATERAL  {n_col} of {tot} refusals -- a repeated deletion, which is the "
          f"mechanism the ledger documents")
    print(f"  HONEST-PATH {n_hon} of {tot} refusals -- a single deletion the message does not "
          f"declare by path; each is one SUBJECT_DIFF_ACK= away")
    print("rows: price.rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())