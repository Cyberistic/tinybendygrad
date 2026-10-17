# axisflip.bend -- `Tensor.flip`'s SHAPE, PER AXIS, ON A BASE THAT CAN DISTINGUISH THE AXIS.
#
#   .venv/bin/python gates/axisflip-gate.py
#
# WHY THIS IS A GATE AND NOT A ROW IN `groupflip.bend`. `gates/groupflip.bend`'s base is
# `mxw_reshape(mxw_base(), [4,4,4,4])`, ALL FOUR DIMS ARE 4, and the defect this file exists to
# catch is a substitution that is the IDENTITY whenever `shape[0] == shape[axis]`. On (4,4,4,4)
# a `flip` that dropped dim 0 where upstream drops dim `axis` builds the same graph. MEASURED,
# as a before/after on the same two calls in `gates/mxgraph-fixture-rows.bend`:
# `shape_asym_a1_on_2448` moved `4,4,4,8` -> `2,4,4,8` when the defect was fixed and
# `shape_sym_a1_on_4444` read `4,4,4,4` on both sides of the same fix. One base can see the
# axis and the other cannot, and the difference is the base.
#
# **THE BASE IS (2,4,4,8) AND NOT (1,4,8,8), BECAUSE (1,4,8,8) HAS A SIZE-1 AXIS 0.**
# `movement.py:255`'s `if resolve((n:=ret.shape[axis]) <= 1, False): continue` skips it, so
# `flip([0])` returns the base node and `flip([0,1])` is `flip([1])`: `flip_0` and `flip_01`
# certify nothing. And it is not (4,4,4,4) for the reason above.
#
# **AND (2,4,4,8) IS THE BEST AVAILABLE, NOT AN ARBITRARY ONE.** The buffer holds 256 ELEMENTS
# (`mxw_base()` is `mxw_buf(.., 0, 256)`) and CPython's `_shape` checks every reshape's size, so
# the base must have product 256. 256 = 2^8, and the partitions of 8 into four POSITIVE parts are
# {5,1,1,1} {4,2,1,1} {3,3,1,1} {2,2,2,2}, i.e. (32,2,2,2) (16,4,2,2) (8,8,2,2) (4,4,4,4) --
# all four REPEAT a dim, so a rank-4 base of four distinct dims does not exist at 256. Rank 3
# would allow (2,4,32) and all-distinct, but rank 3 has no axis 3 to flip. `axisflip-gate.py`'s
# `base_separates_the_axis` holds the property this paragraph states, so a base that goes back to
# a cube turns THIS GATE red while leaving every one of its other rows green.
#
# **THE WITNESS IS THE SHAPE, AND THE REASON IS A MEASUREMENT, NOT A PREFERENCE.** groupflip's
# row is `<OP>x<nsrc>[<src ops>]{order}`: it carries the op, the src count, the src op SEQUENCE
# and the PERMUTE order, and it carries no RESHAPE target shape, no PAD offset and no SHRINK
# size. The defect was a wrong `crop`/`tail` LIST, so it moved those and nothing else. Across the
# fix, `gates/mxgraph-fixture-rows.bend`'s `ctl_a1` (33), `ctl_a1x2` (47) and `ctl_a1x4` (75) --
# the whole `<n> Ops.<TOP>/<nsrc> <srcops>` shape that `gates/mx_graph_census-gate.py` compares --
# were BYTE-IDENTICAL while `ctl_a1`'s shape moved `4,4,8,8` -> `1,4,8,8`. A graph row cannot see
# a wrong shape, so the row that can is the one carrying the size. `n=` is the cut-relative node
# COUNT and it is here because it is the AXIS-SENSITIVE half of the row: CPython's counts are 10 /
# 28 / 37 / 37 / 37 / 52 / 52 across these seven bases, so the oracle lane is seven DISTINCT
# measurements and not one string seven times.
#
# **`axis1` IS THIS GATE'S OWN BLINDNESS GUARD, AND IT IS A ROW RATHER THAN A GATE CHECK.**
# It prints the two lists the defect is about -- `base.shape[1:]` (what the port used) against
# `[base.transpose(0,1).shape[1:]]` (what `movement.py:257` uses, since `:256` makes `x` the
# transpose first) -- so a base on which they are EQUAL turns the gate RED with every other row
# still green. On this (2,4,4,8) they read `4,4,8` against `2,4,8`; on groupflip's (4,4,4,4) they
# read `4,4,4` against `4,4,4` and a gate on it could not fail for this reason at all. A check in
# the gate FILE would have to re-read the lane artifact to learn the base; a row is computed by
# both lanes from their own base and needs nothing but the diff.

import Base
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/mixin/movement.bend as MX

# `<shape> n=<cut-relative node count>`, and the shape comes first because it is the field that
# did the work.
#
# **`n=` IS CUT-RELATIVE AND THE CUT IS `len(topo(base)) - 1` COMPUTED ON EACH SIDE**, for the
# reason `gates/groupflip.bend`'s `gf_cut` gives and MEASURED here: upstream moved a BUFFER's size
# out of `ParamArg` into a size CONST src (`72f98ffe0`), so the port's base is 9 nodes and
# CPython's is 10 and the ABSOLUTE counts differ by one on every row including `base` itself. The
# cut drops everything below the base root, and the difference in what it drops is exactly the
# difference the rows were carrying. An absolute count is how `gates/mx_graph_census-gate.py` is
# red on 16 of 17 rows for a cause that has nothing to do with `flip`.
def af_n(+t: T.Tensor, cut: Nat) -> U32:
  U32.from_nat(List.length(&2, U32, List.drop(&2, U32,
    O.UOp.toposort(O.Arena.budget(T.Tensor.ar(t)), T.Tensor.ar(t), T.Tensor.u(t)), cut)))

def af_row(nm: String, +t: T.Tensor, cut: Nat) -> IO(Unit):
  IO.print(String.concat([nm, "=", MX.mx_show(MX.mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t))),
                          " n=", U32.show(af_n(t, cut))]))

def af_cut(+t: T.Tensor) -> Nat:
  Nat.sub(List.length(&2, U32,
    O.UOp.toposort(O.Arena.budget(T.Tensor.ar(t)), T.Tensor.ar(t), T.Tensor.u(t))), 1n)

# ONE BASE FOR EVERY ROW, and that is CPython's own arrangement: `axisflip-oracle.py` builds its
# base once at module level and every row flips THAT tensor, so both lanes intern the rows'
# CONSTs into one arena. A row that built its own base would count a smaller graph than the
# oracle's row for the same call -- MEASURED in `gates/mxgraph-fixture-rows.bend:20-26`, where
# `flip([1])` reads 33 nodes on a shared arena and 47 for `flip([1,1])` on a fresh one.
def af_rows(+t: T.Tensor) -> IO(Unit):
  +c = af_cut(t)
  do IO<Unit>:
    af_row("base", t, c)
    af_row("fnone", MX.mxw_flip(t, []), c)
    af_row("f0", MX.mxw_flip(t, [0]), c)
    af_row("f1", MX.mxw_flip(t, [1]), c)
    af_row("f2", MX.mxw_flip(t, [2]), c)
    af_row("f3", MX.mxw_flip(t, [3]), c)
    af_row("f01", MX.mxw_flip(t, [0, 1]), c)
    af_row("f10", MX.mxw_flip(t, [1, 0]), c)
    IO.print(String.concat(["axis1=", MX.mx_show(List.drop(&2, U32, MX.mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t)), 1n)),
                            " vs ", MX.mx_show(List.drop(&2, U32, MX.mxm_pick_all(MX.mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t)), MX.mxf_order(4n, 1)), 1n))]))
    return Unit{}

def main() -> IO(Unit):
  +t = MX.mxw_reshape(MX.mxw_base(), [2, 4, 4, 8])
  af_rows(t)