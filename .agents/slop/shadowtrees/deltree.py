#!/usr/bin/env python3
"""How much of each shadow tree is DUPLICATION and how much is the ONLY copy of anything.

A shadow tree of the source is not one thing. It is a mix:

  SAME     same path, same bytes as the reference -> pure duplication, zero information
  DIFF     same path, DIFFERENT bytes           -> someone edited the copy. THIS is the
           only place that edit may exist, so these paths are named individually and are
           never deleted as a class.
  EXTRA    in the shadow, not in the reference -> a file that only exists in the shadow
  MISSING  in the reference, not in the shadow -> proof the shadow is a STALE snapshot,
           which is what makes the SAME rows worthless as evidence

A tree that is all SAME and many MISSING is a dated photograph. A tree with DIFF rows is a
workbench. Those two deserve opposite verdicts and no single classifier can tell them apart,
which is why this prints the split instead of a verdict.

    usage: deltree.py REF TREE [TREE ...]      # compare each TREE to REF
           deltree.py --pairwise A B [B ...]   # compare every tree to the first

Nothing here deletes. Nothing here invokes bend.
"""
from __future__ import annotations
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))


def digest(path: str) -> str:
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def snap(tree: str) -> dict[str, tuple[str, int]]:
    """relpath -> (md5, size). Symlinks skipped so a symlinked .venv is not counted as data."""
    out: dict[str, tuple[str, int]] = {}
    for dirpath, dirnames, files in os.walk(tree, followlinks=False):
        dirnames[:] = sorted(d for d in dirnames
                             if not os.path.islink(os.path.join(dirpath, d)))
        for f in sorted(files):
            p = os.path.join(dirpath, f)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            out[os.path.relpath(p, tree)] = (digest(p), os.path.getsize(p))
    return out


def apath(t: str) -> str:
    return t if os.path.isabs(t) else os.path.join(ROOT, t)


def compare(ref_name: str, ref: dict, name: str, cur: dict, verbose: bool) -> None:
    same = [k for k in cur if k in ref and ref[k][0] == cur[k][0]]
    diff = [k for k in cur if k in ref and ref[k][0] != cur[k][0]]
    extra = [k for k in cur if k not in ref]
    missing = [k for k in ref if k not in cur]
    dup_bytes = sum(cur[k][1] for k in same)
    own_bytes = sum(cur[k][1] for k in diff + extra)
    print(f"\n### {name}   vs   {ref_name}")
    print(f"    SAME {len(same):4d} files {dup_bytes/1048576:7.2f} MB   "
          f"(pure duplication)")
    print(f"    DIFF {len(diff):4d} files {sum(cur[k][1] for k in diff)/1048576:7.2f} MB"
          f"   (edited in the shadow -- the only copy of that edit is here)")
    print(f"    EXTRA{len(extra):4d} files {sum(cur[k][1] for k in extra)/1048576:7.2f} MB"
          f"   (exists only in the shadow)")
    print(f"    MISSING {len(missing):4d} files "
          f"{sum(ref[k][1] for k in missing)/1048576:7.2f} MB   (in the ref, absent here)")
    if diff and verbose:
        print("    DIFF paths: " + ", ".join(diff))
    if extra and verbose:
        print("    EXTRA paths: " + ", ".join(extra))


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    verbose = "--quiet" not in argv
    argv = [a for a in argv if a != "--quiet"]
    if argv[1] == "--pairwise":
        names, trees = argv[2], argv[3:]
    else:
        names, trees = [argv[1]], argv[2:]
    refn, refp = names[0], apath(names[0])
    ref = snap(refp)
    print(f"reference {names[0]}: {len(ref)} files")
    for t in trees:
        compare(names[0], ref, t, snap(apath(t)), verbose)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))