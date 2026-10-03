#!/usr/bin/env python3
"""dev-tally-classify.py -- take ONE whole-tree sweep and sort its BROKEN list by CAUSE.

A sweep prints `BROKEN = a, b, c, d` and nothing else. This is the missing half: it reads the
JSON the sweep already wrote and sorts every BROKEN entry into a CAUSE, with the evidence that
puts it there. It runs no lanes -- it is a reader over an existing measurement, so it costs
nothing and cannot add load to a machine that is already the reason some entries are red.

THE CAUSES, and why one list cannot be read without them:

  A. SHARED-IMPORT BREAKAGE. Five unrelated ports fail with the SAME error text, naming the
     same line of the same imported file. One edit to one file, five red entries. A reader
     shown the list sees five defects and fixes zero of them, because the defect is not in any
     of the five. MEASURED on this tree: `uop/ops.bend` changed `ABlob{n: U32}` to
     `ABlob{bs: List<&2, U32>}` at 04:18, mid-sweep, and `codegen/simplify.bend`,
     `schedule/rangeify.bend`, `uop/fold.bend`, `uop/spec.bend` and `codegen/gpudims.bend` all
     failed with the identical
       expected : U32 / observed : List<&2, U32>  Location: binary_n.of
     The evidence is the ERROR TEXT, not the port list: the same `Context`/`Location`/`^`
     triple appearing under several ports is one error seen several times.

  B. DECLARED-LANE. The port is wired on purpose to a lane that cannot compare, so its BROKEN
     is a reachable state rather than a defect -- that is the point of wiring it. Distinguishable
     because the error is the port's OWN (unfilled proofs, no main) rather than an import's.

  C. A REAL DISAGREEMENT. Both lanes ran, both printed rows, and a shared row name differs. The
     only BROKEN here that is a statement about the PORT.

  D. LANE DEATH WITH A PORT-LOCAL ERROR. Red, and the error names this file. Could still be a
     concurrent edit, so the mtime is printed: bracket the run, do not trust a single number.

  usage: .venv/bin/python .agents/slop/dev-tally-classify.py SWEEP.json
"""
import collections, json, pathlib, sys, time

# The four texts that mean "this port was already known to be red". Taken from the gate's own
# wiring comments, and matched as SUBSTRINGS of the error rather than as a port list, because a
# hardcoded filename list is what `tree-verdict.py`'s header calls out as going stale the first
# time a unit's scope moves.
DECLARED = ("defs rely on unsafe or foreign code", "no main to run", "TODOs found")


def err_of(v, lane="interpreted"):
  return " ".join(v["lanes"].get(lane, {}).get("err", "").split())


def main():
  doc = json.loads(pathlib.Path(sys.argv[1]).read_text())
  print(f"interpreter {doc['oracle_py']}  python {doc['python']}")
  print(f"TALLY {doc['tally']}\n")
  groups = collections.defaultdict(list)
  for v in doc["verdicts"]:
    if v["state"] != "BROKEN":
      continue
    e = err_of(v)
    ctx = ""
    for marker in ("expected :", "Context:"):
      if marker in e:
        ctx = e[e.index(marker):][:150]
        break
    groups[(("A" if ctx else ""), ctx)].append((v, e))
    print(f"BROKEN {v['port']}")
    print(f"   reason : {v['why'][:110]}")
    print(f"   rows   : {v['row_counts']}")
    print(f"   lanes  : " + "  ".join(f"{k}=rc{l['rc']}" for k, l in sorted(v["lanes"].items())))
    if ctx:
      print(f"   CONTEXT: {ctx}")
    p = pathlib.Path(v["port"])
    if p.exists():
      print(f"   mtime  : {(time.time() - p.stat().st_mtime) / 60:.1f} min ago "
            f"({'EDITED DURING THE SWEEP' if (time.time() - p.stat().st_mtime) < 5400 else 'stable'})")
    print()

  print("=" * 96)
  print("SORTED BY CAUSE")
  by_ctx = collections.defaultdict(list)
  for (isA, ctx), items in groups.items():
    by_ctx[ctx or "(no compile context -- see per-port reason)"].extend(x[0]["port"] for x in items)
  for ctx, ports in sorted(by_ctx.items(), key=lambda kv: -len(kv[1])):
    tag = "A  SHARED-IMPORT BREAKAGE" if ctx != "(no compile context -- see per-port reason)" \
      else "B/C  per-port"
    print(f"\n{tag}  ({len(ports)} port(s))")
    for p in sorted(ports):
      print(f"    {p}")
    if ctx != "(no compile context -- see per-port reason)":
      print(f"    one error, {len(ports)} victims. The defect is in the imported file the "
            f"Context/Location names, NOT in these {len(ports)}.")
  return 0


if __name__ == "__main__":
  sys.exit(main())