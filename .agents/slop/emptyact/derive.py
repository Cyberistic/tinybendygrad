#!/usr/bin/env python3
"""derive.py -- re-derive the 33 empty-evidence gaps and gather each one's siblings.

Reads the emptyevid classification (CAPTURES.tsv) and reports, per target path:
  * whether it exists and is git's empty blob (e69de29bb2d1)
  * every sibling file in its directory, with size and first line if non-empty
  * git log commits touching the path
No writes to any other file.
"""
from __future__ import annotations

import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
EMPTY = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
CAPS = ROOT / ".agents/slop/emptyevid/CAPTURES.tsv"
TARGET = {"HOLE", "UNCLASSIFIED"}


def blob(path: str) -> str:
    r = subprocess.run(["git", "ls-tree", "HEAD", "--", path], cwd=ROOT,
                       capture_output=True, text=True)
    return r.stdout.split()[2] if r.stdout.strip() else "-"


def gitlog(path: str) -> list[str]:
    r = subprocess.run(["git", "log", "--oneline", "--all", "--", path], cwd=ROOT,
                       capture_output=True, text=True)
    return r.stdout.splitlines()


def first_line(p: pathlib.Path) -> str:
    try:
        with p.open("rb") as f:
            return f.readline().decode("utf-8", "replace").rstrip()
    except OSError:
        return "-"


def main() -> int:
    rows = [l.split("\t") for l in CAPS.read_text().splitlines()[1:] if l]
    targets = [r for r in rows if r[4] in TARGET]
    counts = {c: sum(1 for r in rows if r[4] == c) for c in
              ("REDUNDANT", "HOLE", "UNCLASSIFIED")}
    print(f"classes: REDUNDANT={counts['REDUNDANT']} HOLE={counts['HOLE']} "
          f"UNCLASSIFIED={counts['UNCLASSIFIED']} total={len(rows)} "
          f"targets={len(targets)}")
    print()
    by_dir: dict[str, list[list[str]]] = {}
    for r in targets:
        by_dir.setdefault(str(pathlib.Path(r[0]).parent), []).append(r)
    for d, group in sorted(by_dir.items()):
        print(f"### {d}  ({len(group)})")
        sibs = sorted(p for p in (ROOT / d).iterdir() if p.is_file())
        empties = {p.name for p in sibs if p.stat().st_size == 0}
        for r in group:
            p, cls = r[0], r[4]
            b = blob(p)
            mark = "EMPTY" if b == EMPTY else f"BLOB!={b}"
            print(f"  {pathlib.Path(p).name:<24} {cls:<13} {mark}  producer={r[2]}")
        print(f"  siblings non-empty in dir:")
        for p in sibs:
            if p.name not in empties:
                t = first_line(p)
                print(f"    {p.name:<24} {p.stat().st_size:>8}  {t[:100]}")
        print()
        for r in group:
            logs = gitlog(r[0])
            print(f"  git log {r[0]}: {len(logs)} commits")
            for l in logs[:2]:
                print(f"    {l[:110]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
