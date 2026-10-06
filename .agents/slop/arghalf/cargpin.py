#!/usr/bin/env python3
"""cargpin.py -- what graphcmp's OWN `carg` renders for a CALL, against a chosen tree.

`graphcmp.py`'s `carg` CALL arm is a HAND-WRITTEN three-slot string, so it is a renderer
that cannot follow either tree by itself. This asks two questions with one number each:

  1. does the tree's `CallInfo` HAVE a `dtype` field at all;
  2. does the tree's `dtype_from_uop` read the ARG's dtype or `src[0]`'s.

USAGE:  cargpin.py <tree-dir>
"""
import os
import sys

tree = sys.argv[1]
sys.path.insert(0, os.path.abspath(tree))
os.environ["DEV"] = "CPU"
sys.path.insert(0, os.path.abspath(".agents/slop"))

import graphcmp  # noqa: E402

graphcmp.load_tinygrad()
import tinygrad.uop.ops as opm  # noqa: E402

import tinygrad  # noqa: E402

print(f"# tree={tinygrad.__file__}")
print(f"# CallInfo fields   = {list(opm.CallInfo.__annotations__)}")
print(f"# has dtype field   = {'dtype' in opm.CallInfo.__annotations__}")

# A CALL over a SINK body, which is `--graph loop`'s shape: src[0] is a SINK, so both
# candidate rules must be READ, not assumed.
sink = opm.UOp(OpsSink := opm.Ops.SINK, (opm.UOp.const(4),), None)
call = opm.UOp(opm.Ops.CALL, (sink,), opm.CallInfo(None, "hcq_fence", False, False, None))
print(f"# dtype_from_uop   = {call.dtype}   src[0].dtype = {sink.dtype}")
print(f"# _shape           = {call._shape!r}")
print(f"# carg(Ops.CALL)   = {graphcmp.carg(opm.Ops.CALL, call.arg)!r}")