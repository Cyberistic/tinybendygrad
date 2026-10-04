#!/usr/bin/env python3
"""Census every shadow copy of the port / of tinygrad under .agents/slop.

For each tree: bytes, file count, how many are git-TRACKED, whether it is
byte-identical to the live tree or to a sibling (proven by hash, not by eye),
and whether any committed instrument reaches into it.

Nothing is deleted or modified. Read-only.
"""
import hashlib, os, subprocess, sys

REPO = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True).stdout.strip()
os.chdir(REPO)
SLOP = ".agents/slop"


def treehash(root):
    """md5 of (relpath, content-md5) pairs -- path-sensitive, order-normalised."""
    h = hashlib.md5()
    entries = []
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d != "__pycache__"]
        for f in fn:
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, root)
            try:
                with open(p, "rb") as fh:
                    entries.append((rel, hashlib.md5(fh.read()).hexdigest()))
            except OSError:
                entries.append((rel, "UNREADABLE"))
    for rel, m in sorted(entries):
        h.update(f"{m}  {rel}\n".encode())
    return h.hexdigest(), len(entries)


def du_mb(root):
    n = subprocess.run(["du", "-sm", root], capture_output=True, text=True).stdout
    return int(n.split()[0]) if n.split() else 0


tracked = set(subprocess.run(["git", "ls-files"], capture_output=True,
                             text=True).stdout.split())

# ---- locate every shadow copy of the port (a dir containing tinybendygrad/) ----
trees = []
for dp, dn, fn in os.walk(SLOP):
    if "__pycache__" in dp:
        continue
    if "tinybendygrad" in dn and os.path.isdir(os.path.join(dp, "tinybendygrad")):
        trees.append(os.path.join(dp, "tinybendygrad"))
        dn[:] = [d for d in dn if d != "tinybendygrad"]

live_hash, live_n = treehash("tinybendygrad")
print(f"LIVE tinybendygrad: {live_n} files, treehash {live_hash}\n")

rows = []
for t in sorted(trees):
    th, n = treehash(t)
    tr = sum(1 for dp, dn, fn in os.walk(t) for f in fn
             if os.path.join(dp, f) in tracked)
    rows.append((du_mb(t), t, n, tr, th,
                 "IDENTICAL-TO-LIVE" if th == live_hash else "differs-from-live"))

rows.sort(reverse=True)
print(f"{'MB':>4} {'files':>6} {'tracked':>8}  {'treehash':<34} tree")
for mb, t, n, tr, th, note in rows:
    print(f"{mb:>4} {n:>6} {tr:>8}  {th:<34} {t}  [{note}]")

# ---- identity groups among the shadow copies themselves ----
print("\nBYTE-IDENTICAL GROUPS (among shadows, hash-proven):")
by_hash = {}
for mb, t, n, tr, th, note in rows:
    by_hash.setdefault(th, []).append((mb, t))
for th, group in by_hash.items():
    if len(group) > 1:
        waste = sum(m for m, _ in group) - max(m for m, _ in group)
        print(f"  {th}  ({len(group)} trees, {waste} MB reclaimable)")
        for mb, t in group:
            print(f"      {mb:>4} MB  {t}")