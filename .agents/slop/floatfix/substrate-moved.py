#!/usr/bin/env python3
"""THROWAWAY: which files under the substrate walks differ from a given commit?

`git diff HEAD` is UNRELIABLE on this tree (the index is armed), so the comparison is
made file by file: `git hash-object` on the worktree bytes against `git rev-parse
<commit>:<path>`.  Both sides are read-only.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
COMMIT = sys.argv[1] if len(sys.argv) > 1 else "HEAD"


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True,
                          text=True, check=True).stdout


listed = git("ls-tree", "-r", COMMIT, "--name-only", "--", "tinybendygrad", "tinygrad").split()
moved, added = [], []
for rel in listed:
    p = ROOT / rel
    if not p.is_file():
        moved.append((rel, "DELETED"))
        continue
    wt = git("hash-object", "--", rel).strip()
    at = git("rev-parse", f"{COMMIT}:{rel}").strip()
    if wt != at:
        moved.append((rel, f"{at[:8]} -> {wt[:8]}"))
on_disk = {str(p.relative_to(ROOT)) for p in (ROOT / "tinybendygrad").rglob("*")
           if p.is_file() and "__pycache__" not in p.parts}
on_disk |= {str(p.relative_to(ROOT)) for p in (ROOT / "tinygrad").rglob("*")
            if p.is_file() and "__pycache__" not in p.parts}
added = sorted(on_disk - set(listed))
print(f"vs {COMMIT}: {len(listed)} files under the walks, {len(moved)} MOVED, "
      f"{len(added)} ADDED")
for rel, how in moved:
    print(f"  MOVED  {rel}  {how}")
for rel in added:
    print(f"  ADDED  {rel}")
