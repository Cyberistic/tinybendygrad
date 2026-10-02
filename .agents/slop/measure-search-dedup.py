#!/usr/bin/env python
"""Measure the DEDUP narrative that search.bend's header tells.

The header claims: "`n_red` and `zero_169` are the rows", "169 is `SPLIT(0, (16, LOCAL))`,
`full_shape[0] == 16 == arg[0]`, and `SPLIT(0, (16->0, LOCAL))` is 121 -- so 169 is
skipped, while 193 (`SPLIT(0, (16, LOCAL, True))`) is PRESENT because the top=True group
has no amt-0 entry."

Every one of those indices is a POSITION into `actions`, and deleting the 60-entry UNROLL
group moves every position at or above 60 down by 60. So the claim has to be re-measured.

NOTHING HERE RE-IMPLEMENTS THE GUARD. `search.replace` is wrapped, so the set of actions
CPython ACTUALLY asked about is observed rather than recomputed; the only membership test
performed is `arg in search.actions` against the real list.

  DEV=PYTHON BEAM=1 .venv/bin/python .agents/slop/measure-search-dedup.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

import tinygrad
from tinygrad import Tensor, Device
import tinygrad.codegen.opt.postrange as PR
import tinygrad.codegen as CG
import tinygrad.codegen.opt.search as S

_real_replace = S.replace
ASKED = {}


def watched_replace(a, **kw):
  """Records `(index of a, a)` every time search.py builds a zeroed twin to test."""
  idx = next((i for i, o in enumerate(S.actions) if o is a), None)
  twin = _real_replace(a, **kw)
  # the TWIN is the replaced Opt, not the arg tuple: membership is `twin in actions`,
  # and testing the tuple against a list of Opts is always False.
  ASKED.setdefault("pairs", []).append((idx, a, twin))
  return twin


def fake_apply_opts(ast, ren, beam=0):
  k = PR.Scheduler(ast, ren)
  k.convert_loop_to_global()
  if ast.arg is None or ast.arg.beam < 1:
    return ast
  ASKED["shape_len"] = k.shape_len
  ASKED["full_shape"] = [str(x) for x in k.full_shape]
  ASKED["axis_types"] = [t.name for t in k.axis_types]
  ASKED["keys"] = sorted(S.get_kernel_actions(k, include_0=False).keys())
  return ast


S.replace = watched_replace
PR.apply_opts = fake_apply_opts
CG.apply_opts = fake_apply_opts


def show(label):
  if "keys" not in ASKED:
    print(f"# {label}: NO SCHEDULER REACHED")
    return
  print(f"# {label} shape={ASKED['full_shape']} shape_len={ASKED['shape_len']} "
        f"axis_types={ASKED['axis_types']}")
  print(f"#   surviving keys n={len(ASKED['keys'])}: {ASKED['keys']}")
  # the guard ran `replace(...)(x) in actions` for exactly these actions; a TRUE membership
  # is a candidate the dedup DROPPED.
  dropped = [(i, a, t) for i, a, t in ASKED.get("pairs", []) if t in S.actions]
  for i, a, arg in dropped:
    print(f"#   DEDUPED idx {i}: {a.op.name} axis={a.axis} arg={a.arg}  "
          f"full_shape[{a.axis}]={ASKED['full_shape'][a.axis]}  twin {arg} IS in actions")
  asked = sorted({i for i, _, _ in ASKED.get("pairs", [])})
  print(f"#   dedup tested indices: {asked}")
  # and the near-miss that is the other half of the claim: same amt, top=True group, whose
  # zeroed twin is NOT in actions, so it survives.
  for i, a, t in ASKED.get("pairs", []):
    if t not in S.actions and a.op.name == "SPLIT":
      print(f"#   KEPT idx {i}: {a.op.name} axis={a.axis} arg={a.arg} twin {t.arg} absent")


with tinygrad.Context(DEV=Device.DEFAULT):
  ((Tensor.rand(16, 32) * Tensor.rand(16, 32)).sum(1)).contiguous().realize()
show("(a*b).sum(1) 16x32")

with tinygrad.Context(DEV=Device.DEFAULT):
  (Tensor.rand(64, 64).contiguous().realize() @ Tensor.rand(64, 64)).contiguous().realize()
show("a@b 64x64x64")