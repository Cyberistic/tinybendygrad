#!/usr/bin/env python3
"""THE A/B ON THE VECTOR-STORE LANE: THE PORT'S EXECUTOR vs UPSTREAM'S OWN INTERPRETER,
ON THE SAME PACKET, THE SAME BUFFERS AND THE SAME GRID.

    .venv/bin/python .agents/slop/vslane/probe.py [seed ...]

THIS IS `.agents/slop/convfix/probe.py`'s METHOD, REUSED: the capture hooks
`BendRenderer.render` (for the UOps the oracle needs) and `BendProgram.__call__`
(for the packet and the buffers), and the oracle is upstream's own
`tinygrad/runtime/ops_python.py` `PythonProgram.__call__` -- NOT the CPython
PYTHON device, and NOT the port.

THE SEEDS ARE THE TREE's OWN: `gates/ops_python_exec-gen.py`'s `SEEDS` table is
the generator's input, and the fixture names in
`gates/ops_python_exec-fixtures.rows` (`f32.sqrt.0`) come from it. The probe
reproduces those expressions so the launch it captures IS the launch the
fixture recorded.

THE THREE ANSWERS PER CASE:
  port    -- the compiled executor (`tinybendygrad/runtime/ops_python.bend`) on
             the captured PACKET.in.
  oracle  -- upstream's own interpreter on the captured UOps and buffers.
  python  -- CPython's PYTHON device, building ITS OWN inputs (the e2e gate's
             own header: an oracle that re-uses the subject's buffers compares
             the wrong answer with itself).

ONE bend PROCESS AT A TIME: the executor is one subprocess per launch and the
cases run in sequence.
"""
import ctypes
import pathlib
import pickle
import struct
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad import Tensor, Context  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.helpers import Target, to_mv  # noqa: E402
from tinygrad.runtime import ops_python as OPY  # noqa: E402

import ops_bend as OB  # noqa: E402
from ops_bend import encode  # noqa: E402

sys.modules['tinygrad.runtime.ops_bend'] = OB

OUT = pathlib.Path(__file__).resolve().parent
CAP = []
UOPS = []


class Elf:
    """`PythonProgram.__init__` reads `obj.lib` (the pickled uops) and `obj.target`."""

    def __init__(self, uops, target):
        self.lib, self.target = pickle.dumps(uops), target


def _install_hooks():
    _render = OB.BendRenderer.render
    _call = OB.BendProgram.__call__

    def render(self, uops):
        UOPS.append(list(uops))
        return _render(self, uops)

    def call(self, *bufs, global_size=(1, 1, 1), local_size=(1, 1, 1), vals=(), wait=False, **kw):
        CAP.append({
            'packet': self.src,
            'bufs': [bytes(to_mv(b, nb)) for b, nb in zip(bufs, self.in_bufs)],
            'gsize': tuple(global_size),
            'lsize': tuple(local_size),
            'vals': tuple(vals),
            'uops': UOPS[-1] if UOPS else None,
        })
        return _call(self, *bufs, global_size=global_size, local_size=local_size, vals=vals, wait=wait, **kw)

    OB.BendRenderer.render = render
    OB.BendProgram.__call__ = call


_install_hooks()


def callee_args(uops, addrs, words):
    """The launch's positional args in the callee's own order: one per popped PARAM."""
    from tinygrad.dtype import AddrSpace
    from tinygrad.uop.ops import Ops
    from ops_bend import is_buf, wire_arg
    out, ai, wi = [], 0, 0
    for u in uops:
        if u.op is not Ops.PARAM:
            continue
        arg = wire_arg(u)
        if is_buf(arg):
            out.append(addrs[ai])
            ai += 1
        elif u.addrspace is AddrSpace.ALU:
            out.append(words[wi])
            wi += 1
    return out


def py_run(uops, bufs, gsize, lsize, words):
    """UPSTREAM'S OWN INTERPRETER, on the packet's own buffers."""
    b2 = [bytearray(b) for b in bufs]
    prog = OPY.PythonProgram.__new__(OPY.PythonProgram)
    prog.__init__(None, Elf(uops, Target(renderer="PYTHON")))
    addrs = [ctypes.addressof(ctypes.c_char.from_buffer(b)) for b in b2]
    prog(*callee_args(uops, addrs, words), global_size=gsize, local_size=lsize)
    return [bytes(b) for b in b2]


FLOATS = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
INTS = [1, 2, 3, 4, 5, 6, 7, 8]
BOOLS = [1, 0, 1, 0, 1, 0, 1, 0]


def _nonneg(x, y):
    return x.abs() + y.abs()


# THE TREE's OWN SEEDS (`gates/ops_python_exec-gen.py:517-545`), the ones the
# VECTOR-STORE LANE touches. A fixture is a SEED name and a dtype prefix.
SEEDS = {
    'sqrt': (dtypes.float, FLOATS, lambda x, y: x.abs().sqrt()),
    'log2': (dtypes.float, FLOATS, lambda x, y: x.abs().log2()),
    'exp2': (dtypes.float, FLOATS, lambda x, y: x.abs().exp2()),
    'recip': (dtypes.float, FLOATS, lambda x, y: _nonneg(x, y).reciprocal()),
    'shl': (dtypes.float, FLOATS, lambda x, y: x.abs().cast(dtypes.int32) << 2),
    'shr': (dtypes.float, FLOATS, lambda x, y: x.abs().cast(dtypes.int32) >> 2),
    'cmod': (dtypes.float, FLOATS, lambda x, y: x.abs().cast(dtypes.int32) % 3),
    'bitcast': (dtypes.float, FLOATS, lambda x, y: x.cast(dtypes.uint32).bitcast(dtypes.int32)),
    'ne': (dtypes.bool, BOOLS, lambda x, y: x != y),
    'neg': (dtypes.bool, BOOLS, lambda x, y: -x),
    'sub': (dtypes.bool, BOOLS, lambda x, y: x - y),
}


def fmt(bs, dt):
    """the bytes as the dtype's own numbers, so a difference is a MEASUREMENT."""
    if dt == dtypes.float:
        n = len(bs) // 4
        return [round(v, 6) for v in struct.unpack(f"<{n}f", bs[:n * 4])]
    if dt == dtypes.bool:
        return list(bs)
    n = len(bs) // 4
    return list(struct.unpack(f"<{n}i", bs[:n * 4]))


def main():
    exe = OB.executor()
    print(f"# executor: {exe}")
    names = sys.argv[1:] or sorted(SEEDS)
    for name in names:
        dt, vals, fn = SEEDS[name]
        CAP.clear()
        UOPS.clear()
        with Context(DEV='BEND'):
            got = fn(Tensor(vals, dtype=dt), Tensor(vals, dtype=dt)).realize().tolist()
        with Context(DEV='PYTHON'):
            want = fn(Tensor(vals, dtype=dt), Tensor(vals, dtype=dt)).realize().tolist()
        cap = CAP[-1]
        d = OUT / "packets" / name
        d.mkdir(parents=True, exist_ok=True)
        pk = d / "PACKET-0.in"
        with pk.open("w") as fh:
            fh.write(cap['packet'])
            for b in cap['bufs']:
                fh.write(f"{len(b)} {b.hex()}\n")
        (d / "packet-0.rows").write_text(cap['packet'])
        r = subprocess.run([str(exe), str(pk), *[str(v) for v in cap['gsize']]],
                           capture_output=True, text=True)
        port_rows = []
        if r.returncode == 0:
            port_rows = [bytes.fromhex(l.split()[1]) for l in (d / "PACKET.out").read_text().splitlines()]
        else:
            port_rows = None
        try:
            oracle = py_run(cap['uops'], cap['bufs'], cap['gsize'], cap['lsize'], cap['vals'])
        except Exception as e:  # noqa: BLE001
            oracle = None
            print(f"== {name}: the ORACLE REFUSED {type(e).__name__}: {str(e)[:200]}")
        print(f"== {name}  (dtype={dt.name}, gsize={cap['gsize']}, lsize={cap['lsize']}, "
              f"nuops={len(cap['uops'])})")
        print(f"#   python (PYTHON device, own inputs): {want}")
        print(f"#   port   (the executor):              "
              f"{fmt(port_rows[0], dt) if port_rows else f'rc={r.returncode} {r.stderr.strip()[:160]}'}")
        if oracle is not None:
            print(f"#   oracle (upstream's interpreter):    {fmt(oracle[0], dt)}")
            if port_rows:
                same = port_rows[0] == oracle[0]
                print(f"#   VERDICT: {'MATCH' if same else 'DIFFER'}")
        print(f"#   packet: {d}/PACKET-0.in")
    return 0


if __name__ == '__main__':
    sys.exit(main())
