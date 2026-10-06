#!/usr/bin/env python3
"""ONE walk, N windows. The point: the tree is frozen so only the clock moves.

A number that moves 8x with no edit is a number about WHEN YOU LOOKED. To say that with
evidence rather than assertion, every figure has to come out of a SINGLE population read at a
single instant, with the window applied afterwards. `--windows` in checks/sweep.py is the
shipped version of this; this file is the scratch measurement behind it.
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

WINDOWS = (0, 60, 1440)
f = sweep.facts()
tracked = res.git_tracked(ROOT)
files = res.walk(ROOT)                       # THE ONE WALK
t0 = time.time()

# --- sweep verdicts, clock-free -------------------------------------------------
rows = []
for rel, sz in files:
    v = sweep.verdict_for(rel, f.mentioned, f)
    try:
        mt = os.lstat(os.path.join(ROOT, rel)).st_mtime
    except OSError:
        continue
    rows.append((rel, sz, v, mt))

# --- residue verdicts, clock-free (window 0) ------------------------------------
age = res.dir_ages(ROOT, files)
auth = res.authorities()
named = f.mentioned
first = lambda rel, n: sweep.verdict_for(rel, n, f)
sweep_delete = [rel for rel, sz, v, mt in rows if v == "DELETE"]
twins_del = res.outside_twins(ROOT, tracked, [(r, 0) for r in sweep_delete])

cites = collections.defaultdict(set)
for rel in sorted(tracked):
    if res.excluded(rel):
        continue
    try:
        with open(os.path.join(ROOT, rel), "rb") as fh:
            blob = fh.read(4 << 20).decode("utf-8", "replace")
    except OSError:
        continue
    res.index_citations(cites, ROOT, rel, blob)

resrows = []
for rel, sz, v, mt in rows:
    if v != "DELETE":
        continue
    _f2, rv, why = res.classify(ROOT, rel, sz, sweep_named=named, first_pass=first,
                                 auth=auth, age=age, window=0, twins=twins_del,
                                 cites=cites, tracked=tracked, disabled=set())
    resrows.append((rel, sz, rv, why))

def table(title, counter_fn):
    print(f"\n=== {title} ===")
    keys = sorted({k for w in WINDOWS for k in counter_fn(w)})
    print("| bucket | " + " | ".join(f"w={w}m" for w in WINDOWS) + " | verdict |")
    print("|---" * (len(WINDOWS) + 2) + "|")
    const = []
    for k in keys:
        vals = [counter_fn(w).get(k, 0) for w in WINDOWS]
        if len(set(vals)) == 1:
            tag = "**CONSTANT**"
            const.append(k)
        else:
            tag = "moves"
        print("| " + k + " | " + " | ".join(str(v) for v in vals) + f" | {tag} |")
    print(f"constant: {', '.join(const) or 'NONE'}")

def sweep_counter(w):
    cutoff = time.time() - w * 60
    c = collections.Counter()
    for rel, sz, v, mt in rows:
        b = sweep.bucket(v)
        if b not in ("PROTECTED", "LIVE-UNIT") and mt >= cutoff:
            b = "LIVE"
        c[b] += 1
    return c

table("SWEEP buckets vs window (ONE frozen population)", sweep_counter)

def res_counter(w):
    cutoff = time.time() - w * 60
    c = collections.Counter()
    for rel, sz, rv, why in resrows:
        if age.get(os.path.dirname(rel), 1e9) <= w * 60:
            c["LIVE"] += 1
        else:
            c[rv] += 1
    return c

table("RESIDUE verdicts vs window (window 0 = residue.py default)", res_counter)

print(f"\nmeasured {len(rows)} rows in {time.time()-t0:.1f}s after the walk")
