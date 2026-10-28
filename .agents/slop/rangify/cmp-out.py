#!/usr/bin/env python3
"""cmp-out.py -- THE PORT's `run_rangeify` OUTPUT AGAINST CPYTHON's.

    env -u PYTHONPATH .venv/bin/python .agents/slop/rangify/cmp-out.py

WHAT THIS FILE IS
-----------------
`tinygrad/schedule/indexing.py:183` is upstream's `run_rangeify`, and
`.agents/slop/rangify/rr-oracle.py` SPIES ON UPSTREAM's OWN CALL to it and
PRINTS THE GRAPH IT RETURNS (`rr_py_out`).  **THE PORT's OWN
`tinybendygrad/schedule/rangify.bend` PRINTS ITS OWN** (`rr_out`), **IN THE
SAME SPELLING** (`op:argkey:srcops`, JOINED BY `;`), **=> SO THE COMPARISON IS
**WHOLE-STRING** WITH **NO TRANSLATOR**.**

THE COMPARISON IS **OVER MULTISETS**, NOT OVER ORDER: the port's `rr_dump` AND
the oracle's `dump` ARE **BOTH** DFS FROM THE ROOT, **=> SO THE ORDER IS THE
SAME TRAVERSAL**, **=> AND THE COMPARISON IS STILL A MULTISET** BECAUSE THE
TRAVERSAL IS NOT THE SUBJECT.

THE COST: **ONE CPYTHON PROCESS FOR THE ORACLE, ~2 s, AND ONE BEND PROCESS
FOR THE PORT, ~1 s.**
"""
import collections
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent


def port_rows() -> dict:
    """RUN THE PORT AND READ ITS ROWS."""
    out = subprocess.run(["./bin/bend", "tinybendygrad/schedule/rangify.bend"],
                         cwd=ROOT, capture_output=True, text=True, timeout=600)
    rows = {}
    for line in out.stdout.splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            rows[k] = v
    return rows


def nodes(row: str) -> list:
    """THE NODE LIST OF A DUMP ROW."""
    return [n for n in row.split(";") if n]


def main() -> int:
    port = port_rows()
    py = {}
    for line in (HERE / "rr_py.rows").read_text().splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            py[k] = v

    p_nodes = nodes(port.get("rr_out", ""))
    c_nodes = nodes(py.get("rr_py_out", ""))
    pc = collections.Counter(p_nodes)
    cc = collections.Counter(c_nodes)

    print("=== THE PORT's `rr_out`")
    print("port_nodes=%d" % len(p_nodes))
    print("=== CPYTHON's `rr_py_out`")
    print("cpython_nodes=%d" % len(c_nodes))
    only_port = sorted((pc - cc).elements())
    only_cpy = sorted((cc - pc).elements())
    print("=== AGREE=%d  ONLY-PORT=%d  ONLY-CPYTHON=%d" %
          (len(set(pc) & set(cc)), len(only_port), len(only_cpy)))
    print("--- ONLY IN THE PORT")
    for n in only_port:
        print("  P %s" % n)
    print("--- ONLY IN CPYTHON")
    for n in only_cpy:
        print("  C %s" % n)
    print("--- THE OP CENSUS")
    print("port   : %s" % sorted({n.split(":")[0] for n in p_nodes}))
    print("cpython: %s" % sorted({n.split(":")[0] for n in c_nodes}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
