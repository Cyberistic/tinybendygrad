#!/usr/bin/env python3
"""THE A/B ON THE FIXTURE'S OWN PACKET: THE PORT'S EXECUTOR vs UPSTREAM'S OWN INTERPRETER.

    .venv/bin/python .agents/slop/vslane/oracle.py <fixture-name> [<fixture-name> ...]

**THE FIXTURE'S PACKET, NOT A FRESH ONE.** `gates/ops_python_exec-fixtures.rows`
holds packets that came from a `DEV=PYTHON` harvest (`gates/ops_python_exec-gen.py`'s
AXIS 1), so the fixture's packet is the PYTHON device's rendering -- it carries a
`SPECIAL lidx0` and NO RANGE loop, because the PYTHON renderer splits an axis to
LOCAL. The BEND device renders the SAME expression DIFFERENTLY (`has_local = False`
-> a RANGE loop), so a probe that captures a BEND launch is measuring a DIFFERENT
PACKET and would answer a different question. THIS PROBE USES THE FIXTURE'S PACKET.

THE ORACLE LANE'S OWN SETTING, copied from the tree: `gates/ops_python_exec-gen.py:416`
runs `prog(*callee_args(...), global_size=fx.gsize, local_size=(1, 1, 1))` -- WARP 1,
the same warp the BEND executor runs at. So this probe runs upstream at warp 1 too.

THE UOPS. The fixture file holds the WIRE, not the UOps, and the oracle needs UOps.
They are recovered the way the generator made them: a `DEV=PYTHON` pass over the
same SEED, captured at `PythonRenderer.render`. THE PAIRING CHECK IS NOT
TAUTOLOGICAL: the harvested packet must be BYTE-IDENTICAL to the fixture's own uop
lines, and this probe refuses to run if it is not.
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
FIXTURES = ROOT / "gates" / "ops_python_exec-fixtures.rows"


# --------------------------------------------------------------------------
# THE FIXTURE FILE, read in place. `<name> <gx> <gy> <gz> <vals...>` then the
# packet text: the uop lines and the buffer lines.
# --------------------------------------------------------------------------
def fixture(name):
    recs, cur = [], None
    for ln in FIXTURES.read_text().splitlines():
        if ln.startswith("@ "):
            head = ln.split()[1:]
            cur = [head[0], tuple(int(x) for x in head[1:]), []]
            recs.append(cur)
        elif cur is not None and ln.strip():
            cur[2].append(ln)
    for n, argv, body in recs:
        if n == name:
            return n, argv, body
    raise KeyError(name)


def split_packet(body):
    """`(uop_lines, buffer_lines)` -- the packet's two halves."""
    head = body[0].split()
    nu = int(head[1])
    return body[1:1 + nu], body[1 + nu:]


# --------------------------------------------------------------------------
# THE HARVEST, for the UOps the oracle needs. `gates/ops_python_exec-gen.py`'s
# AXIS 1, in the four lines that matter.
# --------------------------------------------------------------------------
class Elf:
    def __init__(self, uops, target):
        self.lib, self.target = pickle.dumps(uops), target


def harvest(seed_name, dtype, values):
    """`[(uops, bufs, gsize, vals)]` for the seed, captured at the render boundary."""
    renders, calls = [], []
    _render, _call = OPY.PythonRenderer.render, OPY.PythonProgram.__call__

    def render(self, uops):
        renders.append(list(uops))
        return _render(self, uops)

    def call(self, *bufs, **kw):
        calls.append((encode(self.uops), [bytes(to_mv(a, s)) for a, s in
                                           zip([b for b in bufs if isinstance(b, int)], self.in_bufs)]
                      if hasattr(self, 'in_bufs') else None,
                      tuple(kw.get("global_size", (1, 1, 1)))))
        return _call(self, *bufs, **kw)

    OPY.PythonRenderer.render, OPY.PythonProgram.__call__ = render, call
    try:
        with Context(DEV="PYTHON"):
            x = Tensor(values, dtype=dtype).realize()
            y = Tensor(values, dtype=dtype).contiguous().realize()
            SEEDS[seed_name][2](x, y).realize()
    finally:
        OPY.PythonRenderer.render, OPY.PythonProgram.__call__ = _render, _call
    return renders, calls


def callee_args(uops, addrs, words):
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
    b2 = [bytearray(b) for b in bufs]
    prog = OPY.PythonProgram.__new__(OPY.PythonProgram)
    prog.__init__(None, Elf(uops, Target(renderer="PYTHON")))
    addrs = [ctypes.addressof(ctypes.c_char.from_buffer(b)) for b in b2]
    prog(*callee_args(uops, addrs, words), global_size=gsize, local_size=lsize)
    return [bytes(b) for b in b2]


# THE TREE's OWN SEEDS (`gates/ops_python_exec-gen.py:517-545`).
FLOATS = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
INTS = [1, 2, 3, 4, 5, 6, 7, 8]
BOOLS = [1, 0, 1, 0, 1, 0, 1, 0]


def _nonneg(x, y):
    return x.abs() + y.abs()


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
    'where': (dtypes.float, FLOATS, lambda x, y: Tensor.where(x > 1, x, y)),
}


def elems(bs, dt):
    if dt == dtypes.float:
        n = len(bs) // 4
        return [round(v, 7) for v in struct.unpack(f"<{n}f", bs[:n * 4])]
    if dt == dtypes.bool:
        return list(bs)
    n = len(bs) // 4
    return list(struct.unpack(f"<{n}i", bs[:n * 4]))


def main():
    names = sys.argv[1:]
    exe = OB.executor()
    print(f"# executor: {exe}")
    for name in names:
        seed_name = name.split('.')[1]
        dt = {'f32': dtypes.float, 'i32': dtypes.int, 'u32': dtypes.uint, 'bool': dtypes.bool}[name.split('.')[0]]
        dtype, values, fn = SEEDS[seed_name]
        fx_name, argv, body = fixture(name)
        uop_lines, buf_lines = split_packet(body)
        renders, _calls = harvest(seed_name, dtype, values)
        pairs = [r for r in renders if encode(r) == "\n".join(uop_lines) + "\n"]
        if not pairs:
            print(f"== {name}: NO HARVESTED UOPS MATCH THE FIXTURE'S PACKET -- "
                  f"{len(renders)} harvested, fixture has {len(uop_lines)} uop lines")
            continue
        uops = pairs[0]
        # THE BUFFERS: the FIXTURE's own buffer lines, and the addresses the
        # oracle binds are the SAME bytes.
        bufs = [bytes.fromhex(l.split()[1]) for l in buf_lines]
        d = OUT / "packets" / name
        d.mkdir(parents=True, exist_ok=True)
        pk = d / "PACKET-0.in"
        pk.write_text("\n".join(body) + "\n")
        r = subprocess.run([str(exe), str(pk), *[str(v) for v in argv]], capture_output=True, text=True)
        port = None
        if r.returncode == 0:
            po = (d / "PACKET.out").read_text().splitlines()
            port = [bytes.fromhex(l.split()[1]) for l in po]
        try:
            oracle = py_run(uops, bufs, tuple(argv[:3]), (1, 1, 1), ())
        except Exception as e:  # noqa: BLE001
            oracle = None
            print(f"== {name}: the ORACLE REFUSED {type(e).__name__}: {str(e)[:200]}")
        print(f"== {name}  (warp 1 on both sides; gsize={argv[:3]}; uops matched byte-for-byte)")
        print(f"#   input  b1: {elems(bufs[1], dt)}")
        print(f"#   oracle (upstream, warp 1): {elems(oracle[0], dt) if oracle else '-'}")
        print(f"#   port   (the executor):     "
              f"{elems(port[0], dt) if port else f'rc={r.returncode} {r.stderr.strip()[:160]}'}")
        if port and oracle:
            diff = [i for i in range(min(len(port[0]), len(oracle[0])))
                    if port[0][i] != oracle[0][i]]
            print(f"#   bytes differing at: {diff} of {len(oracle[0])}")
            print(f"#   VERDICT: {'MATCH' if port[0] == oracle[0] else 'DIFFER'}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
