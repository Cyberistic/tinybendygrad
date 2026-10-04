#!/usr/bin/env python3
"""Does a COMMITTED report cite a path INSIDE a shadow tree? Strictly, as a PATH TOKEN.

The classifier's own docstring records that it was wrong twice here:

  * a BARE-BASENAME match reported 3,574 citations, 138 of them copies of one
    __init__.bend -- one mention of a word "cites" every shadow copy of it;
  * a BARE-SUBSTRING match reported 6 citers for a zero-byte .err and 89 for a file
    named `bend`, because `str.endswith`-style containment matches inside longer words.

A shadow tree is exactly where both failures are worst: it holds hundreds of copies of the
same basename, so a basename test over-cites by orders of magnitude, and it holds an upstream
tinygrad whose script names (`dev`, `run`, `setup`, `serve`, `fetch`, `install`, `train`) are
ordinary English substrings of sentences in prose.

So a citation here is: the tree's own path prefix, followed by a path separator, appearing in
the report text. That is a TOKEN test. Two weaker tests are computed alongside purely to
REPRODUCE the over-citation on this real data, and their counts are printed so the difference
is visible rather than asserted:

  TOKEN     "xd1/cur/tinygrad/"  -- the tree prefix plus a separator. The verdict.
  SUBSTR    "xd1/cur/tinygrad"   -- no separator. Over-counts (prose, longer paths).
  BASENAME  "render.py"          -- over-counts catastrophically in a shadow tree.

Reads reports from `git show HEAD:<name>`, so an uncommitted or untracked report cites nothing.

    usage: citations.py TREE [TREE ...]
"""
from __future__ import annotations
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))


def committed_reports() -> list[tuple[str, str]]:
    """[(name, text)] for every COMMITTED .md anywhere in the repo, via HEAD."""
    names = subprocess.run(["git", "ls-files", "*.md"], cwd=ROOT,
                           capture_output=True, text=True).stdout.split()
    out = []
    for nm in names:
        r = subprocess.run(["git", "show", f"HEAD:{nm}"], cwd=ROOT,
                           capture_output=True, text=True, errors="replace")
        if r.returncode == 0:
            out.append((nm, r.stdout))
    return out


def main(argv: list[str]) -> int:
    trees = [t.strip("/") for t in argv[1:]]
    if not trees:
        print(__doc__)
        return 2
    reports = committed_reports()
    blob = "\n".join(t for _n, t in reports)
    print(f"# committed reports read: {len(reports)} files, {len(blob)} chars\n")
    print(f"{'TOKEN':>5} {'SUBSTR':>6} {'BASENAMES':>9}  TREE")
    for t in trees:
        token = blob.count(t + "/")
        substr = blob.count(t)
        base = sorted({b for b in os.listdir(os.path.join(ROOT, t))
                       if os.path.isfile(os.path.join(ROOT, t, b))})
        basehits = sum(1 for b in base if b and b in blob)
        print(f"{token:5d} {substr:6d} {basehits:9d}  {t}")
        if token:
            for nm, text in reports:
                if t + "/" in text:
                    n = text.count(t + "/")
                    print(f"        cited by {nm}  ({n} token occurrence(s))")
    print("\n# NOTE the SUBSTR column is >= TOKEN by construction; the gap is prose.")
    print("# NOTE BASENAMES counts how many of the tree's top-level filenames appear")
    print("#       ANYWHERE in the reports. It is printed to be disbelieved, not used.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))