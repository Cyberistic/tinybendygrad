#!/usr/bin/env python3
"""No port file may shrink against HEAD without being reported. `checks/no-shrink.py`

THE CLAIM, WITH ITS DENOMINATOR: of the port's files, the number that LOST lines against `HEAD`
uncommitted is printed beside the number that gained, and the exit status is non-zero if any lost
more than `--tolerance` lines.

WHY, MEASURED ON 2026-10-05.  Twelve units were killed mid-edit by server restarts. Their residue
sat in the working copy for hours and **`bend --check-only` reported `ALL PROOFS CHECK` on every
word of it**:

    tinybendygrad/uop/ops.bend                   8,334 -> 6,306 lines   2,386 LOST
    tinybendygrad/renderer/amd/generate.bend      2,736 ->    640 lines   2,096 LOST

`ops.bend` had lost `AOpLit{op: Op}` -- a committed fix -- and every `ParamArg` def, including
`ParamArg.no_slot`. `generate.bend` had lost **404 `def`s, 77% of the file**, and still compiled.
Six more files had lost CODE rather than comments (`nvdev.bend`: **333 code lines**), which is a
half-finished rewrite rather than a tidy-up.

**EVERY ONE OF THEM COMPILED.** That is the whole reason this file exists. `--check-only` is blind
to missing code: a file that no longer *calls* a missing def is not red, it is WRONG, and the only
symptom is a later number that disagrees with an oracle.

THE THREE FAILURE CLASSES THIS DOES AND DOES NOT COVER. It catches deletion, which is silent. It
does NOT catch a *plant* -- a mutation that keeps the line count and answers plausibly -- because
nothing but a row count catches that, which is what `checks/differ.py` and each unit's gate are
for. It also does not catch a shrink that is legitimate, which is why `--tolerance` exists and why
the report separates CODE deletions from COMMENT deletions: deleting a paragraph is an edit, and
deleting a `def` with nothing in its place is a different act wearing the same diff.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = "tinybendygrad"


def sh(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout


def is_code(line: str) -> bool:
    """A deleted line that was not a comment, blank, or a section banner."""
    t = line.lstrip("-").strip()
    if not t or t.startswith("#"):
        return False
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tolerance", type=int, default=40,
                    help="lines a file may lose before this reports it (default 40)")
    args = ap.parse_args()

    ns = sh("diff", "HEAD", "--numstat", "--", f"{PORT}/").splitlines()
    rows = []
    for ln in ns:
        p = ln.split("\t")
        if len(p) < 3 or p[0] == "-":
            continue
        rows.append((int(p[0]), int(p[1]), p[2]))

    shrank = [(d - a, a, d, path) for a, d, path in rows if d > a]
    grew = [(a - d, a, d, path) for a, d, path in rows if a > d]
    print(f"no-shrink: {len(rows)} port files differ from HEAD uncommitted -- "
          f"{len(grew)} GREW, {len(shrank)} SHRANK, tolerance {args.tolerance} lines")

    # The empty-file trap, counted first because it is the cheapest way to pass a gate.
    # THE UNPACK HERE WAS WRONG ON THE FIRST RUN -- `rows` holds 3-tuples and this asked for 4 --
    # SO THE GATE RAISED ON A CLEAN TREE. A GUARD THAT CRASHES WHERE THERE IS NOTHING TO REPORT IS
    # THE SAME DEFECT AS ONE THAT PASSES WHERE THERE IS EVERYTHING TO REPORT: both leave the caller
    # with no verdict, and a caller that cannot tell "clean" from "crashed" will assume clean.
    empties = [path for _a, _d, path in rows
               if os.path.exists(os.path.join(ROOT, path))
               and os.path.getsize(os.path.join(ROOT, path)) == 0]
    if empties:
        print(f"  ZERO-BYTE, and `--check-only` answers ALL PROOFS CHECK on each: {len(empties)}")
        for p in empties:
            print(f"    {p}")

    bad = [r for r in shrank if r[0] > args.tolerance]
    for lost, _a, _d, path in sorted(shrank, reverse=True):
        if lost <= args.tolerance:
            continue
        d = sh("diff", "HEAD", "--", path)
        deleted = [l for l in d.splitlines() if l.startswith("-") and not l.startswith("---")]
        code = sum(1 for l in deleted if is_code(l))
        tag = "CODE REMOVED" if code else "comments only"
        print(f"  SHRANK  -{lost:<6d} ({code} of {len(deleted)} deleted lines are {tag})  {path}")
        print(f"          a file that compiles while losing code is not tidy, it is wrong -- "
              f"`git diff HEAD -- {path}` before touching this")

    if not bad and not empties:
        print("  CLEAN: nothing shrank past tolerance, and no port file is zero bytes")
        return 0
    print(f"  NOT CLEAN: {len(bad)} file(s) past tolerance, {len(empties)} zero-byte. "
          f"Restore from HEAD, or commit the deletion as a deliberate act.")
    return 1


if __name__ == "__main__":
    sys.exit(main())