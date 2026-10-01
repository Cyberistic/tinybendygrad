#!/usr/bin/env python3
"""rf-names.py -- does any rangeify.py pattern bind a NAME TWICE inside one
conjunction (which `upat.py:100-105` turns into a `"{0} is {1}"` identity
check)?  Print the compiled match code for every rule so the answer is MEASURED."""
import sys, inspect, types
sys.path.insert(0, '.')
from tinygrad.uop.ops import PatternMatcher, UPat, UOp, Ops
from tinygrad.uop import upat as U
from tinygrad.schedule import rangeify as R
import tinygrad.schedule.prepare as prep
import tinygrad.codegen.simplify as simp

TABLES = [("gs", R.pm_gate_substitute), ("ct", R.pm_const_buffer_folding),
          ("rb", R.pm_remove_bufferize), ("nic", R.pm_no_indexing_calls),
          ("nv", R.pm_no_views), ("lb", R.pm_limit_bufs), ("fb", R.pm_flatten_bufferize),
          ("ab", R.pm_add_buffers), ("dg", R.to_define_global),
          ("aprt", R.pm_add_param_range_tags), ("sk", R.split_kernels)]

for nm, pm in TABLES:
  for i, (pat, fxn) in enumerate(pm.patterns):
    code = U._get_code(pat, True)
    if code is None:
      print(f"{nm}.{i}: NOT COMPILABLE")
      continue
    src = code[0]
    ident = [l.strip() for l in src.split('\n') if ' is ' in l and '{0}' in l and '{1}' in l]
    store = [l.strip() for l in src.split('\n') if 'ctx=' in l]
    print(f"{nm}.{i}: identity_checks={len(ident)} binds={store}")
    for x in ident: print("      ID:", x)
