#!/usr/bin/env python3
# .agents/slop/nv_fixorder.py -- order the top-level defs by asking the COMPILER,
# one error at a time, and MOVE THE BLOCK THAT IS WRONG rather than guessing.
#
# Bend's rule (bend2-constraints.md, rule 1) is that a def must be DECLARED
# BEFORE every def that calls it, and the compiler's message for a violation is
# the same one it gives for a law left unfilled -- so it names the missing callee
# but never says which caller wanted it. This script takes the named callee,
# finds the FIRST block that uses it, and moves one of the two across the other.
# It is a topological sort driven by the compiler instead of by a regex, which is
# the only version of this that was correct: two earlier attempts either missed
# every call (the `(?![A-Za-z_0-9(])` lookahead) or read comments as uses.
#
# IT ONLY MOVES WHOLE BLOCKS, where a block runs from a column-0 `def`/`type`/
# `import` to the next one, so a def's comment travels with it.
import re, subprocess, sys

P = sys.argv[1] if len(sys.argv) > 1 else "tinybendygrad/runtime/support/nv/nvdev.bend"
HEADER = re.compile(r"^(def|type|import|law) ")
DEFN = re.compile(r"^def ([A-Za-z_][A-Za-z_0-9.]*)\s*\(")
TYPEN = re.compile(r"^type ([A-Za-z_][A-Za-z_0-9.]*)\s+is")

def all_names(src):
    n = set(re.findall(r"^(?:def|type)\s+([A-Za-z_][A-Za-z_0-9.]*)", src, re.M))
    n |= set(re.findall(r"\bas ([A-Za-z_][\w]*)", src))
    return n

def blocks(src, names):
    out, cur = [], []
    for ln in src.split("\n"):
        m = re.match(r"^#\s*`([A-Za-z_][A-Za-z_0-9.]*)`", ln)
        # a comment naming a def is that def's DOC and starts a new block
        starts = HEADER.match(ln) or (m and m.group(1) in names)
        if starts and any(l.strip() for l in cur):
            out.append("\n".join(cur).rstrip()); cur = [ln]
        else:
            cur.append(ln)
    out.append("\n".join(cur).rstrip())
    return [b for b in out if b.strip()]

def nm(b):
    for l in b.split("\n"):
        m = DEFN.match(l) or TYPEN.match(l)
        if m:
            return m.group(1)
    return None

def uses(b, t):
    # NOT `(?![A-Za-z_0-9(])`: `f(x)` is a USE of f. Excluding `(` made the graph
    # empty, the sort vacuous, and every call in the file a forward reference.
    return re.search(r"(?<![A-Za-z_0-9.])" + re.escape(t) + r"(?![A-Za-z_0-9])", b) is not None

def main():
    src = open(P).read()
    for it in range(300):
        names = all_names(src)
        bs = blocks(src, names)
        label = [nm(b) for b in bs]
        r = subprocess.run(["./bin/bend", P], capture_output=True, text=True)
        out = r.stdout + r.stderr
        # The callee the compiler names. `- observed : X` is the unfilled name and
        # `- expected : a defined name / observed : X` is the same fact phrased the
        # other way round, so take whichever names a DEF THIS FILE HAS.
        cands = re.findall(r"- observed : ([A-Za-z_][\w.]*)", out)
        t = next((c for c in cands if c in names), None)
        if t is None:
            print(f"CLEAN after {it} moves")
            print(out[:600])
            open(P, "w").write(src)
            return 0
        if t not in label:
            print(f"{t} is named but not defined here (not a Bend base?):\n{out[:500]}")
            return 1
        ti = label.index(t)
        caller = next((j for j, b in enumerate(bs) if j != ti and uses(b, t)), None)
        if caller is None:
            print(f"{t} has no caller in this file; the error is not an ordering one:\n{out[:500]}")
            return 1
        if caller < ti:
            # the caller already precedes the callee: sink the caller below it
            blk = bs.pop(caller); bs.insert(ti, blk); verb = "sink"
        else:
            blk = bs.pop(ti); bs.insert(caller, blk); verb = "hoist"
        src = "\n\n".join(b for b in bs if b.strip()) + "\n"
        open(P, "w").write(src)
        print(f"  {verb} {nm(blk)}")
    print("GAVE UP after 300 moves")
    return 1

sys.exit(main())