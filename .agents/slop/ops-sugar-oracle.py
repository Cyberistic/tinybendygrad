#!/usr/bin/env python3
"""ops-sugar-oracle.py -- the CPython lane for the sugar constructors of
`tinybendygrad/uop/ops.bend` (ops.py:565-674).

    sh .agents/slop/ops-sugar-gate.sh

Every row is printed by CALLING CPython. No op name, no arg order, no fixture
index and no expected value in this file is transcribed: the fixtures are built
from `tinygrad`'s own constructors and the answers are read back off the UOps.

`TG_TREE` picks the tree, so the same script diffs the port against the vendored
pin and against upstream, and the two answers differ in exactly the rows upstream
moved:

    TG_TREE=.                                  the vendored pin
    TG_TREE=.agents/slop/opstree               upstream master

ROWS. Four shapes:

  * `sg_<name>=<OP>/<SRC OPS> <ARG> t=<TAG>` -- a MINT, as the op name, the SRC OP
    SEQUENCE, the arg and the tag. The src sequence is the second fact and the arg
    the third: swapping two srcs leaves op and nsrc identical, and every dtype and
    every `(rop, 0)` pair in this unit lives in the ARG alone. A gate that printed
    the op would gate nothing here.
  * `sg_<name>=<bool>` -- a PREDICATE, printed `True`/`False` to match the port's
    `row`.
  * `sg_<name>=some:<OP>` / `some:<bool>` / `none` -- a `Maybe`, where `none` is a
    Python RAISE and is printed as the exception's NAME (`RuntimeError`,
    `AttributeError`). Spelling the raise as the port does would be transcribing
    the port, which is the one thing an oracle must not do.
  * `sg_idx=<op,op,...>` -- the fixture op names in arena order, so a miscount in
    either lane's index arithmetic is a row rather than twenty-four silently
    re-labelled rows.

A MINT'S ARENA IS THE ONE IT RETURNED. `sg.minted` in the port reads the `Found`'s
own arena, not the caller's, because a node interned into a discarded arena reads
back as the bottom -- a NOOP, which is a visibly wrong op name rather than an
empty answer. Nothing in this file has to know that: it prints what CPython
built, and the port has to match it.
"""
import os
import sys

TG_TREE = os.environ.get('TG_TREE', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'opstree'))
sys.path.insert(0, TG_TREE)

from tinygrad.uop.ops import (UOp, Ops, AxisType, Invalid, CallInfo, CustomFunction,  # noqa: E402
                           KernelInfo, ParamArg, sint_to_uop)
from tinygrad.dtype import DType, dtypes  # noqa: E402

rows = []


def row(k, v):
  rows.append(f"{k}={v}")


def nm(u: UOp) -> str:
  """`Ops.name(u.op)` -- the PORT prints the `Ops.` prefix because `str(FastEnum)`
  is `"Ops.MEMBER"` and its `name` is `"MEMBER"`, and the row is `Ops.name`."""
  return f"Ops.{u.op.name}"


def seps(u: UOp) -> str:
  """The SRC OP SEQUENCE, space separated. `-` is not used: an empty src list
  prints as the empty string between the slashes, which is what the port's
  `s5.seps` does for `Nil{}`."""
  return " ".join(nm(s) for s in u.src)


def ctor(u: UOp) -> str:
  """The ARG, structurally, as the port's `sg.ctor` spells it. Only the arms a row
  in this unit can produce are named; anything else is `other`, and a port with an
  `AReduce` where the tree has a plain op shows up as a diff rather than as a
  silently agreeing `other`."""
  a = u.arg
  if a is None:
    return "none"
  if isinstance(a, DType):
    return f"dt:{a.name}"
  if a is Invalid:
    return "cinvalid"
  if isinstance(a, Ops):
    return f"cop:{a}"
  if isinstance(a, CallInfo):
    return f"call:{a}"
  if isinstance(a, CustomFunction):
    return f"custom:{a}"
  if isinstance(a, ParamArg):
    return "param"
  if isinstance(a, tuple) and len(a) == 2 and isinstance(a[0], Ops) and isinstance(a[1], int):
    return f"reduce:Ops.{a[0].name}/{a[1]}"
  if isinstance(a, tuple) and len(a) == 4:
    return f"wmma:{a[2]}/{a[1].name}"
  if isinstance(a, tuple) and len(a) == 2 and isinstance(a[1], DType):
    return f"ink:{a[0]}/{a[1].name}"
  if isinstance(a, tuple):
    return "cint" if len(a) == 2 else "other"
  if isinstance(a, bool):
    return f"cbool:{a}"
  if isinstance(a, int):
    return "cint"
  if isinstance(a, float):
    return "cfloat"
  return "other"


def tagstr(u: UOp) -> str:
  """`u.tag`, as the port's `sg.tag` spells it."""
  t = u.tag
  if t is None:
    return "none"
  if isinstance(t, bool):
    return "True" if t else "False"
  if isinstance(t, int):
    return str(t)
  if isinstance(t, str):
    return t
  return "tuple"


def sig(u: UOp) -> str:
  return f"{nm(u)}/{seps(u)} {ctor(u)} t={tagstr(u)}"


# ---------------------------------------------------------------------------
# THE FIXTURES, in the arena order `ops.bend`'s `sg.arena` writes them. The comment
# on each is the name that block gives it, and `sg_idx` below prints the op
# sequence so a divergence in either lane's ORDER is a row.
# ---------------------------------------------------------------------------
c0, c1, c2 = UOp.const(0), UOp.const(1), UOp.const(2)
ci = UOp(Ops.CONST, arg=Invalid)
bu = UOp(Ops.BUFFER, arg=ParamArg(1, dtypes.int32))
ta = UOp(Ops.ADD, (c0, c1), tag=9)
al = UOp(Ops.ALLOC, arg=ParamArg(3, dtypes.int32))
ab = UOp(Ops.ALLOC, arg=ParamArg(4, dtypes.int32, bind_on_realize=True))
us = UOp(Ops.UNSHARD, src=(al,), arg=(0,))
st = UOp.stack(c0, c1)
sk = UOp(Ops.SINK, (bu,))
ki = UOp(Ops.SINK, (bu,), arg=KernelInfo())
csk = UOp(Ops.CALL, (sk,), CallInfo(None, "f", False, False, None))
ckp = UOp(Ops.CALL, (sk,), CallInfo(None, "f", True, False, None))
cbs = UOp(Ops.CALL, (ta,), CallInfo(None, "f", False, False, None))
cki = UOp(Ops.CALL, (ki,), CallInfo(None, "f", False, False, None))
cfn = UOp(Ops.CALL, (sk,), CustomFunction("f"))
ca0 = UOp(Ops.CALL, (al,), CallInfo(None, "f", False, False, None))
cau = UOp(Ops.CALL, (sk, al), CallInfo(None, "f", False, False, None))
cab = UOp(Ops.CALL, (sk, ab), CallInfo(None, "f", False, False, None))
cbu = UOp(Ops.CALL, (sk, bu), CallInfo(None, "f", False, False, None))
cun = UOp(Ops.CALL, (sk, us), CallInfo(None, "f", False, False, None))
aau = UOp(Ops.ADD, (al, bu))
atn = UOp(Ops.ADD, (c0, c1))
aaf = UOp(Ops.AFTER, (sk,), CallInfo(None, "f", False, False, None))
aal = UOp(Ops.ADD, (c0, al))

FIXTURES = (c0, c1, c2, ci, bu, ta, al, ab, us, st, sk, ki, csk, ckp, cbs, cki, cfn, ca0, cau, cab, cbu, cun, aau, atn, aaf, aal)

# ---------------------------------------------------------------------------
# `UOp.body` -- ops.py:562. TWO rows, and the second is the `case _` arm: without a
# non-CALL, `UOp.body.of`'s `None` is dead code and a dead arm cannot be mutated
# into moving anything.
# ---------------------------------------------------------------------------
def body_str(u: UOp) -> str:
  try:
    return f"some:{nm(u.body)}"
  except Exception as e:  # noqa: BLE001
    return f"none:{type(e).__name__}"


row("sg_body_call", body_str(csk))
row("sg_body_add", body_str(aau))

# ---------------------------------------------------------------------------
# `UOp.is_inline_call` -- ops.py:567. FOUR conjuncts and a raise, so FIVE rows plus
# the op half. `pre` is `not self.arg.precompile`, `body` is `body.op is SINK`,
# `kernel` is `body.arg is None`, `add` is `op is CALL` and `cfun` is the
# AttributeError a `CustomFunction` arg raises.
# ---------------------------------------------------------------------------
def inline_str(u: UOp) -> str:
  try:
    return f"some:{u.is_inline_call}"
  except Exception as e:  # noqa: BLE001
    return f"none:{type(e).__name__}"


row("sg_inline_call", inline_str(csk))
row("sg_inline_pre", inline_str(ckp))
row("sg_inline_body", inline_str(cbs))
row("sg_inline_kernel", inline_str(cki))
row("sg_inline_cfun", inline_str(cfn))
row("sg_inline_aft", inline_str(aaf))
row("sg_inline_add", inline_str(aau))

# ---------------------------------------------------------------------------
# `UOp.has_unbound_outputs` -- ops.py:570. `src[1:]` is TWO of the six rows: `ca0`'s
# only ALLOC is src[0], which is the CALL's BODY, so a def that walked `src` would
# answer True there. `cun`'s ALLOC is under an UNSHARD, so it is the only row that
# sees the `unsharded_base` peel, and `aau` is the only row that separates the op
# test from the ALLOC test on a node that HAS an ALLOC src.
# ---------------------------------------------------------------------------
for k, u in (("alloc", cau), ("bind", cab), ("buffer", cbu), ("src0", ca0), ("unshard", cun), ("noncall", aal), ("op", aau)):
  row(f"sg_huo_{k}", u.has_unbound_outputs)

# ---------------------------------------------------------------------------
# `UOp.invalid` and `UOp.is_invalid` -- ops.py:663 and :267. One fact read two ways,
# and two rows because a port whose `CInvalid` arm is unreachable answers
# `sg_isinv_ci=False` while the ctor row still looks right.
# ---------------------------------------------------------------------------
row("sg_invalid", sig(UOp.invalid()))
row("sg_isinv_ci", UOp.invalid().is_invalid)
row("sg_isinv_c0", c0.is_invalid)

# `UOp.reduce` -- ops.py:671. `sg_reduce_none` is the row the `isinstance(arg, Ops)
# -> (arg, 0)` normalisation cannot be dropped from: with no `arg` the tree's arg
# is `None`, and a port that always built `AReduce` prints `reduce:Ops.NOOP/0`.
row("sg_reduce_some", sig(bu.reduce(arg=Ops.ADD)))
row("sg_reduce_none", sig(bu.reduce()))
row("sg_reduce_two", sig(bu.reduce(c1, arg=Ops.MAX)))

# `UOp.cconst` -- ops.py:640. The CAST is interned into the arena `UOp.const`
# grew, so this row is also the stale-arena check: a port that interned into the
# caller's arena would read the bottom back and print `Ops.NOOP`.
row("sg_cconst_i32", sig(UOp.cconst(7, dtypes.int32)))
row("sg_cconst_f32", sig(UOp.cconst(7, dtypes.float32)))

# ---------------------------------------------------------------------------
# `UOp.index` -- ops.py:578. The GUARD: a STACK indexed by one CONST answers that
# element of the STACK's own srcs, and the only CPython-checkable fact about that is
# IDENTITY, so `hit0` and `hit1` are `is` tests. Two rows, because one would agree
# with a def that answered the same fixture for both.
#
# `hitmiss` is the NON-MOVEMENT row: `bu` is a BUFFER, so the same CONST must NOT
# come back, and it is what keeps `UOp.index.pick`'s `False` arm from being dead.
# An out-of-range index is NOT a row: CPython raises IndexError and `Arena.src`
# answers the bottom, so that case is a named divergence in the inventory rather
# than a diff either lane could satisfy.
# ---------------------------------------------------------------------------
row("sg_index_hit1", st.index(1) is c1)
row("sg_index_hit0", st.index(0) is c0)
row("sg_index_hitmiss", bu.index(1) is c1)
row("sg_index_plain", sig(bu.index()))
row("sg_index_one", sig(bu.index(1)))
row("sg_index_two", sig(bu.index(1, 2)))
row("sg_index_nc", sig(st.index(bu)))
row("sg_index_st2", sig(st.index(1, 2)))

# `UOp.store` -- ops.py:613. The two rows differ in the THIRD src and in nothing
# else, which is what makes the optional gate load-bearing: SELF FIRST, then the
# value, then the gate.
row("sg_store_nogate", sig(bu.store(c0)))
row("sg_store_gate", sig(bu.store(c0, c1)))

# `UOp.ins` -- ops.py:622. The two rows differ ONLY in the tag, so a port that
# hardcoded `TNone` passes the second and fails the first.
row("sg_ins_tag", sig(ta.ins("x", dtype=dtypes.int32)))
row("sg_ins_none", sig(atn.ins("x", dtype=dtypes.int32)))

# `UOp.wmma` -- ops.py:649.
row("sg_wmma", sig(UOp.wmma(bu, c0, ta, (16, 16, 16), 32)))

# ---------------------------------------------------------------------------
# `UOp.ufix` -- ops.py:606, which in this port IS `UOp.sint_to_uop`: a UOp is a
# `U32` and a bare Python value is a `Const`, so `if isinstance(x, UOp): return x`
# is the `SU` arm of a def that already existed. What was MISSING is a row for that
# arm -- `s5_sint_const` gates the `SI` arm and nothing gated the `SU` one, so a
# `sint_to_uop` that always minted a CONST would have been green.
#
# The row prints the OP and not a Bool on purpose: a Bool would also pass for a def
# that minted a CONST whose op happened to be the input's, and the op is the fact.
# CPython's spelling is `UOp.sint_to_uop`'s own: `UOp.const(9, dtypes.weakint)` for
# the literal and the node itself for the UOp, so the oracle asks both of those
# rather than of a `ufix` that only exists on the pin.
# ---------------------------------------------------------------------------
row("sg_ufix_uop", nm(c0.ufix(c0)))
row("sg_ufix_lit", sig(c0.ufix(9)))
row("sg_ufix_miss", aau.ufix(aau) is aau)

# `sg_idx` is printed LAST and not with the fixtures, because the gate is a BYTE
# DIFF and Bend has no forward references: the port's `sg_idx` reads defs declared
# above it, so it lands after the rows rather than before them. The row is the
# fixture op sequence in arena order, so a divergence in either lane's ORDER -- or a
# fixture written into the arena list twice -- is a row instead of twenty-four
# silently re-labelled rows. It is the row that caught exactly that.
row("sg_idx", "".join(f"{nm(u)}," for u in FIXTURES))

if __name__ == '__main__':
  for r in rows:
    print(r)
