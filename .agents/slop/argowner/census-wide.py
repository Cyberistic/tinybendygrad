#!/usr/bin/env python3
"""ARGOWNER census, WIDE scope: the port tree AND every other .bend file that
imports `tinybendygrad/uop/ops.bend`.

WHY A SECOND SCOPE.  census.py's scope is `tinybendygrad/`, which is what the
brief asked for and it is the right scope for "the PORT's Arg surface".  It is
also, MEASURED, an incomplete denominator for "what breaks when Arg grows":
`.agents/slop/graphcmp.bend` -- the differ's OWN harness, the file the differ
runs `./bin/bend` against for the bend side of all 34 graphs -- has a FOURTH
closed `Arg` match at `argstr`.  Adding `ABoolList` made the differ emit
`0 rows after 5 attempts` for 34 of 34 graphs, which is DEAD, not zero.

The population is still not a hand list: the CONSTRUCTORS are parsed from
`type Arg is Data:`, and the FILES are `os.walk` from the repo root over
`*.bend`, keeping only files whose text contains an `import .../ops.bend`.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import census  # the parser is the SAME code, not a second copy

ROOT = census.ROOT


def walk_all():
    files = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        # `argowner/` is EXCLUDED because this instrument's own scratch lives there
        # (`handoff-graphcmp.bend`, `mine/*.bend`). Left in, it counted the census
        # from inside its own output: 288 -> 296 .bend files and 273 -> 339 sites,
        # with 3 phantom "closed" rows that are copies of rows already counted.
        dirnames[:] = [d for d in dirnames
                       if d not in (".git", ".jj", ".venv", "__pycache__", "references",
                                    os.path.basename(os.path.dirname(os.path.abspath(__file__))))]
        for fn in sorted(filenames):
            if fn.endswith(".bend"):
                files.append(os.path.join(dirpath, fn))
    return files


def main():
    allf = walk_all()
    # MULTILINE, whole file: the first cut read only the first 80 lines with a
    # non-MULTILINE `^`, which matched exactly ONE file (ops.bend's own import of
    # nothing) and reported "1 of 288 import ops.bend". A filter that resolves to
    # a near-empty set has measured the filter.
    imp = re.compile(r"^import\s+\S*ops\.bend\s+as\s+(\w+)\s*$", re.M)
    importing = [f for f in allf
                 if imp.search(open(f).read()) or f == census.OPS]
    name, ctors = census.ctors_of(census.OPS, "Arg")
    if not ctors:
        print("REFUSED: parsed ZERO constructors -- that is a None, not a zero")
        return 3
    alias = census.aliases(importing)
    variants = set(alias) | {""}
    cset = set(ctors)

    def names_ctor(pat, variants):
        hit = None
        for part in pat.split(","):
            m = re.match(r"\s*(?:(\w+)\.)?([A-Z]\w*)\s*\{", part)
            if m and m.group(2) in cset and (m.group(1) or "") in variants:
                hit = m.group(2)
        toks = pat.split()
        return hit, bool(toks) and all(re.fullmatch(r"_\w*", t) for t in toks)

    closed, nsites = [], 0
    for f in sorted(importing):
        rel = os.path.relpath(f, ROOT)
        lines = open(f).read().split("\n")
        local = variants if f == census.OPS else {a for a in variants if a}
        def_at, cur = [], None
        for ln in lines:
            m = census.DEF_RE.match(ln)
            cur = m.group(2) if m else cur
            def_at.append(cur)
        for start, indent, arms, shape in census.blocks(lines):
            seen, wild = set(), False
            for pat in arms:
                h, w = names_ctor(pat.strip(), local)
                wild |= w
                if h:
                    seen.add(h)
            if not seen:
                continue
            nsites += 1
            missing = [c for c in ctors if c not in seen]
            if not wild and (not missing or missing == ["AOpLit"] or missing == ["ABoolList"]
                             or "ABoolList" in missing or "AOpLit" in missing):
                closed.append((rel, start + 1, def_at[start],
                               "EXHAUSTIVE" if not missing else "INCOMPLETE",
                               ",".join(missing) if missing else "-"))
    print(f"# ARGOWNER census, WIDE scope: os.walk(REPO ROOT) *.bend = {len(allf)} files,")
    print(f"#   of which {len(importing)} import tinybendygrad/uop/ops.bend "
          f"(aliases {sorted(alias)})")
    print(f"#   Arg ctors PARSED from ops.bend: {len(ctors)}")
    print(f"#   Arg match SITES across those files: {nsites}")
    print()
    print(f"{'file':34s} {'line':>5s} {'def':14s} kind")
    for r in closed:
        print(f"{r[0]:34s} {r[1]:5d} {str(r[2]):14s} {r[3]} missing={r[4]}")
    print()
    print(f"# CLOSED over the WHOLE repo, scope = every .bend importing ops.bend: {len(closed)}")
    inside = [r for r in closed if r[0].startswith("tinybendygrad/")]
    print(f"#   inside tinybendygrad/ (the port): {len(inside)}")
    print(f"#   OUTSIDE it (harnesses under .agents/slop/): {len(closed) - len(inside)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())