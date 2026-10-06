"""Print per-graph census. Run from repo root.
python .agents/slop/newgraphs/census.py"""
import os, sys
os.environ["DEV"] = "CPU"
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", ".."))

# Execute graphcmp.py as a module, then grab its names
_gcmp_p = os.path.join(os.path.dirname(__file__), "..", "graphcmp.py")
with open(_gcmp_p) as f:
  _src = f.read()
_g_ns = {"__file__": _gcmp_p, "__name__": "__graphcmp_census__"}
exec(compile(_src, _gcmp_p, "exec"), _g_ns)

# Now _g_ns has everything graphcmp.py defines, including load_tinygrad
_g_ns["load_tinygrad"]()
_g_ns["COMM"] = _g_ns["commutative"]()

from tinygrad.helpers import Context
with Context(NO_COLOR=1):
  gs = sorted(_g_ns["GRAPHS"])
  all_ops = set()
  for nm in gs:
    g = _g_ns["GRAPHS"][nm]
    lst = list(g().toposort())
    ops = set(n.op.name for n in lst)
    all_ops.update(ops)
    print(f"{nm:12s} {len(lst):3d} nodes  ops={sorted(ops)}")
  print()
  print(f"Total reached: {len(all_ops)} of 77 ops")
  unreached = sorted(set(o.name for o in _g_ns["Ops"]) - all_ops)
  print(f"Unreached ({len(unreached)}): {unreached}")