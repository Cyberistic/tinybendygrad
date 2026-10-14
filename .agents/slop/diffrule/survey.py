#!/usr/bin/env python3
"""survey.py -- how many of each commit's diff paths does its MESSAGE name?

A MEASUREMENT, not a gate. It answers the calibration question the new rule depends on:
what is the distribution of "paths the message does not name" over real history, and is
the six-commit collateral separable from ordinary porting work by that number alone?

    .venv/bin/python .agents/slop/diffrule/survey.py [--since=<date>] [--rows <file>]

Writes `<file>` (default `survey.rows`), one row per commit:
    sha  total  named  outside  D  A  R  subject-glob

`subject-glob` is the leading path component of every path the MESSAGE names, which is the
coarsest thing a message can be said to declare. It is reported so a reader can see whether
the outsides cluster under a subject or scatter.
"""
import argparse
import re  # noqa: F401 -- kept: the survey prints `re`-derived subject tokens
import subprocess
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

# msgdiff-gate.py's PATH grammar, IMPORTED FROM THE GATE -- not a second copy of the list. A
# second copy is a contract with no generator, and this file is a measurement that must agree
# with the gate it calibrates. The gate's FILENAME carries a hyphen, so it is loaded by path.
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location("msgdiff_gate", ROOT / "gates" / "msgdiff-gate.py")
_g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_g)
PATH = _g.PATH


def git(*args):
    r = subprocess.run(["git", "--no-optional-locks", "-C", str(ROOT), *args],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"survey: git {' '.join(args)}: {r.stderr.strip()[:200]}")
    return r.stdout


def subject_globs(message):
    """The set of leading path components the message NAMES. Coarse on purpose: a message
    that says `gates/tn_where.bend` declares `gates`, not that one file."""
    return {t.split("/")[0] for t in PATH.findall(message)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="2026-10-06T00:00")
    ap.add_argument("--rows", default=str(HERE / "survey.rows"))
    a = ap.parse_args()

    shas = git("log", "--format=%H", f"--since={a.since}").split()
    rows = ["sha\ttotal\tnamed\toutside\tD\tA\tR\tsubject-glob"]
    outside_fracs, outside_counts = [], []
    for sha in shas:
        msg = git("log", "-1", "--format=%B", sha)
        entries = []
        for line in git("diff-tree", "-r", "-M", "--no-commit-id", "--name-status", sha).splitlines():
            p = line.split("\t")
            if len(p) < 2:
                continue
            # `R100 old new` -- the NEW name is the path the commit leaves behind.
            entries.append((p[0], p[-1]))
        globs = subject_globs(msg)
        # A path is NAMED if the message names it exactly, OR if it lives under a component
        # the message names. The second half is the generous reading and is the one this
        # calibration measures, because the strict reading refuses a message that says
        # `gates` for editing three files in it.
        def named(path):
            if path in set(PATH.findall(msg)):
                return True
            g = path.split("/")[0]
            return g in globs or (path.count("/") and "/".join(path.split("/")[:2]) in
                                  {"/".join(t.split("/")[:2]) for t in PATH.findall(msg)})

        total = len(entries)
        out = [path for _st, path in entries if not named(path)]
        d = sum(1 for st, _ in entries if st.startswith("D"))
        ad = sum(1 for st, _ in entries if st.startswith("A"))
        r = sum(1 for st, _ in entries if st.startswith("R"))
        outside_counts.append(len(out))
        outside_fracs.append(len(out) / total if total else 0.0)
        rows.append("\t".join([sha[:12], str(total), str(total - len(out)), str(len(out)),
                               str(d), str(ad), str(r), ",".join(sorted(globs)) or "-"]))

    Path(a.rows).write_text("\n".join(rows) + "\n")
    n = len(outside_counts)
    print(f"population: {n} commits, git log --since={a.since}, HEAD")
    print(f"outside-count : min {min(outside_counts)}  median "
          f"{sorted(outside_counts)[n // 2]}  max {max(outside_counts)}")
    print(f"outside-frac  : median {sorted(outside_fracs)[n // 2]:.3f}  max {max(outside_fracs):.3f}")
    top = Counter(outside_counts).most_common(8)
    print(f"histogram of outside-count: {sorted(top)}")
    print(f"rows: {a.rows}")
    return 0


if __name__ == "__main__":
    sys.exit(main())