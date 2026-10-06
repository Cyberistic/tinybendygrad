#!/usr/bin/env python3
"""Emit the counts artifact: for every file under tinybendygrad/, what the OLD deep
rule and the NEW shape flag. Read-only; writes counts.rows.
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad"
OUT = Path(__file__).resolve().parent / "counts.rows"

OLD = re.compile(r"\.staged-(mem|blob)-\d+$|\.mut$|~\d*$|\.(bak|orig|rej|swp)$")
NEW = re.compile(
    r"\.staged-(mem|blob)-\d+$|\.mut$|~\d*$|\.(bak|orig|rej|swp)$"
    r"|^zz|(?:_|\.)(mutant|scratch|sweep|diag)(?:\.|_|$)|^_[^_]"
)
TREE = re.compile(r"^_[^_]|probe|_work|\.mut\.")  # tinybendygrad's own SCRATCH_RE (tree-verdict.py:60)


def main() -> int:
    files = sorted(p for p in PORT.rglob("*") if p.is_file())
    rows = []
    for p in files:
        rel = str(p.relative_to(PORT))
        rows.append((rel, bool(OLD.search(p.name)), bool(NEW.search(p.name)),
                     bool(TREE.search(p.name))))
    with OUT.open("w") as f:
        f.write("file\told_residue\tnew_shape\ttree_scratch_re\n")
        for rel, o, n, t in rows:
            f.write(f"{rel}\t{int(o)}\t{int(n)}\t{int(t)}\n")
    n_files = len(rows)
    old_hits = [r for r, o, _, _ in rows if o]
    new_hits = [r for r, _, n, _ in rows if n]
    tree_hits = [r for r, _, _, t in rows if t]
    print(f"files={n_files}  old={len(old_hits)}  new={len(new_hits)}  tree_re={len(tree_hits)}")
    print("old:", old_hits)
    print("new:", new_hits)
    print("tree_scratch_re:", tree_hits)
    return 0


if __name__ == "__main__":
    sys.exit(main())
