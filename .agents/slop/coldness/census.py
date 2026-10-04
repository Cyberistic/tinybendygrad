#!/usr/bin/env python3
"""Coldness census: FOUR independent properties of every .bend in the port, one row each.

The point of this script is that it never emits a bare number. Every tally it prints
carries the definition that produced it, and the four definitions are computed from
FOUR INDEPENDENT INSTRUMENTS so that agreement between them is evidence rather than
a tautology.

  reach_live   the file is transitively imported from a ROOT (see ROOTS below)
  red_law      `bend --check-only` first output line is not "ALL PROOFS CHECK"
               (this is substrate-check.sh's own COLD predicate, re-derived here so
               the census does not depend on the guard's argument plumbing)
  imports_none the file declares no `import "./x.bend" as A`
  reached_none NO file in the population imports it, and no root reaches it

Denominator discipline: `on_disk` (every .bend), `in_index` (git knows it -- the
script's own PORT criterion), `port_1to1` (in index AND an upstream .py exists).
"""
import collections
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(ROOT, "..", "..", ".."))
TREE = os.path.join(REPO, "tinybendygrad")
BEND = os.path.join(REPO, "bin", "bend")

IMPORT = re.compile(r'^import\s+(?:\./)?([A-Za-z0-9_./-]*\.bend)\s+as\s+([A-Za-z_]\w*)\s*$')

# ROOTS: files with a `def main`, plus the proof/law files the project gates on.
# A file that nothing imports AND that no root reaches is unreachable by any chain,
# so the root set only ever ADDS warmth -- a bigger root set is a weaker claim.
ROOT_RX = re.compile(r'^def\s+main\b', re.M)


def rel(p):
    return os.path.relpath(p, REPO)


def has_upstream(p):
    if not p.endswith(".bend"):
        return None
    return os.path.isfile(os.path.join(REPO, "tinygrad", p[len("tinybendygrad/"):-5] + ".py"))


def in_index(p):
    return subprocess.run(["git", "ls-files", "--error-unmatch", "--", p],
                          capture_output=True, cwd=REPO).returncode == 0


def imports_of(path):
    """[(target_abs_path, alias)] declared by `path`."""
    out = []
    for ln in open(path, errors="replace"):
        m = IMPORT.match(ln)
        if m:
            out.append((os.path.normpath(os.path.join(os.path.dirname(path), m.group(1))),
                        m.group(2)))
    return out


def coldness(path):
    """substrate-check.sh's COLD predicate, verbatim in meaning: rc is IGNORED, the
    first output line is the verdict. `--check-only` exits 1 for a file that inherits
    a red law and 0 for one that carries the cause itself, so rc is a DIFFERENT
    instrument; agent-core.md's 14 was taken with it."""
    p = subprocess.run(["perl", "-e", "alarm 600; exec @ARGV", BEND, path, "--check-only"],
                       capture_output=True, text=True, cwd=REPO)
    first = (p.stdout + p.stderr).split("\n")[0].strip()
    return first, p.returncode


def main():
    files = sorted(
        os.path.join(dirpath, f)
        for dirpath, _, fs in os.walk(TREE)
        for f in fs if f.endswith(".bend")
    )
    paths = [rel(p) for p in files]
    P = len(paths)

    # --- denominator -----------------------------------------------------------
    idx = [p for p in paths if in_index(p)]
    port = [p for p in idx if has_upstream(p) is not False]
    print("DENOMINATOR  on_disk=%d  in_index=%d  port_1to1=%d" % (P, len(idx), len(port)))
    print("             not_in_index=%s" % ([p for p in paths if p not in idx] or "-"))

    # --- import graph ----------------------------------------------------------
    edges = {}                     # relpath -> set(relpath) it imports
    redges = collections.defaultdict(set)   # relpath -> set(relpath) importing it
    for p, ab in zip(paths, files):
        tgts = {rel(t) for t, _ in imports_of(ab) if t.endswith(".bend")}
        edges[p] = tgts
        for t in tgts:
            if t in redges or t in set(paths):
                redges[t].add(p)

    # --- roots + reachability --------------------------------------------------
    roots = [p for p, ab in zip(paths, files) if ROOT_RX.search(open(ab, errors="replace").read())]
    reach = set(roots)
    stack = list(roots)
    while stack:
        cur = stack.pop()
        for t in edges.get(cur, ()):
            if t not in reach:
                reach.add(t)
                stack.append(t)

    # --- four properties -------------------------------------------------------
    rows = []
    for p, ab in zip(paths, files):
        first, rc = coldness(ab)
        rows.append({
            "file": p,
            "reach_live": p in reach,
            "red_law": first != "ALL PROOFS CHECK",
            "red_line": first,
            "rc": rc,
            "imports_n": len(edges[p]),
            "imports_none": len(edges[p]) == 0,
            "reached_by": len(redges.get(p, ())),
            "reached_none": len(redges.get(p, ())) == 0,
            "root": p in roots,
        })

    json.dump(rows, open(os.path.join(ROOT, "census.json"), "w"), indent=1)

    def tally(name, pred):
        hit = [r["file"] for r in rows if pred(r)]
        print("%-24s %3d of %d" % (name, len(hit), P))
        return hit

    print()
    a = tally("red_law (guard COLD)", lambda r: r["red_law"])
    b = tally("reach_live", lambda r: r["reach_live"])
    c = tally("imports_nothing", lambda r: r["imports_none"])
    d = tally("reached_by_nothing", lambda r: r["reached_none"])
    e = tally("red AND reached_none", lambda r: r["red_law"] and r["reached_none"])

    print()
    print("roots (def main) = %d ; unreached-by-root but imported-by-someone = %d"
          % (len(roots), len([r for r in rows if not r["reach_live"] and not r["reached_none"]])))
    print()
    for name, hit in (("RED_LAW", a), ("REACHED_BY_NOTHING", d)):
        print("%s (%d):" % (name, len(hit)))
        for f in hit:
            print("   %s" % f)
    print()
    print("rc!=0 but first line IS 'ALL PROOFS CHECK' (rc is the other instrument): %d"
          % len([r for r in rows if r["rc"] != 0 and not r["red_law"]]))
    print("first line IS 'ALL PROOFS CHECK' but rc!=0 -> agent-core would count these red")


if __name__ == "__main__":
    main()