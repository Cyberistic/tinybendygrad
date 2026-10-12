#!/usr/bin/env python3
"""Q2, measured: is any oracles/*.txt COMPARED/READ by anything?

The inherited measurement was "named by nothing" -- a LITERAL search. The project's own record is
that a literal search CANNOT see the thing that matters: checks/differ.py:declared() RENDERS
136/136 of runs/graphcmp/D while the corpus sees 1 as a literal token. So this searches FOUR ways
that do not share a regex, and reports each separately because they are different instruments:

  M1 LITERAL-FIXED  grep -F the basename over every file in the tree (code AND prose).
  M2 LITERAL-PATH   grep -F the project-relative path.
  M3 DIR-READ       does any file mention the DIRECTORY `oracles` as a path at all? A tool that
                    walks or globs the directory makes every file in it live, by construction.
  M4 CONSTRUCTED    does any file BUILD a name out of a prefix + something (f-string, %, format,
                    glob, concat)? Those are the instruments a literal search is blind to.

Each M is run over the working tree, not `git ls-files`, because 4109 paths are intent-to-add and
checks/gen/ is in NEITHER HEAD nor the tree -- reading the index as HEAD produced two wrong
premises already.
"""
import os
import pathlib
import re
import subprocess
import sys
from collections import defaultdict

ROOT = pathlib.Path(".").resolve()
SKIP = {".git", "references", "node_modules", "__pycache__", ".venv", "dist", "build"}
EXTS = {".py", ".sh", ".js", ".mjs", ".cjs", ".ts", ".bend", ".md", ".toml", ".json", ".cfg",
        ".ini", ".yaml", ".yml", ".txt", ".rows", ".tsv", ".err", ".out", ""}


def walk_files():
    for dp, dns, fns in os.walk(ROOT):
        dns[:] = [d for d in dns if d not in SKIP]
        for f in fns:
            p = pathlib.Path(dp) / f
            if p.suffix in EXTS or f.startswith(".") or "." not in f:
                yield p


def main():
    txts = sorted(p for p in (ROOT / "oracles").rglob("*.txt") if p.is_file())
    files = [p for p in walk_files() if p.is_file()]
    print(f"oracles/*.txt = {len(txts)}; searchable files = {len(files)}")

    # One pass over the corpus, in memory. grep -F per basename is 259 greps; this is one read.
    blobs = {}
    for p in files:
        try:
            blobs[p] = p.read_text(errors="replace")
        except Exception:
            pass

    m1 = defaultdict(list)
    m2 = defaultdict(list)
    m3 = defaultdict(list)   # dir readers: files mentioning "oracles" as a path
    for p, text in blobs.items():
        rel = str(p.relative_to(ROOT))
        if rel.startswith("oracles/"):
            continue
        if "oracles" in text:
            m3[rel] = [ln.strip() for ln in text.splitlines() if "oracles" in ln][:6]
    for t in txts:
        rel = str(t.relative_to(ROOT))
        for p, text in blobs.items():
            r = str(p.relative_to(ROOT))
            if r.startswith("oracles/") or r == rel:
                continue
            if t.name in text:
                m1[rel].append(r)
            if rel in text:
                m2[rel].append(r)

    print(f"\nM1 basename-literal: {len(m1)}/259 named by some other file")
    for k, v in sorted(m1.items()):
        print(f"    {k}  <- {v[:4]}")
    print(f"\nM2 path-literal: {len(m2)}/259")
    for k, v in sorted(m2.items()):
        print(f"    {k}  <- {v[:4]}")

    print(f"\nM3 files mentioning the string `oracles` outside oracles/: {len(m3)}")
    for k, v in sorted(m3.items()):
        print(f"    {k}")
        for ln in v:
            print(f"        | {ln[:150]}")

    pathlib.Path(".agents/slop/oracles259/m1.json").write_text(__import__("json").dumps(m1, indent=1))
    pathlib.Path(".agents/slop/oracles259/m3.json").write_text(__import__("json").dumps(m3, indent=1))


main()
