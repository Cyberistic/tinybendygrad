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
from tinygrad.uop.ops import Ops, ParamArg, UOp
from tinygrad.schedule import CallifyCtx, canonicalize_alloc, collect_stores, is_store_after


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
