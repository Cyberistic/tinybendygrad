#!/usr/bin/env python3
"""tn_minimum-gate.py -- THE GATE for "which `Ops` does CPython have that the port lacks".

    .venv/bin/python gates/tn_minimum-gate.py

THE ANSWER IS: NONE. The brief that spawned this gate believed `Tensor.minimum`
was walled on a missing `OpsMIN{}`; that is false twice over. CPython's `Ops`
has no `MIN` member at all -- `minimum` (mixin/elementwise.py:393) is built from
`Ops.MAX` -- and the port's `Ops` and CPython's `Ops` are the SAME member SET,
so no constructor is missing in either direction. THE FIGURE IS NOT WRITTEN HERE: it is an
OUTPUT of this gate and not an input to it, so run `.venv/bin/python
gates/tn_minimum-gate.py` rather than believe this paragraph -- `cpython_ops_count` and
`port_ops_count` are the two halves and `missing_from_port` / `extra_in_port` are what make
"the same" checkable instead of adjectival.

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

THE SIXTH ROW IS AN ORDER ROW, AND IT IS A DIFFERENT KIND OF CLAIM. `tinygrad/uop/__init__.py:12`
says, in upstream's own file: `# the order of these Ops controls the order of the
toposort`. The five rows above are all SETS, so every one of them reads PASS on a
reordered enum -- `set(x) == set(y)` cannot see a permutation. `declaration_order_match`
compares the two declaration orders POSITIONALLY and is 1 only if they are the same
permutation.

WHAT IT HONOURS AND WHAT IT MEASURES, BECAUSE THE TWO ARE NOT THE SAME THING. MEASURED
2026-10-18T18:01:50Z against `refs/remotes/upstream/HEAD` (`002630241913`, NOT
re-fetched): `git grep -e 'for [a-z_]* in Ops\\b' -e 'list(Ops)' -e 'Ops.__members__'
refs/remotes/upstream/HEAD -- tinygrad` exits rc=1, ZERO hits, and
`tinygrad/uop/ops.py:286 toposort()` is a stack walk over `node.src` that never reads the
enum. **NO UPSTREAM CODE PATH CONSUMES THE ORDER.** So this row HONOURS A CLAIM UPSTREAM
MAKES IN A COMMENT; it does not measure an upstream behaviour, and the PASS line below
prints that distinction rather than leaving it in a docstring. What it DOES measure is
this project's: that the port's declaration order still agrees with upstream's.
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
    decl = rows["cpython_ops_decl"].split(",") if rows["cpython_ops_decl"] else []
    return names, decl, int(rows["min_in_cpython"])


def port_lane():
    return VARIANT.findall(OPS.read_text())


def main():
    cp = cpython_lane()
    if cp is None:
        return 3  # REFUSED: the CPython witness did not run
    py, py_decl, min_in_cpython = cp
    bd = port_lane()

    missing = sorted(set(py) - set(bd))
    extra = sorted(set(bd) - set(py))
    # THE ORDER ROW. An empty declaration list is `REFUSED`-shaped, not `equal`: two empty
    # lists compare equal, so a lane that read nothing would score 1 and be INDISTINGUISHABLE
    # from agreement -- `gates/prose-census.py`'s own `PLANT empty` state, in one operator.
    order_ok = int(bool(py_decl) and py_decl == bd)
    divergence = next((i for i, (a, b) in enumerate(zip(py_decl, bd)) if a != b),
                      min(len(py_decl), len(bd)))
    rows = {
        "cpython_ops_count": len(py),
        "port_ops_count": len(bd),
        "missing_from_port": len(missing),
        "extra_in_port": len(extra),
        "min_in_cpython": min_in_cpython,
        "declaration_order_match": order_ok,
        "declaration_order_first_divergence": divergence if not order_ok else -1,
    }
    for name, value in rows.items():
        print(f"{name}={value}")

    ok = (rows["missing_from_port"] == 0 and rows["extra_in_port"] == 0
          and rows["cpython_ops_count"] == rows["port_ops_count"]
          and rows["min_in_cpython"] == 0 and order_ok == 1)
    if ok:
        print(f"tn_minimum-gate: PASS -- CPython `Ops` and the port's `Ops` are the "
              f"SAME {rows['port_ops_count']} members, in the SAME declaration order "
              f"(0..{rows['port_ops_count'] - 1}), and CPython has no MIN")
        print("ORDER CLAIM: HONOURED, NOT MEASURED -- `tinygrad/uop/__init__.py:12` states "
              "the order controls the toposort and NO upstream code path reads the enum's "
              "order (0 hits for `for .. in Ops` / `list(Ops)` / `Ops.__members__` at "
              "refs/remotes/upstream/HEAD, and `tinygrad/uop/ops.py:286 toposort()` is a "
              "stack walk over node.src). This row checks the PORT against that comment; it "
              "is not evidence that upstream consumes the order.")
    else:
        print(f"tn_minimum-gate: FAIL -- missing_from_port={missing} "
              f"extra_in_port={extra} "
              f"declaration_order_first_divergence={rows['declaration_order_first_divergence']}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
