#!/usr/bin/env python3
"""THE SHARPEST QUESTION MEASURED: does a tree property exist that says "generated"?

THE FOUR CANDIDATES THE BRIEF NAMES, and the fifth that fell out of measuring them. Each is
MEASURED here and each verdict is printed with its denominator, because a property that cannot
be counted is a property nobody can audit.

  P1  IGNORED      -- `git check-ignore` says a `.gitignore` rule names it.
  P2  WRITTEN      -- a static write call in the tree resolves into it.
  P3  UNCITED      -- no file in the tree names it. (the citation index, and its 3 failures)
  P4  IGNORE-NAMED -- a `.gitignore` RULE LITERALLY NAMES the directory.
  P5  EMPTY-BLOB   -- NEW. Every entry under it is indexed at git's EMPTY BLOB while the
                      worktree file is non-empty: the index says "there is a file here and its
                      content is nothing", which is a declaration made BY GIT about a directory
                      whose bytes live somewhere else.

`git ls-files` RETURNS TRACKED-BUT-DELETED PATHS, so this script uses `os.lstat` and says
`ABSENT` rather than counting a deletion as a zero-byte file.
"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EMPTY = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"


def g(*a):
    return subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True).stdout


def index():
    """`{path: (mode, sha, stage)}` from `git ls-files -s`. FIELD 1 IS THE MODE AND FIELD 2 IS
    THE SHA -- confusing them makes an empty blob look like a mode, which is the specific trap
    the brief names."""
    out = {}
    for line in g("ls-files", "-s").splitlines():
        meta, _, path = line.partition("\t")
        mode, sha, stage = meta.split()
        out[path] = (mode, sha, stage)
    return out


def on_disk(p):
    full = ROOT / p
    try:
        st = os.lstat(full)
    except OSError:
        return "ABSENT", 0
    return ("DIR" if os.path.isdir(full) else "FILE"), st.st_size


def gitignore_lines():
    gi = (ROOT / ".gitignore")
    out = []
    for line in gi.read_text().splitlines():
        line = line.split("#")[0].strip()
        if line and not line.startswith("!"):
            out.append(line)
    return out


def main():
    idx = index()
    by_dir = {}
    for path, (_mode, sha, _stage) in idx.items():
        d = os.path.dirname(path)
        kind, size = on_disk(path)
        e = by_dir.setdefault(d, {"n": 0, "empty": 0, "empty_nonzero": 0, "absent": 0})
        e["n"] += 1
        if sha == EMPTY:
            e["empty"] += 1
            if kind == "FILE" and size:
                e["empty_nonzero"] += 1
        if kind == "ABSENT":
            e["absent"] += 1

    print(f"INDEX ENTRIES: {len(idx)}   DIRECTORIES THEY IMPLY: {len(by_dir)}")
    print("\n=== P5: DIRECTORIES WHERE THE INDEX IS ALL-EMPTY-BLOBS ===")
    print("    (this is the property that names checks/gen/ without a list)")
    hits = []
    for d, e in sorted(by_dir.items()):
        if e["empty"] == e["n"] and e["n"]:
            hits.append((d, e))
    for d, e in hits:
        nz = sum(1 for p in idx if os.path.dirname(p) == d and on_disk(p)[1])
        print(f"  {d:56} {e['n']:4} tracked, {e['empty']:4} empty-blob, "
              f"{nz:6} non-empty bytes on disk")
    print(f"  P5 VERDICT: {len(hits)} directories")
    print("\n=== DIRECTORIES WITH *SOME* EMPTY-BLOB ENTRIES (mixed: not generated, just has "
          "empty files) ===")
    mixed = [(d, e) for d, e in sorted(by_dir.items())
             if 0 < e["empty"] < e["n"] and e["empty_nonzero"] == 0]
    print(f"  {len(mixed)} directories, e.g. "
          f"{', '.join(d for d, _ in mixed[:6])}{' ...' if len(mixed) > 6 else ''}")
    print("\n=== THE SHARPEST SHAPE: an empty index blob whose worktree file is NON-EMPTY ===")
    split = [(p, on_disk(p)[1]) for p in sorted(idx)
             if idx[p][1] == EMPTY and on_disk(p)[0] == "FILE" and on_disk(p)[1]]
    by = {}
    for p, sz in split:
        by.setdefault(os.path.dirname(p), []).append((p, sz))
    for d in sorted(by):
        print(f"  {d:52} {len(by[d])} file(s), {sum(s for _, s in by[d])} bytes on disk, "
              f"0 in the index   e.g. {by[d][0][0]}")
    print(f"  TOTAL: {len(split)} files in {len(by)} director"
          f"{'y' if len(by) == 1 else 'ies'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())