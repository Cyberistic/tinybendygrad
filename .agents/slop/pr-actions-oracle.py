#!/usr/bin/env python3
"""`get_kernel_actions`' KEY SETS, by CALLING CPython.

`codegen/opt/postrange.bend` pins its fixtures to the `enumerate` INDICES of
`tinygrad/codegen/opt/search.py`'s `actions` table -- `acted[i+1] = s2` (search.py:101) --
so every key is a 1-based index into that list. The rebase rebuilt `actions`
(AxisType.UNROLL and AxisType.REDUCE were deleted and the table reordered), so every one
of those indices MOVED while every COUNT held. That is the trap this file exists for: a
row that says 4 or 18 or 32 cannot tell "the axis guard fired" from "the divisibility
check fired", and it cannot tell a stale index from a live one.

    DEV=CPU .venv/bin/python .agents/slop/pr-actions-oracle.py

WHY THIS NEEDS A SEAM AT ALL, in four measured steps. Each one produced a run that
LOOKED healthy and captured nothing, which is the whole reason the capture count is
asserted rather than trusted:

  1. Patching `search.get_kernel_actions` captures only what BEAM search reaches.
     `beam_search` calls it at search.py:129 and `_time_program` at :143, which dies under
     a NULL device with "TypeError: '>' not supported between 'float' and 'NoneType'" --
     AFTER the capture, so the crash swallowed the rows unless each realize is wrapped.
  2. Patching `codegen.apply_opts` is one step closer and wrong for a quieter reason:
     `apply_opts(ast: UOp, ren, beam=0)` receives the sink UOP, not a Scheduler
     ("AttributeError: 'UOp' object has no attribute 'full_shape'").
  3. Patching `Scheduler.convert_loop_to_global` is the RIGHT seam but is not reached:
     kernels reach `to_program` through `pm_lower_calls` (codegen/__init__.py:421), which
     lowers each CALL body with `full_rewrite_to_sink(call.body, ctx, optimize=False)`, and
     `optimize=False` skips the `apply_opts` line (:298) entirely. So zero captures, on a
     patch that was demonstrably installed.
  4. Dedupe the captures by `id(s)`: the Schedulers are transient and CPython reuses `id()`
     after collection, so four fixtures collapsed into one printed key set.

THE FIX FOR (3) IS TO RUN THE OPTIMIZE PATH OURSELVES on the captured body and let
`apply_opts` be reached the way a BEAM build reaches it. The Scheduler captured on the way
out of `convert_loop_to_global` is then the exact object `get_kernel_actions` is asked
about, and its `applied_opts` is empty -- which is what `include_0=True` expects.
"""
import os

# SET BEFORE ANY tinygrad IMPORT: `CACHELEVEL` and `IGNORE_BEAM_CACHE` are read into
# module globals at import time (search.py:108). With the default CACHELEVEL=2 the
# kernels come out of the disk cache, DEBUG=2 still prints "scheduled 4 kernels ...
# 439 uops in cache", and the run looks healthy while capturing nothing.
os.environ.update(DEV="CPU", CACHELEVEL="0", IGNORE_BEAM_CACHE="1", BEAM="0", DEBUG="0")

import tinygrad.codegen as CG
from tinygrad.codegen.opt import search
from tinygrad.codegen.opt.postrange import Scheduler

CAPTURED = []
_cltg = Scheduler.convert_loop_to_global


def recording_cltg(self):
  r = _cltg(self)
  CAPTURED.append(self)
  return r


Scheduler.convert_loop_to_global = recording_cltg

_frs = CG.full_rewrite_to_sink


def frs(ast, ren, optimize=True):
  out = _frs(ast, ren, optimize)
  if not optimize:
    # THE SECOND PASS. `_frs(..., optimize=True)` is a fresh walk over the same body, so
    # it reaches `apply_opts` (:298) and therefore `convert_loop_to_global`, which is where
    # the Scheduler is captured. Its result is DISCARDED: this oracle wants the scheduler
    # AS IT WAS BEFORE any opt was applied, not a second optimized kernel.
    _frs(ast, ren, True)
  return out


CG.full_rewrite_to_sink = frs


def build():
  from tinygrad.tensor import Tensor
  out = []
  t = Tensor.rand(4)
  (t + 1).tolist()
  out.append("rand(4) + 1")
  m = Tensor.rand(16, 32)
  (m + 1).tolist()
  out.append("rand(16,32) + 1")
  a = Tensor.rand(64, 64)
  (a @ a).tolist()
  out.append("rand(64,64) @ rand(64,64)")
  return out


try:
  build()
except Exception as e:
  print(f"# the build ended with {type(e).__name__}: {e}")
  print("# (fine when the capture already happened -- the count below is the evidence)")

print("# captures:", len(CAPTURED))
if not CAPTURED:
  raise SystemExit("ZERO captures -- the seam was not reached. This oracle prints no key "
                   "set from an empty capture; see the four numbered steps in the header.")

# DEDUPED BY THE FIXTURE'S OWN SHAPE (see step 4 in the header).
seen = {}
for s in CAPTURED:
  seen.setdefault((tuple(s.full_shape), tuple(t.name for t in s.axis_types)), s)

for (shape, ats), s in seen.items():
  print(f"full_shape {list(shape)} axis_types {list(ats)}")
  for i0 in (False, True):
    ks = sorted(search.get_kernel_actions(s, include_0=i0).keys())
    print(f"  include_0={str(i0):<5} -> {len(ks):>2} keys: {' '.join(map(str, ks))}")
  print("  what include_0=True adds: "
        f"{sorted(set(search.get_kernel_actions(s, include_0=True)) - set(search.get_kernel_actions(s, include_0=False)))}")

print("# distinct fixtures:", len(seen))
if len(seen) < 3:
  raise SystemExit(f"only {len(seen)} distinct fixture(s) captured, three were asked for, "
                   "so a key set is MISSING rather than empty")