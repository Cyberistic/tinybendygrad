#!/usr/bin/env python
"""The nameable fix: `tcptx-mutate.py`'s 14 dead anchors, re-pointed to `renderer/tc.bend`.

And: the single rf2 anchor that still counts 0 in the restored subject. `bend` is held by
another unit, so this produces the exact re-point (which anchors -> which path:line) and does
NOT apply it.
"""
import ast
import os
import subprocess

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
os.chdir(ROOT)


def load_list(path, name):
    tree = ast.parse(open(path, errors="replace").read())
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name for t in node.targets):
            out = []
            for elt in node.value.elts:
                vals = [eval(compile(ast.Expression(e), "<a>", "eval"), {"chr": chr}) for e in elt.elts]
                out.append(vals)
            return out


def linenos(text, needle):
    hits, start = [], 0
    while True:
        i = text.find(needle, start)
        if i < 0:
            break
        hits.append(text.count("\n", 0, i) + 1)
        start = i + 1
    return hits


print("== tcptx-mutate.py: anchors whose subject moved to renderer/tc.bend")
old_subj = open("tinybendygrad/renderer/tc_ptx.bend", errors="replace").read()
new_subj = open("tinybendygrad/renderer/tc.bend", errors="replace").read() if os.path.exists("tinybendygrad/renderer/tc.bend") else ""
rows = load_list(".agents/slop/tcptx-mutate.py", "MUTATIONS")
dead = []
for mid, old, new, what in rows:
    a, b = old_subj.count(old), new_subj.count(old)
    if a == 0:
        loc = linenos(new_subj, old)
        dead.append((mid, b, loc))
        print(f"  {mid:<4} tc_ptx=0  tc.bend={b}  lines={loc}  :: {old.splitlines()[0][:58]}")
print(f"  dead anchor ENTRIES: {len(dead)}  (distinct strings: {len({r[0] for r in dead})})")

# machine-readable re-point: dead anchor -> action
with open(".agents/slop/instrepair/TCPTX-REPOINT.tsv", "w") as f:
    f.write("mith\tdead_anchor_first_line\ttc_ptx_count\ttc_bend_count\ttc_bend_lines\taction\n")
    for mid, old, new, what in rows:
        if old_subj.count(old) != 0:
            continue
        loc = linenos(new_subj, old)
        if loc:
            act = "repoint subject -> tinybendygrad/renderer/tc.bend line %d" % loc[0]
        else:
            cur = ""
            for ln in old.splitlines():
                for s in new_subj.splitlines():
                    if ln.strip() and ln.strip()[:20] in s:
                        cur = s
                        break
                if cur:
                    break
            act = "STAYS in tc_ptx.bend; re-quote anchor (text evolved): %s" % cur[:90]
        f.write(f"{mid}\t{old.splitlines()[0][:60]}\t{old_subj.count(old)}\t{new_subj.count(old)}\t{loc}\t{act}\n")
print("wrote .agents/slop/instrepair/TCPTX-REPOINT.tsv")

print("\n== rf2-mutate.py: the one anchor that still counts 0 in the restored subject")
subj = open(".agents/slop/rf2root/schedule/rf2_work.bend", errors="replace").read()
for mid, old, new, what in load_list(".agents/slop/rf2-mutate.py", "MUT"):
    n = subj.count(old)
    if n == 0:
        print(f"  {mid} counts 0  :: {old[:70]!r}")
        # is the second line present anywhere?
        if "\n" in old:
            tail = old.splitlines()[1]
            print(f"     second line {tail[:60]!r} appears {subj.count(tail)}x")
