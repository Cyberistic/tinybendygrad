#!/usr/bin/env python3
"""rw-gate-oracle.py -- CPython's answer for EVERY row `codegen/rewriter.bend`
prints, at either end of the pin window.

The oracle this replaces (`.agents/slop/notes/rw-truth.py`) could not be run at
HEAD at all: it named `GD.pm_add_gpudims` unconditionally, so `78d482262`'s rename
turned line 104 into `AttributeError` and the oracle printed NOTHING. A gate whose
oracle dies at one end cannot tell "the port is unchanged" from "nobody ran it" --
the `0 rows` shape `UPSTREAM-PIN.md` Step 4 is written about. So every table here
is resolved through `getattr` with a recorded fallback and the fallback is PRINTED
rather than raised.

It also `sys.path.insert(0, <repo root>)` at line 14, which puts the WORKING tree
at position 0 so `PYTHONPATH` cannot point it anywhere else -- it can only ever
measure the tree it ships beside. This file has no such line.

    PYTHONPATH=<tree> python3 rw-gate-oracle.py > tree.txt
"""
import sys

from tinygrad.uop.ops import UOp, Ops, AxisType, range_start
import tinygrad.codegen.simplify as S
import tinygrad.codegen.late.coalesce as CO
import tinygrad.codegen.gpudims as GD
from tinygrad.uop.symbolic import symbolic

OUT = []
C = UOp.const
LP = AxisType.LOOP
FLAT = isinstance(UOp.range(4, 0, AxisType.WEAK).arg[0], AxisType)


def row(nm, fn):
  try:
    v = fn()
  except Exception as e:
    v = f"!{type(e).__name__}: {e}"
  OUT.append(f"{nm}={v}")


def rng(n, ids, at):
  """a RANGE with a FLAT arg `(at, *ids)`, which is the shape ops.bend's
  `ARange{ids, at}` means and the only one `axis_id[-1]` and `len(axis_id)` are
  stated over. `UOp.range`'s own 2-tuple arg carries `axis_id == ids`, so the two
  agree on a single id and differ on two -- and a fixture that cannot tell them
  apart cannot pin either."""
  return UOp(Ops.RANGE, src=(C(n),), arg=(at,) + tuple(ids))


def tlen(mod, name):
  t = getattr(mod, name, None)
  return f"!{name}:ABSENT" if t is None else len(t.patterns)


def fixture():
  r0, r1, r2 = UOp.range(4, (0,), LP), UOp.range(2, (1,), LP), UOp.range(4, (2,), LP)
  rd1 = UOp(Ops.REDUCE, src=(C(0), r0), arg=(Ops.ADD, 1))
  rd2 = UOp(Ops.REDUCE, src=(C(1), r0, r1), arg=(Ops.ADD, 2))
  en1 = UOp(Ops.END, src=(rd1, r0))
  mx1 = UOp(Ops.MAX, src=(C(1), C(2)))
  rd3 = UOp(Ops.REDUCE, src=(mx1, r0, r1, r2), arg=(Ops.MAX, 3))
  rd4 = UOp(Ops.REDUCE, src=(C(1), r0), arg=(Ops.ADD, 1))
  en2 = UOp(Ops.END, src=(C(0), r0, r0))
  return dict(r0=r0, r1=r1, r2=r2, rd1=rd1, rd2=rd2, en1=en1, mx1=mx1,
              rd3=rd3, rd4=rd4, en2=en2)


f = fixture()
ans = S.pm_reduce_unparented.rewrite(f['rd1'])
row("ru_answer_c0", lambda: int(ans is not None and len(ans.src) == 2
                                and ans.src[0] is f['rd1'].src[0]))
row("fr_len", lambda: len(S.pm_flatten_range.patterns))
row("ru_len", lambda: len(S.pm_reduce_unparented.patterns))
row("fr_off_reduce", lambda: range_start.get(Ops.REDUCE, 0))
row("fr_off_end", lambda: range_start.get(Ops.END, 0))
row("fr_off_call", lambda: range_start.get(Ops.CALL, 0))
row("fr_off_linear", lambda: range_start.get(Ops.LINEAR, 0))
row("fr_red", lambda: int(S.pm_flatten_range.rewrite(f['rd1']) is None))
e1, e2 = S.pm_flatten_range.rewrite(f['en1']), S.pm_flatten_range.rewrite(f['en2'])
row("fr_grow_same", lambda: int(e1 is not None))
row("fr_grow_moves", lambda: int(e2 is not None))
row("fr_en2_shape", lambda: len(e2.src) if e2 is not None else 0)
row("fr_dedup", lambda: len({id(f['r0']), id(f['r0'])}))
row("fr_unclaimed", lambda: int(S.pm_flatten_range.rewrite(f['mx1']) is None))
row("ru_rop_add", lambda: int(S.pm_reduce_unparented.rewrite(f['rd4']) is not None))
row("ru_rop_max", lambda: int(S.pm_reduce_unparented.rewrite(f['rd3']) is not None))
row("ru_rop_pow", lambda: int(S.pm_reduce_unparented.rewrite(
    UOp(Ops.REDUCE, src=(C(1), f['r0']), arg=(Ops.POW, 1))) is not None))
row("ru_ranges", lambda: int(all(x.op is Ops.RANGE for x in f['rd3'].src[1:])))
row("ru_wall", lambda: int(f['rd1'].src[0].op is not Ops.RANGE))
row("ru_range_yes", lambda: int(f['r0'].op is Ops.RANGE))
srcs, par = f['rd2'].src[1:], f['rd2'].src[0].ranges
row("ru_part_p", lambda: sum(1 for x in srcs if x in par))
row("ru_part_n", lambda: sum(1 for x in srcs if x not in par))
row("ru_answer_rd1", lambda: "MUL" if ans is not None and ans.op is Ops.MUL else "NONE")
row("ru_bnd", lambda: f['r0'].src[0].val)
row("sr_len", lambda: len(S.pm_simplify_ranges.patterns))
row("xr_len", lambda: len(S.pm_split_ranges.patterns))
row("rc_len", lambda: len(S.pm_reduce_collapse.patterns) - len(symbolic.patterns))
row("rc_composite", lambda: len(S.pm_reduce_collapse.patterns))
row("lc_len", lambda: len(S.pm_load_collapse.patterns))
row("is_len", lambda: len(CO.indexing_simplify.patterns))
row("im_len", lambda: len(CO.pm_simplify_add_image.patterns))
row("dv_len", lambda: len(GD.pm_device_to_var.patterns))
# `pm_add_gpudims` at the pin, `pm_group_gpudims` at head -- BOTH are asked, and
# BOTH BEING ABSENT is itself the evidence that this is a rename.
gd = getattr(GD, "pm_group_gpudims", None) or getattr(GD, "pm_add_gpudims", None)
row("gd_len", lambda: len(gd.patterns) if gd is not None else -1)
# `pm_range_to_special` did not exist at the pin; `-1` is the ABSENT sentinel and
# it is a VALUE, not a crash.
row("rs_len", lambda: tlen(GD, "pm_range_to_special"))
row("se_len", lambda: len(GD.pm_split_ends.patterns) if hasattr(GD, "pm_split_ends") else 0)
row("rs_ownlen", lambda: max(0, tlen(GD, "pm_range_to_special")
                             - (len(GD.pm_split_ends.patterns)
                                if hasattr(GD, "pm_split_ends") else 0)))

# `pm_range_to_special`'s RULE, asked as a VALUE.
def rts(r):
  t = getattr(GD, "pm_range_to_special", None)
  if t is None:
    return "NONE"
  out = t.rewrite(r)
  return "NONE" if out is None else f"{out.op}/{out.arg}"


def claimed(r):
  return int(r.axis_type in (AxisType.GLOBAL, AxisType.LOCAL))


def rewrites(r):
  t = getattr(GD, "pm_range_to_special", None)
  return int(t is not None and t.rewrite(r) is not None)


def rop(r):
  t = getattr(GD, "pm_range_to_special", None)
  if t is None:
    return "NONE"
  o = t.rewrite(r)
  return "NONE" if o is None else str(o.op)


def rarg(r):
  t = getattr(GD, "pm_range_to_special", None)
  if t is None:
    return "NONE"
  o = t.rewrite(r)
  return "NONE" if o is None else str(o.arg)


RG, RL, RW, RK = rng(4, (0,), AxisType.GLOBAL), rng(4, (1,), AxisType.LOCAL), \
                 rng(4, (2,), AxisType.WARP), rng(4, (3,), AxisType.LOOP)
row("rs_claim_global", lambda: claimed(RG))
row("rs_claim_local", lambda: claimed(RL))
row("rs_claim_warp", lambda: claimed(RW))
row("rs_claim_loop", lambda: claimed(RK))
row("rs_rewrite_global", lambda: rewrites(RG))
row("rs_rewrite_local", lambda: rewrites(RL))
row("rs_rewrite_warp", lambda: rewrites(RW))
row("rs_rewrite_loop", lambda: rewrites(RK))
row("rs_op_global", lambda: rop(RG))
row("rs_op_warp", lambda: rop(RW))
row("rs_arg_global", lambda: rarg(RG))
row("rs_arg_local", lambda: rarg(RL))
row("rs_name_global", lambda: "gidx" + str(RG.axis_id[-1]))
row("rs_name_warp", lambda: "lidx" + str(RW.axis_id[-1]))
row("rs_idlast_global", lambda: RG.axis_id[-1])
# A TAGGED range and a TWO-ID range, because N-g (the tag is dropped) and N-d
# (`List.head` for `List.last`) each moved NOTHING on a fixture that had neither.
def tagged(r):
  """the tag's NAME, not `repr(tag)`. `repr` of a tag is the quoted string
  `"'rstag'"` and the port prints the bare name -- and a disagreement of one pair
  of quotes is a harness asking two different questions, which is what
  `verify.py` exists to make visible rather than to absorb."""
  t = getattr(GD, "pm_range_to_special", None)
  if t is None:
    return "None"
  o = t.rewrite(r)
  return "None" if o is None else str(o.tag)


row("rs_idlast_two", lambda: rng(4, (0, 1), AxisType.GLOBAL).axis_id[-1])
row("rs_rewrite_const", lambda: rewrites(C(4)))
row("rs_tag_kept", lambda: tagged(rng(4, (0,), AxisType.GLOBAL).replace(tag="rstag")))
row("rs_tag_plain", lambda: tagged(RG))

print("\n".join(OUT))
sys.stderr.write(f"# rows={len(OUT)}\n")