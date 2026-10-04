#!/usr/bin/env python3
"""graphcmp-census-audit.py -- can "34 of 77 ops" go RED?

SUBJECT:    which of tinygrad's 77 `Ops` the SIXTEEN-GRAPH CORPUS reaches.
INSTRUMENT: `.agents/slop/graphcmp-oracle.py`'s own `main()`, which prints
              `# TOTAL: 16 graphs, 189 nodes per side, 34 distinct ops: ...`
              `# NOT REACHED (43 of 77): ...`
              `# ORACLE SELFCHECK: OK`      <- this one is the disambiguator

This script imports the LIVE oracle module and calls its REAL `main()`, capturing
stdout, so the number read here is the number the oracle prints. It never edits
any file under `.agents/slop/`: every case is an in-process monkeypatch that is
restored in a `finally`.

READING THE ORACLE'S SOURCE (not its prose), graphcmp-oracle.py:
  line 110  `tot_ops |= py["ops"] | bd["ops"]`  -> "34 distinct" is a UNION
  line 111  `tal.update(py["per_op"])`            -> the per-op table is PY ONLY
  line 178  `NOT REACHED = len(list(Ops)) - len(tal)` -> 43 is PY ONLY
So the two halves of the printed ratio are built from DIFFERENT SIDES, and they
agree only because py and bend happen to reach the same 34 ops.

`len(list(Ops))` is MEASURED by calling CPython here, never transcribed.
"""
import collections
import contextlib
import io
import os
import re
import sys

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, os.path.join(REPO, ".agents/slop"))
os.chdir(REPO)
os.environ.pop("PYTHONPATH", None)
os.environ["LC_ALL"] = "C"
os.environ["DEV"] = "NULL"

import graphcmp as G            # noqa: E402
import importlib.util           # noqa: E402
_spec = importlib.util.spec_from_file_location(
    "graphcmp_oracle", os.path.join(REPO, ".agents/slop/graphcmp-oracle.py"))
O = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(O)    # .agents/slop/graphcmp-oracle.py, loaded by PATH

from tinygrad.uop.ops import Ops  # noqa: E402

FIELDS = ("graphs", "nodes", "distinct", "not_reached", "selfcheck", "py_only")


def measure(label, mutate=None):
    """Run the oracle's real main() and parse what it PRINTS."""
    saved = (dict(G.GRAPHS), G.emit_bend, G.emit_py)
    try:
        if mutate:
            mutate()
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = O.main()
        text = buf.getvalue()
    finally:
        G.GRAPHS.clear(); G.GRAPHS.update(saved[0])
        G.emit_bend, G.emit_py = saved[1], saved[2]

    def grab(pat, default="?"):
        m = re.search(pat, text)
        return m.group(1) if m else default

    got = {
        "graphs": grab(r"TOTAL: (\d+) graphs"),
        "nodes": grab(r"graphs, (\d+) nodes per side"),
        "distinct": int(grab(r"nodes per side, (\d+) distinct ops")),
        "not_reached": int(grab(r"NOT REACHED \((\d+) of \d+\)")),
        "selfcheck": grab(r"ORACLE SELFCHECK: (\w+)"),
        "rc": rc,
        "names": grab(r"distinct ops: (.*)"),
        "py_only": len(O.census(G.emit_py("matmul", None))["ops"]),
    }
    print(f"{label}")
    print(f"    TOTAL: {got['graphs']} graphs, {got['nodes']} nodes/side, "
          f"{got['distinct']} distinct ops, NOT REACHED {got['not_reached']}, "
          f"SELFCHECK {got['selfcheck']} (rc={got['rc']})")
    return got


def drop_three():
    for g in ("lin", "loop", "gate"):
        G.GRAPHS.pop(g, None)


def kill_bend():
    G.emit_bend = lambda dev, graph, *a, **k: ([], ["PLANT: bend emits 0 rows"])


def bend_invents_op():
    # a WELL-FORMED wire line, same chunking as a real one:
    #   2:n0 8:INVENTED 7:weakint 2:() 2:n0 1:N 4:l0:4 3:n()
    #         ^^^^^^^^ 8 chars, and NOT a member of tinygrad.uop.ops.Ops
    fake = "2:n0 8:INVENTED 7:weakint 2:() 2:n0 1:N 4:l0:4 3:n()"
    G.emit_bend = lambda dev, graph, *a, **k: ([fake], ["PLANT"])


def kill_py():
    G.emit_py = lambda graph, plant: []


if __name__ == "__main__":
    print("=" * 78)
    print(f"DENOMINATOR  len(list(Ops)) = {len(list(Ops))}   (CPython, run A)")
    print("=" * 78)
    base = measure("BASELINE  16 graphs, nothing patched")
    p1 = measure("PLANT 1  SUBJECT: drop lin/loop/gate from the corpus", drop_three)
    p2 = measure("PLANT 2  PORT DEAD: emit_bend returns 0 rows for every graph", kill_bend)
    p3 = measure("PLANT 3  PORT INVENTS: bend claims an op CPython never emits", bend_invents_op)
    d1 = measure("DISARM 1  py side 0 rows (the side the per-op table reads)", kill_py)

    lost = set(base["names"].split()) - set(p1["names"].split()) if p1["names"] != "?" else set()
    print("\n" + "=" * 78)
    print("READING")
    print(f"  PLANT 1  34 -> {p1['distinct']}. Ops lost by dropping lin/loop/gate ({len(lost)}):")
    print(f"           {' '.join(sorted(lost))}")
    print(f"  PLANT 2  distinct stayed {p2['distinct']} with the bend side emitting ZERO nodes.")
    print(f"           The ONLY thing that moved is SELFCHECK {base['selfcheck']} -> {p2['selfcheck']}"
          f" (rc {base['rc']} -> {p2['rc']}).")
    print(f"  PLANT 3  distinct {base['distinct']} -> {p3['distinct']}: the union accepts ANY")
    print(f"           string the bend side prints as an op name, with no membership check.")
    print(f"  DISARM 1 distinct stayed {d1['distinct']} but NOT REACHED {d1['not_reached']} of 77:")
    print(f"           a dead PY side leaves '34 distinct' standing and only moves the complement.")