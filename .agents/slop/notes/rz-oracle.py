# rz-oracle.py -- CPython answers for engine/realize.py, read out of a LIVE tinygrad.
# Every `want_*` the realize.bend gate asserts is printed here.
import sys, os
sys.path.insert(0, '.')
from tinygrad.uop.ops import Ops, UOp, UPat, PatternMatcher, AxisType, dtypes, KernelInfo, ProgramInfo
from tinygrad.engine.realize import get_call_arg_uops, get_call_var_uops, get_call_outs_ins, \
    get_call_written_bufs, get_call_kernels, get_call_name, estimate_uop
from tinygrad.engine.realize import pm_flatten_linear

# ---------------------------------------------------------------- the fixture
# A program CALL over one ordinary global BUFFER and one BOUND PARAM (a
# variable carrying a value), plus a STORE call and an encdec call.
K = UOp(Ops.SINK, src=(UOp(Ops.NOOP),), arg=KernelInfo(name="k1"))
buf = UOp.new_buffer("CPU", 16, dtypes.i32, None)
print("=== buf facts")
print("want_buf_is_bound =", buf.is_bound_var)
print("want_buf_dev      =", buf.device)
print("want_buf_shape    =", buf.shape)
print("want_buf_itemsize =", buf.dtype.itemsize)
# NOTE: `buf.expr` is NOT read here. `unwrap(None)` ASSERTS (helpers.py:95), so a
# nameless buffer raises AssertionError rather than answering None. Measured, and
# it contradicts the port's header comment -- see the gate's `expr_name` row.
from tinygrad.uop.ops import ParamArg, CallInfo
from tinygrad.uop.ops import AddrSpace
from dataclasses import replace
# `UOp.variable` is the documented constructor for a bound-able Variable, and
# `.bind` is what sets the `val` payload `is_bound_var` reads. Building the
# ParamArg by hand gets it re-wrapped (PARAM drops `val` on the way in, ops.py
# :1241), so both go through the API the module actually offers.
VAR = UOp.variable("n", 0, 8, dtypes.i32).bind(7)
print("=== VAR facts")
print("want_var_is_variable =", VAR.is_variable)
print("want_var_is_bound    =", VAR.is_bound_var)
print("want_var_expr        =", VAR.expr)
print("want_var_slot        =", VAR.arg.slot)
print("want_var_addr        =", VAR.arg.addrspace)
print("want_var_has_vm      =", VAR.arg.vmin_vmax is not None)
print("want_var_has_val     =", VAR.arg.val is not None)
print("want_var_val         =", VAR.arg.val)
print("want_var_nsrc        =", len(VAR.src))
NOOP = UOp(Ops.NOOP)
ZERO = UOp.const(0, dtypes.i32)
LIN = UOp(Ops.LINEAR, src=(NOOP,))
prog = UOp(Ops.PROGRAM, src=(K, LIN),
           arg=ProgramInfo(vars=(VAR,), globals=(0,), outs=(0,), ins=(1,)))
# The CALLs are built directly rather than through `.call()`, so the fixture does
# not depend on `UOp.ranges`/`sym_infer` -- which is exactly the wall this file
# defers, and asking the oracle to cross it would make the expectations circular.
def mkcall(body, *params): return UOp(Ops.CALL, src=(body, *params), arg=CallInfo())
call = mkcall(prog, buf, VAR)
store = mkcall(UOp(Ops.STORE, src=(ZERO, VAR)), buf, VAR)
encdec = mkcall(UOp(Ops.CUSTOM_FUNCTION, src=(NOOP,), arg="encdec"), buf, VAR)
valcall = mkcall(UOp(Ops.CUSTOM_FUNCTION, src=(NOOP,), arg="validate"), buf)

# `unique_num` restarts per interpreter run, so identities are compared by NAME
# rather than by number: `want_*_are` below lists the names, in order.
NAMES = {}
for nm, u in [("buf", buf), ("VAR", VAR), ("K", K), ("prog", prog), ("call", call),
              ("store", store), ("enc", encdec), ("val", valcall), ("NOOP", NOOP),
              ("ZERO", ZERO), ("LIN", LIN), ("CONST7", UOp.const(7, VAR.dtype))]:
  NAMES[u] = nm
def who(us): return [NAMES.get(u, "?") for u in us]

print("=== ids")
for nm in ["buf", "VAR", "K", "prog", "call", "store", "enc", "val"]:
  print("want_id_%s = %s" % (nm, nm))

print("=== get_call_arg_uops")
print("want_args_len   =", len(get_call_arg_uops(call)))
print("want_args_are   =", who(get_call_arg_uops(call)))
print("want_store_args =", who(get_call_arg_uops(store)))
print("want_enc_args   =", who(get_call_arg_uops(encdec)))
print("want_val_args   =", who(get_call_arg_uops(valcall)))

print("=== get_call_var_uops")
print("want_varuops    =", who(get_call_var_uops(call, prog)))
print("want_varuops_st =", who(get_call_var_uops(store, prog)))
print("want_varuops_va =", who(get_call_var_uops(valcall, prog)))
print("want_varuops_0  =", who(get_call_var_uops(store, prog)) [0])

print("=== get_call_outs_ins")
print("want_oi_call  =", get_call_outs_ins(call))
print("want_oi_store =", get_call_outs_ins(store))
print("want_oi_enc   =", get_call_outs_ins(encdec))
print("want_oi_none  =", get_call_outs_ins(valcall))

print("=== get_call_written_bufs")
print("want_wb_call  =", who(get_call_written_bufs(call)))
print("want_wb_store =", who(get_call_written_bufs(store)))
print("want_wb_enc   =", who(get_call_written_bufs(encdec)))
print("want_wb_val   =", who(get_call_written_bufs(valcall)))

print("=== get_call_kernels")
print("want_gk_call  =", [d for d, _, _ in get_call_kernels(call)])
print("want_gk_store =", [d for d, _, _ in get_call_kernels(store)])
print("want_gk_val   =", [d for d, _, _ in get_call_kernels(valcall)])
print("want_gk_enc   =", [d for d, _, _ in get_call_kernels(encdec)])

print("=== get_call_name")
print("want_name_call  =", repr(get_call_name(call, [buf, VAR])))
# The STORE and encdec arms need `sym_infer` and real `Buffer`s (`_dev_str` reads
# `buf.device`, which is None on an unrealized UOp) -- group [b], and the port
# answers None for those arms. Not an oracle row.

print("=== estimate_uop")
e = estimate_uop(call)
print("want_est_ops  =", e.ops)
print("want_est_mem  =", e.mem)
print("want_est_lds  =", e.lds)
e2 = estimate_uop(store)
print("want_est2_mem =", e2.mem)
print("want_est2_lds =", e2.lds)
print("want_est2_ops =", e2.ops)
e3 = estimate_uop(encdec)
print("want_est3_mem =", e3.mem)
e4 = estimate_uop(valcall)
print("want_est4_mem =", e4.mem)
print("want_est4_ops =", e4.ops)

print("=== pm_flatten_linear")
inner = UOp(Ops.LINEAR, src=(UOp(Ops.NOOP), UOp(Ops.NOOP)))
outer = UOp(Ops.LINEAR, src=(inner, UOp(Ops.NOOP)))
print("want_lin_fired   =", pm_flatten_linear.rewrite(outer) is not None)
print("want_lin_nsrc    =", len(pm_flatten_linear.rewrite(outer).src))
print("want_lin_none    =", pm_flatten_linear.rewrite(UOp(Ops.LINEAR, src=(UOp(Ops.NOOP),))) is None)
print("want_lin_inner   =", pm_flatten_linear.rewrite(inner) is None)

print("=== is_bound_var")
print("want_ibv_var   =", VAR.is_bound_var)
print("want_ibv_buf   =", buf.is_bound_var)

print("=== _resolve / resolve_params")
from tinygrad.engine.realize import resolve_params, _resolve
print("want_rp_call   =", who(resolve_params(call, [buf, ZERO])))
print("want_rp_store  =", who(resolve_params(store, [buf, ZERO])))
# the view recursion: a BITCAST over a PARAM resolves its src[0]
P0 = UOp(Ops.PARAM, dtypes.i32, arg=ParamArg(0, dtypes.i32, None, None, 1, "p0",
                                               AddrSpace.GLOBAL, ("CPU",), False, None, None, False, None))
P1 = UOp(Ops.PARAM, dtypes.i32, arg=ParamArg(1, dtypes.i32, None, None, 1, "p1",
                                               AddrSpace.GLOBAL, ("CPU",), False, None, None, False, None))
print("want_rs_param  =", who([_resolve(P0, [buf, ZERO])]))
print("want_rs_p1     =", who([_resolve(P1, [buf, ZERO])]))
# The view arms recurse over `b.src`, which is what makes them need a real src
# list. `UOp(BITCAST, dtypes.f32, (P0,))` builds dtype as a SRC, so the arg
# keyword is used instead.
bit = UOp(Ops.BITCAST, arg=dtypes.f32, src=(P0,))
rb = _resolve(bit, [buf, ZERO])
print("want_rs_bit_op      =", rb.op)
print("want_rs_bit_nsrc    =", len(rb.src))
print("want_rs_bit_src0    =", NAMES.get(rb.src[0], "?"))   # buf -- the PARAM became it
msel = UOp(Ops.MSELECT, arg=(0,), src=(bit, UOp.const(1, dtypes.i32)))
rm = _resolve(msel, [buf, ZERO])
print("want_rs_msel_op     =", rm.op)
print("want_rs_msel_nsrc   =", len(rm.src))
print("want_rs_msel_deep   =", NAMES.get(rm.src[0].src[0], "?"))   # buf, two levels down
ms2 = UOp(Ops.MSELECT, arg=(0,), src=(msel, UOp.const(1, dtypes.i32)))
print("want_rs_msel_x3     =", NAMES.get(_resolve(ms2, [buf, ZERO]).src[0].src[0].src[0], "?"))

print("=== unwrap_multi has_dnum")
from tinygrad.uop.ops import AxisType
def dnum(bd):
  return any((x.op is Ops.RANGE and x.axis_type is AxisType.DEVICE) or
             (x.op is Ops.PARAM and x.arg.name == '_device_num') for x in bd.toposort())
R0 = UOp.range(4, (0,), AxisType.DEVICE)
RG = UOp.range(4, (0,), AxisType.GLOBAL)
print("want_dnum_none =", dnum(prog))
print("want_dnum_dev  =", dnum(prog))   # prog has no RANGE
# the RANGE has to be INSIDE the body, so it goes in the LINEAR
prog_d = UOp(Ops.PROGRAM, src=(K, UOp(Ops.LINEAR, src=(R0, NOOP))),
             arg=ProgramInfo(vars=(), globals=(0,), outs=(0,), ins=(1,)))
print("want_dnum_dev  =", dnum(prog_d))
prog_g = UOp(Ops.PROGRAM, src=(K, UOp(Ops.LINEAR, src=(RG, NOOP))),
             arg=ProgramInfo(vars=(), globals=(0,), outs=(0,), ins=(1,)))
print("want_dnum_glob =", dnum(prog_g))
prog_dn = UOp(Ops.PROGRAM, src=(K, UOp(Ops.CUSTOM, arg="_device_num", src=(NOOP,))),
              arg=ProgramInfo(vars=(), globals=(0,), outs=(0,), ins=(1,)))
print("want_dnum_cust =", dnum(prog_dn))
prog_pn = UOp(Ops.PROGRAM, src=(K, UOp(Ops.PARAM, arg=ParamArg(-1, dtypes.i32, None,
              None, 1, "_device_num", AddrSpace.ALU))),
              arg=ProgramInfo(vars=(), globals=(0,), outs=(0,), ins=(1,)))
print("want_dnum_parm =", dnum(prog_pn))
print("want_dnum_weak =", dnum(prog_g))

print("=== _get_call_to_compile")
from tinygrad.engine.realize import _get_call_to_compile
print("want_gcc_call  =", _get_call_to_compile(call) is not None)
print("want_gcc_store =", _get_call_to_compile(store) is not None)
print("want_gcc_enc   =", _get_call_to_compile(encdec) is not None)
prog_c = UOp(Ops.PROGRAM, src=(K, UOp(Ops.BINARY, arg=b"\x00", src=())),
             arg=ProgramInfo(vars=(), globals=(0,), outs=(0,), ins=(1,)))
print("want_gcc_cbin  =", _get_call_to_compile(mkcall(prog_c, buf)) is not None)
prog_n = UOp(Ops.PROGRAM, src=(K, NOOP), arg=None)
print("want_gcc_nopi  =", _get_call_to_compile(mkcall(prog_n, buf)) is not None)

print("=== pm_beam")
from tinygrad.engine.realize import pm_beam
# `pm_beam`'s pattern is `CALL(src=(SINK(name="sink"),))`, so it only claims a
# CALL whose BODY is a SINK -- a PROGRAM call is not claimed at all. That is the
# row: the rule's claim is on the BODY op, not on the kernel.
sink0 = mkcall(UOp(Ops.SINK, src=(NOOP,), arg=KernelInfo(name="k1", beam=0)), buf)
beamed = pm_beam.rewrite(sink0, ctx=3)
print("want_beam_fired  =", beamed is not None)
print("want_beam_val    =", beamed.src[0].arg.beam if beamed is not None else None)
print("want_beam_nsrc   =", len(beamed.src) if beamed is not None else None)
K5 = UOp(Ops.SINK, src=(NOOP,), arg=KernelInfo(name="k1", beam=5))
nb = pm_beam.rewrite(mkcall(K5, buf), ctx=3)
print("want_beam_skip   =", nb is None)
print("want_beam_prog   =", pm_beam.rewrite(call, ctx=3) is None)

print("=== pm_validate claim")
from tinygrad.engine.realize import pm_validate
sinkcall = mkcall(UOp(Ops.SINK, src=(NOOP,), arg=KernelInfo(name="k1")), buf)
out = pm_validate.rewrite(sinkcall)
print("want_val_fired   =", out is not None)
print("want_val_is_call =", out.op if out is not None else None)
print("want_val_nsrc    =", len(out.src) if out is not None else None)
print("want_val_stores  =", [c.op for c in out.src] if out is not None else None)
outc = pm_validate.rewrite(call)
print("want_val_prog    =", outc is not None)

print("=== lower_and_compile collection")
lin = UOp(Ops.LINEAR, src=(call, store, encdec, valcall, sinkcall))
todo = [c for c in lin.toposort() if c.op is Ops.CALL and _get_call_to_compile(c) is not None]
print("want_ar_len  =", len(todo))
print("want_ar_who  =", who(todo))
print("want_lin_len =", len(lin.src))

print("=== compile_linear stage order (source only)")
import inspect, tinygrad.engine.realize as R
print(inspect.getsource(R.compile_linear))