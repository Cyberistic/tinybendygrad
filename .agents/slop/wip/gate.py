"""Row-keyed diff of the cstyle gate against live CPython.

  python3 .agents/slop/wip/gate.py

Runs BOTH lanes (interpreted and native), checks they agree, and compares every
row's `[bend]` half against the `[py]` half it carries. Prints the red rows BESIDE
each other -- never a count -- because a row that merely says "False" cannot be
diffed and a dropped literal is exactly the failure this file is about.
"""

import re, subprocess, sys, os, difflib

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
BEND = os.path.join(ROOT, "bin", "bend")
SRC = os.path.join(ROOT, "tinybendygrad/renderer/cstyle.bend")
BIN = "/tmp/cstyle_gate_bin"

def sh(cmd):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)

ROW = re.compile(r"^(?P<nm>.*?) = \[(?P<bend>.*)\]   py=\[(?P<py>.*)\]$")

def parse(out, tag):
    rows, bad = {}, []
    for line in out.split("\n"):
        if not line.strip():
            continue
        m = ROW.match(line)
        if not m:
            bad.append((tag, line))
            continue
        nm = m.group("nm")
        if nm in rows:
            bad.append((tag, "DUPLICATE ROW NAME: " + nm))
        rows[nm] = (m.group("bend"), m.group("py"))
    return rows, bad

def lanes():
    a = sh([BEND, SRC])
    if a.returncode != 0:
        print("interpreted lane failed:\n" + a.stdout + a.stderr); sys.exit(1)
    c = sh([BEND, SRC, "-o", BIN])
    if c.returncode != 0:
        print("native compile failed:\n" + c.stdout + c.stderr); sys.exit(1)
    b = subprocess.run([BIN], cwd=ROOT, capture_output=True, text=True)
    if b.returncode != 0:
        print("native lane failed:\n" + b.stdout + b.stderr); sys.exit(1)
    return a.stdout, b.stdout

interp, native = lanes()
ri, bi = parse(interp, "interpreted")
rn, bn = parse(native, "native")
problems = bi + bn

if interp != native:
    problems.append(("LANES", "interpreted and native output DIFFER"))
    for d in difflib.unified_diff(interp.split("\n"), native.split("\n"), "interpreted", "native", lineterm="", n=0):
        print(d)

for tag, line in bi + bn:
    print("UNPARSED %s: %r" % (tag, line))

print("interpreted rows: %d   native rows: %d   parsed names equal: %s" % (len(ri), len(rn), set(ri) == set(rn)))

red, green = [], 0
for nm in ri:
    bend, py = ri[nm]
    if bend == py:
        green += 1
    else:
        red.append(nm)

print("\nGREEN %d / %d rows match CPython byte for byte" % (green, len(ri)))
if red:
    print("\nRED ROWS -- bend side printed beside the py side it must equal:\n")
    for nm in red:
        bend, py = ri[nm]
        print("  %s" % nm)
        print("    bend: [%s]" % bend)
        print("    py  : [%s]" % py)
print("\nproblems: %d" % len(problems))
sys.exit(1 if (red or problems) else 0)