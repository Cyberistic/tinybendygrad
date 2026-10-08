#!/usr/bin/env python3
"""tn_minimum-gate.py -- THE GATE for "which `Ops` does CPython have that the port lacks".

    .venv/bin/python gates/tn_minimum-gate.py

THE ANSWER IS: NONE. The brief that spawned this gate believed `Tensor.minimum`
was walled on a missing `OpsMIN{}`; that is false twice over. CPython's `Ops`
has no `MIN` member at all -- `minimum` (mixin/elementwise.py:393) is built from
`Ops.MAX` -- and the port's `Ops` and CPython's `Ops` are the SAME 77 members,
so no constructor is missing in either direction.

TWO LANES, BOTH BY DISCOVERY, AND NEITHER READS THE OTHER'S SOURCE:

  py  CPython's enum, from the interpreter via `tn_minimum-oracle.py`
      (`list(Ops)` -- a generator's own declaration, not a hand list).
  bd  the port's constructors, from `tinybendygrad/uop/ops.bend` by regex.

A BEND LANE IS DELIBERATELY ABSENT. `gatekit`'s canonical shape diffs a `.bend`
driver against the oracle, but the subject here is the SET of constructors,
which lives in the port's source text; a `.bend` driver cannot enumerate `Data`
variants without a hand list, and a hand list is exactly the population a gate
must not declare by. So the port lane reads the file it is about.

FIVE ROWS. `missing_from_port` and `extra_in_port` are the two directions of the
set difference; both must be 0. `min_in_cpython` must be 0. A mutation that adds
a constructor to `ops.bend` makes `extra_in_port` 1; one that deletes a
constructor makes `missing_from_port` 1. Both go RED.
"""

import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY = ROOT / ".venv" / "bin" / "python"
ORACLE = HERE / "tn_minimum-oracle.py"
OPS = ROOT / "tinybendygrad" / "uop" / "ops.bend"

VARIANT = re.compile(r"^  Ops([A-Z_0-9]+)\{\}", re.M)


def cpython_lane():
    r = subprocess.run([str(PY), str(ORACLE)], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"the oracle failed rc={r.returncode}: {r.stderr.strip()[:200]}",
              file=sys.stderr)
        return None
    rows = dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)
    names = rows["cpython_ops"].split(",") if rows["cpython_ops"] else []
    return names, int(rows["min_in_cpython"])


def port_lane():
    return VARIANT.findall(OPS.read_text())


def main():
    cp = cpython_lane()
    if cp is None:
        return 3  # REFUSED: the CPython witness did not run
    py, min_in_cpython = cp
    bd = port_lane()

    missing = sorted(set(py) - set(bd))
    extra = sorted(set(bd) - set(py))
    rows = {
        "cpython_ops_count": len(py),
        "port_ops_count": len(bd),
        "missing_from_port": len(missing),
        "extra_in_port": len(extra),
        "min_in_cpython": min_in_cpython,
    }
    for name, value in rows.items():
        print(f"{name}={value}")

    ok = (rows["missing_from_port"] == 0 and rows["extra_in_port"] == 0
          and rows["cpython_ops_count"] == rows["port_ops_count"]
          and rows["min_in_cpython"] == 0)
    if ok:
        print(f"tn_minimum-gate: PASS -- CPython `Ops` and the port's `Ops` are the "
              f"SAME {rows['port_ops_count']} members, and CPython has no MIN")
    else:
        print(f"tn_minimum-gate: FAIL -- missing_from_port={missing} "
              f"extra_in_port={extra}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
