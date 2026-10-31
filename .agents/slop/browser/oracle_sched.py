#!/usr/bin/env python3
"""oracle_sched.py -- CPython's OWN ANSWER for THE PORT's OWN PROGRAM.

    .venv/bin/python .agents/slop/browser/oracle_sched.py

WHAT IT ANSWERS, AND THE DENOMINATOR IS STATED:

  1. `py_lin_raw`   -- `create_schedule(sink)` on the port's own program, AS-IS.
  2. `py_lin_ranged`-- `create_schedule(get_kernel_graph(prepare_rangeify(sink)))`,
                       which is UPSTREAM's OWN SHAPE
                       (`tinygrad/schedule/__init__.py:132`:
                       `create_schedule(get_kernel_graph(prepare_rangeify(function)))`).
  3. `py_ops`       -- THE SAME FINGERPRINT THE PORT's `bridge_ops` PRINTS:
                       `gate.ops` IS A DIGIT OVER THE OPS OF A KERNEL'S SRCS,
                       BASE 10, LEFT TO RIGHT (`schedule/__init__.bend:2258`).

THE PROGRAM IS THE PORT's OWN `realize.bend`'s `rz_program`, AND IT IS
TRANSCRIBED HERE LINE FOR LINE:

    dst = buffer(20) reshaped (4,5)
    lhs = buffer(12) reshaped (4,3)
    rhs = buffer(15) reshaped (3,5)
    val = (lhs.reshape(4,1,3) * rhs.reshape(1,3,5).permute(0,2,1)).sum(-1)
    dst.assign(val)
    sink(dst)

**⇒ AND THE `sum(-1)` IS `rz_reduce`'s `(2,0,1)` PERMUTE PLUS `AReduce{ADD,1}`**,
which is upstream's `_rop` (`tinygrad/uop/ops.py:633-643`): the reduced axes
move to the FRONT and the reduce's arg is `(op, len(reduce_axis))`.

**⇒ AND NOTHING HERE IS TRANSCRIBED FROM THE PORT's OUTPUT.** The expectation
is CPython's OWN answer, computed by CPython's OWN scheduler, on the SAME
program.
"""
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))

from tinygrad import Tensor, Context  # noqa: E402
from tinygrad.schedule import create_schedule  # noqa: E402
from tinygrad.schedule.rangeify import get_kernel_graph  # noqa: E402
from tinygrad.schedule.prepare import prepare_rangeify  # noqa: E402
from tinygrad.uop.ops import Ops  # noqa: E402


def build():
    """THE PORT's OWN PROGRAM."""
    dst = Tensor.empty(20).realize().reshape(4, 5)
    lhs = Tensor.empty(12).realize().reshape(4, 3)
    rhs = Tensor.empty(15).realize().reshape(3, 5)
    val = (lhs.reshape(4, 1, 3) * rhs.reshape(1, 3, 5).permute(0, 2, 1)).sum(-1)
    dst.assign(val)
    return dst


# THE PORT's OWN `gate.code` (`schedule/__init__.bend:2190`) -- **THE PORT'S
# OWN SYMBOLIC OP CODES**, NOT `Ops.value`. **⇒ AND THIS IS THE WHOLE
# DIFFERENCE BETWEEN THE TWO FINGERPRINTS**: the port's `gate.ops` is a digit
# over `gate.code(op)` and this oracle's first version used `Ops.value`, so the
# two numbers were computed over DIFFERENT ALPHABETS and were not comparable.
#
# **⇒ AND THE TABLE IS COPIED HERE, AND IT IS COPIED FROM THE PORT's OWN
# SOURCE, WHICH IS THE POINT**: the oracle is allowed to name the port's
# vocabulary, because the QUESTION is "does the port's own kernel have the same
# SHAPE as CPython's", and the shape is expressed in the port's alphabet.
GATE_CODE = {
    Ops.BUFFER: 1, Ops.AFTER: 2, Ops.PARAM: 3, Ops.CALL: 4, Ops.END: 5,
    Ops.STORE: 6, Ops.SINK: 7, Ops.SPECIAL: 8, Ops.CONST: 9, Ops.NOOP: 99,
    Ops.LINEAR: 10, Ops.MSTACK: 11, Ops.STAGE: 12,
}


def gate_ops(kernels):
    """THE PORT's OWN `gate.ops` (`schedule/__init__.bend:2258`), in CPython.

    `gate.ops.of(ss, ar, acc)` folds `acc = acc*10 + code(op)` over the OP's
    SRCS, LEFT TO RIGHT -- so the DIGIT IS BASE 10 OVER THE OPS IN SOURCE
    ORDER.
    """
    acc = 0
    for k in kernels:
        for s in k.src:
            acc = acc * 10 + GATE_CODE.get(s.op, 0)
    return acc


def main():
    with Context(DEV="CPU"):
        y = build()
    sink = y.uop

    raw = create_schedule(sink)
    print(f"py_lin_raw={len(raw.src)}")

    prep = prepare_rangeify(sink)
    kg = get_kernel_graph(prep)
    ranged = create_schedule(kg)
    print(f"py_lin_ranged={len(ranged.src)}")
    print(f"py_ops={gate_ops(ranged.src)}")
    for i, s in enumerate(ranged.src):
        print(f"py_kernel[{i}]={s.op}")


if __name__ == "__main__":
    main()
