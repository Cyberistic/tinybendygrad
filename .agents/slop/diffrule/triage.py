#!/usr/bin/env python3
"""triage.py -- are (a)'s firings REAL collateral, or honest deletions?

The question a rule cannot answer for itself: rule (a) with `D` only fires on 28 of 300
commits since 2026-10-06T00:00. Is that 28 collateral incidents, or 28 honest deletions
that a rule would now refuse? The difference is a policy and a guard.

The TEST, and it is not a hand list: a deletion is COLLATERAL when the removed path is
absent from this commit's tree AND present in the tree of a commit that is NOT this commit
or its parent -- i.e. some OTHER commit had already removed and then restored it, or another
later commit restores it. That is `git log --all -- <path>` on the removal side.

Simpler and stronger: **a deletion is REPEATED if the same path is DELETED more than once in
the population.** MEASURED: `9144d179e25a` deleted `.agents/slop/unreachable/*` and
`e982d2057536` deleted it AGAIN, and `08eb1265ebef` restored it again. A path deleted twice
and restored in between was collateral the first time -- no porting unit deletes its own
work and then has it restored.

    .venv/bin/python .agents/slop/diffrule/triage.py [--since=2026-10-06T00:00]

Writes `triage.rows`, one row per (a)-firing commit.
"""
import argparse
import importlib.util
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

_spec = importlib.util.spec_from_file_location("msgdiff_gate", ROOT / "gates" / "msgdiff-gate.py")
_g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_g)
PATH = _g.PATH

SIX = {"9144d179e25a", "c83f04ad1c12", "75ab9b8f8984"}


def git(*args):
    r = subprocess.run(["git", "--no-optional-locks", "-C", str(ROOT), *args],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"triage: git {' '.join(args)}: {r.stderr.strip()[:200]}")
    return r.stdout


def named_set(msg):
    toks = set(PATH.findall(msg))
    parents = set()
    for t in toks:
        parts = t.split("/")
        for i in range(1, len(parts)):
            parents.add("/".join(parts[:i]))
    return lambda p: p in toks or any(p.startswith(pre + "/") for pre in parents)


def deleted_paths(sha):
    """Every path the commit REMOVES: `D` entries AND rename sources. `-M` is on, so a
    reverted rename reads as `R100` and its source is exactly what vanished."""
    out = []
    for line in git("diff-tree", "-r", "-M", "--no-commit-id", "--name-status", sha).splitlines():
        p = line.split("\t")
        if len(p) < 2:
            continue
        if p[0].startswith("D"):
            out.append(p[1])
        elif p[0].startswith("R") and len(p) >= 3:
            out.append(p[1])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="2026-10-06T00:00")
    a = ap.parse_args()
    shas = git("log", "--format=%H", f"--since={a.since}").split()

    # ONE git call for every commit's status, in history order. 300 commits x 2 calls was
    # MEASURED at over 120 s and timed out -- a measurement that does not finish is not a
    # measurement. `git log --name-status -M` walks every commit in one process.
    del_count = defaultdict(int)
    per = {}
    named = {}
    stream = git("log", "--format=%x00COMMIT %H", "--name-status", "-M", f"--since={a.since}")
    cur, rows_by = None, {}
    for line in stream.splitlines():
        if line.startswith("\x00COMMIT "):
            cur = line[len("\x00COMMIT "):].strip()
            rows_by[cur] = []
        elif cur and line:
            rows_by[cur].append(line)
    for sha in shas:
        msg = git("log", "-1", "--format=%B", sha)
        named[sha] = named_set(msg)
        dp = []
        for line in rows_by.get(sha, []):
            p = line.split("\t")
            if len(p) < 2:
                continue
            if p[0].startswith("D"):
                dp.append(p[1])
            elif p[0].startswith("R") and len(p) >= 3:
                dp.append(p[1])
        per[sha] = dp
        for p in dp:
            del_count[p] += 1

    rows = ["sha\ttotal_D\toutside_D\trepeated_D\tin-the-six\tverdict"]
    tot_out = tot_rep = 0
    firings = rep_firings = 0
    for sha in shas:
        dp = per[sha]
        out = [p for p in dp if not named[sha](p)]
        if not out:
            continue
        firings += 1
        rep = [p for p in out if del_count[p] > 1]
        tot_out += len(out)
        tot_rep += len(rep)
        rep_firings += 1 if rep else 0
        rows.append("\t".join([sha[:12], str(len(dp)), str(len(out)), str(len(rep)),
                               "yes" if sha[:12] in SIX else "-",
                               "REFUSED" if rep else "PASS(repeat-only)"]))
        print(f"{sha[:12]} D={len(dp):4d} outside={len(out):4d} repeated={len(rep):4d}  "
              f"{'COLLATERAL' if rep else 'single       '}  "
              f"{git('log', '-1', '--format=%s', sha)[:60]}")

    (HERE / "triage.rows").write_text("\n".join(rows) + "\n")
    n = len(shas)
    inpop = len(SIX & {s[:12] for s in shas})
    print()
    print(f"population: {n} commits, git log --since={a.since}, HEAD")
    print(f"rule (a) with D: fires on {firings} of {n} commits; "
          f"{rep_firings} of those carry a REPEATED deletion")
    print(f"unacknowledged deletions: {tot_out}; of those REPEATED: {tot_rep}")
    print(f"named incidents present in this population: {inpop} of {len(SIX)}")
    print("rows: triage.rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())