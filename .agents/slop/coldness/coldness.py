#!/usr/bin/env python3
"""COLDNESS -- every coldness number in this tree, computed over ONE fixed population,
each with its definition attached, and the root cause of each red file collapsed to
the thing that actually has to be fixed.

READS  the population off disk, the import graph off the source, and the compiler
       verdicts off the raw output `sweep.sh` already wrote (so the 138 compiler
       runs happen once and the two halves cannot drift by being re-measured apart).
Writes  TABLE.tsv -- one row per file, one column per property.
PRINTS  the summary and the root-cause collapse.

EVERY PROPERTY IS NAMED FOR WHAT IT MEASURES. None of them is called "cold" here;
`COLDNESS.md` picks one, and says so.
"""
from __future__ import annotations

import collections
import os
import re
import sys

RAW = ".agents/slop/coldness/raw"
OK = "ALL PROOFS CHECK"
IMPORT = re.compile(r"^import\s+(?:\./)?([A-Za-z0-9_./-]*\.bend)\s+as\s+([A-Za-z_]\w*)\s*$")
DEF = re.compile(r"^def\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)")
TYPE = re.compile(r"^type\s+([A-Za-z_]\w*)")
LAW = re.compile(r"^law\s+([A-Za-z_]\w*)")
VARIANT = re.compile(r"^[ \t]+([A-Za-z_]\w*)\s*[{(:=]")

# The five shapes `bend --check-only` actually emitted over this population, measured.
SHAPES = [
    (re.compile(r"^Error: (\d+) TODOs found"),        "HOLES"),
    (re.compile(r"^Error: (\d+) defs rely on unsafe or foreign code:"), "FOREIGN"),
    (re.compile(r"^- expected : a fresh name \(duplicate declaration: (\S+)\)"), "DUPLICATE"),
    (re.compile(r"^- expected : a defined name"),      "MISSING-DEF"),
    (re.compile(r"^- message  : a declared constructor \(unknown: (\S+)\)"), "UNKNOWN-CTOR"),
    (re.compile(r"^- expected : (?:'def', 'type' or 'law')"), "SYNTAX"),
    (re.compile(r"^- expected : (.+)$"),              "TYPE-MISMATCH"),
]


def population() -> list[str]:
    return sorted(
        os.path.join(d, f)
        for d, _, fs in os.walk("tinybendygrad")
        for f in fs
        if f.endswith(".bend")
    )


def imports_of(path: str) -> dict[str, str]:
    out = {}
    for ln in open(path, errors="replace"):
        m = IMPORT.match(ln)
        if m:
            out[m.group(2)] = os.path.normpath(
                os.path.join(os.path.dirname(path), m.group(1))
            )
    return out


def top_decls(path: str) -> tuple[int, int]:
    """(defs, laws) declared at column 0 -- the guard's own decls(), shapes only."""
    defs = laws = 0
    for ln in open(path, errors="replace"):
        if DEF.match(ln):
            defs += 1
        elif LAW.match(ln):
            laws += 1
        elif TYPE.match(ln):
            defs += 1
    return defs, laws


def shape_of(out: str) -> tuple[str, str]:
    """(shape, symbol) for the first error in `out`; ('', '') if the file is WARM."""
    lines = out.split("\n")
    for i, ln in enumerate(lines):
        if ln.strip() == OK:
            return "", ""
        m = next((m for rx, _ in SHAPES if (m := rx.match(ln))), None)
        if m:
            shape = next(s for rx, s in SHAPES if rx is m.re)
            sym = m.group(1) if m.groups() else ln[2:].strip()
            if shape == "MISSING-DEF":            # the symbol is on the NEXT line
                nxt = next((l for l in lines[i + 1:] if l.startswith("- observed :")), "")
                sym = nxt.split(": ", 1)[-1].strip().strip("'")
            return shape, sym
    return "", ""


def main() -> int:
    pop = population()
    ins = {p: imports_of(p) for p in pop}
    indeg = collections.Counter()
    for p in pop:
        for t in set(ins[p].values()):
            indeg[t] += 1
    live = {p for p in pop if indeg[p] > 0}      # "live" = has at least one importer
    pset = set(pop)

    rows = []
    for p in pop:
        raw = os.path.join(RAW, p.replace("/", "_") + ".txt")
        out = open(raw, errors="replace").read() if os.path.isfile(raw) else ""
        shape, sym = shape_of(out)
        tgts = sorted(set(ins[p].values()))
        defs, laws = top_decls(p)
        # WHERE THE FIX BELONGS. A name the file calls through an import alias belongs
        # to that alias's module file -- which is why 16 files can share one cause.
        if shape == "MISSING-DEF":
            owner = ins[p].get(sym.partition(".")[0]) or "NOWHERE (no module declares it)"
        elif shape:
            owner = p
        rows.append({
            "file": p,
            "imports": len(tgts),
            "indeg": indeg[p],
            "imports_nothing": int(not tgts),
            "reaches_live": sum(1 for t in tgts if t in live and t in pset),
            "reached_by_nothing": int(indeg[p] == 0),
            "defs": defs,
            "laws": laws,
            "verdict": "COLD" if shape else ("WARM" if out else "NOT RUN"),
            "shape": shape,
            "symbol": sym,
            "cause_owner": owner,
            # DRIVEN: the file declares the thing bend is actually RUN on it. Every
            # unit's own gate is this project's convention (agent-core.md: "the file's
            # own gate()"), and `main` is the driver of record.
            "driver": int(re.search(r"^def (main|gate)\b", open(p, errors="replace").read(), re.M) is not None),
        })

    key = lambda r: (r["shape"], r["symbol"])          # noqa: E731
    groups = collections.defaultdict(list)
    for r in rows:
        if r["verdict"] == "COLD":
            groups[key(r)].append(r)

    with open(".agents/slop/coldness/TABLE.tsv", "w") as fh:
        fh.write("file\timports\timporters\treaches_live\timports_nothing\t"
                 "reached_by_nothing\tdefs\tlaws\tdriven\tverdict\tshape\tsymbol\tcause_owner\n")
        for r in rows:
            fh.write("%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\t%s\t%s\n" % (
                r["file"], r["imports"], r["indeg"], r["reaches_live"],
                r["imports_nothing"], r["reached_by_nothing"], r["defs"], r["laws"],
                r["driver"], r["verdict"], r["shape"], r["symbol"].replace("\t", " "),
                r["cause_owner"]))

    n = len(rows)
    cold = [r for r in rows if r["verdict"] == "COLD"]
    print("POPULATION  .bend on disk under tinybendygrad/            : %d" % n)
    print("  in the git index (the guard's `port=` loose sense)      : %d"
          % sum(1 for p in pop if os.system("git ls-files --error-unmatch -- %s >/dev/null 2>&1" % p) == 0))
    print("  reachable from >=1 other file (importers > 0)          : %d" % (n - sum(r["reached_by_nothing"] for r in rows)))
    print()
    print("PROPERTY                                   COUNT   OF 138")
    print("  COLD (guard HALF 1, first line != ALL PROOFS CHECK)     %3d" % len(cold))
    print("  reached-by-nothing (importers == 0)                     %3d" % sum(r["reached_by_nothing"] for r in rows))
    print("  imports-nothing (0 sibling imports)                     %3d" % sum(r["imports_nothing"] for r in rows))
    print("  reaches-a-live-importer (imports >=1 file that has an importer)  %3d" % sum(r["reaches_live"] > 0 for r in rows))
    print("  declares >=1 `law` at column 0                          %3d" % sum(r["laws"] > 0 for r in rows))
    print("  has neither an importer nor an import (ISOLATED)         %3d" % sum(r["reached_by_nothing"] and r["imports_nothing"] for r in rows))
    print("  DRIVEN (declares `def main` or `def gate`)               %3d" % sum(r["driver"] for r in rows))
    dead = [r for r in rows if r["reached_by_nothing"] and r["imports_nothing"] and not r["driver"]]
    wired_or_driven = [r for r in rows if not (r["reached_by_nothing"] and r["imports_nothing"] and not r["driver"])]
    print("  DEAD SURFACE (no importer, no import, not runnable)      %3d" % len(dead))
    print()
    print("-- DEAD SURFACE: nothing imports it, it imports nothing, bend cannot RUN it --")
    for r in dead:
        print("  %-52s defs=%-5d laws=%d" % (r["file"].replace("tinybendygrad/", ""), r["defs"], r["laws"]))
    print()
    print("COLDNESS (defined as: no port file imports it, and bend cannot run it) = %d of %d"
          % (len(dead), n))
    print("  i.e. %d of %d are WIRED (some file imports them) and %d of %d are DRIVEN"
          % (sum(not r["reached_by_nothing"] for r in rows), n, sum(r["driver"] for r in rows), n))
    print()
    print("ROOT CAUSES: %d red FILES come from %d distinct causes" % (len(cold), len(groups)))
    for (shape, sym), rs in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        owner = next((r["cause_owner"] for r in rs if r["cause_owner"]), "<unattributed>")
        print("  %2d file(s)  %-14s %-30s  declared in %s" % (
            len(rs), shape, (sym or "-")[:30], owner.replace("tinybendygrad/", "<here>/") or "-"))
    return 0


if __name__ == "__main__":
    sys.exit(main())