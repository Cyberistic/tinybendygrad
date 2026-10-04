#!/usr/bin/env python3
"""anchor-audit.py -- WHICH MUTATION ANCHORS NO LONGER EXIST, AND MAY I RUN THAT?

Two questions, one static pass, nothing executed.

  1. STALE.  A mutation is a literal searched for in a text file.  The file
     moves; the literal does not; the edit silently stops landing.  The harness
     then reports `PATCH-NOT-APPLY`, which is honest and useless: it names a
     symptom while the record still has no measurement.  This prints which ids
     are stale and against WHICH file, so the anchor can be re-aimed.

  2. RUNNABLE.  Three harnesses rewrite the LIVE tree in place, and a snapshot
     that does not match live is a `jj restore` gun -- one put a dead
     6,623-line `ops.bend` over the live 6,306-line one and destroyed committed
     work.  A STALE finding is worth nothing if the only way to confirm it is
     to run the harness that will do it, so the zone is printed beside it.

A row is only ANCHOR-GONE when the harness both DECLARES its anchors (a literal
list, read with `ast`) and DECLARES its target (a resolvable path).  Everything
else is UNDECLARED and reported as such: an undeclared harness is not a clean
one, and this directory has been charged six times for reading one as the other.

  usage: anchor-audit.py [--harness NAME_SUBSTRING] [--only-stale]
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mutanchor as MA


def main():
    only = "--only-stale" in sys.argv
    sel = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--harness=")), "")
    W = 96
    rows, stale = [], []
    for h in sorted(glob.glob(os.path.join(MA.HERE, "*.py"))):
        base = os.path.basename(h)
        if base == os.path.basename(__file__) or base in ("mutanchor.py", "patch_not_apply.py"):
            continue
        src = open(h, errors="replace").read()
        if "patch_not_apply" not in src:
            continue
        if sel and sel not in base:
            continue
        tree = MA.parse(h)
        if tree is None:
            rows.append((base, "UNREADABLE", "-", "-", 0, 0, "does not parse"))
            continue
        tgts = MA.targets(tree, base)
        zone = sorted(set(z for z, _ in MA.writes(tree, base))) or ["NONE"]
        if not tgts:
            rows.append((base, "NO-SUBSTRATE", "-", ",".join(zone), 0, 0,
                         "no existing source file named; nothing to measure against"))
            continue
        texts = [open(p, errors="replace").read() for _, p in tgts]
        anc = MA.anchors(tree, texts)
        if anc is None:
            rows.append((base, "UNDECLARED", ",".join(os.path.basename(p) for _, p in tgts[:2]),
                         ",".join(zone), 0, 0,
                         "no literal mutation list; anchors not readable statically"))
            continue
        # An anchor of `None` is a cell this reader declined to treat as an
        # anchor, so it is UNDECLARED per-id and excluded from the denominator
        # rather than counted as either present or stale.
        declared = sorted(k for k, v in anc.items() if v)
        undec = sorted(k for k, v in anc.items() if not v)
        gone = sorted(k for k in declared
                      if not any(anc[k] in t for t in texts))
        rows.append((base, "OK" if not gone else "STALE",
                     os.path.basename(tgts[0][1]), ",".join(zone),
                     len(declared), len(gone),
                     ("no anchor cell at index 1: " + " ".join(undec[:6])) if undec else ""))
        stale += [(base, k, anc[k], tgts[0][1]) for k in gone]
    rows = [r for r in rows if not (only and r[1] not in ("STALE", "NO-SUBSTRATE"))]
    print("=" * W)
    print("ANCHOR AUDIT -- every patch_not_apply harness, read with ast.  NOT run.")
    print("STALE means the harness's own literal is absent from the file it names")
    print("TODAY.  IN-PLAY under ZONE means: do not run it against the live tree.")
    print("=" * W)
    print("%-24s %-13s %-22s %-10s %5s %5s  %s"
          % ("HARNESS", "STATE", "TARGET", "ZONE", "ANCH", "GONE", "NOTE"))
    print("-" * W)
    for r in rows:
        print("%-24s %-13s %-22s %-10s %5d %5d  %s" % r)
    print("-" * W)
    print("%d harnesses, %d stale anchors across %d harnesses"
          % (len(rows), len(stale), len(set(s[0] for s in stale))))
    for base, mid, anchor, tgt in stale:
        print("  %-22s %-6s -> %s" % (base, mid, os.path.relpath(tgt, MA.ROOT)))
    print("=" * W)
    return 1 if only and not stale else 0


sys.exit(main())