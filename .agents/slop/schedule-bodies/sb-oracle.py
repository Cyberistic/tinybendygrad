#!/usr/bin/env python3
"""CPython oracle for the schedule/__init__.py:82-301 RULE BODIES.

Every `py=` expectation in the gate comes from HERE. None is typed.

MEASURED, in the order the defs appear in the file:
  1  is_store_after          __init__.py:217-218      NO ctx
  2  CallifyCtx              __init__.py:192-197      THE C2 CLAUSE
  3  collect_stores          __init__.py:220-221      ctx
  4  lower_sink_to_linear    __init__.py:124-126      NO ctx  (the GUARD)
  5  copy_kernel_to_store    __init__.py:161-163      NO ctx
  6  simplify_copy_kernel    __init__.py:165-167      NO ctx  (the GUARD)
  7  assert_all_same_devices __init__.py:157-159      NO ctx
  8  apply_binds             __init__.py:110-112      NO ctx  (the DISPATCH)
  9  canonicalize_alloc      __init__.py:235-237      ctx

Devices are PARAMs, not BUFFERs. That is CPython's own shape for two of these
rules -- `pm_copy_from_store`'s two patterns at :179-184 match
`UPat(Ops.PARAM, name="dst")` / `name="src"`, and `assert_all_same_devices`
filters on `x.op is Ops.PARAM` -- and a BUFFER's device lives in a `Buffer` arg
that `UOp.new` does not mint for me.
"""
import sys
from tinygrad.uop.ops import UOp, Ops, KernelInfo, ParamArg, CallInfo
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.device import Device

rows = []
def row(nm, v): rows.append(f"{nm}={v}")
def b(x): return 1 if x else 0
def op(u): return u.op.name
def code(u):
  n = u.op.name
  return {"CONST":"9","BUFFER":"1","AFTER":"2","PARAM":"3","CALL":"4","END":"5",
          "STORE":"6","SINK":"7","SPECIAL":"8","LINEAR":"10","MSTACK":"11",
          "STAGE":"12","PROGRAM":"13","ALLOC":"14","NOOP":"99"}.get(n, "0")

DEV_CPU, DEV_DISK = Device["CPU"], Device["DISK"]
C0 = UOp.const(0, dtypes.int32)
N1 = UOp.const(1, dtypes.int32)
BO = UOp(Ops.SINK, src=(UOp(Ops.STORE, src=(C0, N1)),))
def pslot(slot): return slot if slot is not None else -1

def P(nm, slot=None, dev=None, ast=AddrSpace.GLOBAL, val=None):
  return UOp(Ops.PARAM, src=(UOp(Ops.SPECIAL, arg=nm, src=(N1,)),),
    arg=ParamArg(slot=slot, dtype=dtypes.int32, size=None, vmin_vmax=None, multiple_of=None,
                 name=nm, addrspace=ast, device=dev, volatile=None, image=None,
                 buffer=None, bind_on_realize=False, val=val))
def AL(nm, slot=None):
  return UOp(Ops.ALLOC, src=(N1,),
    arg=ParamArg(slot=slot, dtype=dtypes.int32, size=None, vmin_vmax=None, multiple_of=None,
                 name=nm, addrspace=AddrSpace.GLOBAL, device=None, volatile=None,
                 image=None, buffer=None, bind_on_realize=False, val=None))
def CI(pre): return CallInfo(None, None, pre, False, None)

# --- THE FIXTURES. Construction ORDER is the contract; `--map` prints the
# --- indices so the arena in the .bend file is checked, not assumed.
PC   = P("c", dev=DEV_CPU)      #  0  PARAM, CPU
PC2  = P("c2", dev=DEV_CPU)     #  1  PARAM, CPU  (a second one, same device)
PD   = P("d", dev=DEV_DISK)     #  2  PARAM, DISK
PN   = P("n")                    #  3  PARAM, device None
VAL  = P("v", val=3)             #  4  bound Variable, ALU
VU   = P("v2")                   #  5  unbound Variable, ALU
K    = UOp(Ops.CALL, src=(BO, PC, PC2), arg=CI(True))    #  6  same-device copy call
KS   = UOp(Ops.CALL, src=(BO, PD, PC), arg=CI(True))     #  7  cross-device copy call
E    = UOp(Ops.END, src=(K,))                            #  8
S_NK = UOp(Ops.STORE, src=(C0, N1))                      #  9
SA_B = UOp(Ops.AFTER, src=(PC, K))                       # 10  base is a PARAM
A_L  = AL("al", slot=7)                                  # 11  ALLOC, positive slot
SA_A = UOp(Ops.AFTER, src=(A_L, K))                      # 12  base is an ALLOC
SA_S = UOp(Ops.AFTER, src=(A_L, S_NK))                   # 13  base ALLOC, src1 STORE
SA_E = UOp(Ops.AFTER, src=(A_L, E))                      # 14  base ALLOC, src1 END
A_N  = AL("an", slot=-3)                                 # 15  already canonical
SIN  = UOp.sink(SA_B, SA_A, SA_S, SA_E)                  # 16
A2   = AL("a2", slot=9)                                  # 17  a second fresh ALLOC

# `lower_sink_to_linear`'s fixture set. Three NEGATIVES are measured by CALLING
# the real function (it returns None before touching anything), and the POSITIVE
# is measured as its three PREDICATES over CPython's own UOps, because the
# positive runs the whole schedule pipeline and that is not this unit's subject.
SINK_N  = UOp(Ops.SINK, src=(BO,), arg=None)
SINK_KI = UOp(Ops.SINK, src=(BO,), arg=KernelInfo())
NOTSK   = UOp(Ops.CALL, src=(BO,))
L_PRE   = UOp(Ops.CALL, src=(SINK_N, PC), arg=CI(True))
L_NOPRE = UOp(Ops.CALL, src=(SINK_N, PC), arg=CI(False))
L_KI    = UOp(Ops.CALL, src=(SINK_KI, PC), arg=CI(True))
L_NOSK  = UOp(Ops.CALL, src=(NOTSK, PC), arg=CI(True))

# `apply_binds`' three arms. C_LIN/C_PROG need a `CallInfo`, and PROGRAM's body
# here is `BO` (a SINK) -- `apply_binds` reads `si.body.op` only.
LIN    = UOp(Ops.LINEAR, src=(BO,))                     # 18
PROG   = UOp(Ops.PROGRAM, src=(BO,))                    # 19
C_LIN  = UOp(Ops.CALL, src=(LIN, PC), arg=CI(False))    # 20
C_PROG = UOp(Ops.CALL, src=(PROG, PC), arg=CI(False))   # 21
C_PLN  = UOp(Ops.CALL, src=(BO, PC), arg=CI(False))     # 22

ORDER = [("PC",PC),("PC2",PC2),("PD",PD),("PN",PN),("VAL",VAL),("VU",VU),
         ("K",K),("KS",KS),("E",E),("S_NK",S_NK),("A_L",A_L),("SA_B",SA_B),
         ("SA_A",SA_A),("SA_S",SA_S),("SA_E",SA_E),("A_N",A_N),("SIN",SIN),
         ("A2",A2),("LIN",LIN),("PROG",PROG),("C_LIN",C_LIN),("C_PROG",C_PROG),
         ("C_PLN",C_PLN)]

if "--map" in sys.argv:
  seen, idx = [], {}
  for nm, u in ORDER:
    k = (u.op, u.src, str(u.arg), u.tag)
    if k not in idx: idx[k] = len(seen); seen.append(k)
  for nm, u in ORDER: row(f"ix_{nm}", idx[(u.op,u.src,str(u.arg),u.tag)])
  print("\n".join(rows)); sys.exit(0)

# ==========================================================================
# 1  is_store_after -- __init__.py:217-218. FIVE rows, and each conjunct is
#    separately load-bearing: SA_A is the only False from `unsharded_base is
#    ALLOC`, SA_S is the only True from the `or src[1] is STORE` rescue, SA_E is
#    the False that says the rescue reads src[1] and not `nsrc`, and K is the
#    False that says the AFTER test is not vacuous.
# ==========================================================================
from tinygrad.schedule import is_store_after
row("isa_SA_B", b(is_store_after(SA_B)))
row("isa_SA_A", b(is_store_after(SA_A)))
row("isa_SA_S", b(is_store_after(SA_S)))
row("isa_SA_E", b(is_store_after(SA_E)))
row("isa_K",    b(is_store_after(K)))
# the READER the AND is built on, as a CODE -- a BUFFER and an ALLOC have
# different codes, so a port that read `base` instead of `unsharded_base` is
# caught by the value and not only by the boolean.
row("usb_SA_A", code(SA_A.src[0].unsharded_base))
row("usb_SA_B", code(SA_B.src[0].unsharded_base))
row("usb_K",    code(K.src[0].unsharded_base))
row("usb_nsrc_SA_B", len(SA_B.src))
row("usb_nsrc_SA_A", len(SA_A.src))

# ==========================================================================
# 2/3  CallifyCtx + collect_stores -- __init__.py:192-197, 220-221.
#     The list after ONE call, the list after EIGHT calls in an order that has
#     the two negative nodes (K, E) interleaved with the four positives, and the
#     DUPLICATE row -- `list.append` does not dedup, so SA_E and SA_B are each
#     called twice and a `set` would answer 4 where the list answers 4 too, but
#     in a DIFFERENT ORDER only if it were a set of the same elements; the row
#     that separates them is `cs_dup2`, an identity test, not a count.
# ==========================================================================
from tinygrad.schedule import CallifyCtx, collect_stores
c1 = CallifyCtx()
a1 = collect_stores(c1, SA_B)
row("cs_len1", len(c1.stores))
row("cs_op1",  code(c1.stores[0]))
row("cs_none1", b(a1 is None))

c2 = CallifyCtx()
for u in (K, SA_A, SA_S, E, SA_B, SA_E, SA_E, SA_B): collect_stores(c2, u)
row("cs_len2", len(c2.stores))
row("cs_ops2", "".join(code(x) for x in c2.stores))
row("cs_dup2", b(c2.stores[1] is c2.stores[2]))
row("cs_ord2", b(c2.stores[0] is SA_S))
row("cs_reps",  len(c2.replacements))
row("cs_allocs", len(c2.allocs))
row("cs_views",  len(c2.views))
# the ORDER, as indices into the same arena the .bend fixture builds

# ==========================================================================
# 4  lower_sink_to_linear -- __init__.py:124-126, THE GUARD. Three negatives by
#    a REAL CALL (the function returns None before it does anything) and the
#    positive as CPython's own three predicates, AND-ed exactly as the source
#    OR-s them.
# ==========================================================================
from tinygrad.schedule import lower_sink_to_linear
def lsl_none(u): return b(lower_sink_to_linear(u) is None)
row("lsl_none_ki",    lsl_none(L_KI))       # isinstance(arg, KernelInfo)
row("lsl_none_nopre", lsl_none(L_NOPRE))    # not call.arg.precompile
row("lsl_none_nosink", lsl_none(L_NOSK))    # body.op is not SINK
def lsl_ok(call):
  f = call.body
  return b(f.op is Ops.SINK and not isinstance(f.arg, KernelInfo) and call.arg.precompile)
row("lsl_ok_plain", lsl_ok(L_PRE))
row("lsl_ok_ki",    lsl_ok(L_KI))
row("lsl_ok_nopre", lsl_ok(L_NOPRE))
row("lsl_ok_nosink", lsl_ok(L_NOSK))
# the three predicates SEPARATELY, so an inverted conjunct is visible as which
# conjunct moved rather than only as the row that flipped
row("lsl_p_sink",  b(L_PRE.body.op is Ops.SINK))
row("lsl_p_ki",    b(isinstance(SINK_KI.arg, KernelInfo)))
row("lsl_p_noki",  b(isinstance(SINK_N.arg, KernelInfo)))
row("lsl_p_pre",   b(L_PRE.arg.precompile))
row("lsl_p_nopre", b(L_NOPRE.arg.precompile))

# ==========================================================================
# 5/6  copy_kernel_to_store (161) and simplify_copy_kernel (165). The GUARD is
#     ONE LINE, shared by both, and it is a PAIR test: `dst.device == src.device`
#     AND the DISK prefix. `cks_same` and `cks_cross` are one row apart and
#     differ only in that equality.
# ==========================================================================
from tinygrad.schedule import copy_kernel_to_store, simplify_copy_kernel
def cks(c, dst, src):
  g = copy_kernel_to_store(c, dst, src)
  return "None" if g is None else code(g)
row("cks_same",  cks(K, PC, PC2))     # same device, not DISK -> None
row("cks_cross", cks(KS, PD, PC))     # different device  -> fires
row("cks_disk",  cks(KS, PD, PC2))    # same DISK device  -> fires on the prefix
row("cks_rev",   cks(KS, PC, PD))     # the pair, other order -> fires
# the ANSWER's SHAPE, which is `dst.store(src)` then `call.replace`: the new
# first src is a STORE with two srcs, and `call.src[1:]` is preserved.
g = copy_kernel_to_store(KS, PD, PC)
row("cks_call_code",  code(g))
row("cks_call_nsrc",  len(g.src))
row("cks_call_s0",    code(g.src[0]))
row("cks_call_s1",    code(g.src[1]))
row("cks_store_code", code(g.src[0]))
row("cks_store_nsrc", len(g.src[0].src))
row("cks_store_s0",   code(g.src[0].src[0]))   # dst  -- PARAM
row("cks_store_s1",   code(g.src[0].src[1]))   # src  -- PARAM
row("cks_store_same", b(g.src[0].src[0] is PD))
row("cks_store_same1", b(g.src[0].src[1] is PC))
row("cks_tail_same", b(g.src[1] is PD and g.src[2] is PC))  # `call.src[1:]` kept
row("cks_head_new", b(g.src[0] is not KS.src[0]))          # `call.src[0]` REPLACED
def sck(c, dst, src):
  g = simplify_copy_kernel(c, BO, dst, src)
  return "None" if g is None else code(g)
row("sck_same",  sck(K, PC, PC2))
row("sck_cross", sck(KS, PD, PC))

# ==========================================================================
# 7  assert_all_same_devices -- __init__.py:157-159. The predicate is
#    `len(devices) >= 2`, a THRESHOLD, so `asd_two` (one device) is the row that
#    pins it: a `>= 1` mutation leaves every other row green.
# ==========================================================================
from tinygrad.schedule import assert_all_same_devices
def asd(u):
  try: assert_all_same_devices(u); return "ok"
  except RuntimeError: return "raise"
def dedup(xs):
  out = []
  for x in xs:
    if x not in out: out.append(x)
  return out
def devs(u): return dedup([x.device for x in u.toposort() if x.op is Ops.PARAM and x.device is not None])
SINK2 = UOp.sink(PC, PC2)
SINKD = UOp.sink(PD, PC2)
row("asd_none", asd(BO))
row("asd_one",  asd(UOp.sink(PN)))
row("asd_two",  asd(SINK2))
row("asd_diff", asd(SINKD))
row("asd_ndev_none", len(devs(BO)))
row("asd_ndev_one",  len(devs(UOp.sink(PN))))
row("asd_ndev_two",  len(devs(SINK2)))
row("asd_ndev_diff", len(devs(SINKD)))
# the COLLECTION, as codes, so a port that gathers the wrong nodes is caught by
# a row that is not a count
row("asd_ops_two",  "".join(code(x) for x in SINK2.toposort() if x.op is Ops.PARAM))
row("asd_ops_diff", "".join(code(x) for x in SINKD.toposort() if x.op is Ops.PARAM))
row("asd_topo_two", len(SINK2.toposort()))
row("asd_topo_diff", len(SINKD.toposort()))

# ==========================================================================
# 8  apply_binds -- __init__.py:110-112. THE 3-ARM DISPATCH, read straight out
#    of the source text so the rows are CPython's own decision and not my
#    paraphrase: arm 1 `CALL & body LINEAR`, arm 2 `CALL & body PROGRAM`, arm 3
#    everything else (substitute). `UOp.substitute` and `UOp.variables` are what
#    arm 3 needs and NEITHER exists in the tree.
# ==========================================================================
def ab_arm(si, binds):
  if si.op is Ops.CALL and si.body.op is Ops.LINEAR: return 1
  if si.op is Ops.CALL and si.body.op is Ops.PROGRAM: return 2
  return 3
row("ab_C_LIN",  ab_arm(C_LIN, {}))
row("ab_C_PROG", ab_arm(C_PROG, {}))
row("ab_C_PLN",  ab_arm(C_PLN, {}))
row("ab_LIN",    ab_arm(LIN, {}))
row("ab_BO",     ab_arm(BO, {}))
row("ab_C_KS",   ab_arm(KS, {}))
# the predicates, SEPARATELY. `ab_bo_isCALL` and `ab_lin_isCALL` are the pair
# that makes arm 3 reachable at all.
def iscall(u): return b(u.op is Ops.CALL)
def bodycode(u):
  try: return code(u.body)
  except Exception: return "0"
row("ab_iscall_C_LIN",  iscall(C_LIN))
row("ab_iscall_C_PROG", iscall(C_PROG))
row("ab_iscall_LIN",    iscall(LIN))
row("ab_iscall_BO",     iscall(BO))
row("ab_body_C_LIN",    bodycode(C_LIN))
row("ab_body_C_PROG",   bodycode(C_PROG))
row("ab_body_C_PLN",    bodycode(C_PLN))
row("ab_body_LIN",      bodycode(LIN))

# ==========================================================================
# 9  canonicalize_alloc -- __init__.py:235-237. THE SLOT ARITHMETIC is the port:
#    `-1 - len(ctx.allocs)`, so consecutive fresh ALLOCs get -1 and -2 and NOT
#    0 and -1. `ca_slot1`/`ca_slot2` are that, one row apart.
# ==========================================================================
from tinygrad.schedule import canonicalize_alloc
cA = CallifyCtx()
r1 = canonicalize_alloc(cA, A_L)
row("ca_slot1", pslot(r1.arg.slot))
row("ca_n1",     len(cA.allocs))
row("ca_same1",  b(r1 is cA.allocs[A_L]))
row("ca_name1",  r1.arg.name)
r2 = canonicalize_alloc(cA, A2)
row("ca_slot2", pslot(r2.arg.slot))
row("ca_n2",     len(cA.allocs))
r3 = canonicalize_alloc(cA, A_L)          # already canonical: no second write
row("ca_slot3", pslot(r3.arg.slot))
row("ca_n3",     len(cA.allocs))
row("ca_repeat", b(r3 is r1))
cB = CallifyCtx()
r4 = canonicalize_alloc(cB, A_N)          # slot < 0: ALREADY canonical
row("ca_neg_none", b(r4 is None))
row("ca_neg_n",    len(cB.allocs))
cC = CallifyCtx()
try:
  r5 = canonicalize_alloc(cC, UOp(Ops.ALLOC, src=(N1,), arg=None))
  row("ca_noarg", "None" if r5 is None else "Some")
except AttributeError: row("ca_noarg", "raise")

print("\n".join(rows))