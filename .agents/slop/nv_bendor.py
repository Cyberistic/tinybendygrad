#!/usr/bin/env python3
# .agents/slop/nv_bendor.py -- topological sort of the top-level defs, done
# PROPERLY this time: a def block is every line from a column-0 `def`/`type`/
# `import` up to the next column-0 one, so a def's COMMENT stays with it, and the
# order comes from a dependency graph rather than from one compiler error at a
# time. Bend has no forward references and the message for a mis-ordered def is
# the one it also gives for a law left unfilled, so the compiler cannot tell you
# which of the two you have -- which is why this script exists.
#
# Usage: python3 .agents/slop/nv_bendor.py [file.bend]
import re, subprocess, sys

P = sys.argv[1] if len(sys.argv) > 1 else "tinybendygrad/runtime/support/nv/nvdev.bend"

HEADER = re.compile(r'^(def|type|import|law) ')
DEFNAME = re.compile(r'^def ([A-Za-z_][A-Za-z_0-9.]*)\s*\(')
TYPENAME = re.compile(r'^type ([A-Za-z_][A-Za-z_0-9.]*)\s+is')

def blocks(src, allnames):
    """One entry per top-level def/type/import, comments attached to the def
    BELOW them -- and a COMMENT THAT NAMES A DEF IS ITS OWN BLOCK'S PREFIX."""
    out, cur = [], []
    for ln in src.split("\n"):
        m = re.match(r"^#\s*`([A-Za-z_][A-Za-z_0-9.]*)`", ln)
        starts = HEADER.match(ln) or (m and m.group(1) in allnames)
        if starts and any(l.strip() for l in cur):
            out.append("\n".join(cur).rstrip()); cur = [ln]
        else:
            cur.append(ln)
    out.append("\n".join(cur).rstrip())
    return [b for b in out if b.strip()]

def names_of(b):
    out = []
    for l in b.split("\n"):
        m = DEFNAME.match(l) or TYPENAME.match(l)
        if m:
            out.append(m.group(1))
    if b.lstrip().startswith("import "):
        # `import Base` names NOTHING in this file's namespace and `import X as Y`
        # introduces Y. Registering "Base" as a name made every later block depend
        # on a node that no block could ever place, which reads as a 300-name cycle.
        out += re.findall(r'\bas ([A-Za-z_][\w]*)', b)
    return out

def uses(b, t):
    # The lookahead must NOT exclude `(`: `nv.ones(x)` is a USE of `nv.ones`, and
    # excluding `(` made every call look like a non-use. With that exclusion the
    # whole dependency graph was empty, the topological sort was vacuous, and the
    # compiler then reported 25 real ordering errors one at a time -- each of
    # which `nv_bendor.py` had been supposed to prevent.
    return re.search(r'(?<![A-Za-z_0-9.])' + re.escape(t) + r'(?![A-Za-z_0-9])', b) is not None

def main():
    src = open(P).read()
    # collect the names FIRST: a comment naming a def can only be recognised as
    # a block boundary once the names are known, so this is a two-pass read.
    allnames = set(re.findall(r"^(?:def|type)\s+([A-Za-z_][A-Za-z_0-9.]*)", src, re.M))
    allnames |= set(re.findall(r"\bas ([A-Za-z_][\w]*)", src))
    bs = blocks(src, allnames)
    # the FILE HEADER (everything before the first `import`) is block 0 and must
    # stay first: it is a comment, and moving it is pointless.
    head, rest = [], bs
    for i, b in enumerate(bs):
        if b.lstrip().startswith("import "):
            head, rest = bs[:i], bs[i:]
            break
    graph = []
    for b in rest:
        graph.append((names_of(b), b))
    allnames = {n for ns, _ in graph for n in ns}
    # ONE PASS per block over allnames: O(blocks * names) regexes. The first
    # draft re-ran `uses` for every (def, name) PAIR and then ran the placement
    # loop to a fixpoint, which is O(blocks^3) and took over SIX MINUTES on a
    # 313-block file. Kahn's algorithm with a reverse index is O(blocks*names).
    deps = {}
    for ns, b in graph:
        for n in ns:
            deps[n] = {m for m in allnames if m not in ns and uses(b, m)}
    # Kahn over BLOCKS, keyed on DEPS ONLY. Two earlier drafts added a
    # `not (set(ns) & remaining)` guard, and both were wrong in the same way:
    # `remaining` starts as EVERY name, so that guard is false for every block on
    # the first pass, nothing is ever ready, and 300 names read as one cycle. The
    # deps check alone is the real test, because a block is re-tested every pass
    # and `placed` grows monotonically.
    order, placed = [], set()
    while True:
        ready = [ns for ns, _ in graph
                 if ns and all(n not in placed for n in ns)
                 and all(d in placed for n in ns for d in deps[n])]
        if not ready:
            break
        for ns in ready:
            order.append(next(b for ns2, b in graph if ns2 == ns))
            placed.update(ns)
    unplaced = sorted(placed.symmetric_difference(allnames) or (allnames - placed))
    if allnames - placed:
        # a cycle: report it and leave the file alone. Bend has no mutual
        # recursion without @unsafe, so a cycle here is a design error and the
        # honest move is to say which names are in it.
        print("CYCLE among:", sorted(allnames - placed))
        return 1
    open(P, "w").write("\n\n".join(head + order) + "\n")
    print(f"ordered {len(order)} blocks, {len(head)} header block(s) kept first")
    r = subprocess.run(["./bin/bend", P], capture_output=True, text=True)
    print((r.stdout + r.stderr).split("\n")[0])
    return 0

sys.exit(main())