# rw-truth.py -- the ORACLE for tinybendygrad/codegen/rewriter.bend.
#
# It prints its rows in the SAME ORDER and with the SAME SPELLING as the gate in
# rewriter.bend, so
#
#   diff <(python3 .agents/slop/notes/rw-truth.py) <(./bin/bend tinybendygrad/codegen/rewriter.bend)
#
# is the acceptance test and NEITHER side can be nudged to match the other. Every
# value here is read out of the real `tinygrad.codegen.simplify` matchers; nothing
# is restated from the .bend file.
#
#   cd <repo> && python3 .agents/slop/notes/rw-truth.py
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))

from tinygrad.uop.ops import UOp, Ops, PatternMatcher, UPat, range_start, AxisType
import tinygrad.codegen.simplify as S
import tinygrad.codegen.late.coalesce as CO
import tinygrad.codegen.gpudims as GD
from tinygrad.uop.symbolic import symbolic
from tinygrad.codegen.simplify import pm_flatten_range, pm_reduce_unparented, flatten_range

C = UOp.const
LP = AxisType.LOOP

def fixture():
  r0, r1, r2 = UOp.range(4, (0,), LP), UOp.range(2, (1,), LP), UOp.range(4, (2,), LP)
  rd1 = UOp(Ops.REDUCE, src=(C(0), r0), arg=(Ops.ADD, 1))
  rd2 = UOp(Ops.REDUCE, src=(C(1), r0, r1), arg=(Ops.ADD, 2))
  en1 = UOp(Ops.END, src=(rd1, r0))
  r3 = UOp.range(1, (3,), LP)
  mx1 = UOp(Ops.MAX, src=(C(1), C(2)))
  rd3 = UOp(Ops.REDUCE, src=(mx1, r0, r1, r2), arg=(Ops.MAX, 3))
  rd4 = UOp(Ops.REDUCE, src=(C(1), r0), arg=(Ops.ADD, 1))
  en2 = UOp(Ops.END, src=(C(0), r0, r0))
  return dict(r0=r0, r1=r1, r2=r2, rd1=rd1, rd2=rd2, en1=en1, r3=r3, mx1=mx1,
              rd3=rd3, rd4=rd4, en2=en2)

def off(op):
  # `if self.op in range_start: return self.src[range_start[self.op]:]`, and an op
  # OUTSIDE the dict takes the `()` arm -- so an absent op is 0, like LINEAR's.
  return range_start.get(op, 0)

def main():
  f = fixture()
  rows = []
  # `ru_answer_c0` -- `reduce_parented` is empty, so the answer's FIRST src is
  # `red.src[0]` and NOT a REDUCE. `ru_answer_rd1` says the answer is a MUL; this
  # says what it multiplies, and only this row moves when `ru_ret`'s arms swap.
  f = fixture()
  _ans = pm_reduce_unparented.rewrite(f['rd1'])
  rows.append(("ru_answer_c0", int(_ans is not None and len(_ans.src) == 2
                                   and _ans.src[0] is f['rd1'].src[0])))
  rows.append(("fr_len", len(pm_flatten_range.patterns)))
  rows.append(("ru_len", len(pm_reduce_unparented.patterns)))
  rows.append(("fr_off_reduce", off(Ops.REDUCE)))
  rows.append(("fr_off_end", off(Ops.END)))
  rows.append(("fr_off_call", off(Ops.CALL)))
  rows.append(("fr_off_linear", off(Ops.LINEAR)))
  # `pm_flatten_range.rewrite(x) is None`
  rows.append(("fr_red", int(pm_flatten_range.rewrite(f['rd1']) is None)))
  # EN1 does not move, so nothing is added; EN2's duplicated RANGE collapses, so
  # exactly one node is added. Both are read off the ANSWER, not off a counter.
  e1, e2 = pm_flatten_range.rewrite(f['en1']), pm_flatten_range.rewrite(f['en2'])
  rows.append(("fr_grow_same", int(e1 is not None)))
  rows.append(("fr_grow_moves", int(e2 is not None)))
  rows.append(("fr_en2_shape", len(e2.src) if e2 is not None else 0))
  rows.append(("fr_dedup", len({id(f['r0']), id(f['r0'])})))
  rows.append(("fr_unclaimed", int(pm_flatten_range.rewrite(f['mx1']) is None)))
  # `red.arg[0] not in {ADD, MAX, MUL}`
  rows.append(("ru_rop_add", int(pm_reduce_unparented.rewrite(f['rd4']) is not None)))
  rows.append(("ru_rop_max", int(pm_reduce_unparented.rewrite(f['rd3']) is not None)))
  pow_red = UOp(Ops.REDUCE, src=(C(1), f['r0']), arg=(Ops.POW, 1))
  rows.append(("ru_rop_pow", int(pm_reduce_unparented.rewrite(pow_red) is not None)))
  # `assert all(x.op is Ops.RANGE for x in red.src[1:])`
  rows.append(("ru_ranges", int(all(x.op is Ops.RANGE for x in f['rd3'].src[1:]))))
  # `red.src[0].ranges` on a CONST: the fold defers `_ranges`, and Python's own
  # answer is the EMPTY set -- which the port spells `None`.
  rows.append(("ru_wall", int(f['rd1'].src[0].op is not Ops.RANGE)))
  rows.append(("ru_range_yes", int(f['r0'].op is Ops.RANGE)))
  # `partition(red.src[1:], lambda x: x in red.src[0].ranges)` on RD2, whose
  # `src[0]` is `CONST(1)` and therefore has no ranges at all.
  srcs, par = f['rd2'].src[1:], f['rd2'].src[0].ranges
  rows.append(("ru_part_p", sum(1 for x in srcs if x in par)))
  rows.append(("ru_part_n", sum(1 for x in srcs if x not in par)))
  # the RULE'S OWN ANSWER, as a row: it must be a MUL whose second src is R0's
  # BOUND (`C4`) and not its axis id. `ru_answer_rd1` is the arena INDEX in the
  # .bend and the OP NAME here -- both read the same rule, and a mutation of
  # `r.src[0]` to `r.src[1:]` changes the op here and the index there.
  ans = pm_reduce_unparented.rewrite(f['rd1'])
  rows.append(("ru_answer_rd1", "MUL" if ans is not None and ans.op is Ops.MUL else "NONE"))
  # `r.src[0]` -- R0's BOUND. C0/C2/C4 are all CONSTs, so only the VALUE tells
  # them apart and this row is what pins it.
  rows.append(("ru_bnd", f['r0'].src[0].val))
  # The TABLE LENGTHS. Every one is `len(<table>.patterns)` read out of Python.
  rows.append(("sr_len", len(S.pm_simplify_ranges.patterns)))
  rows.append(("xr_len", len(S.pm_split_ranges.patterns)))
  rows.append(("rc_len", len(S.pm_reduce_collapse.patterns) - len(symbolic.patterns)))
  rows.append(("rc_composite", len(S.pm_reduce_collapse.patterns)))
  rows.append(("lc_len", len(S.pm_load_collapse.patterns)))
  rows.append(("is_len", len(CO.indexing_simplify.patterns)))
  rows.append(("im_len", len(CO.pm_simplify_add_image.patterns)))
  rows.append(("dv_len", len(GD.pm_device_to_var.patterns)))
  rows.append(("gd_len", len(GD.pm_add_gpudims.patterns)))
  for nm, v in rows:
    print(f"{nm}={v}")

if __name__ == "__main__":
  main()