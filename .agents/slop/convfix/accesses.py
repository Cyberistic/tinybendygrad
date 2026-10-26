#!/usr/bin/env python3
"""WHAT UPSTREAM'S OWN INTERPRETER ACTUALLY TOUCHES, ON THE PORT'S OWN PACKET.

    .venv/bin/python .agents/slop/convfix/accesses.py

UPSTREAM'S `_load` AND `_store` ARE MONKEYPATCHED -- NOT EDITED. `tinygrad/` IS
THE ORACLE AND IS NOT MINE, so the patch is at runtime and in this process only.

THE QUESTION THIS ANSWERS: the port refused a packet at `pc=333 off=3100 buf=1`
-- offset 3100 into a 3072-element buffer. Upstream's `_load` RAISES IndexError
there (ops_python.py:19), so if upstream never calls `_load` with 3100, THE PORT
REFUSED AN ACCESS THAT NEVER HAPPENED.

THE BUFFER IS IDENTIFIED BY ITS LENGTH. The packet's four buffers have four
distinct lengths -- 8192 (the output), 3072 (the input), 216 (the weight) and 16
(the local scratch) -- so `len(m)` names the buffer without any address
bookkeeping.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad import Tensor, Context  # noqa: E402
from tinygrad.dtype import AddrSpace, dtypes  # noqa: E402
from tinygrad.helpers import Target, to_mv  # noqa: E402
from tinygrad.runtime import ops_python as OPY  # noqa: E402
from tinygrad.uop.ops import Ops  # noqa: E402

from ops_bend import buf_extent, encode, is_buf, wire_arg  # noqa: E402

ACCESS = []
_load, _store = OPY._load, OPY._store


def patched_load(m, i, dtype):
    if i is not None:
        ACCESS.append(('load', len(m), i))
    return _load(m, i, dtype)


def patched_store(m, i, v, dtype):
    ACCESS.append(('store', len(m), i))
    return _store(m, i, v, dtype)


OPY._load, OPY._store = patched_load, patched_store


class Elf:
    def __init__(self, uops, target):
        self.lib, self.target = pickle_uops(uops), target


def pickle_uops(uops):
    import pickle
    return pickle.dumps(uops)


def vals(n, seed=1.0):
    return [((i * 37) % 11 - 5) * seed + 0.5 for i in range(n)]


def main():
    xshape, wshape = (1, 3, 32, 32), (8, 3, 3, 3)
    xn, wn = 1 * 3 * 32 * 32, 8 * 3 * 3 * 3
    xv, wv = vals(xn), vals(wn, 0.25)

    # THE CAPTURE: the launch's OWN uops, buffers and grid, from the PYTHON
    # device -- the same kernel the BEND device renders, because the two
    # renderers are the same scheduler over the same expression.
    CAP = []
    _render = OPY.PythonRenderer.render
    _call = OPY.PythonProgram.__call__

    def render(self, uops):
        CAP.append(list(uops))
        return _render(self, uops)

    def call(self, *bufs, **kw):
        plan = []
        for u in self.uops:
            if u.op is not Ops.PARAM:
                continue
            arg = wire_arg(u)
            if is_buf(arg):
                plan.append(("buf", buf_extent(arg)))
            elif u.addrspace is AddrSpace.ALU:
                plan.append(("word", 0))
        ext = [e for kind, e in plan if kind == "buf"]
        addrs = [a for a, (kind, _e) in zip(bufs, plan) if kind == "buf"]
        CAP.append({'uops': list(self.uops), 'ext': ext,
                    'bufs': [bytes(to_mv(a, s)) for a, s in zip(addrs, ext)],
                    'gsize': tuple(kw.get('global_size', (1, 1, 1))),
                    'lsize': tuple(kw.get('local_size', (1, 1, 1))),
                    'words': tuple(a for a, (kind, _e) in zip(bufs, plan) if kind == "word")})
        return _call(self, *bufs, **kw)

    OPY.PythonRenderer.render, OPY.PythonProgram.__call__ = render, call
    try:
        with Context(DEV='PYTHON'):
            x = Tensor(xv, dtype=dtypes.float32).reshape(*xshape).realize()
            w = Tensor(wv, dtype=dtypes.float32).reshape(*wshape).realize()
            x.conv2d(w, padding=1, stride=1).realize()
    finally:
        OPY.PythonRenderer.render, OPY.PythonProgram.__call__ = _render, _call

    cap = CAP[-1]
    print(f"# launch: nuops={len(cap['uops'])} gsize={cap['gsize']} lsize={cap['lsize']} "
          f"nbuf={len(cap['bufs'])}")

    ACCESS.clear()
    b2 = [bytearray(b) for b in cap['bufs']]
    prog = OPY.PythonProgram.__new__(OPY.PythonProgram)
    prog.__init__(None, Elf(cap['uops'], Target(renderer="PYTHON")))
    import ctypes
    addrs = [ctypes.addressof(ctypes.c_char.from_buffer(b)) for b in b2]
    plan = []
    for u in cap['uops']:
        if u.op is not Ops.PARAM:
            continue
        arg = wire_arg(u)
        if is_buf(arg):
            plan.append(("buf", buf_extent(arg)))
        elif u.addrspace is AddrSpace.ALU:
            plan.append(("word", 0))
    args, ai, wi = [], 0, 0
    for kind, _e in plan:
        if kind == "buf":
            args.append(addrs[ai])
            ai += 1
        else:
            args.append(cap['words'][wi])
            wi += 1
    prog(*args, global_size=cap['gsize'], local_size=cap['lsize'])

    per = {}
    for kind, ln, i in ACCESS:
        per.setdefault((kind, ln), []).append(i)
    print(f"# upstream ran the packet: {len(ACCESS)} memory accesses")
    for (kind, ln), idxs in sorted(per.items()):
        oob = [i for i in idxs if i >= ln or i < 0]
        print(f"#   {kind}: buffer len={ln}, {len(idxs)} accesses, index range "
              f"[{min(idxs)}, {max(idxs)}], out-of-range={len(oob)}")
    print(f"# THE PORT'S REFUSAL WAS at offset 3100 into the 3072-element buffer: "
          f"upstream accessed it {sum(1 for k, l, i in ACCESS if l == 3072 and i == 3100)} time(s)")


if __name__ == '__main__':
    sys.exit(main())
