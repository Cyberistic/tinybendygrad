#!/usr/bin/env python3
"""THE DENOMINATOR, RE-MEASURED. Why this file exists instead of a number in a report.

The batch I was handed — "the 35 `ag-verify.sh` copies" — does not exist. The census's
"35 files, 1 gate" came from `gatecensus/group.py:108`, which buckets a file it cannot
`open()` under the key `"unreadable"` and then admits that key into `aliases` at line 109
alongside real sha256 keys. 35 files were unreadable at 16:18 because a concurrent sweep had
deleted them; they were 35 DISTINCT scripts. `group.py` reported the family by its first
member's name, so a delete turned into a duplicate claim.

So this unit re-measures rather than inherits. Four rules, each of which is a trap the census
already paid for:

  1. SHADOW TREES EXCLUDED AT THE WALK, not filtered afterwards. `.agents/slop/differverdict/`,
     `opstree`, `xd1/*` hold copies of this tree; a count that includes them is a count of
     files that are not this project. (`enum.py` excluded them, then a later `git ls-files`
     pathspec `*` readmitted them — REPORT.md §2 defect 1.)
  2. `os.lstat`, never `os.path.getsize`: 174 symlinks under slop and following them made a
     168 MB tree report as 1,291 MB (commit 21fe30f29).
  3. A CITATION IS A WHOLE PATH TOKEN, matched over a corpus enumerated with `:(glob)`.
     Git's pathspec `*` crosses `/` and matched 195 files where `:(glob)` matches 98.
  4. THE POPULATION IS THE FILESYSTEM (os.walk), and every file's existence is re-checked at
     report time — because the census's own rows outlived the files they describe.

    .venv/bin/python .agents/slop/gateport/enum.py            # the table
    .venv/bin/python .agents/slop/gateport/enum.py --json     # rows for the selector
"""
from __future__ import annotations

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SLOP = os.path.join(ROOT, ".agents/slop")

# Rule 1. A directory is a shadow tree if it holds a copy of the repository's own top level.
SHADOW = ("differverdict", "opstree", "xd1", "references", "_cleanup", "gatecensus",
          "gateport", "__pycache__")
SCRIPT_EXT = (".sh", ".py")
EXE = re.compile(r"^\s*#!.*\b(ba|z|k)?sh\b")


def rel(p: str) -> str:
    return os.path.relpath(p, ROOT)


def walk() -> list[str]:
    """Every `.sh`/`.py` under slop that is not inside a shadow tree. ONE walk, one filter."""
    out = []
    for dirpath, dirs, files in os.walk(SLOP):
        dirs[:] = [d for d in dirs if d not in SHADOW and not d.startswith("xd1-")]
        for name in files:
            if name.endswith(SCRIPT_EXT):
                out.append(rel(os.path.join(dirpath, name)))
    return sorted(out)


def size(path: str) -> int:
    """Rule 2. `lstat`, so a symlink counts as the link and not as its 168 MB target."""
    return os.lstat(path).st_size


def main() -> int:
    rows = []
    for r in walk():
        p = os.path.join(ROOT, r)
        head = b""
        with open(p, "rb") as fh:                      # a gate-shaped script is small
            head = fh.read(4096)
        rows.append({
            "rel": r,
            "sh": r.endswith(".sh"),
            "bytes": size(p),
            "exec": os.access(p, os.X_OK),
            "shebang_sh": bool(EXE.search(head.decode("utf-8", "replace"))),
            "toplevel": r[len(".agents/slop/"):].count("/") == 0,
        })
    sh = [r for r in rows if r["sh"]]
    print(f"# re-measured {__import__('time').strftime('%Y-%m-%d %H:%M')}")
    print(f"#   .sh/.py under .agents/slop, shadow trees excluded   {len(rows)}")
    print(f"#   of which `.sh`                                     {len(sh)}")
    print(f"#     at slop top level                               {sum(1 for r in sh if r['toplevel'])}")
    print(f"#     in a subdirectory                               {sum(1 for r in sh if not r['toplevel'])}")
    print(f"#     with a shell shebang                             {sum(1 for r in sh if r['shebang_sh'])}")
    print(f"#     executable bit set                              {sum(1 for r in sh if r['exec'])}")
    print(f"#     carrying an ORACLE_PIN (already ported)           {sum(1 for r in sh if r['sh'] and pin(r['rel']))}")
    print(f"#   GATE-SHAPED BY NAME (see NAME_SHAPED)              {len([r for r in sh if NAME_SHAPED(r['rel'])])}")
    if "--json" in sys.argv:
        json.dump(rows, sys.stdout)
        return 0
    for r in sh:
        print(f"   {r['bytes']:7d} {'x' if r['exec'] else '-'} "
              f"{'ORACLE_PIN' if pin(r['rel']) else '         '} {r['rel']}")
    return 0


# A NAME SHAPE IS EVIDENCE ABOUT INTENT, NOT A MEASUREMENT — this is TIER 3 of the census's own
# migration order, and the 16 NAME-ONLY gates exist because a name is not a measurement.
NAME_SHAPED = re.compile(
    r"(^|[-_/])(gate|check|verify|oracle|sweep|census|assert|audit|compare|diff)([-_.]|$)")


def pin(r: str) -> bool:
    """A gate already migrated says so in its own body. That is a CLAIM, and it is checked."""
    try:
        return "ORACLE_PIN" in open(os.path.join(ROOT, r), encoding="utf-8", errors="replace").read()
    except OSError:
        return False


if __name__ == "__main__":
    sys.exit(main())
