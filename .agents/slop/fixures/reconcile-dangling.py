#!/usr/bin/env python3
"""RECONCILE `checks/repro-paths.py`'s DANGLING COUNT AGAINST GIT.

`checks/repro-paths.py` COUNTS the paths a committed report names and that do not resolve. It does
not say WHICH of them a commit could give back, so "57 dangling" and "1 irrecoverable" are both
consistent with its output and it cannot tell a reader which is which.

A DANGLING PATH THAT `git cat-file -e <commit>:<path>` FINDS IS NOT LOST, IT IS UNRESTORED, AND THE
TWO HAVE DIFFERENT FIXES: one is `git checkout <commit> -- <path>`, the other is a report that has
to be corrected because the file was never committed.

    .venv/bin/python .agents/slop/fixures/reconcile-dangling.py --commit 371cc64c9^
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def dangling_paths(report: Path) -> list[str]:
    """The paths `repro-paths.py` printed as DANGLING, indented two spaces under the DANGLING line."""
    out, inside = [], False
    for line in report.read_text(errors="replace").splitlines():
        if line.startswith("  DANGLING"):
            inside = True
            continue
        if inside:
            if not line.startswith("    "):
                break
            if not line.startswith("    .") and not line.startswith("    checks") \
                    and not line.startswith("    gates"):
                continue
            out.append(line.strip())
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--report", default=str(HERE / "repro-before.out"),
                    help="captured checks/repro-paths.py output")
    ap.add_argument("--commit", required=True, help="the revision to test recoverability against")
    args = ap.parse_args()

    paths = dangling_paths(Path(args.report))
    recoverable, unrecoverable = [], []
    for p in paths:
        r = subprocess.run(["git", "cat-file", "-e", f"{args.commit}:{p}"],
                           cwd=ROOT, capture_output=True)
        (recoverable if r.returncode == 0 else unrecoverable).append(p)

    # ONE REVISION IS NOT THE WHOLE HISTORY. A path the pre-sweep commit does not hold may still be
    # in ANY older commit, and `git checkout <that> -- <path>` recovers it exactly as well. So the
    # honest question is not "did the commit that broke it still have it" but "was it EVER committed",
    # and a report that conflates the two calls 15 recoverable files unrecoverable.
    never = []
    for p in paths:
        r = subprocess.run(["git", "log", "--all", "--format=%H", "--", p],
                           cwd=ROOT, capture_output=True, text=True)
        if not r.stdout.split():
            never.append(p)

    n = len(paths)
    print(f"dangling: {n}")
    print(f"  recoverable from {args.commit}: {len(recoverable)}  "
          f"(`git checkout {args.commit} -- <path>` restores it)")
    print(f"  not in that commit: {len(unrecoverable)}  -- "
          f"{len(unrecoverable) - len(never)} of them ARE in an older commit and are recoverable "
          f"from it; the remaining {len(never)} were never committed")
    print(f"  NEVER COMMITTED IN ANY REVISION: {len(never)}  "
          f"-- these need a report corrected, not a checkout")
    print(f"  ratio, any revision: {n - len(never)}/{n} recoverable, {len(never)}/{n} irrecoverable")
    print("\nrecoverable from the named commit:")
    for p in recoverable:
        print(f"  {p}")
    print("\nNOT in that commit, but in an OLDER one (recoverable, just not from here):")
    for p in unrecoverable:
        if p not in never:
            print(f"  {p}")
    print("\nNEVER COMMITTED -- irrecoverable, each one needs a report corrected:")
    for p in never:
        print(f"  {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())