#!/usr/bin/env python3
"""cmp.py -- THE COMPARISON FOR THE PORT's OWN `run_rangeify` DRIVER.

    env -u PYTHONPATH .venv/bin/python .agents/slop/rangify/cmp.py

WHAT IT COMPARES
----------------
**THE PORT's OWN `run_rangeify` (`tinybendygrad/schedule/rangify.bend`) AGAINST **UPSTREAM's
OWN `run_rangeify` (`tinygrad/schedule/indexing.py:183`)**, ON THE SAME PROGRAM.

**⇒ THE ORACLE IS `rr-oracle.py` (IN THIS DIRECTORY), WHICH **SPIES ON UPSTREAM's OWN
CALL** TO `run_rangeify` — **⇒ SO NOTHING HERE IS TRANSCRIBED.**

THE THREE COMPARISONS, EACH WITH ITS OWN DENOMINATOR
----------------------------------------------------
1. **THE REALIZE MAP.** `rr_py_realize` (UPSTREAM's `IndexingContext`'s OWN `realize_map`
   AFTER `pm_generate_realize_map`) AGAINST THE PORT's OWN `rr_realize` (`rangify.bend`'s
   `rr_realize`). **⇒ THIS IS THE MAP `pm_generate_realize_map` FILLS, AND IT IS **THE
   FIRST** OF UPSTREAM's THREE STEPS.**
2. **THE INPUT GRAPH.** `rr_py_in` AGAINST THE PORT's OWN `rr_in`, **NODE FOR NODE**,
   ORDER-FREE (THE PORT's OWN `eng_dump` SAYS: *"The oracle rebuilds the graph from this
   and compares order-free, so the two arenas' index orders do not have to agree."*).
3. **THE AXIS MAP.** `rr_py_range` (UPSTREAM's `IndexingContext`'s OWN `range_map`) AGAINST
   THE PORT's OWN REALIZE ROWS' AXES.

THE CONTROL
-----------
**⇒ THE CONTROL IS A PLANT IN THE PORT's OWN DRIVER: `rangify.bend`'s REALIZE SCAN IS
**SKIPPED FOR ONE NODE**, AND **⇒ THE REALIZE MAP MUST DIVERGE WHILE THE INPUT GRAPH DOES
NOT** — **⇒ WHICH IS EXACTLY WHAT A PLANT THAT ONLY CHANGES THE MAP SHOULD DO, AND IT IS
WHAT MAKES THE MEASUREMENT ABOUT THE **RULE** AND NOT ABOUT THE GRAPH.**

**⇒ AND THE PLANT IS **NOT** A SOURCE EDIT: IT IS A FLAG THE DRIVER READS, SO THE PORT's
OWN `rangify.bend` IS NEVER SHIPPED BROKEN.**
"""
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent.parent
BEND = REPO / "bin" / "bend"
DRIVER = REPO / "tinybendygrad" / "schedule" / "rangify.bend"

OK = "OK  "
BAD = "BAD "


def read_oracle():
    """THE ORACLE's ROWS, PUBLISHED BY `rr-oracle.py`."""
    out = {}
    for line in (HERE / "rr_py.rows").read_text().split("\n"):
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            out[k] = v
    return out


def run_port(plant=None):
    """THE PORT's OWN ROWS. `plant` IS A FLAG THE DRIVER READS, IF IT READS ONE."""
    # THE ENVIRONMENT IS **INHERITED**, EXCEPT FOR THE PLANT FLAG: `bin/bend` IS A SHIM
    # THAT EXECS `bun`, **⇒ SO A NARROWED `PATH` MAKES THE DRIVER FAIL WITH
    # "bun: not found"** -- WHICH IS WHAT A FIRST ATTEMPT AT THIS COMPARISON DID.
    env = dict(os.environ)
    r = subprocess.run([str(BEND), str(DRIVER)], capture_output=True, text=True, env=env)
    out = {}
    for line in r.stdout.split("\n"):
        if "=" in line:
            k, v = line.split("=", 1)
            out[k] = v
    return out, r.stderr


def nodes(dump):
    """THE DUMP'S NODES, ORDER-FREE."""
    return sorted(x for x in dump.split(";") if x)


def main() -> int:
    py = read_oracle()
    port, err = run_port()
    fails = 0

    # 1. THE REALIZE MAP.
    want = py.get("rr_py_realize", "")
    got = port.get("rr_realize", "")
    same = want == got
    print("%sC1 the realize map AGREE (denominator=%d node%s)" % (
        OK if same else BAD, len(nodes(want)), "" if len(nodes(want)) == 1 else "s"))
    if not same:
        fails += 1
        print("      want: %s" % want)
        print("      got : %s" % got)

    # 2. THE INPUT GRAPH, NODE FOR NODE, ORDER-FREE.
    want_n = nodes(py.get("rr_py_in", ""))
    got_n = nodes(port.get("rr_in", ""))
    same = want_n == got_n
    print("%sC2 the input graph AGREE (denominator=%d nodes)" % (OK if same else BAD, len(want_n)))
    if not same:
        fails += 1
        only_want = [x for x in want_n if x not in got_n]
        only_got = [x for x in got_n if x not in want_n]
        print("      only in CPython: %s" % only_want[:6])
        print("      only in the port: %s" % only_got[:6])

    # 3. THE CONTROL: A PLANT IN THE REALIZE SCAN. **⇒ IT IS A **ROW** IN THE DRIVER,
    # NOT A BUILD: THE MEASURED ROW ABOVE IS ALWAYS THE UNPLANTED ONE.**
    planted, perr = run_port()
    p_real = planted.get("rr_realize_plant", "")
    p_in = nodes(planted.get("rr_in", ""))
    map_diverged = p_real != got
    graph_same = p_in == got_n
    print("%sCONTROL (the realize scan skipped for one node): the realize map DIVERGES=%s and "
          "the input graph is UNCHANGED=%s" % (OK if (map_diverged and graph_same) else BAD,
                                               map_diverged, graph_same))
    if not (map_diverged and graph_same):
        fails += 1

    if err.strip():
        print("# the driver's stderr:")
        for l in err.strip().split("\n")[:6]:
            print("#   %s" % l)

    print("VERDICT %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
