#!/usr/bin/env python3
"""Prove two shadow trees are byte-identical by HASH, not by eye, and say which.

Three different identities, and the difference between them is the whole point of this file:

  MANIFEST  md5 over sorted (relpath, filemd5) lines. Equal => same paths, same bytes.
  CONTENT   md5 over sorted filemd5 lines ONLY, paths discarded.
                 Equal MANIFEST, different CONTENT => the same bytes rearranged.
                 Equal CONTENT, different MANIFEST => the same bytes at different paths.
                 This is the one that matters when a unit copied a tree and then edited it:
                 MANIFEST differs (one file changed) so a manifest-only test calls it unique,
                 while CONTENT tells you exactly HOW MUCH of it is duplication.
  BYBASENAME md5 over sorted (basename, filemd5). This is the OVER-CITING trap the
                 classifier's own docstring records -- a bare-basename match reported 3,574
                 false citations, 138 of them copies of one __init__.bend. It is computed here
                 ONLY to reproduce that failure on real data, never to decide anything.

A tree is a shadow of the repo when its MANIFEST matches the real tree's. A tree is a
LEFTOVER when its MANIFEST matches a SIBLING shadow's -- that is duplication of a copy, and
it is the cheapest kind of thing to reclaim because there is no unique content anywhere in it.

Nothing here deletes. Nothing here invokes bend.
"""
from __future__ import annotations
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))


def walk(tree: str) -> list[tuple[str, str, int]]:
    """(relpath, filemd5, size) for every regular file, symlinks skipped, sorted by path."""
    out = []
    for dirpath, dirnames, files in os.walk(tree, followlinks=False):
        dirnames[:] = sorted(d for d in dirnames
                             if not os.path.islink(os.path.join(dirpath, d)))
        for f in sorted(files):
            p = os.path.join(dirpath, f)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            rel = os.path.relpath(p, tree)
            h = hashlib.md5()
            with open(p, "rb") as fh:
                for chunk in iter(lambda: fh.read(1 << 20), b""):
                    h.update(chunk)
            out.append((rel, h.hexdigest(), os.path.getsize(p)))
    return sorted(out)


def identities(rows: list[tuple[str, str, int]]) -> tuple[str, str, str]:
    m = hashlib.md5()
    c = hashlib.md5()
    b = hashlib.md5()
    for rel, dig, _sz in rows:
        m.update(f"{dig}  {rel}\n".encode())
        c.update((dig + "\n").encode())
        b.update(f"{dig}  {os.path.basename(rel)}\n".encode())
    return m.hexdigest(), c.hexdigest(), b.hexdigest()


def main(argv: list[str]) -> int:
    trees = argv[1:]
    if not trees:
        print(__doc__)
        return 2
    print(f"{'BYTES':>12} {'N':>5}  {'MANIFEST':34} {'CONTENT':34} PATH")
    seen: list[tuple[str, tuple[str, str, str], int, str]] = []
    for t in trees:
        ap = t if os.path.isabs(t) else os.path.join(ROOT, t)
        if not os.path.isdir(ap):
            print(f"{'-':>12} {'-':>5}  {'MISSING':34} {'':34} {t}")
            continue
        rows = walk(ap)
        man, con, bas = identities(rows)
        tot = sum(r[2] for r in rows)
        seen.append((os.path.relpath(ap, ROOT), (man, con, bas), tot, t))
        print(f"{tot:12d} {len(rows):5d}  {man:34} {con:34} {t}")

    print("\n== MANIFEST groups (same paths AND same bytes = a byte-identical duplicate) ==")
    g: dict[str, list[str]] = {}
    for rel, (man, _c, _b), _t, _o in seen:
        g.setdefault(man, []).append(rel)
    for man, members in g.items():
        if len(members) > 1:
            print(f"  IDENTICAL {man[:16]}  {members}")

    print("\n== CONTENT groups (same multiset of file bytes, possibly different paths) ==")
    gc: dict[str, list[str]] = {}
    for rel, (_m, con, _b), _t, _o in seen:
        gc.setdefault(con, []).append(rel)
    for con, members in sorted(gc.items(), key=lambda kv: -len(kv[1])):
        tag = "IDENTICAL" if len(members) > 1 else "unique   "
        print(f"  {tag} {con[:16]}  {members}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))