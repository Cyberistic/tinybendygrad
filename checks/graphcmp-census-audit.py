#!/usr/bin/env python3
"""graphcmp-census-audit.py -- can the coverage census go RED, and can its denominator move?

SUBJECT:  the numbers `.agents/slop/graphcmp-oracle.py` prints, and whether they can be
          wrong rather than merely printed.
INSTRUMENT: the LIVE oracle, loaded by path and run through its REAL `main()`, one
          subprocess per state so each census is about the device it names.

WHY ONE PROCESS PER STATE, MEASURED: `main()` REFUSES to run once `tinygrad` is imported,
because `Device.DEFAULT` freezes at import and a second census would print a device it is
not running on. `main()` is called six times below and in ONE process the second call
raises `SystemExit` -- so the earlier revision of this file was already dead on its second
state. `--all` re-invokes this file per state.

WHY `emit_bend` IS MIRRORED (the py stream) FOR THE BASELINE, AND SAID SO. The orchestrator
owns `bend` exclusively. The four PORT plants below OVERRIDE the mirror deliberately, so the
vocabulary union (`tot_ops`), the both-sides device precondition and the selfcheck are still
driven by a planted port stream. What the mirror CANNOT test is the real port; that is what
the differ's own `D0-coverage-census.txt` is for, and this file says so rather than hiding it.

READING THE ORACLE'S SOURCE (not its prose):
  `tot_ops |= py["ops"] | bd["ops"]`   -> "N distinct" is a UNION of both sides
  `tal.update(py["per_op"])`           -> the per-op table, and NOT REACHED, are PY ONLY
  `program_op_split(sections, tal)`    -> the corrected denominator, PY-side and enum-side
So the two halves of `N of 77` are built from DIFFERENT SIDES, and they coincide only
because the port reaches a SUBSET of the py ops today.
"""
from __future__ import annotations
import contextlib
import importlib.util
import io
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, ".agents", "slop"))
os.environ.pop("PYTHONPATH", None)
os.environ["PYTHONHASHSEED"] = "0"
os.environ["LC_ALL"] = "C"
os.environ["DEV"] = "CPU"

import graphcmp as G  # noqa: E402

# THE CORPUS IS LIVE. `OPDENOM_PIN` restricts `G.GRAPHS` to the list RECORDED in an artifact
# (column 1 of its two-space-indented table), so the states below are comparable to the
# baseline the artifact holds even while another unit is adding graphs to `graphcmp.py`.
# Without a pin the audit runs on whatever corpus exists, which is the gate's normal mode.
_PIN = os.environ.get("OPDENOM_PIN")
if _PIN:
    _names = {ln.split()[0] for ln in open(_PIN).read().splitlines()
              if ln.startswith("  ") and ln.split()}
    _dropped = sorted(set(G.GRAPHS) - _names)
    for _k in _dropped:
        del G.GRAPHS[_k]
    print(f"# PINNED to {len(G.GRAPHS)} graphs from {_PIN} (dropped {_dropped})")

FIELDS = ("graphs", "nodes", "distinct", "not_reached", "by_construction", "unexercised",
          "program", "selfcheck", "rc", "names")


def _oracle():
    spec = importlib.util.spec_from_file_location(
        "graphcmp_oracle", os.path.join(REPO, ".agents", "slop", "graphcmp-oracle.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _mirror(dev, graph, *a, **k):
    """A declared plant: the port stream is the py stream. Keeps the both-sides precondition
    satisfiable and exercises every assertion without spawning a compiler."""
    return (G.emit_py(graph, None), ["(emit_bend mirrored -- no bend process)"])


def _grab(text, pat, default="?"):
    m = re.search(pat, text)
    return m.group(1) if m else default


def measure(state: str, mutate=None) -> dict:
    """Run the oracle's real `main()` ONCE and parse what it PRINTS. `mutate` is applied after
    the mirror and may override `emit_bend`/`emit_py` for a PORT or DISARM plant."""
    O = _oracle()
    G.emit_bend = _mirror
    if mutate:
        mutate()
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = O.main()
    text = buf.getvalue()
    return {
        "graphs": _grab(text, r"TOTAL: (\d+) graphs"),
        "nodes": _grab(text, r"graphs, (\d+) nodes per side"),
        "distinct": int(_grab(text, r"nodes per side, (\d+) distinct ops")),
        "not_reached": int(_grab(text, r"NOT REACHED \((\d+) of \d+")),
        "by_construction": int(_grab(text, r"OF WHICH (\d+) CANNOT APPEAR")),
        "unexercised": int(_grab(text, r"AND (\d+) ARE PROGRAM OPS")),
        "program": int(_grab(text, r"-> (\d+) PROGRAM OPS")),
        "selfcheck": _grab(text, r"ORACLE SELFCHECK: (\w+)"),
        "rc": rc,
        "names": _grab(text, r"distinct ops: (.*)"),
    }


def drop_three():
    for g in ("lin", "loop", "gate"):
        G.GRAPHS.pop(g, None)


def kill_bend():
    G.emit_bend = lambda dev, graph, *a, **k: ([], ["PLANT: bend emits 0 rows"])


def bend_invents_op():
    fake = "2:n0 8:INVENTED 7:weakint 2:() 2:n0 1:N 4:l0:4 3:n()"
    G.emit_bend = lambda dev, graph, *a, **k: ([fake], ["PLANT"])


def kill_py():
    G.emit_py = lambda graph, plant, *a, **k: []


def drop_sole_op():
    """Remove the op the corpus reaches in EXACTLY ONE graph -- the only removal that moves
    the reached set. DISCOVERED from the corpus, lazily on the first emission, because
    tinygrad is loaded by `main()` and the oracle refuses to run after an early import."""
    orig = G.emit_py
    st: dict = {"done": False}

    def wrapper(graph, plant, *a, **k):
        if not st["done"]:
            from collections import Counter
            gof: Counter = Counter()
            for g in sorted(G.GRAPHS):
                gof.update({G.unchunks(ln)[1] for ln in orig(g, None)})
            st["op"] = min(op for op, c in gof.items() if c == 1)
            st["graph"] = next(g for g in sorted(G.GRAPHS)
                               if any(G.unchunks(ln)[1] == st["op"] for ln in orig(g, None)))
            st["done"] = True
            print(f"# PLANT drop-sole-op: removing `{st['op']}` from `{st['graph']}`")
        rows = orig(graph, plant, *a, **k)
        return [r for r in rows if G.unchunks(r)[1] != st["op"]] if graph == st["graph"] else rows
    G.emit_py = wrapper


STATES = (
    ("baseline", None, "BASELINE  both sides, emit_bend mirrored"),
    ("drop-three", drop_three, "PLANT 1  drop lin/loop/gate from the corpus"),
    ("port-dead", kill_bend, "PLANT 2  PORT DEAD: emit_bend returns 0 rows"),
    ("port-invents", bend_invents_op, "PLANT 3  PORT INVENTS: bend prints an op not in Ops"),
    ("drop-sole-op", drop_sole_op, "PLANT 4  remove the op only ONE graph reaches"),
    ("py-dead", kill_py, "DISARM 1  py side 0 rows (the side NOT REACHED reads)"),
)


def one(name: str) -> int:
    mutate = next(m for n, m, _ in STATES if n == name)
    label = next(l for n, _, l in STATES if n == name)
    got = measure(name, mutate)
    print(f"{label}")
    print(f"    graphs={got['graphs']} nodes={got['nodes']} distinct={got['distinct']} "
          f"NOT REACHED={got['not_reached']} [by-construction={got['by_construction']} "
          f"unexercised={got['unexercised']}] of {got['program']} program ops, "
          f"SELFCHECK {got['selfcheck']} (rc={got['rc']})")
    return got["rc"] if got["selfcheck"] == "OK" else 0  # a RED selfcheck is this file's point


if __name__ == "__main__":
    print("=" * 78)
    print("DENOMINATOR  len(list(Ops)) is printed by the oracle per state, read live (CPython)")
    print("=" * 78)
    if len(sys.argv) > 1 and sys.argv[1] == "--all":
        for name, _, _ in STATES:
            subprocess.run([sys.executable, os.path.abspath(__file__), name])
        raise SystemExit(0)
    sys.exit(one(sys.argv[1] if len(sys.argv) > 1 else "baseline"))
