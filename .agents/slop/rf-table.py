#!/usr/bin/env python3
"""rf-table.py -- the TABLE data for rangeify.bend: per rule, the pdict op set
and `early_reject` (ops.py:1477), read straight out of the Python UPats."""
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, PatternMatcher, UPat
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.schedule import rangeify as R

def ops_of(p):
  """the pdict key: `pdict` is keyed on `p.op` (ops.py:1600)."""
  return p.op

def rej_of(p):
  """early_reject -- the op set of the pattern's FIRST src (ops.py:1477)."""
  return p.early_reject

TABLES = [
  ("gs", R.pm_gate_substitute), ("ct", R.pm_const_buffer_folding),
  ("rb", R.pm_remove_bufferize), ("nic", R.pm_no_indexing_calls),
  ("nv", R.pm_no_views), ("lb", R.pm_limit_bufs), ("fb", R.pm_flatten_bufferize),
  ("ab", R.pm_add_buffers), ("dg", R.to_define_global),
  ("aprt", R.pm_add_param_range_tags), ("sk", R.split_kernels),
]
for nm, pm in TABLES:
  print(f"--- {nm}: {len(pm.patterns)} rules, pdict keys")
  for k in sorted(pm.pdict.keys(), key=lambda s: sorted(o.name for o in (s if isinstance(s, (set, frozenset)) else [s]))):
    ks = k if isinstance(k, (set, frozenset)) else [k]
    print(f"    KEY {' '.join(sorted(o.name for o in ks))}")
  for i, (pat, fxn) in enumerate(pm.patterns):
    o = pat.op
    ks = 'ANY' if o is None else '|'.join(sorted(x.name for x in o))
    er = pat.early_reject
    ers = 'EMPTY' if er is None else ' '.join(sorted(x.name for x in er))
    loc = f"{pat.location[0].split('/')[-1]}:{pat.location[1]}"
    fsrc = getattr(fxn, 'location', None)
    floc = f"{fsrc[0].split('/')[-1]}:{fsrc[1]}" if fsrc else '?'
    print(f"  {i:2d} ops={ks:24s} rej={ers:20s} pat@{loc} fxn@{floc}")
