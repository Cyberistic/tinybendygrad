#!/usr/bin/env python3
"""rf-claims.py -- search the rangeify tables for a node TWO rules both CLAIM and
where the two BODIES DISAGREE, because that node is the only thing that can tell
first-wins from a conjunction (brief-port.md, GATE DISCIPLINE)."""
import sys, itertools
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, PatternMatcher, UPat, ParamArg, AxisType
from tinygrad.dtype import dtypes, AddrSpace, Invalid
from tinygrad.schedule.indexing import BufferizeOpts
import tinygrad.schedule.prepare as prep
from tinygrad.schedule import rangeify as R

IDX = dtypes.weakint
def C(n): return UOp.const(n, IDX)
def B(n=4): return UOp(Ops.BUFFER, arg=ParamArg(0, dtypes.int32, n, addrspace=AddrSpace.GLOBAL))

c0, c1, c2, c4 = C(0), C(1), C(2), C(4)
r0, r1 = UOp.range(4, 0), UOp.range(4, 1)
b4, bx = B(4), B(4)
a4 = UOp(Ops.ALLOC, arg=ParamArg(1, dtypes.int32, 4, addrspace=AddrSpace.GLOBAL))
p_g = UOp(Ops.PARAM, arg=ParamArg(2, dtypes.int32, 4, addrspace=AddrSpace.GLOBAL))
p_a = UOp(Ops.PARAM, arg=ParamArg(3, dtypes.int32, 4, addrspace=AddrSpace.ALU))
n0 = UOp(Ops.NOOP); nx = UOp(Ops.NOOP, (c0,))
e_n0 = UOp(Ops.END, (n0,)); e_nx = UOp(Ops.END, (nx,))
after = UOp(Ops.AFTER, (b4, e_n0))
after2 = UOp(Ops.AFTER, (b4, UOp(Ops.END, (UOp(Ops.STORE, (b4, c0)),))))
stg = UOp(Ops.STAGE, (b4, r0), arg=BufferizeOpts(device='CPU'))
stg3 = UOp(Ops.STAGE, (b4, r0, r1), arg=BufferizeOpts(device='CPU'))
ix_stg = UOp(Ops.INDEX, (stg, r0))
ix_af = UOp(Ops.INDEX, (after, r0))
ix_c = UOp(Ops.INDEX, (c4, r0))
ix_cast = UOp(Ops.INDEX, (UOp(Ops.CAST, (c0,), dtypes.float32), r0))
rs = UOp(Ops.RESHAPE, (b4, c4))
rs_i = UOp(Ops.RESHAPE, (ix_stg, c4))
sh0 = UOp(Ops.SHRINK, (b4, c0, c4))
sh1 = UOp(Ops.SHRINK, (b4, c1, c2))
call_i = UOp(Ops.CALL, (ix_stg, rs))
call_s = UOp(Ops.CALL, (sh1, c0))
ms_rs = UOp(Ops.MSTACK, (rs, rs))
st_self = UOp(Ops.STORE, (b4, b4))
st_inv = UOp(Ops.STORE, (b4, UOp.const(Invalid, IDX)))
e_n = UOp(Ops.END, (n0,))
mop = UOp(Ops.MUL, (r0, c4))
mop_i = UOp(Ops.MUL, (ix_stg, c4))

NODES = [c0, c1, c4, r0, r1, b4, bx, a4, p_g, p_a, n0, nx, e_n0, e_nx, after, after2,
         stg, stg3, ix_stg, ix_af, ix_c, ix_cast, rs, rs_i, sh0, sh1, call_i, call_s,
         ms_rs, st_self, st_inv, e_n, mop, mop_i]

# a 2-src STAGE is what `pm_add_buffers`' rules 3 (flatten_bufferize) and 4
# (bufferize_to_store) BOTH claim -- verified in Python, not assumed.

class Ctx:
  """a stand-in for the itertools.count / dataclass ctxs the rule bodies want."""
  range = 0
  def __next__(self): Ctx.range += 1; return Ctx.range
  def __iter__(self): return self

TABLES = [("gs", R.pm_gate_substitute), ("ct", R.pm_const_buffer_folding),
          ("rb", R.pm_remove_bufferize), ("nic", R.pm_no_indexing_calls),
          ("nv", R.pm_no_views), ("lb", R.pm_limit_bufs), ("fb", R.pm_flatten_bufferize),
          ("ab", R.pm_add_buffers), ("dg", R.to_define_global),
          ("aprt", R.pm_add_param_range_tags), ("sk", R.split_kernels)]

def call_body(fxn, uop, store):
  """the body of a rule, called the way PatternMatcher calls it."""
  import inspect
  names = list(store.keys())
  try:
    sig = inspect.signature(fxn)
  except (TypeError, ValueError):
    return ('SKIP', None)
  args = []
  for p in sig.parameters:
    if p == 'ctx': args.append(Ctx())
    else: args.append(store[p])
  try:
    return ('OK', fxn(*args))
  except Exception as e:
    return ('RAISE', type(e).__name__)

print("=== per node: which rules CLAIM, and what each body answers ===")
for nm, pm in TABLES:
  for u in NODES:
    claims = [i for i, (pat, f) in enumerate(pm.patterns) if pat.match(u, {})]
    if len(claims) < 2: continue
    answers = []
    for i in claims:
      pat, fxn = pm.patterns[i]
      binds = pat.match(u, {})[0]
      st, val = call_body(fxn, u, binds)
      answers.append((i, st, None if val is None else val.render()[:44]))
    # a DISAGREEMENT: two non-None answers that differ
    live = [(i, v) for i, s, v in answers if s == 'OK' and v is not None]
    dis = len(set(v for _, v in live)) > 1
    print(f"{nm} op={u.op.name:10s} nsrc={len(u.src)} claims={claims} dis={int(dis)}")
    for i, s, v in answers:
      print(f"      rule {i}: {s} {v}")
