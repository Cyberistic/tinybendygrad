#!/usr/bin/env python3
"""DENOMINATOR. What is actually in `.agents/slop`, and what is a copy of something else.

    .venv/bin/python .agents/slop/gatecensus/enum.py            # the denominator, human-readable
    .venv/bin/python .agents/slop/gatecensus/enum.py --json     # same, as rows for the runner

WHY A SEPARATE FILE FOR COUNTING. Every other number in this project was produced by a script
that also ran the thing it counted, and one that ran it in parallel (`census.py -j 10`, no memory
bound) recorded 925 runs whose tripwire shows gates writing into `tinybendygrad/`. A denominator
produced by the same run as the measurements is not checkable. So counting stands alone.

SHADOW TREES. 515 executables were reported under `.agents/slop`. 367 of them are upstream's own
`dev`/`run`/`setup`/`serve`/`train`, sitting inside shadow trees of the source. A shadow tree is
detected by CONTENT, not by name: a file whose body is a copy of a file that also exists outside
slop is a copy. That is the same test the runner uses to collapse duplicates, so the denominator
and the dedup count cannot disagree.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
SLOP = os.path.join(ROOT, ".agents/slop")

SKIP_DIRS = {"__pycache__", ".git"}
# Never a gate population: these are another unit's tree, a vendored checkout, or my own output.
NEVER_GATE = {"gatecensus", "_cleanup", "references", "__pycache__"}

# Extensions that are script-shaped. A `.bend` is source, `.json` an artifact, `.bin` a binary.
SCRIPT_EXT = (".sh", ".py")

UPSTREAM_SCRIPT = re.compile(
    r"^\s*(#!/bin/(ba)?sh|#!/usr/bin/env (ba)?sh|#!/bin/zsh)", re.M)


def rel(p: str) -> str:
    return os.path.relpath(p, ROOT)


def md5(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.md5(fh.read()).hexdigest()


def walk_scripts() -> list[str]:
    out = []
    for dirpath, dirs, files in os.walk(SLOP):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if name.endswith(SCRIPT_EXT):
                out.append(rel(os.path.join(dirpath, name)))
    return sorted(out)


def is_shadow(path: str, in_gitignore: dict) -> dict:
    """A shadow copy if the same byte-content exists OUTSIDE `.agents/slop`, or if the file is
    inside a vendored/tree copy of the source rather than at slop's top level."""
    r = rel(os.path.join(ROOT, path))
    depth_inside_slop = r[len(".agents/slop/"):].count("/")
    d = md5(os.path.join(ROOT, r))
    return {
        "bytes": os.path.getsize(os.path.join(ROOT, r)),
        "depth": depth_inside_slop,
        "toplevel": depth_inside_slop == 0,
        "exec": os.access(os.path.join(ROOT, r), os.X_OK),
        "md5": d,
    }


def main() -> int:
    rows = []
    scripts = walk_scripts()
    # How many distinct byte-contents exist outside slop? That is what makes a slop file a COPY.
    outside: dict[str, int] = {}
    for base in ("tinygrad", "tinybendygrad", "checks", "examples", "extra_models",
                 "test", "tools", "sz"):
        p = os.path.join(ROOT, base)
        if not os.path.isdir(p):
            continue
        for dirpath, dirs, files in os.walk(p):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for name in files:
                if name.endswith(SCRIPT_EXT):
                    try:
                        outside.setdefault(md5(os.path.join(dirpath, name)), 0)
                        outside[md5(os.path.join(dirpath, name))] += 1
                    except OSError:
                        pass

    for r in scripts:
        info = is_shadow(r, outside)
        info.update(rel=r, shadow=info["md5"] in outside,
                    vendored=any(seg in r.split("/")[2:4] for seg in NEVER_GATE))
        rows.append(info)

    toplevel = [r for r in rows if r["toplevel"]]
    subdir = [r for r in rows if not r["toplevel"]]
    copies = [r for r in rows if r["shadow"]]
    execs = [r for r in rows if r["exec"]]

    # Distinct by content, over the population that is NOT a copy.
    live = [r for r in rows if not r["shadow"] and not r["vendored"]]
    live_tl = [r for r in live if r["toplevel"]]
    content_groups: dict[str, list[str]] = {}
    for r in live:
        content_groups.setdefault(r["md5"], []).append(r["rel"])

    print(f"# DENOMINATOR -- .agents/slop, measured {time_note()}")
    print(f"#   .sh/.py files anywhere under .agents/slop            {len(rows)}")
    print(f"#     at slop top level                                  {len(toplevel)}")
    print(f"#     in subdirectories                                  {len(subdir)}")
    print(f"#   executable bit set                                   {len(execs)}")
    print(f"#   byte-identical to a file OUTSIDE slop (SHADOW COPY)  {len(copies)}")
    print(f"#   in a tree no gate may come from (vendored/mine)      {sum(1 for r in rows if r['vendored'])}")
    print(f"#   POPULATION: not a copy, not vendored                 {len(live)}"
          f"   ({len(live_tl)} of them at top level)")
    print(f"#   DISTINCT by byte content                             {len(content_groups)}"
          f"   [{len(live) - len(content_groups)} byte-identical aliases]")
    dupes = {k: v for k, v in content_groups.items() if len(v) > 1}
    print(f"#   families of byte-identical copies                    {len(dupes)}"
          f"   (max {max((len(v) for v in dupes.values()), default=1)} in one)")

    if "--json" in sys.argv:
        json.dump({"rows": rows, "content_groups": content_groups,
                   "n_scripts": len(rows), "n_toplevel": len(toplevel),
                   "n_exec": len(execs), "n_shadow": len(copies),
                   "n_population": len(live), "n_distinct": len(content_groups)},
                  sys.stdout)
        return 0

    if "--families" in sys.argv:
        by_stem: dict[str, list[str]] = {}
        for r in live_tl:
            by_stem.setdefault(r["rel"].rsplit("/", 1)[-1].rsplit(".", 1)[0], []).append(r["rel"])
        print(f"# TOP-LEVEL BY SUBJECT STEM ({len(by_stem)} distinct stems over {len(live_tl)} files)")
        for stem, fs in sorted(by_stem.items(), key=lambda kv: (-len(kv[1]), kv[0])):
            print(f"   {len(fs):3d}  {stem}")
        return 0
    return 0


def time_note() -> str:
    import time
    return time.strftime("%Y-%m-%d %H:%M")


if __name__ == "__main__":
    sys.exit(main())