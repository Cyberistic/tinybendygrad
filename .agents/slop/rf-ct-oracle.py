#!/usr/bin/env python3
"""rf-ct-oracle.py -- WHAT `ct_4`, `ct_5`, `ct_7` and `ct_8` ACTUALLY DO, asked of
CPython.  Every `py=` value a rangeify.bend row needs is here, and NOTHING in
this file re-transcribes a Python expression: the table keys come from `pdict`,
the bindings come from `UPat.match`, the answers come from `PatternMatcher.rewrite`.

THE FIRST QUESTION, because everything else depends on it.  A `.f()` chain is
`def f(self, op, **kwargs): return UPat(op, src=(self,), **kwargs)` (ops.py:1449),
so the chain REBUILDS the pattern with `op` as the ROOT and `self` as the CHILD,
and `PatternMatcher.__init__` keys `pdict` on `p.op` -- the ROOT.  So for a `.f()`
entry the ROOT is the op passed to `f` and the CHILD is the op of the pattern `f`
was called on.  The port's `ct_table` carries the CHILD's op for tags 0,1,2,5,8
and the ROOT's for 3,4,6,7, and the claim test is `pdict.get(uop.op)`.  So a node
whose op is the CHILD's is never even looked at.

THE SECOND QUESTION, which the first one makes sharp: a rewrite engine's
identity is the SRC OP SEQUENCE plus the arg identity, so every row below prints
`srcops=<the op of every src, in order>` and the answer's op/nsrc/srcops, not a
count.  A count is not a gate.
"""
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, PatternMatcher, UPat, ParamArg, KernelInfo, AxisType
from tinygrad.dtype import dtypes, AddrSpace, Invalid
from tinygrad.helpers import prod
from tinygrad.schedule.indexing import BufferizeOpts
from tinygrad.schedule import rangeify as R

IDX = dtypes.weakint
def C(n): return UOp.const(n, IDX)
def B(n=4, a=AddrSpace.GLOBAL, s=0, dev=None): return UOp(Ops.BUFFER, arg=ParamArg(s, dtypes.i32, n, addrspace=a, device=dev))
def Rg(n, i=0): return UOp.range(n, i)
def NO(): return BufferizeOpts(device=None, addrspace=AddrSpace.GLOBAL, removable=False)

def srcops(u): return "[" + ",".join(s.op.name for s in u.src) + "]"
def desc(u):
  if u is None: return "None"
  return f"{u.op.name}/nsrc{len(u.src)}/srcops={srcops(u)}/arg={u.arg!r}"

def claim_count(pm, u, tag=None):
  return sum(1 for p, _ in pm.patterns if (tag is None or pm.patterns.index((p, _)) == tag) and p.match(u, {}))

def first_tag(pm, u):
  """which pattern index the compiled `rewrite` would use, read off pdict order"""
  for i, (p, _f) in enumerate(pm.patterns):
    if u.op in p.op and p.early_reject.issubset({s.op for s in u.src}) and p.match(u, {}): return i
  return None

print("=== 0. TABLE KEYS, read off the PATTERNS and off pdict ===")
for tag, (p, _fxn) in enumerate(R.pm_const_buffer_folding.patterns):
  print(f"ct[{tag}] root={','.join(o.name for o in p.op)} rej={sorted(x.name for x in p.early_reject)} "
        f"n_op={len(p.op)}")
print("pdict:", {k.name: [i for i, (p, _f) in enumerate(R.pm_const_buffer_folding.patterns) if k in p.op]
                  for k in R.pm_const_buffer_folding.pdict})
print()
print("--- pm_mops alone (prepare.py:76-83), the three FOREIGN tags ---")
from tinygrad.schedule.prepare import pm_mops
for tag, (p, _fxn) in enumerate(pm_mops.patterns):
  print(f"mops[{tag}] root={','.join(o.name for o in p.op)} n_op={len(p.op)} "
        f"child_src0_op={p.src[0][0].op if p.src is not None and p.src[0] and p.src[0][0].op is not None else None}")
print("mops root-set sizes:", [len(p.op) for p, _ in pm_mops.patterns])
print("GroupOp.Movement size:", len(Ops.__members__) and __import__('tinygrad.uop.ops', fromlist=['GroupOp']).GroupOp.Movement)
print()

# ---------------------------------------------------------------------------
# fixtures.  Each PAIR differs only in WHICH op is at the inner vs the outer
# position, which is the discriminator the whole exercise needs.
# ---------------------------------------------------------------------------
c0, c1, c4 = C(0), C(1), C(4)
b4 = B(4, AddrSpace.GLOBAL, 0)
b5 = B(5, AddrSpace.GLOBAL, 1)
b4dev = B(4, AddrSpace.GLOBAL, 2, dev='CPU')
r0, r1 = Rg(4, 0), Rg(4, 1)

print("=== 1. ct_4 -- UPat(Ops.INDEX,name='idx').f(Ops.STAGE,name='b2') ===")
print("python source: def remove_noop_bufferize(idx,b2):")
print("   if idx.src[1:] != b2.src[1:]: return None")
print("   return idx.src[0].shrink(tuple((0,s) for s in b2.shape)) if b2.shape else idx.src[0]")
print()
# A: the shape the pattern wants -- a STAGE whose src[0] is an INDEX, tails equal
ix_b4  = UOp(Ops.INDEX, (b4, r0))
stgA   = UOp(Ops.STAGE, (ix_b4, r0), arg=NO())
# B: the mirror -- an INDEX whose src[0] is a STAGE.  `rewrite` is called on the
#    INDEX here, and the INDEX is tag 6/7/8 territory, never tag 4.
stgB0  = UOp(Ops.STAGE, (b4, r0), arg=NO())
ixB    = UOp(Ops.INDEX, (stgB0, r0))
# C: a STAGE whose src[0] is a BUFFER -- the inner op is NOT the sub-pattern's
ixC    = UOp(Ops.INDEX, (b5, r0))
stgC   = UOp(Ops.STAGE, (ixC, r0), arg=NO())
# D: tails DIFFER -- the `!=` refuses
ixD    = UOp(Ops.INDEX, (b4, r0))
stgD   = UOp(Ops.STAGE, (ixD, r1), arg=NO())
# E: no ranges at all, so `b2.shape` is `()` and the `if b2.shape` arm is FALSE
ixE    = UOp(Ops.INDEX, (b4,))
stgE   = UOp(Ops.STAGE, (ixE,), arg=NO())

for lbl, u in [("ct4A_stg_of_ix", stgA), ("ct4B_ix_of_stg", ixB), ("ct4C_stg_of_ix_b5", stgC),
               ("ct4D_stg_tail_diff", stgD), ("ct4E_stg_no_rng", stgE), ("ct4_b4_bare", b4)]:
  m = R.pm_const_buffer_folding.patterns[4][0].match(u, {})
  a = R.pm_const_buffer_folding.rewrite(u)
  print(f"{lbl}: in={desc(u)} tag4_nbind={len(m)} first_tag={first_tag(R.pm_const_buffer_folding, u)} "
        f"out={desc(a)} claim_n={claim_count(R.pm_const_buffer_folding, u)}")
print()
print("-- the body called DIRECTLY, so the pattern and the body are separated --")
for lbl, (i, b2) in [("ct4A_fn", (ix_b4, stgA)), ("ct4C_fn", (ixC, stgC)), ("ct4D_fn", (ixD, stgD)),
                     ("ct4E_fn", (ixE, stgE))]:
  a = R.remove_noop_bufferize(i, b2)
  print(f"{lbl}: idx.srcops={srcops(i)} b2.srcops={srcops(b2)} b2.shape={b2.shape} "
        f"tails_eq={int(i.src[1:] == b2.src[1:])} out={desc(a)}")
print()

# ---------------------------------------------------------------------------
print("=== 2. ct_5 -- UPat.cvar('c').or_casted().f(Ops.STAGE,name='b') ===")
print("python source: lambda c,b: b.const_like(c.val)")
print()
stgCst   = UOp(Ops.STAGE, (c4, r0), arg=NO())
cast_c4  = UOp(Ops.CAST, (c4,), arg=dtypes.f16)
stgCast  = UOp(Ops.STAGE, (cast_c4, r0), arg=NO())
stgBuf   = UOp(Ops.STAGE, (b4, r0), arg=NO())
stgCstN  = UOp(Ops.STAGE, (c4,), arg=NO())
for lbl, u in [("ct5_stg_of_const", stgCst), ("ct5_stg_of_cast", stgCast),
               ("ct5_stg_of_buf", stgBuf), ("ct5_stg_of_const_norng", stgCstN)]:
  m = R.pm_const_buffer_folding.patterns[5][0].match(u, {})
  a = R.pm_const_buffer_folding.rewrite(u)
  print(f"{lbl}: in={desc(u)} tag5_nbind={len(m)} first_tag={first_tag(R.pm_const_buffer_folding, u)} "
        f"out={desc(a)}")
print("-- the body called DIRECTLY --")
for lbl, (c, b) in [("ct5_fn_const", (c4, stgCst)), ("ct5_fn_cast", (cast_c4, stgCast)),
                    ("ct5_fn_cast_bare", (cast_c4, stgCst))]:
  a = b.const_like(c.val if c.op is Ops.CONST else c.src[0].val)
  print(f"{lbl}: c={desc(c)} c.val={c.val if c.op is Ops.CONST else '-'} out={desc(a)} "
        f"dtype={a.dtype}")
print()

# ---------------------------------------------------------------------------
print("=== 3. ct_8 -- UPat(Ops.MSTACK,src=(UPat.var('s'),),allow_any_len=True).f(Ops.INDEX,name='idx') ===")
print("python source: lambda s,idx: idx.replace(src=(s,)+idx.src[1:]) if s.device is None else None")
print()
ms_devless = UOp(Ops.MSTACK, (c4, c1))
ix_msdl    = UOp(Ops.INDEX, (ms_devless,))
ms_dev     = UOp(Ops.MSTACK, (b4dev,))
ix_msd     = UOp(Ops.INDEX, (ms_dev,))
ms_bufnodev= UOp(Ops.MSTACK, (b4,))
ix_msbn    = UOp(Ops.INDEX, (ms_bufnodev,))
# an INDEX over an MSTACK WITH ranges, so `idx.src[1:]` is non-empty
ix_ms_rng  = UOp(Ops.INDEX, (ms_devless, r0))
for lbl, u in [("ct8_ix_ms_devless", ix_msdl), ("ct8_ix_ms_dev", ix_msd),
               ("ct8_ix_ms_bufnodev", ix_msbn), ("ct8_ix_ms_rng", ix_ms_rng),
               ("ct8_bare_mstack", ms_devless)]:
  m = R.pm_const_buffer_folding.patterns[8][0].match(u, {})
  a = R.pm_const_buffer_folding.rewrite(u)
  print(f"{lbl}: in={desc(u)} tag8_nbind={len(m)} first_tag={first_tag(R.pm_const_buffer_folding, u)} "
        f"out={desc(a)} is_self={int(a is u)}")
print("-- s.device, which is the ONLY thing the body tests --")
for lbl, s in [("ct8_devless_s", ms_devless.src[0]), ("ct8_dev_s", ms_dev.src[0]),
               ("ct8_bufnodev_s", ms_bufnodev.src[0])]:
  print(f"{lbl}: op={s.op.name} device={s.device!r} device_is_none={int(s.device is None)}")
print("-- the body called DIRECTLY --")
for lbl, (s, idx) in [("ct8_fn_devless", (c4, ix_msdl)), ("ct8_fn_dev", (b4dev, ix_msd)),
                      ("ct8_fn_rng", (c4, ix_ms_rng))]:
  a = idx.replace(src=(s,)+idx.src[1:]) if s.device is None else None
  print(f"{lbl}: in={desc(idx)} s={desc(s)} out={desc(a)} is_self={int(a is idx)}")
print()

# ---------------------------------------------------------------------------
print("=== 4. ct_7 -- UPat(Ops.INDEX,src=(UPat(Ops.AFTER,name='after'),),name='idx') ===")
print("python source: lambda idx,after: idx.const_like(Invalid) if after_all_invalid(after) else None")
print()
stc = UOp(Ops.CONST, (), Invalid)
store_inv = UOp(Ops.STORE, (b4, stc))
end_inv = UOp(Ops.END, (store_inv,))
end_inv_r = UOp(Ops.END, (store_inv, r0))
af_inv = UOp(Ops.AFTER, (b4, end_inv))
af_inv_r = UOp(Ops.AFTER, (b4, end_inv_r))
ix_af = UOp(Ops.INDEX, (af_inv,))
ix_af_r = UOp(Ops.INDEX, (af_inv_r,))
for lbl, u in [("ct7_ix_after", ix_af), ("ct7_ix_after_rng", ix_af_r), ("ct7_bare_after", af_inv)]:
  m = R.pm_const_buffer_folding.patterns[7][0].match(u, {})
  try: a = R.pm_const_buffer_folding.rewrite(u)
  except Exception as e: a = f"RAISED {type(e).__name__}: {e}"
  print(f"{lbl}: in={desc(u)} tag7_nbind={len(m)} first_tag={first_tag(R.pm_const_buffer_folding, u)} "
        f"out={a if isinstance(a, str) else desc(a)}")
for lbl, a in [("ct7_after_norng", af_inv), ("ct7_after_rng", af_inv_r)]:
  try: print(f"ct7_fn({lbl}) -> {R.after_all_invalid(a)}")
  except Exception as e: print(f"ct7_fn({lbl}) RAISED {type(e).__name__}: {e}")
print("# MEASURED DEFECT, reported not fixed: after_all_invalid ends in")
print("# `resolve(cast(UOp, prod(r.src[0] for r in s.ended_ranges)).eq(buf.numel()), False)`")
print("# (rangeify.py:113) and `prod()` of an EMPTY ended_ranges is the python int 1,")
print("# so `.eq` on it raises AttributeError.  A CAST/expand-only END has no RANGE, so")
print("# an all-invalid AFTER with no ranges CRASHES the rule rather than answering.")
print("ct7_empty_ended_ranges_prod =", prod([]), type(prod([])).__name__)
print("ct7_buf_numel =", b4.numel(), type(b4.numel()).__name__)
print()

# ---------------------------------------------------------------------------
print("=== 6. THE ARG GATE, on the node ct_8 REBUILDS ===")
print("the old gate could not see an arg because every node a mp_replace rule")
print("reaches was given ANone.  `UOp` does NOT type-check arg against op, so an")
print("INDEX may carry an arbitrary arg; prepare.py:70 does exactly that with")
print("`arg=idx.arg`.  Probed: which args an INDEX accepts, and which SURVIVE the")
print("ct_8 rebuild.")
print()
AR = (7, AxisType.LOOP)
for name, arg in [("none", None), ("range", AR), ("kinfo", KernelInfo()),
                  ("parmarg", b4.arg), ("int", 3), ("tup", (0, 1))]:
  try:
    u = UOp(Ops.INDEX, (ms_devless,), arg=arg)
    ok = "built"
  except Exception as e:
    print(f"ct8arg_{name}: RAISED {type(e).__name__}: {e}")
    continue
  a = R.pm_const_buffer_folding.rewrite(u)
  same = int(a is not None and a.arg is arg)
  isnone = int(a is not None and a.arg is None)
  print(f"ct8arg_{name}: in={desc(u)} out={'None' if a is None else desc(a)} "
        f"arg_is_own={same} arg_is_none={isnone} claim_n={claim_count(R.pm_const_buffer_folding, u)} "
        f"first_tag={first_tag(R.pm_const_buffer_folding, u)}")
print()
# and the ANone twin of the LIVE one, so a row pair is not a pair of absolutes
u_r = UOp(Ops.INDEX, (ms_devless,), arg=AR)
u_n = UOp(Ops.INDEX, (ms_devless,))
for lbl, u in [("ct8R_ix_arg_range", u_r), ("ct8N_ix_arg_none", u_n)]:
  a = R.pm_const_buffer_folding.rewrite(u)
  print(f"{lbl}: out={'None' if a is None else desc(a)} "
        f"arg_is_own_range={int(a is not None and a.arg is AR)} arg_is_none={int(a is not None and a.arg is None)}")
print()
print("=== 7. ct_8 WITH RANGES, the src[1:] half -- the rebuild is a real rebuild ===")
for lbl, u in [("ct8R_ix_arg_range_r0", UOp(Ops.INDEX, (ms_devless, r0), arg=AR)),
               ("ct8D_ix_dev_arg_range", UOp(Ops.INDEX, (ms_dev, r0), arg=AR))]:
  a = R.pm_const_buffer_folding.rewrite(u)
  print(f"{lbl}: in={desc(u)} out={'None' if a is None else desc(a)} is_self={int(a is u)}")
print()
# ---------------------------------------------------------------------------
print("=== 8. THE DISCRIMINATING PAIRS, as the gate will name them ===")
print("# every pair below differs ONLY in which op is inner vs outer.")
print(f"ct4A_claim = {claim_count(R.pm_const_buffer_folding, stgA)}   ct4A_out = {desc(R.pm_const_buffer_folding.rewrite(stgA))}")
print(f"ct4B_claim = {claim_count(R.pm_const_buffer_folding, ixB)}   ct4B_out = {desc(R.pm_const_buffer_folding.rewrite(ixB))}")
print(f"ct5_const_claim = {claim_count(R.pm_const_buffer_folding, stgCst)} ct5_const_out = {desc(R.pm_const_buffer_folding.rewrite(stgCst))}")
print(f"ct5_cast_claim = {claim_count(R.pm_const_buffer_folding, stgCast)} ct5_cast_out = {desc(R.pm_const_buffer_folding.rewrite(stgCast))}")
print(f"ct5_buf_claim = {claim_count(R.pm_const_buffer_folding, stgBuf)} ct5_buf_out = {desc(R.pm_const_buffer_folding.rewrite(stgBuf))}")
print(f"ct8_devless_claim = {claim_count(R.pm_const_buffer_folding, ix_msdl)} ct8_devless_out = {desc(R.pm_const_buffer_folding.rewrite(ix_msdl))}")
print(f"ct8_dev_claim = {claim_count(R.pm_const_buffer_folding, ix_msd)} ct8_dev_out = {desc(R.pm_const_buffer_folding.rewrite(ix_msd))}")

# ---------------------------------------------------------------------------
# CT7B: the one node where tag 7's REJECT SET is not its CLAIM.  `early_reject`
# is `{AFTER}` and `ler` is `{RANGE, AFTER}`, so the set test passes on an AFTER
# in ANY src while the PATTERN needs it at src[0].  This is the shape the Bend
# row `ct7b_cnt` gates, so it is measured here and nowhere else.
print()
print("=== 9. CT7B: the reject set is not the claim ===")
ct7b = UOp(Ops.INDEX, (r0, af_inv))
_m = R.pm_const_buffer_folding.patterns[7][0].match(ct7b, {})
print(f"ct7b_ix_range_after: in={desc(ct7b)} ler={{{','.join(sorted(s.op.name for s in ct7b.src))}}} "
      f"rej={sorted(x.name for x in R.pm_const_buffer_folding.patterns[7][0].early_reject)} "
      f"tag7_nbind={len(_m)} claim_n={claim_count(R.pm_const_buffer_folding, ct7b)} "
      f"rewrite={'None' if R.pm_const_buffer_folding.rewrite(ct7b) is None else 'NODE'}")
print(f"ct7a_ix_after:      ler={{{','.join(sorted(s.op.name for s in ix_af.src))}}} "
      f"tag7_nbind={len(R.pm_const_buffer_folding.patterns[7][0].match(ix_af, {}))} "
      f"claim_n={claim_count(R.pm_const_buffer_folding, ix_af)}")
