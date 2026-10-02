#!/usr/bin/env python
"""Measure the `get_kernel_actions` key sets that search.bend's header quotes.

Those numbers are INDICES INTO `actions`, so deleting the 60-entry UNROLL group moves
every one of them -- and a comment quoting stale indices looks exactly like a gate row
without being one, which is the `device.bend` `sig=0 4 5` shape. Measured at HEAD, not
carried over.

The header says these were read "by patching `apply_opts`", and that is the only place
a `Scheduler` is constructed on the way to beam search (codegen/__init__.py:298), so that
is what this patches: build the real `Scheduler`, let the real `get_kernel_actions` run on
it, record the keys, and hand back the untouched ast so nothing downstream notices.

  DEV=PYTHON BEAM=1 .venv/bin/python .agents/slop/measure-search-keys.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

import tinygrad
from tinygrad import Tensor, Device
import tinygrad.codegen.opt.postrange as PR
import tinygrad.codegen as CG

SEEN = {}


def fake_apply_opts(ast, ren, beam=0):
  k = PR.Scheduler(ast, ren)
  k.convert_loop_to_global()
  if ast.arg is None or ast.arg.beam < 1:
    return ast
  from tinygrad.codegen.opt.search import get_kernel_actions
  SEEN["keys"] = sorted(get_kernel_actions(k, include_0=False).keys())
  SEEN["keys0"] = sorted(get_kernel_actions(k, include_0=True).keys())
  SEEN["shape"] = [str(x) for x in k.full_shape]
  SEEN["axis_types"] = [t.name for t in k.axis_types]
  return ast


PR.apply_opts = fake_apply_opts
CG.apply_opts = fake_apply_opts


def show(label):
  if "keys" not in SEEN:
    print(f"# {label}: NO SCHEDULER REACHED -- beam was not used")
    return
  print(f"# {label} shape={SEEN['shape']} axis_types={SEEN['axis_types']}")
  print(f"#   n={len(SEEN['keys'])} keys={SEEN['keys']}")
  print(f"#   include_0=True n={len(SEEN['keys0'])} keys={SEEN['keys0']}")


with tinygrad.Context(DEV=Device.DEFAULT):
  (Tensor.rand(4) + 1).contiguous().realize()
show("(a+1) 4 elements")

with tinygrad.Context(DEV=Device.DEFAULT):
  ((Tensor.rand(16, 32) * Tensor.rand(16, 32)).sum(1)).contiguous().realize()
show("(a*b).sum(1) 16x32")

with tinygrad.Context(DEV=Device.DEFAULT):
  (Tensor.rand(64, 64).contiguous().realize() @ Tensor.rand(64, 64)).contiguous().realize()
show("a@b 64x64x64")