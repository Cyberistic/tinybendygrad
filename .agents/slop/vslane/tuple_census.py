#!/usr/bin/env python3
"""DOES UPSTREAM's `exec_alu` TUPLE BRANCH EVER FIRE ON THIS TREE's POPULATION?

    .venv/bin/python .agents/slop/vslane/tuple_census.py

**THE QUESTION.** `tinygrad/uop/ops.py:1423` is
    if any(isinstance(x, tuple) for x in operands):
and the port's `symbolic.bend` says it is DEFERRED. **THE TASK THIS UNIT WAS
GIVEN SAYS THAT BRANCH IS THE CAUSE OF 29 DIVERGENCES.** SO: DOES IT EVER
FIRE?

**THE MEASUREMENT.** `exec_alu` IS UPSTREAM's OWN FUNCTION AND IT IS CALLED
FROM `tinygrad/runtime/ops_python.py:158`, SO WRAPPING IT OBSERVES EVERY ALU
OP OF EVERY FIXTURE. THE WRAPPER COUNTS TWO THINGS: THE CALLS, AND THE CALLS
WHOSE OPERANDS CONTAIN A TUPLE (WHICH IS EXACTLY THE BRANCH'S CONDITION).

**THE POPULATION** IS THE TREE's OWN `gates/ops_python_exec-fixtures.rows`,
READ IN PLACE, AND THE UOPS COME FROM RE-HARVESTING THE TREE'S OWN SEEDS
(`gates/ops_python_exec-gen.py`'s `SEEDS`), SO NOTHING HERE IS TYPED.
"""
import ctypes
import pathlib
import pickle
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "gates"))
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location("ops_python_exec_gen", ROOT / "gates" / "ops_python_exec-gen.py")
GEN = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(GEN)

from tinygrad import Tensor                                          # noqa: E402
from tinygrad.dtype import dtypes                                    # noqa: E402
from tinygrad.helpers import Context, Target, to_mv                  # noqa: E402
from tinygrad.runtime import ops_python as OPY                       # noqa: E402
from tinygrad.uop import ops as OPS                                  # noqa: E402



class Elf:
    def __init__(self, uops, target): self.lib, self.target = pickle.dumps(uops), target


def main():
    calls = {"n": 0, "tuple": 0, "ops": {}, "tuple_ops": {}}
    real = OPS.exec_alu

    def spy(op, dtype, operands, truncate_output=True):
        calls["n"] += 1
        calls["ops"][op.name] = calls["ops"].get(op.name, 0) + 1
        if any(isinstance(x, tuple) for x in operands):
            calls["tuple"] += 1
            calls["tuple_ops"][op.name] = calls["tuple_ops"].get(op.name, 0) + 1
        return real(op, dtype, operands, truncate_output)

    OPY.exec_alu = spy
    try:
        n, canon = GEN.sweep(lambda f, _: GEN.py_rows(f))
    finally:
        OPY.exec_alu = real
    print(f"# fixtures: {n}")
    print(f"# exec_alu CALLS: {calls['n']}")
    print(f"# CALLS WHOSE OPERANDS CONTAIN A TUPLE (the branch's condition): {calls['tuple']}")
    print(f"# OPS SEEN: {sorted(calls['ops'])}")
    print(f"# OPS THAT SAW A TUPLE: {sorted(calls['tuple_ops'])}")
    print(f"# CALLS PER OP: {dict(sorted(calls['ops'].items()))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
