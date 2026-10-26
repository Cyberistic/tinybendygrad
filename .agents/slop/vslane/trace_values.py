#!/usr/bin/env python3
"""UPSTREAM's OWN `values` ARENA, ONE LINE OF ops_python.py AT A TIME.

    .venv/bin/python .agents/slop/vslane/trace_values.py <fixture-name> [maxlines]

`tinygrad/runtime/ops_python.py`'s `PythonProgram.__call__` keeps its arena in a
LOCAL `values` dict (ops_python.py:60) and nothing else exposes it. `sys.settrace`
reads the frame's OWN locals, so this observes upstream's arena without editing
upstream and without re-implementing a step of it: the trace fires on every LINE
of `__call__`, and the arena is dumped when the line changes.

THE ARENA IS PRINTED AS THE PYTHON OBJECT IT IS -- a list per uop -- so the
SHAPE (a scalar, a tuple, a list of tuples) is visible, which is the whole
question: `exec_alu`'s tuple branch (ops.py:1423) fires on a TUPLE OPERAND, and
whether the operands ARE tuples is a fact about the arena, not a guess.
"""
import ctypes, pathlib, pickle, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad import Tensor                                          # noqa: E402
from tinygrad.dtype import dtypes                                    # noqa: E402
from tinygrad.helpers import Context, Target, to_mv                  # noqa: E402
from tinygrad.runtime import ops_python as OPY                       # noqa: E402

SEED_VALUES = {
    dtypes.float: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0],
    dtypes.int: [1, 2, 3, 4, 5, 6, 7, 8],
    dtypes.uint: [1, 2, 3, 4, 5, 6, 7, 8],
    dtypes.bool: [1, 0, 1, 0, 1, 0, 1, 0],
}


class Elf:
    def __init__(self, uops, target): self.lib, self.target = pickle.dumps(uops), target


def harvest(fn):
    renders, calls = [], []
    _render, _call = OPY.PythonRenderer.render, OPY.PythonProgram.__call__

    def render(self, uops):
        renders.append(list(uops)); return _render(self, uops)

    def call(self, *bufs, **kw):
        calls.append(([bytes(to_mv(a, 32)) for a in bufs],
                      tuple(kw.get("global_size", (1, 1, 1)))))
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
    maxlines = int(sys.argv[2]) if len(sys.argv) > 2 else 10_000
    kind = want.split(".")[0]
    if kind == "bool":
        maker = lambda: (Tensor(SEED_VALUES[dtypes.bool], dtype=dtypes.bool) == 1).realize()
    else:
        dt = {"f32": dtypes.float, "i32": dtypes.int, "u32": dtypes.uint}[kind]
        maker = lambda: Tensor(SEED_VALUES[dt], dtype=dt).abs().sqrt().realize()

    renders, calls = harvest(maker)
    uops = renders[-1]

    bufs = [bytearray(b) for b in calls[-1][0]]
    prog = OPY.PythonProgram.__new__(OPY.PythonProgram)
    prog.__init__(None, Elf(uops, Target(renderer="PYTHON")))
    addrs = [ctypes.addressof(ctypes.c_char.from_buffer(b)) for b in bufs]

    state = {"last": None, "n": 0, "pc": None}

    def tracer(frame, event, arg):
        if frame.f_code is not OPY.PythonProgram.__call__.__code__:
            return None
        if event == "call":
            return tracer
        if event == "line":
            loc = frame.f_locals
            vals = loc.get("values")
            u = loc.get("u")
            i = loc.get("i")
            key = (id(u), i)
            if vals is not None and key != state["last"]:
                state["last"] = key
                state["n"] += 1
                if state["n"] > maxlines:
                    return None
                op = u.op.name if u is not None else "?"
                print(f"-- i={i} {op}")
                for k, v in vals.items():
                    try:
                        shown = repr(v)
                    except Exception:                                        # noqa: BLE001
                        shown = "<unrepr>"
                    if len(shown) > 160: shown = shown[:160] + "..."
                    print(f"     values[{k.op.name}] = {shown}")
        return tracer

    sys.settrace(tracer)
    try:
        prog(*addrs, global_size=calls[-1][1], local_size=(1, 1, 1))
    finally:
        sys.settrace(None)
    print("# BUFFERS AFTER:", [bytes(b).hex() for b in bufs])
    return 0


if __name__ == "__main__":
    sys.exit(main())
