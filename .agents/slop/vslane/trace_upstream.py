#!/usr/bin/env python3
"""WHAT UPSTREAM's `PythonProgram.__call__` ACTUALLY PUTS IN `values`, FOR ONE FIXTURE.

    .venv/bin/python .agents/slop/vslane/trace_upstream.py <fixture-name>

THE ORACLE IS UPSTREAM's OWN SOURCE, AND THIS INSTRUMENT READS IT RATHER THAN
GUESSING IT. `tinygrad/runtime/ops_python.py`'s `PythonProgram.__call__` keeps its
arena in a LOCAL `values` dict, so the only way to see it is to wrap the two
functions it calls: `exec_alu` (the ALU) and `PythonProgram.__call__` itself.

`exec_alu` IS `tinygrad/uop/ops.py:1422` (imported into ops_python.py:12), so
wrapping it observes UPSTREAM's OWN tuple branch, with its own arguments, at every
ALU op of the packet.

THE FIXTURE IS THE TREE's OWN (`gates/ops_python_exec-fixtures.rows`), READ IN
PLACE, AND THE UOPS COME FROM RE-HARVESTING THE SAME EXPRESSION, SO NOTHING HERE
IS TYPED.
"""
import ctypes, pathlib, pickle, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad import Tensor                                          # noqa: E402
from tinygrad.dtype import dtypes                                    # noqa: E402
from tinygrad.helpers import Context, Target, to_mv                  # noqa: E402
from tinygrad.runtime import ops_python as OPY                       # noqa: E402
from tinygrad.uop import ops as OPS                                  # noqa: E402

FIXTURES = ROOT / "gates" / "ops_python_exec-fixtures.rows"

SEED_VALUES = {
    dtypes.float: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0],
    dtypes.int: [1, 2, 3, 4, 5, 6, 7, 8],
    dtypes.uint: [1, 2, 3, 4, 5, 6, 7, 8],
    dtypes.bool: [1, 0, 1, 0, 1, 0, 1, 0],
}


class Elf:
    def __init__(self, uops, target): self.lib, self.target = pickle.dumps(uops), target


def records():
    recs, cur = [], None
    for ln in FIXTURES.read_text().splitlines():
        if ln.startswith("@ "):
            cur = [ln.split()[1:], []]
            recs.append(cur)
        elif cur is not None and ln.strip():
            cur[1].append(ln)
    return recs


def harvest(fn):
    """`[(uops, bufs, gsize, vals)]` -- the real launches, captured at the boundary."""
    renders, calls = [], []
    _render, _call = OPY.PythonRenderer.render, OPY.PythonProgram.__call__

    def render(self, uops):
        renders.append(list(uops)); return _render(self, uops)

    def call(self, *bufs, **kw):
        calls.append(([bytes(to_mv(a, 32)) for a in bufs],
                      tuple(kw.get("global_size", (1, 1, 1))), kw.get("vals", ())))
        return _call(self, *bufs, **kw)

    OPY.PythonRenderer.render, OPY.PythonProgram.__call__ = render, call
    try:
        with Context(DEV="PYTHON"):
            fn()
    finally:
        OPY.PythonRenderer.render, OPY.PythonProgram.__call__ = _render, _call
    return renders, calls


def main():
    want = sys.argv[1]
    dt, seed = {
        "f32": (dtypes.float, "sqrt"), "i32": (dtypes.int, "sqrt"),
        "u32": (dtypes.uint, "sqrt"), "bool": (dtypes.bool, "neg"),
    }[want.split(".")[0]]

    if want.startswith("bool."):
        maker = lambda: (Tensor(SEED_VALUES[dtypes.bool], dtype=dtypes.bool) == 1).realize()
    else:
        maker = lambda: Tensor(SEED_VALUES[dt], dtype=dt).abs().sqrt().realize()

    renders, calls = harvest(maker)
    print(f"# {want}: {len(renders)} renders, {len(calls)} calls")
    uops = renders[-1]
    for i, u in enumerate(uops):
        try:
            mn = u.max_numel()
        except Exception:                                                 # noqa: BLE001
            mn = "?"
        print(f"  uop {i + 1}: {u.op.name} {u.dtype.name} arg={u.arg!r} "
              f"max_numel={mn} srcs={[s.op.name for s in u.src]}")

    # THE ORACLE'S OWN `exec_alu`, WRAPPED.
    real = OPS.exec_alu
    log = []

    def spy(op, dtype, operands, truncate_output=True):
        r = real(op, dtype, operands, truncate_output)
        log.append((op.name, dtype.name, operands, r))
        return r

    OPY.exec_alu = spy
    try:
        bufs = [bytearray(b) for b in calls[-1][0]]
        prog = OPY.PythonProgram.__new__(OPY.PythonProgram)
        prog.__init__(None, Elf(uops, Target(renderer="PYTHON")))
        addrs = [ctypes.addressof(ctypes.c_char.from_buffer(b)) for b in bufs]
        prog(*addrs, global_size=calls[-1][1], local_size=(1, 1, 1))
    finally:
        OPY.exec_alu = real

    print("# exec_alu CALLS, IN ORDER:")
    for op, dt_, operands, r in log:
        print(f"  exec_alu({op}, {dt_}, operands={operands!r}) -> {r!r}")
    print("# BUFFERS AFTER:", [bytes(b).hex() for b in bufs])
    return 0


if __name__ == "__main__":
    sys.exit(main())
