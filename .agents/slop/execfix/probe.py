#!/usr/bin/env python3
"""Render the packets for the failing lanes and dump them as .rows.

    .venv/bin/python .agents/slop/execfix/probe.py

ONE bend process at a time is the rule; this script renders packets only (no
executor launch), so it does not start the compiler at all.

It uses `ops_bend.py` at the repo root -- the repo's own encoder -- so the
packets are the ones the executor would really receive.
"""
import pathlib, sys, os

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad import Tensor, Context, Device
from tinygrad.dtype import dtypes

import ops_bend as OB

# tinygrad's device loader imports `tinygrad.runtime.ops_bend` by NAME; the
# module lives at the repo root so that `tinygrad/` stays pristine. Registering
# it under the name tinygrad looks for is what the gate does too.
sys.modules['tinygrad.runtime.ops_bend'] = OB

OUT = pathlib.Path(__file__).resolve().parent

CAP = []
_orn = OB.BendRenderer.render


def _render(self, uops):
    CAP.append(uops)
    return _orn(self, uops)


OB.BendRenderer.render = _render
_oi = OB.BendProgram.__init__


def _init(self, dev, obj):
    _oi(self, dev, obj)
    CAP[-1] = (self, obj)


OB.BendProgram.__init__ = _init

GRID = []
_oc = OB.BendProgram.__call__


def _call(self, *bufs, global_size=(1, 1, 1), local_size=(1, 1, 1), wait=False, **kw):
    GRID.append((global_size, local_size))
    return _oc(self, *bufs, global_size=global_size, local_size=local_size, wait=wait, **kw)


OB.BendProgram.__call__ = _call


def cases():
    T = Tensor

    def bcast_mul():
        a = T(list(range(1, 17))).realize().reshape(4, 1, 4)
        b = T([2 * i + 2 for i in range(16)]).realize().reshape(1, 4, 4)
        return lambda: a * b

    def bcast_mul_f():
        a = T([float(i + 1) for i in range(16)]).realize().reshape(4, 1, 4)
        b = T([float(2 * i + 2) for i in range(16)]).realize().reshape(1, 4, 4)
        return lambda: a * b

    def max0():
        a = T(list(range(16))).realize().reshape(4, 4)
        return lambda: a.max(axis=0)

    def max0f():
        a = T([float(i) for i in range(16)]).realize().reshape(4, 4)
        return lambda: a.max(axis=0)

    def max1():
        a = T(list(range(16))).realize().reshape(4, 4)
        return lambda: a.max(axis=1)

    def sum0():
        a = T(list(range(16))).realize().reshape(4, 4)
        return lambda: a.sum(axis=0)

    def dot():
        xs = T([float(i + 1) for i in range(16)]).realize().reshape(4, 4)
        ys = T([float(2 * i + 2) for i in range(16)]).realize().reshape(4, 4)
        return lambda: xs @ ys

    return [('bcast_mul', bcast_mul), ('bcast_mul_f', bcast_mul_f), ('max0', max0),
            ('max0f', max0f), ('max1', max1), ('sum0', sum0), ('dot', dot)]


def main():
    names = sys.argv[1:]
    for name, mk in cases():
        if names and name not in names:
            continue
        CAP.clear()
        GRID.clear()
        with Context(DEV='BEND'):
            got = mk()().tolist()
        n = len(CAP)
        pkt = CAP[-1][1].lib.decode() if n else ''
        (OUT / f'packet-{name}.rows').write_text(pkt)
        print(f'== {name}: packets={n} grid={GRID} got={got}')
        print(pkt)


if __name__ == '__main__':
    main()
