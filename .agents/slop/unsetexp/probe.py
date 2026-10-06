#!/usr/bin/env python3
"""Re-measure every corpus graph, N times, into THIS directory. Never touches `runs/`.

    .venv/bin/python .agents/slop/unsetexp/probe.py [trials] [--graphs a,b,c]

TWO CLAIMS, AND THEY ARE THE WHOLE POINT OF THE DIRECTORY:

1. It writes under `.agents/slop/unsetexp/` and nowhere else. `runs/graphcmp/D/` is SHARED --
   seven units are working in this tree -- so a regeneration there would trade a stale artifact
   for a half-written one, which is worse. Everything this needs is stdout from
   `graphcmp.py diff --graph G`, which has no file side effects (MEASURED: the child writes only
   the stdout it is given).

2. It reports, per graph per trial, the DENOMINATOR as well as the verdict, and it counts TRIALS
   rather than runs of `differ.py`. A pin may be written for a graph whose verdict is STABLE; a
   verdict that moved between two trials of the same tree is not a claim anybody should write
   down, and a single-trial table cannot tell the difference between `stable` and `lucky`.
"""
import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]   # unsetexp -> slop -> .agents -> repo root
OUT = Path(__file__).resolve().parent
PY, GCMP = ".venv/bin/python", ".agents/slop/graphcmp.py"
# `differ.py:44-48`, verbatim. `DEV=NULL` is the differ's own setting and `graphcmp.py --dev`
# overrides it, so this only has to match what the recorded run used.
ENV = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {"LC_ALL": "C", "DEV": "NULL"}
FIELDS = ("nodes", "shared-cores", "field-mismatches", "rung2-pairs", "rung3.5-crossrefs")


def corpus() -> list[str]:
    import importlib.util
    spec = importlib.util.spec_from_file_location("gc", ROOT / GCMP)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return sorted(mod.GRAPHS)


def probe(graph: str, trial: int) -> dict[str, str]:
    """One `diff --graph`, its raw report kept beside the row it produced."""
    dst = OUT / f"trial-{graph}-{trial}.rows"
    with dst.open("wb") as f:
        rc = subprocess.run([PY, GCMP, "diff", "--graph", graph], cwd=ROOT, env=ENV,
                            stdout=f, stderr=subprocess.DEVNULL).returncode
    text = dst.read_text(errors="replace")
    row = {"graph": graph, "trial": str(trial), "rc": str(rc)}
    row["verdict"] = re.findall(r"VERDICT: [A-Z]*", text)[-1].split()[1] if "VERDICT:" in text else ""
    denom = next((ln for ln in text.splitlines() if ln.startswith("# DENOMINATOR:")), "")
    for f in FIELDS:
        m = re.search(rf"\b{f}=(\S+)", denom)
        row[f] = m.group(1) if m else "?"
    row["nodes"] = (re.search(r"nodes=(\S+)", denom) or [None, "?"])[1] if denom else "?"
    row["rows"] = f"{len(dst.read_bytes().splitlines())}"
    # The canonical bytes, from the OTHER code path: `emit` + `cmp`, which is what `D2-cmp-*`
    # does. Recomputed here so the byte column is not read out of the shared run's artifacts.
    sides = {}
    for side in ("py", "bend"):
        p = subprocess.run([PY, GCMP, "emit", "--side", side, "--graph", graph], cwd=ROOT,
                           env=ENV, capture_output=True)
        sides[side] = p.stdout
    row["bytes"] = f"{len(sides['py'])}/{len(sides['bend'])}"
    row["canonical"] = "IDENTICAL" if sides["py"] and sides["py"] == sides["bend"] \
        else "0-BYTE" if not sides["py"] or not sides["bend"] else "DIFFERS"
    return row


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("trials", nargs="?", type=int, default=3)
    ap.add_argument("--graphs", default="")
    a = ap.parse_args()
    graphs = a.graphs.split(",") if a.graphs else corpus()
    rows = [probe(g, t) for t in range(1, a.trials + 1) for g in graphs]
    cols = ["graph", "trial", "verdict", "nodes", "shared-cores", "field-mismatches",
            "rung2-pairs", "rung3.5-crossrefs", "canonical", "bytes", "rc", "rows"]
    (OUT / "trials.tsv").write_text("\n".join(
        ["\t".join(cols)] + ["\t".join(r[c] for c in cols) for r in rows]) + "\n")
    # THE SUMMARY THAT DECIDES ANY PIN: one line per graph, and a VERDICT THAT MOVED between two
    # trials OF THE SAME TREE is named rather than averaged away.
    for g in graphs:
        seen = [(r["verdict"], r["nodes"], r["canonical"]) for r in rows if r["graph"] == g]
        verdicts = {v for v, _, _ in seen}
        stable = "STABLE" if len(verdicts) == 1 else f"MOVED {sorted(verdicts)}"
        print(f"{g:<10} {stable:<22} {seen[0][0]:<9} nodes={seen[0][1]:<7} "
              f"canonical={seen[0][2]:<10} {len(seen)} trials")
    return 0


if __name__ == "__main__":
    sys.exit(main())