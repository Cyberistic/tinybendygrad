#!/usr/bin/env python3
"""G8, ON THE SWEEP SIDE, WHERE THE CLASS ACTUALLY IS.

`sweep.verdict_for` returns `UNKNOWN:residue-internal-citer` when belt B found the name and EVERY
citer is inside the residue. That is 79 rows on this tree. `residue.py` computes the same class but
`copy` is resolved BEFORE `cited` there, so a row with an outside twin never reaches it -- **the two
instruments count different populations for the same class name**, which is finding #4 in the report.

THE DISCRIMINATOR: is the citer itself a COPY? One lookup in a twin map keyed on citers.
"""
import collections, importlib.util, os, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

sweep = load("sweep", os.path.join(ROOT, "checks/sweep.py"))
res = load("residue", os.path.join(ROOT, "checks/residue.py"))

f = sweep.facts()
tracked = res.git_tracked(ROOT)
files = res.walk(ROOT)

t0 = time.time()
twins_all = res.outside_twins(ROOT, tracked, [(r, 0) for r, _ in files])
copies = twins_all                      # THE DICT. one key test is the whole discriminator.
print(f"# twin map over {len(files)} residue files: {len(copies)} have an outside twin "
      f"({time.time()-t0:.1f}s)")

g8 = []
for rel, sz in files:
    v = sweep.verdict_for(rel, f.mentioned, f)
    if v.startswith("UNKNOWN:residue-internal-citer"):
        g8.append((rel, sz, v))

print(f"\n# sweep UNKNOWN:residue-internal-citer rows: {len(g8)}")
split = collections.Counter()
dirs = collections.Counter()
citer_dirs = collections.Counter()
for rel, sz, v in g8:
    name = os.path.basename(rel)
    citers = f.cites[1].get(name, set())
    internal = {c for c in citers if sweep.in_residue(c)}
    cp = {c for c in internal if c in copies}
    rest = internal - cp
    if rest:
        split["some citer is NOT a copy -> genuinely ambiguous"] += 1
        citer_dirs[sorted(rest)[0].split(os.sep, 2)[1]] += 1
    elif cp:
        split["EVERY citer is a COPY -> decided by one lookup"] += 1
    else:
        split["belt-B citer with no internal citer left"] += 1
    dirs[rel.split(os.sep, 2)[1]] += 1

print("\n# G8 SPLIT:")
for k, n in split.most_common():
    print(f"#   {k:44s} {n:4d} rows")
print("\n# rows by top directory (buckets, not paths):")
for k, n in dirs.most_common(12):
    print(f"#   {k:40s} {n:4d}")
print("\n# the deciding non-copy citers, by directory:")
for k, n in citer_dirs.most_common(12):
    print(f"#   {k:40s} {n:4d}")

# ---- WHAT IS A CITER, MEASURED --------------------------------------------------------------
kinds = collections.Counter()
for rel, sz, v in g8:
    name = os.path.basename(rel)
    for c in f.cites[1].get(name, set()):
        if not sweep.in_residue(c):
            continue
        ext = os.path.splitext(c)[1]
        kinds["copy" if c in copies else f"not-copy .{ext or '(none)'}"] += 1
print("\n# every internal citer, by kind (one row = one citer):")
for k, n in kinds.most_common():
    print(f"#   {k:28s} {n:5d}")
