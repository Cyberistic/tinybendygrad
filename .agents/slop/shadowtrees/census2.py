#!/usr/bin/env python3
"""Census shadow copies keyed on a DISTINCTIVE PORT FILE, so a tree named
anything at all (ctl-comment, revert-both, ...) is still caught.

dd-cone-wt holds four full port copies under variant names; keying on the
directory name `tinybendygrad` missed all 44 MB of them.
"""
import hashlib, os, subprocess

REPO = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True).stdout.strip()
os.chdir(REPO)

MARKERS = ["codegen/rewriter.bend", "uop/render.bend", "LAWS/spec.bend"]


def treehash(root):
    h, n = hashlib.md5(), 0
    e = []
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d != "__pycache__"]
        for f in fn:
            p = os.path.join(dp, f)
            try:
                e.append((os.path.relpath(p, root),
                          hashlib.md5(open(p, "rb").read()).hexdigest()))
            except OSError:
                pass
            n += 1
    for rel, m in sorted(e):
        h.update(f"{m}  {rel}\n".encode())
    return h.hexdigest(), n


def du(path):
    o = subprocess.run(["du", "-sm", path], capture_output=True, text=True).stdout.split()
    return int(o[0]) if o else 0


tracked = set(subprocess.run(["git", "ls-files"], capture_output=True,
                             text=True).stdout.split())

# every dir that CONTAINS a marker, walking up to the tree root
roots = set()
for dp, dn, fn in os.walk(".agents/slop"):
    if "__pycache__" in dp:
        continue
    for m in MARKERS:
        if os.path.isfile(os.path.join(dp, m)):
            roots.add(dp)
            break

live_h, _ = treehash("tinybendygrad")
print(f"LIVE tinybendygrad treehash {live_h}\n")
print(f"{'MB':>4} {'files':>6} {'tracked':>8}  tree")
rows = []
for r in sorted(roots):
    th, n = treehash(r)
    tr = sum(1 for dp, dn, fn in os.walk(r) for f in fn
             if os.path.join(dp, f) in tracked)
    rows.append((du(r), r, n, tr, th))
rows.sort(reverse=True)
for mb, r, n, tr, th in rows:
    tag = "  <-- IDENTICAL TO LIVE" if th == live_h else ""
    print(f"{mb:>4} {n:>6} {tr:>8}  {r}{tag}")

print("\nBYTE-IDENTICAL GROUPS:")
g = {}
for mb, r, n, tr, th in rows:
    g.setdefault(th, []).append((mb, r))
for th, grp in g.items():
    if len(grp) > 1:
        print(f"  {th}: " + ", ".join(f"{m}MB {r}" for m, r in grp))