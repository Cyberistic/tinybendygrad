#!/usr/bin/env python3
"""cmp.py -- THE COMPARISON FOR THE PORT's OWN `run_rangeify`.

    env -u PYTHONPATH .venv/bin/python .agents/slop/rmap/cmp.py

WHAT IT COMPARES
----------------
**THE PORT's OWN `run_rangeify` (`tinybendygrad/schedule/rangify.bend`) AGAINST **UPSTREAM's
OWN `run_rangeify` (`tinygrad/schedule/indexing.py:183`), ON THE SAME PROGRAM.**

**⇒ THE ORACLE IS `.agents/slop/rangify/rr-oracle.py`, WHICH **SPIES ON UPSTREAM's OWN
CALL** AND PRINTS UPSTREAM's OWN `realize_map`, `range_map` AND THE 27-NODE OUTPUT — **⇒ SO
NOTHING HERE IS TRANSCRIBED.**

THE THREE COMPARISONS, EACH WITH ITS OWN DENOMINATOR
----------------------------------------------------
1. **THE REALIZE MAP.** `rr_py_realize` AGAINST THE PORT's OWN `rr_realize`.
2. **THE RANGE MAP.** `rr_py_range` AGAINST THE PORT's OWN `rr_range`, **ENTRY BY ENTRY**,
   ON THE **NODE ID** AND THE **INPUT** AND **OUTPUT** AXIS LISTS.
3. **THE OUTPUT GRAPH.** `rr_py_out` AGAINST THE PORT's OWN `rr_out`, **NODE FOR NODE**,
   ORDER-FREE.

**⇒ ⇒ AND THE RANGE MAP'S COMPARISON MUST BE **HONEST ABOUT THE FIVE THAT DIFFER** — **⇒ THE
PORT CANNOT BUILD UPSTREAM's `_apply_reshape` AFFINE EXPRESSIONS (`ADD(MUL(RANGE,CONST(k)),
RANGE)`) BECAUSE IT HAS NO `UOp.sink`, NO `usum`, NO `%`/`//` AND NO `symbolic` REWRITER — **⇒
SO THE PORT's ANSWER FOR THOSE IS **THE INPUT RANGE ITSELF**, WHICH IS WHAT
`rangify.bend`'s OWN HEADER ALREADY SAYS.** **⇒ ⇒ ⇒ SO THE ROW IS **"N OF M AGREE"** AND THE
**NAMES** OF THE DIFFERING ONES ARE PRINTED, **⇒ BECAUSE A COMPARISON THAT HUNTS FOR A GREEN
VERDICT IS NOT A COMPARISON.**

THE CONTROL
-----------
**⇒ THE CONTROL IS **A ROW IN THE PORT's OWN DRIVER** (`rangify.bend`'s `rr_run_rangeify_plant`
— **THE PORT HAS NO ENV READER**, **⇒ SO A PLANT IS A **SEPARATE DEF**), AND **⇒ THE
PLANTED OUTPUT MUST DIFFER FROM THE MEASURED ONE.**
"""
import os
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent.parent
BEND = REPO / "bin" / "bend"
DRIVER = REPO / "tinybendygrad" / "schedule" / "rangify.bend"

OK = "OK  "
BAD = "BAD "


def read_oracle():
    out = {}
    for line in (HERE.parent / "rangify" / "rr_py.rows").read_text().split("\n"):
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            out[k] = v
    return out


def run_port():
    env = dict(os.environ)
    env.pop("RR_PLANT", None)
    r = subprocess.run([str(BEND), str(DRIVER)], capture_output=True, text=True, env=env)
    out = {}
    for line in r.stdout.split("\n"):
        if "=" in line:
            k, v = line.split("=", 1)
            out[k] = v
    return out, r.stderr


def nodes(dump):
    return sorted(x for x in dump.split(";") if x)


def range_entries(text):
    """`#N <NODE-STRING>:[in]->[out]` -> {N: (node, in, out)}.

    **⇒ THE NODE STRING IS ITSELF COLON-SEPARATED (`PARAM:other:CONST`,
    `RESHAPE:none:PARAM,STACK`), **⇒ SO THE NODE IS MATCHED BY "EVERYTHING UP TO THE
    FIRST `[`", WHICH IS WHAT MAKES THE TWO SIDES' DUMPS COMPARABLE WITHOUT A
    TRANSLATOR.**"""
    out = {}
    for m in re.finditer(r"#(\d+) ([^;]*?):\[([^\]]*)\]->\[([^\]]*)\]", text):
        out[int(m.group(1))] = (m.group(2), m.group(3), m.group(4))
    return out


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

    # 2. THE RANGE MAP, ENTRY BY ENTRY.
    pyE = range_entries(py.get("rr_py_range", ""))
    ptE = range_entries(port.get("rr_range", ""))
    keys = sorted(set(pyE) | set(ptE))
    agree = [k for k in keys if k in pyE and k in ptE and pyE[k] == ptE[k]]
    differ = [k for k in keys if k in pyE and k in ptE and pyE[k] != ptE[k]]
    missing = [k for k in keys if k not in ptE or k not in pyE]
    print("%sC2 the range map: %d of %d entries AGREE (denominator=%d), %d DIFFER, %d MISSING"
          % (OK if not missing else BAD, len(agree), len(keys), len(keys), len(differ), len(missing)))
    print("      agree : %s" % agree)
    print("      differ: %s" % differ)
    if missing:
        fails += 1
        print("      missing: %s" % missing)
    for k in differ:
        print("      #%d  upstream: %s" % (k, pyE[k]))
        print("      #%d  the port: %s" % (k, ptE[k]))

    # 3. THE OUTPUT GRAPH, NODE FOR NODE, ORDER-FREE.
    want_n = nodes(py.get("rr_py_out", ""))
    got_n = nodes(port.get("rr_out", ""))
    same = want_n == got_n
    print("%sC3 the output graph AGREE (denominator=%d nodes)" % (OK if same else BAD, len(want_n)))
    if not same:
        fails += 1
        print("      only in CPython: %s" % [x[:40] for x in want_n if x not in got_n][:6])
        print("      only in the port: %s" % [x[:40] for x in got_n if x not in want_n][:6])

    # 4. THE CONTROL: A PLANTED OUTPUT MUST DIFFER.
    planted = port.get("rr_out_plant", "")
    measured = port.get("rr_out", "")
    differs = planted != measured
    print("%sCONTROL (the plant row): the output DIVERGES from the measured one=%s"
          % (OK if differs else BAD, differs))
    if not differs:
        fails += 1

    # 5. THE NODE COUNTS, WHICH ARE THE PAYOFF'S PRECONDITION.
    print("#  the port's rangeified graph has %s nodes; upstream's has %s"
          % (port.get("rr_out_nodes", "?"), py.get("rr_py_out_nodes", "?")))
    print("#  the port's own schedule() answers %s kernels; the planted one answers %s"
          % (port.get("rr_lin_n", "?"), port.get("rr_lin_n_plant", "?")))

    if err.strip():
        print("# the driver's stderr:")
        for l in err.strip().split("\n")[:6]:
            print("#   %s" % l)

    print("VERDICT %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
