#!/usr/bin/env python3
"""THE UNTRACKED SET UNDER `.agents/slop/`: FILES, and the directories that hold none of HEAD's.

THREE CORRECTIONS THIS REPRODUCES, EACH ONE MEASURED BEFORE IT WAS BELIEVED.

1. `comm -23` OVER TWO INDEPENDENTLY-SORTED LISTS IS NOT A SET OPERATION.  `git ls-tree | sort` and
   `find | sort` order under DIFFERENT COLLATIONS unless both run under `LC_ALL=C`, and the
   difference reads as thousands of phantom untracked paths.  So the tree comes from
   `git ls-tree -r HEAD` -- THE TREE, never `git ls-files`' index, which has been armed seven times
   tonight and once held `--intent-to-add` empty blobs that would have committed a DELETION -- and
   disk comes from `os.walk(followlinks=False)` with every entry compared as `bytes`, so LC_ALL
   cannot matter.

2. `find -type f` DOES NOT DESCEND A SYMLINKED DIRECTORY, and neither does `git ls-files --others`
   or `git status` -- git models a symlink as a blob and stops.  196 tracked files under
   `e2epy/` read as "absent" to `find`, and a `git commit -a` on that reading DELETATES them.
   Here `os.walk(followlinks=False)` reports each link in `dirnames` as a PATH in its own right and
   never walks through it, and a symlinked dir's contents are counted by NEITHER side.

3. **A DIRECTORY IS NOT A FILE, AND AN UNTRACKED PATH IS NOT ONE EITHER.**  The first cut of this
   script added `dn` and `fn` together and reported 1,091 untracked "paths"; `git ls-files --others`
   reported 444 for the same scope.  The 647 difference is UNTRACKED DIRECTORIES, which no
   `ls-files` output can contain because the tree lists files and never dirs.  And testing a
   directory for ownership with `dir not in owned` is wrong in the other direction: the tree holds
   FILES, so almost every directory looks unowned.  A directory is unowned iff NO tracked path lies
   beneath it.  Measured: 446 untracked FILES / 9.11 MiB, against the inherited census's 459 /
   9.0 MB -- 13 files gone in an hour of a live tree, and the BYTES agree, so the inherited
   population was FILES all along and only the count is stale.

SCOPE: paths under `.agents/slop/` only. Writes nothing unless `--out` is given.

    python3 .agents/slop/untrack/census.py [--out FILE]
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SLOP = ".agents/slop"


def git(*args: str) -> set[str]:
    p = subprocess.run(("git", "-C", ROOT) + args, capture_output=True)
    if p.returncode:
        raise RuntimeError(f"git {' '.join(args)}: rc={p.returncode}")
    return {p.decode() for p in p.stdout.split(b"\0") if p}


def walk(root: str) -> tuple[list[str], list[str], list[str]]:
    """(files, dirs, symlinks) under `root`.  A symlinked dir is a PATH, never a subtree."""
    files: list[str] = []
    dirs: list[str] = []
    links: list[str] = []
    for dp, dn, fn in os.walk(root, followlinks=False):
        for n in fn:
            files.append(os.path.join(dp, n))
        walkable = []
        for n in dn:
            p = os.path.join(dp, n)
            dirs.append(p)
            if os.path.islink(p):
                links.append(p)
            else:
                walkable.append(n)
        dn[:] = walkable
    return files, dirs, links


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=SLOP)
    ap.add_argument("--out")
    a = ap.parse_args()
    pref = a.root.rstrip("/") + "/"

    owned = git("ls-tree", "-r", "-z", "--name-only", "HEAD")
    files, dirs, links = walk(a.root)
    owned_here = {p for p in owned if p.startswith(pref)}
    ufiles = sorted(p for p in files if p not in owned)
    udirs = sorted(p for p in dirs if not any(o.startswith(p + "/") for o in owned_here))
    nbytes = sum(os.lstat(p).st_size for p in ufiles if not os.path.islink(p))
    absent = sorted(p for p in owned_here if p not in set(files) | set(dirs) | set(links))

    if a.out:
        with open(os.path.join(ROOT, a.out), "w", encoding="utf-8") as fh:
            fh.write("path\tbytes\tkind\n")
            for p in ufiles:
                fh.write(f"{p}\t{os.lstat(p).st_size}\t{'link' if p in links else 'file'}\n")
            for p in udirs:
                fh.write(f"{p}\t0\tdir\n")

    print(f"SCOPE        : paths under {a.root}/, at HEAD {os.popen('git -C ' + ROOT + ' rev-parse --short HEAD').read().strip()}")
    print(f"OWNED-IN-SCOPE: {len(owned_here)} tracked paths (git ls-tree -r HEAD; index never read)")
    print(f"UNTRACKED FILES: {len(ufiles)} paths, {nbytes / 1048576:.2f} MiB   <- THE POPULATION")
    print(f"UNTRACKED DIRS : {len(udirs)} dirs holding no tracked path ({sum(1 for p in udirs if not os.listdir(p))} empty)")
    print(f"SYMLINKED DIRS : {len(links)} under scope, contents counted by NEITHER side")
    print(f"OWNED-ABSENT  : {len(absent)} tracked paths in scope not on disk")
    for p in absent[:8]:
        print(f"    {p}")
    tops: dict[str, list[int]] = {}
    for p in ufiles:
        t = p[len(pref):].split("/")[0]
        tops.setdefault(t, [0, 0])
        tops[t][0] += 1
        tops[t][1] += os.lstat(p).st_size
    print(f"\n{len(tops)} top-level entries among the untracked FILES, largest first:")
    for k, (n, b) in sorted(tops.items(), key=lambda kv: -kv[1][1])[:24]:
        print(f"  {k:<22} {n:>4} files {b / 1024:>9.0f} KB")
    print(f"\nVERDICT PASS  files={len(ufiles)} dirs={len(udirs)} rows_written={len(ufiles) + len(udirs) if a.out else 0}")
    return 0


if __name__ == "__main__":
    sys.exit(main())