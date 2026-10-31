#!/usr/bin/env python3
"""schedstore-oracle.py -- CPython's answers to `gates/schedstore.bend`'s twenty-five rows.

The two lanes share no code: the Bend lane calls the PORT's `is_store_after`,
`collect_stores` and `canonicalize_alloc` from
`tinybendygrad/schedule/__init__.bend`, this lane calls CPython's from
`tinygrad/schedule` and asks the same questions. A row agrees only if two
implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/schedstore-oracle.py

THE SUBJECT IS `tinygrad/schedule/__init__.py:213-237`, which is in the region
the port's own header DEFERS:

    def is_store_after(u:UOp) -> bool:
      return u.op is Ops.AFTER and (u.src[0].unsharded_base.op is not Ops.ALLOC
                                    or u.src[1].op is Ops.STORE)

    def collect_stores(ctx:CallifyCtx, u:UOp):
      if is_store_after(u): ctx.stores.append(u)

    def canonicalize_alloc(ctx:CallifyCtx, b:UOp):
      if b.arg.slot >= 0 and b not in ctx.allocs:
        ctx.allocs[b] = b.replace(arg=replace(b.arg, slot=-1-len(ctx.allocs)))
      return ctx.allocs.get(b)

`is_store_after` is the rule the port's header called "the clearest case" of
the ctx DICT: `CallifyCtx` is a dataclass of a list, a dict, a set and another
list.

THE FIXTURE IS THE PORT'S, ONE FOR ONE -- the same ops, the same srcs and the
same CONSTRUCTION ORDER, so the two lanes compare the same nodes. An ALLOC and
a BUFFER are built the same way and differ only in their op, which is what
makes the ALLOC arm of the `or` reachable at all: `AFTER(ALLOC, CALL)` is the
one AFTER that upstream REJECTS.

THE `RESHAPE` FIXTURES ARE WHAT MAKE THE GATE FALSIFIABLE. `unsharded_base` is
a WALK, and a walk over an ALLOC is the IDENTITY -- so `AFTER(ALLOC, CALL)`
reads the same under `src[0].op` and under `src[0].unsharded_base.op`, and a
gate built only from the DIRECT children cannot see the walk. MEASURED
2026-10-30: with `src[0].op` in place of `src[0].unsharded_base.op`, this gate
was GREEN on all fifteen rows it then had. `AFTER(RESHAPE(ALLOC), CALL)` is
the fixture that separates them: `unsharded_base` peels the RESHAPE to the
ALLOC underneath and upstream answers 0, while `src[0].op` reads RESHAPE and
answers 1.

THE ROW IS THE BOOLEAN and not the OP, because the property IS a boolean: four
different fixtures exercise four different arms of the same `or`, and an OP row
would read `AFTER` on both sides for the wrong fixture and would not move.

`cs_allocs` IS THE ROW THAT SAYS THE CTX DICT IS NOT THE WALL. CPython's
`CallifyCtx` has FOUR fields and `collect_stores` writes ONE of them, so the
other three are empty -- and a port that modelled the ctx as a single list, or
that wrote the wrong field, would answer 1 here.

`ca_slot3` IS THE ROW THAT FOUND A REAL PORT DEFECT. Upstream's
`canonicalize_alloc` on an ALLOC that is ALREADY in `ctx.allocs` answers THE
STORED NODE -- the canonicalized one, with its negative slot -- and the port
answered `None{}`, because its guard's arm never read `ctx.allocs` at all.
"""

from tinygrad.dtype import AddrSpace, dtypes
from tinygrad.uop.ops import Ops, ParamArg, UOp, CallInfo, KernelInfo
from tinygrad.schedule import (CallifyCtx, canonicalize_alloc, collect_stores, is_store_after,
                                copy_kernel_to_store, simplify_copy_kernel, assert_all_same_devices,
                                lower_sink_to_linear, resolve_linear_call)


def code(u):
  return u.op.name if u is not None else "None"


# THE PORT'S `pb` -- `ParamArg(slot, dtype, name=..., device=...)`, CPU is the
# device NAME here and the port's `SP.D1{0}` TAG there.
def pb(slot: int, nm: str) -> ParamArg:
  return ParamArg(slot, dtypes.int32, name=nm, device="CPU")


# THE PORT'S `buf` -- a BUFFER with a size CONST src.
def buf(slot: int, nm: str) -> UOp:
  UOp(Ops.SPECIAL, src=(UOp.const(1, dtypes.int32),), arg=nm)
  return UOp(Ops.BUFFER, src=(UOp.const(4, dtypes.int32),), arg=pb(slot, nm))


# THE PORT'S `alloc` -- an ALLOC with a `ParamArg`, the same shape as the BUFFER.
def alloc(slot: int, nm: str) -> UOp:
  return UOp(Ops.ALLOC, src=(UOp.const(4, dtypes.int32),), arg=pb(slot, nm))


# THE PORT'S `body` -- `UOp(Ops.SINK, src=(UOp(Ops.STORE, src=(c0, cn)),))`.
def body(n: int) -> UOp:
  c0 = UOp.const(0, dtypes.int32)
  cn = UOp.const(n, dtypes.int32)
  st = UOp(Ops.STORE, src=(c0, cn))
  return UOp(Ops.SINK, src=(st,))


# THE FIXTURE, in the port's order.
b = buf(0, "a")
al = alloc(1, "al")
bd = body(1)
cl = UOp(Ops.CALL, src=(bd, b))
en = UOp(Ops.END, src=(cl,))
c1 = UOp.const(1, dtypes.int32)
c4 = UOp.const(4, dtypes.int32)
sto = UOp(Ops.STORE, src=(b, c1))
rsa = UOp(Ops.RESHAPE, src=(al, c4))
rsb = UOp(Ops.RESHAPE, src=(b, c4))
stal = UOp(Ops.STORE, src=(al, c1))
sab = UOp(Ops.AFTER, src=(b, cl))
sas = UOp(Ops.AFTER, src=(b, sto))
saa = UOp(Ops.AFTER, src=(al, cl))
saas = UOp(Ops.AFTER, src=(al, sto))
sae = UOp(Ops.AFTER, src=(b, en))
sask = UOp(Ops.AFTER, src=(bd, cl))
sarst = UOp(Ops.AFTER, src=(rsa, cl))
srsb = UOp(Ops.AFTER, src=(rsb, cl))
srsast = UOp(Ops.AFTER, src=(rsa, stal))

# THE TEN PREDICATE ROWS -- five different arms of the same `or`.
print("isa_SA_buffer_call=" + ("1" if is_store_after(sab) else "0"))
print("isa_SA_buffer_store=" + ("1" if is_store_after(sas) else "0"))
print("isa_SA_alloc_call=" + ("1" if is_store_after(saa) else "0"))
print("isa_SA_alloc_store=" + ("1" if is_store_after(saas) else "0"))
print("isa_SA_buffer_end=" + ("1" if is_store_after(sae) else "0"))
print("isa_SA_sink_call=" + ("1" if is_store_after(sask) else "0"))
print("isa_K=" + ("1" if is_store_after(cl) else "0"))
print("isa_SA_reshape_alloc=" + ("1" if is_store_after(sarst) else "0"))
print("isa_SA_reshape_buffer=" + ("1" if is_store_after(srsb) else "0"))
print("isa_SA_reshape_alloc_store=" + ("1" if is_store_after(srsast) else "0"))

# THE FIVE CTX ROWS -- `collect_stores` APPENDS to `ctx.stores` and nothing else.
ctx = CallifyCtx()
for u in (sab, sas, saa, saas, sae, sask, sarst, srsb, srsast, cl):
  collect_stores(ctx, u)
print(f"cs_reps={len(ctx.replacements)}")
print(f"cs_allocs={len(ctx.allocs)}")
print(f"cs_views={len(ctx.views)}")
print(f"cs_stores={len(ctx.stores)}")
print("cs_ord=" + ",".join(code(x) for x in ctx.stores) + ",")

# THE `canonicalize_alloc` ROWS -- the SECOND ctx BODY, and the one that
# WRITES THE ctx's `dict` FIELD:
#
#     def canonicalize_alloc(ctx:CallifyCtx, b:UOp):
#       if b.arg.slot >= 0 and b not in ctx.allocs:
#         ctx.allocs[b] = b.replace(arg=replace(b.arg, slot=-1-len(ctx.allocs)))
#       return ctx.allocs.get(b)
#
# THE ALLOC FIXTURE IS THE PORT'S: `al7` HAS SLOT 7, `al9` HAS SLOT 9, AND
# `al9b` IS `al9` BUILT AGAIN -- SO THE `ucache` INTERNS IT ONCE AND BOTH
# NAMES ARE ONE UOp, WHICH IS WHAT MAKES THE `b not in ctx.allocs` GUARD
# REACHABLE. `alneg` HAS SLOT -3 AND IS ALREADY CANONICAL.
al7 = UOp(Ops.ALLOC, src=(UOp.const(4, dtypes.int32),), arg=pb(7, "al"))
al9 = UOp(Ops.ALLOC, src=(UOp.const(4, dtypes.int32),), arg=pb(9, "al"))
al9b = UOp(Ops.ALLOC, src=(UOp.const(4, dtypes.int32),), arg=pb(9, "al"))
alneg = UOp(Ops.ALLOC, src=(UOp.const(4, dtypes.int32),), arg=pb(-3, "al"))

cctx = CallifyCtx()
r1 = canonicalize_alloc(cctx, al7)
n1 = len(cctx.allocs)
r2 = canonicalize_alloc(cctx, al9)
n2 = len(cctx.allocs)
r3 = canonicalize_alloc(cctx, al9b)
n3 = len(cctx.allocs)
r4 = canonicalize_alloc(cctx, alneg)
n4 = len(cctx.allocs)


def slot_of(r):
  """THE SLOT, or `none` -- upstream's `None` and the port's `None{}` in one
  spelling."""
  return "none" if r is None else str(r.arg.slot)


print("ca_slot1=" + slot_of(r1))
print("ca_slot2=" + slot_of(r2))
print("ca_slot3=" + slot_of(r3))
print("ca_neg_none=" + slot_of(r4))
print(f"ca_n1={n1}")
print(f"ca_n2={n2}")
print(f"ca_n3={n3}")
print(f"ca_n4={n4}")
print(f"ca_reps={len(cctx.replacements)}")
print(f"ca_views={len(cctx.views)}")

# ===========================================================================
# THE FIVE BODIES THAT HAD NO ROW. MEASURED 2026-10-31.
#
# `lower_sink_to_linear`, `copy_kernel_to_store`, `simplify_copy_kernel`,
# `assert_all_same_devices` and `apply_binds` were all PORTED and all had NO
# ROW anywhere, so no gate could go red on any of them.
#
# THE PORT'S SIDE IS NOT UPSTREAM'S SIDE -- upstream's `graph_rewrite` is a
# PATTERN-MATCHER REWRITER the port does not have -- so a row is never "the
# port's output == upstream's output". Every row below asks a QUESTION THAT
# BOTH SIDES CAN ANSWER, and the port's answer is its own def's answer:
#
#   lsl_*  DID THE GUARD HOLD? upstream answers "did `lower_sink_to_linear`
#          return None", and the port's `lower_sink_to_linear` answers `None{}`
#          exactly where upstream's guard sends it home. The wall -- `function
#          .key` and `schedule_cache` -- is BEYOND the guard, and the guard is
#          the whole of the ported body.
#   cks_*  DID THE REWRITE HAPPEN? upstream's `copy_kernel_to_store` returns
#          `None` for "no rewrite" and a CALL for "rewritten".
#   sck_*  THE GUARD, over upstream's `simplify_copy_kernel`.
#   ads_*  HOW MANY DEVICES, AND DOES IT RAISE? upstream's
#          `assert_all_same_devices` returns None and RAISES, so the row is
#          the DEVICE COUNT and the RAISE.
#   ab_*  WHICH ARM? upstream's `apply_binds` is a CLOSURE inside
#          `resolve_linear_call` and is not importable, so the lane calls
#          `resolve_linear_call` and reads the arm off its OUTPUT.
# ===========================================================================

# ---------------------------------------------------------------------------
# `lower_sink_to_linear` -- __init__.py:121-147. THE GUARD:
#
#     function = call.body
#     if function.op is not Ops.SINK or isinstance(function.arg, KernelInfo)
#        or not call.arg.precompile: return None
#
# THE PORT'S BODY IS THE GUARD AND NOTHING ELSE, so the row is "did upstream
# return None", and upstream returns None EXACTLY when the guard fires -- the
# rest of the function always returns a rewritten CALL.
# ---------------------------------------------------------------------------
CI_T = CallInfo(None, None, True, False, None)
CI_F = CallInfo(None, None, False, False, None)
sink_plain = UOp(Ops.SINK, src=())
sink_kernel = UOp(Ops.SINK, src=(), arg=KernelInfo(name="test"))
linear_body = UOp(Ops.LINEAR, src=())


def lsl_rewrites(body, ci):
  """DID UPSTREAM REWRITE? `lower_sink_to_linear` returns None iff the guard
  fires, and a rewritten CALL otherwise."""
  call = UOp(Ops.CALL, src=(body,), arg=ci)
  return 0 if lower_sink_to_linear(call) is None else 1


print("lsl_sink=" + str(lsl_rewrites(sink_plain, CI_T)))
print("lsl_pre=" + str(lsl_rewrites(sink_plain, CI_F)))
print("lsl_ki=" + str(lsl_rewrites(sink_kernel, CI_T)))
print("lsl_body=" + str(lsl_rewrites(linear_body, CI_T)))

# ---------------------------------------------------------------------------
# `copy_kernel_to_store` -- __init__.py:157-159, and `simplify_copy_kernel`
# -- __init__.py:161-168. BOTH OPEN WITH THE SAME LINE:
#
#     if dst.device == src.device and not dst.on_disk(): return None
#
# SO THE REWRITE HAPPENS WHEN THE GUARD DOES NOT HOLD, and the two rules differ
# only in what they do with the answer.
#
# THE DEVICES. `CPU` IS TAG 0 AND `DISK:1` IS TAG 1 ON THE PORT'S SIDE, and
# the port's `disk` parameter is the SET OF DISK TAGS -- so the port's lane
# passes `[1]` for every row and the only variable is the device PAIR.
# ---------------------------------------------------------------------------
DEV_CPU = "CPU"
DEV_DISK = "DISK:1"


def buf_dev(slot, nm, dev):
  return UOp(Ops.BUFFER, src=(UOp.const(4, dtypes.int32),), arg=ParamArg(slot, dtypes.int32, name=nm, device=dev))


def cks_call():
  return UOp(Ops.CALL, src=(UOp(Ops.SINK, src=()), buf_dev(0, "a", DEV_CPU), buf_dev(1, "b", DEV_CPU)))


def cks_ast():
  return UOp(Ops.SINK, src=())


DEVS = (("same", DEV_CPU, DEV_CPU), ("diff", DEV_CPU, DEV_DISK), ("disk", DEV_DISK, DEV_CPU),
        ("diskdisk", DEV_DISK, DEV_DISK), ("none", None, None), ("nonecpu", None, DEV_CPU))

for nm, d, s in DEVS:
  dst, src = buf_dev(0, "a", d), buf_dev(1, "b", s)
  rewrote = copy_kernel_to_store(cks_call(), dst, src) is not None
  print(f"cks_{nm}=" + ("1" if rewrote else "0"))

for nm, d, s in DEVS:
  dst, src = buf_dev(0, "a", d), buf_dev(1, "b", s)
  # `simplify_copy_kernel` RETURNS None FOR "no rewrite", so this row is the
  # GUARD: 1 means upstream returned None.
  print(f"sck_{nm}=" + ("1" if simplify_copy_kernel(cks_call(), cks_ast(), dst, src) is None else "0"))

# ---------------------------------------------------------------------------
# `assert_all_same_devices` -- __init__.py:153-155:
#
#     devices = dedup([x.device for x in ast.toposort()
#                      if x.op is Ops.PARAM and x.device is not None])
#     if len(devices) >= 2: raise RuntimeError(...)
#
# THE DEDUP IS OVER THE DEVICES AND NOT OVER THE NODES, and `dedup` is
# `list(dict.fromkeys(x))` -- so TWO PARAMS ON ONE DEVICE ARE ONE DEVICE. The
# row is the DEVICE COUNT and the RAISE.
# ---------------------------------------------------------------------------
def ads_probe(devs):
  """THE DEVICES UPSTREAM SEES, and whether it raises."""
  ps = [UOp(Ops.PARAM, src=(), arg=ParamArg(i, dtypes.int32, name=f"p{i}", device=d)) for i, d in enumerate(devs)]
  ast = UOp(Ops.SINK, src=tuple(ps))
  devices = list(dict.fromkeys(x.device for x in ast.toposort() if x.op is Ops.PARAM and x.device is not None))
  raised = 0
  try:
    assert_all_same_devices(ast)
  except RuntimeError:
    raised = 1
  return devices, raised


for nm, devs in (("same", (DEV_CPU, DEV_CPU)), ("diff", (DEV_CPU, DEV_DISK)), ("none", (None,))):
  devices, raised = ads_probe(devs)
  print(f"ads_{nm}_n={len(devices)}")
  print(f"ads_{nm}_raises={raised}")

# ---------------------------------------------------------------------------
# `apply_binds` -- __init__.py:107-111. A CLOSURE inside `resolve_linear_call`
# and NOT IMPORTABLE, so the lane calls `resolve_linear_call` and reads the ARM
# off its OUTPUT:
#
#     if si.op is Ops.CALL and si.body.op is Ops.LINEAR:  return resolve_linear_call(si, binds)   # 1
#     if si.op is Ops.CALL and si.body.op is Ops.PROGRAM: return si                              # 2
#     ...                                                                                         # 3
#
# ARM 1 RETURNS A LINEAR, ARM 2 RETURNS `si` ITSELF, AND ARM 3 RETURNS A NEW
# NODE -- the three outputs are DISTINGUISHABLE WITHOUT RESTATING UPSTREAM'S
# CONDITION.
# ---------------------------------------------------------------------------
def ab_arm(si, bind):
  """THE ARM UPSTREAM TOOK, read off `resolve_linear_call`'s output."""
  linbody = UOp(Ops.LINEAR, src=(si,))
  lc = UOp(Ops.CALL, src=(linbody, bind), arg=CI_T)
  out = resolve_linear_call(lc)
  s0 = out.src[0]
  if s0.op is Ops.LINEAR:
    return 1
  if s0 is si:
    return 2
  return 3


# THE BIND IS A NAMED ALU PARAM AND THE ARM-3 USE IS A NAMELESS ONE, because a
# nameless PARAM is a VARIABLE and arm 3's substitution REPLACES it -- so the
# arm-3 output is a NEW node and the three arms are DISTINGUISHABLE.
BIND = UOp(Ops.PARAM, src=(), arg=ParamArg(0, dtypes.float32, name="x", addrspace=AddrSpace.ALU))
ARM1 = UOp(Ops.CALL, src=(UOp(Ops.LINEAR, src=()),), arg=CI_T)
ARM2 = UOp(Ops.CALL, src=(UOp(Ops.PROGRAM, src=()),), arg=CI_T)
ARM3 = UOp(Ops.PARAM, src=(), arg=ParamArg(0, dtypes.float32, name=None, addrspace=AddrSpace.ALU))

print(f"ab_arm1={ab_arm(ARM1, BIND)}")
print(f"ab_arm2={ab_arm(ARM2, BIND)}")
print(f"ab_arm3={ab_arm(ARM3, BIND)}")
