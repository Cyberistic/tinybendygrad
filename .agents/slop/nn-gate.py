#!/usr/bin/env python3
"""The CPython lane for `tinybendygrad/nn/optim.bend`'s gate.

    .venv/bin/python .agents/slop/nn-gate.py > /tmp/py.txt
    ./bin/bendygrad/nn/optim.bend      > /tmp/bd.txt
    diff

NOTHING IS EXECUTED. Every row is a STRING or the SIGNATURE of a lazily built graph --
`n=<count> OP/<nsrc> ...` in toposort with the bare `Enum.name` -- so no device is
needed, which is the whole reason this is a graph gate.

THE MOMENTUM BUFFER IS REPLACED BEFORE EVERY `_step`, and that is WALL 1 applied to the
ORACLE as well as to the port: Python's `self.b[i]` is a `Tensor.zeros` whose graph is
six `empty_like` nodes the port does not build, so both sides get a plain BUFFER. A
reader comparing against an unreplaced oracle sees six extra nodes and should read the
Bend file's header.
"""
import sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)
from tinygrad import Tensor
from tinygrad.nn import optim
from tinygrad.helpers import Context

def sig(u, nm):
  ts = u.toposort()
  print('%s=%d %s ' % (nm, len(ts), ' '.join('%s/%d' % (x.op.name, len(x.src)) for x in ts)))

a  = Tensor([1.0, 2.0], device='PYTHON'); a.is_param_(True)
c  = Tensor([4.0, 5.0, 6.0], device='PYTHON'); c.is_param_(True)
bu = Tensor([3.0], device='PYTHON'); bu.is_param_(False)

o = optim.Optimizer([a, bu, c], lr=0.1)
print('op_params=%s' % ','.join(str(t.numel()) for t in o.params))
print('op_bufs=%s' % ','.join(str(t.numel()) for t in o.buffers))
with Context(FUSE_OPTIM=1):
  print('op_acc=%s' % ','.join(str(x) for x in optim.Optimizer([a, c], lr=0.1).pos_params))
# _new_optim_param's three arms: Nzs when the device is a plain string, Nzl when it is a
# TUPLE (a multi-device param), Nz when fused. The tag is what says WHICH arm fired, so
# a row that only compared sizes could not see a wrong arm.
print('op_nop=%s' % ','.join('%s:%d' % ('Nz' if o.fused else 'Nzl' if isinstance(o.device, tuple) else 'Nzs', x.numel())
                             for x in o._new_optim_param()))

g = Tensor([0.5, 0.25], device='PYTHON')
def bsig(L, nm):
  L.b = [Tensor([0.0, 0.0], device='PYTHON')]
  sig(L._step([a], [g])[0][0].uop, nm)
def lars(**kw): return optim.LARS([a], lr=0.1, ns_steps=0, **kw)

sig(o._apply_update(a, g).uop, 'unverified_apply')
bsig(lars(momentum=0.0, weight_decay=0.1, nesterov=False, classic=True, pre_wd=True, tcoef=0.0), 'unverified_prewd')
bsig(lars(momentum=0.0, weight_decay=0.0, nesterov=False, classic=True, pre_wd=True, tcoef=0.0), 'unverified_lars0')
bsig(lars(momentum=0.0, weight_decay=0.0, nesterov=False, classic=True, pre_wd=True, tcoef=0.001), 'unverified_trust')
bsig(lars(momentum=0.9, weight_decay=0.0, nesterov=False, classic=True, pre_wd=True, tcoef=0.0), 'unverified_mom')
bsig(lars(momentum=0.9, weight_decay=0.0, nesterov=True,  classic=True, pre_wd=True, tcoef=0.0), 'unverified_nesterov')

L = optim.LAMB([a], lr=0.1, adam=True)
L.b1_t = Tensor([0.9], device='PYTHON'); L.b2_t = Tensor([0.999], device='PYTHON')
L.m = [Tensor([0.0, 0.0], device='PYTHON')]; L.v = [Tensor([0.0, 0.0], device='PYTHON')]
sig(L._step([a], [g])[0][0].uop, 'unverified_lamb')
