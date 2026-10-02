#!/usr/bin/env python3
"""rf-rows.py -- every gate row for rangeify.bend, as `name = value`, with the
CLAIM COUNT of each fixture node.  The claim counts are what make first-wins
visible: a node two rules both claim is the only node that can tell a first-wins
fold from a conjunction (brief-port.md, GATE DISCIPLINE)."""
import sys, inspect
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, PatternMatcher, UPat, ParamArg, AxisType
from tinygrad.dtype import dtypes, AddrSpace, Invalid
from tinygrad.schedule.indexing import BufferizeOpts
from tinygrad.helpers import prod
from tinygrad.schedule import rangeify as R
import tinygrad.schedule.prepare as prep
import tinygrad.codegen.simplify as simp

IDX = dtypes.weakint
def C(n): return UOp.const(n, IDX)
def B(n=4, a=AddrSpace.GLOBAL, s=0): return UOp(Ops.BUFFER, arg=ParamArg(s, dtypes.i32, n, addrspace=a))

c0, c1, c2, c4 = C(0), C(1), C(2), C(4)
r0, r1 = UOp.range(4, 0), UOp.range(4, 1)
b4 = B(4, AddrSpace.GLOBAL, 0)
bx = B(4, AddrSpace.GLOBAL, 1)
a4 = UOp(Ops.ALLOC, arg=ParamArg(1, dtypes.i32, 4, addrspace=AddrSpace.GLOBAL))
p_g = UOp(Ops.PARAM, arg=ParamArg(2, dtypes.i32, 4, addrspace=AddrSpace.GLOBAL))
p_a = UOp(Ops.PARAM, arg=ParamArg(3, dtypes.i32, 4, addrspace=AddrSpace.ALU))
n0 = UOp(Ops.NOOP); nx = UOp(Ops.NOOP, (c0,))
e_n0 = UOp(Ops.END, (n0,)); e_nx = UOp(Ops.END, (nx,))
after = UOp(Ops.AFTER, (b4, e_n0, e_nx, UOp(Ops.END, (b4,))))
after1 = UOp(Ops.AFTER, (b4, e_n0))
afterk = UOp(Ops.AFTER, (b4, UOp(Ops.END, (b4,))))
stg2 = UOp(Ops.STAGE, (b4, r0), arg=BufferizeOpts(device='CPU'))
stg3 = UOp(Ops.STAGE, (b4, r0, r1), arg=BufferizeOpts(device='CPU'))
ix_stg = UOp(Ops.INDEX, (stg2, r0))
ix_c = UOp(Ops.INDEX, (c4, r0))
rs = UOp(Ops.RESHAPE, (b4, c4))
rs_i = UOp(Ops.RESHAPE, (ix_stg, c4))
rs_m = UOp(Ops.RESHAPE, (b4, c4))
sh0 = UOp(Ops.SHRINK, (b4, c0, c4))
sh1 = UOp(Ops.SHRINK, (b4, c1, c2))
call_i = UOp(Ops.CALL, (ix_stg, rs))
call_s = UOp(Ops.CALL, (sh1, c0))
call_m = UOp(Ops.CALL, (UOp(Ops.MSTACK, (sh1, sh0)), c0))
ms_rs = UOp(Ops.MSTACK, (rs, rs))
mse_rs = UOp(Ops.MSELECT, (b4, rs), arg=(0,))
st_self = UOp(Ops.STORE, (b4, b4))
st_inv = UOp(Ops.STORE, (b4, UOp.const(Invalid, IDX)))
call_rs = UOp(Ops.CALL, (rs, c0))
r0_t, p_t, p_at = r0.rtag(()), p_g.rtag(()), p_a.rtag(())

def n(x): return 0 if x is None else 1
def nm(x): return 0 if x is None else OPMAP.get(x.op, 99)
OPMAP = {}

def claims(pm, u): return len([1 for pat, f in pm.patterns if pat.match(u, {})])
def rw(pm, u):
  try: return pm.rewrite(u)
  except Exception: return 'RAISE'

print("### TABLE LENGTHS (the COUNT rows)")
print("ct_len =", len(R.pm_const_buffer_folding.patterns))
print("rb_len =", len(R.pm_remove_bufferize.patterns))
print("nic_len =", len(R.pm_no_indexing_calls.patterns))
print("nv_len =", len(R.pm_no_views.patterns))
print("lb_len =", len(R.pm_limit_bufs.patterns))
print("fb_len =", len(R.pm_flatten_bufferize.patterns))
print("ab_len =", len(R.pm_add_buffers.patterns))
print("dg_len =", len(R.to_define_global.patterns))
print("aprt_len =", len(R.pm_add_param_range_tags.patterns))
print("sk_len =", len(R.split_kernels.patterns))
print("gs_len =", len(R.pm_gate_substitute.patterns))
print("mops_len =", len(prep.pm_mops.patterns))
print("flatrange_len =", len(simp.pm_flatten_range.patterns))
print("sym_len =", len(__import__('tinygrad.uop.symbolic', fromlist=['symbolic']).symbolic.patterns))

print("### is_noop_after_dep / remove_noop_afters")
for k, u in (("n0", n0), ("nx", nx), ("e_n0", e_n0), ("e_nx", e_nx), ("b4", b4)):
  print(f"noopf_{k} =", int(R.is_noop_after_dep(u)))
print("raf_after_nsrc =", len(R.remove_noop_afters(after).src))
print("raf_after_op =", 1 if R.remove_noop_afters(after).op is Ops.AFTER else 0)
print("raf_afterk =", n(R.remove_noop_afters(afterk)))
print("raf_after1_is_src0 =", int(R.remove_noop_afters(after1) is b4))

print("### strip_zero_offset_shrink / no_indexing_calls / pm_no_views")
print("szs_sh1_is_src0 =", int(R.strip_zero_offset_shrink(sh1) is b4))
print("szs_sh0_is_src0 =", int(R.strip_zero_offset_shrink(sh0) is b4))
print("szs_n0_is_self =", int(R.strip_zero_offset_shrink(n0) is n0))
print("nic_calli =", n(R.pm_no_indexing_calls.rewrite(call_i)))
print("nic_calls =", n(R.pm_no_indexing_calls.rewrite(call_s)))
print("nic_callm =", n(R.pm_no_indexing_calls.rewrite(call_m)))
print("nic_b4 =", n(R.pm_no_indexing_calls.rewrite(b4)))
ci = R.pm_no_indexing_calls.rewrite(call_i)
print("nic_calli_nsrc =", len(ci.src) if ci is not None else 0)
cs = R.pm_no_indexing_calls.rewrite(call_s)
print("nic_calls_src0_is_b4 =", int(cs.src[0] is b4) if cs is not None else 0)
cm = R.pm_no_indexing_calls.rewrite(call_m)
print("nic_callm_src0_nsrc =", len(cm.src[0].src) if cm is not None else 0)
print("nv_rs_is_src0 =", int(R.pm_no_views.rewrite(rs) is b4))
print("nv_rsi =", n(R.pm_no_views.rewrite(rs_i)))
print("nv_b4 =", n(R.pm_no_views.rewrite(b4)))

print("### pm_remove_bufferize")
print("rb_self_is_noop =", int(R.pm_remove_bufferize.rewrite(st_self) is not None and R.pm_remove_bufferize.rewrite(st_self).op is Ops.NOOP))
print("rb_self_nsrc =", len(R.pm_remove_bufferize.rewrite(st_self).src))
print("rb_diff =", n(R.pm_remove_bufferize.rewrite(UOp(Ops.STORE, (b4, bx)))))
print("rb_e_n0 =", n(R.pm_remove_bufferize.rewrite(e_n0)))
print("rb_ix_stg =", n(R.pm_remove_bufferize.rewrite(ix_stg)))

print("### pm_add_param_range_tags")
for k, u in (("r0", r0), ("r0t", r0_t), ("pglob", p_g), ("pgloT", p_t),
             ("palu", p_a), ("paluT", p_at), ("b4", b4)):
  y = R.pm_add_param_range_tags.rewrite(u)
  print(f"aprt_{k} =", n(y), "" if y is None else repr(y.tag))

print("### renumber_range")
class Cx:
  def __init__(s): s.range = 0
c = Cx(); o = R.renumber_range(c, r0_t)
print("ren_none =", n(R.renumber_range(Cx(), r0)))
print("ren_arg0 =", o.arg[0])
print("ren_tag_none =", int(o.tag is None))
print("ren_next =", c.range)
c = Cx(); c.range = 7; o2 = R.renumber_range(c, r0_t)
print("ren7_arg0 =", o2.arg[0])
print("ren7_next =", c.range)

print("### CLAIM COUNTS (the first-wins rows)")
for k, pm, u in (("ab_stg2", R.pm_add_buffers, stg2), ("ab_stg3", R.pm_add_buffers, stg3),
                 ("ab_rs", R.pm_add_buffers, rs), ("ab_call", R.pm_add_buffers, call_i),
                 ("ab_ms", R.pm_add_buffers, ms_rs), ("ab_mse", R.pm_add_buffers, mse_rs),
                 ("ab_stinv", R.pm_add_buffers, st_inv), ("ab_callrs", R.pm_add_buffers, call_rs),
                 ("ab_after", R.pm_add_buffers, after), ("ab_afterk", R.pm_add_buffers, afterk),
                 ("ct_stg2", R.pm_const_buffer_folding, stg2),
                 ("ct_ixstg", R.pm_const_buffer_folding, ix_stg),
                 ("ct_ixc", R.pm_const_buffer_folding, ix_c),
                 ("ct_after", R.pm_const_buffer_folding, after),
                 ("ct_mse", R.pm_const_buffer_folding, mse_rs),
                 ("rb_self", R.pm_remove_bufferize, st_self),
                 ("rb_en0", R.pm_remove_bufferize, e_n0),
                 ("rb_ixstg", R.pm_remove_bufferize, ix_stg),
                 ("nv_rs", R.pm_no_views, rs), ("nv_rsi", R.pm_no_views, rs_i),
                 ("dg_b4", R.to_define_global, b4), ("dg_a4", R.to_define_global, a4),
                 ("dg_pg", R.to_define_global, p_g), ("dg_pa", R.to_define_global, p_a),
                 ("dg_pat", R.to_define_global, p_at), ("dg_r0", R.to_define_global, r0),
                 ("dg_r0t", R.to_define_global, r0_t), ("dg_after", R.to_define_global, after),
                 ("dg_stg", R.to_define_global, stg2),
                 ("dg_ixpa", R.to_define_global, UOp(Ops.INDEX, (p_a,))),
                 ("dg_ixpg", R.to_define_global, UOp(Ops.INDEX, (p_g,))),
                 ("dg_ms", R.to_define_global, ms_rs),
                 ("sk_stinv", R.split_kernels, st_inv),
                 ("sk_e_n0", R.split_kernels, e_n0),
                 ("fb_stg3", R.pm_flatten_bufferize, stg3),
                 ("nic_calli", R.pm_no_indexing_calls, call_i),
                 ):
  print(f"claim_{k} =", claims(pm, u))

print("### the two-rules-claim-one-node node, resolved")
print("ab_stg2_flatten =", n(R.flatten_bufferize(stg2)))
print("ab_stg3_flatten =", n(R.flatten_bufferize(stg3)))
