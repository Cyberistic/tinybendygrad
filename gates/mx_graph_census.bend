# mx_graph_census.bend -- A GRAPH CENSUS over the ported PUBLIC movement WRAPPERS in
# `tinybendygrad/mixin/movement.bend`: each driven once per fixture, with its toposort OP
# SEQUENCE printed in the format CPython prints for the method it mirrors.
#
#   .venv/bin/python gates/mx_graph_census-gate.py
#
# THE POPULATION IS DISCOVERED, AND THE DISCOVERY IS TWO FILTERS, NOT A LIST.
#
#   .venv/bin/python -c "..."   # see the gate's docstring for the exact command
#
#   (1) the `mx*` names: `grep -o '^def mx[a-z_0-9]*' tinybendygrad/mixin/movement.bend
#       | sort -u` -> 85, which is the whole public surface (`mx_`, `mxm_`, `mxw_`).
#   (2) A name is a METHOD PORT iff, after stripping one of the three prefixes `mxw_`,
#       `mxm_`, `mx_`, the remainder names a method of CPython's
#       `tinygrad/mixin/movement.py`. That is 7: `mxm_expand`->expand, `mxm_shape`->shape,
#       `mxw_flip`->flip, `mxw_pad`->pad, `mxw_permute`->permute, `mxw_reshape`->reshape,
#       `mxw_shrink`->shrink.
#   (3) A METHOD PORT is a ROW iff it BUILDS A UOp GRAPH -- i.e. its body calls
#       `O.UOp.new`, so it returns a `T.Tensor` and there is a toposort to print. That
#       drops `mxm_shape` (`-> List<&2, U32>`, the `_shape` arms of ops.py, not a
#       movement.py method body) and `mxm_expand` (`-> Bool`, a one-bit op test), which
#       are READERS of a graph and not builders of one. What remains is the WRITE HALF:
#
#           mxw_reshape  mxw_permute  mxw_pad  mxw_shrink  mxw_flip        (5)
#
#       and four of the five are methods `mixin/movement.py` gives an IDENTITY TEST
#       (`return self if ret.shape == self.shape else ret`, :184/:190/:212/:231). The
#       FIFTH IS `flip` -- WHICH NO LONGER HAS ONE. `900880433` ("remove Ops.FLIP [pr]",
#       #18729) deleted `Ops.FLIP` and `flip` is a loop (movement.py:253-267) whose early
#       exit is `movement.py:255`'s per-axis
#       `if resolve((n:=ret.shape[axis]) <= 1, False): continue`, so `mxw_flip`'s header
#       says so and `flip_noop` below returns the base without reaching an identity test.
#       The rest of `movement.py` is NOT PORTED (see the file header's NOT PORTED list),
#       so 5 is the whole graph-building surface and not a sample of it.
#
# THE FIXTURE IS THE PORT'S OWN, AND IT IS `MX.mxw_base()`. The write half's identity
# test reads the SOURCE's shape, so the source cannot be a bare node -- it is
# `RESHAPE(BUFFER, STACK(1,4,8,8))`, the port's own `mxw_base` (movement.bend:1722). The CPython
# lane builds the SAME graph from a raw `UOp.new_buffer` and not from `Tensor.empty`, and the
# reason is MEASURED: `Tensor.empty(1,4,8,8, device='PYTHON')` is
# `6 Ops.RESHAPE/2 Ops.ALLOC Ops.STACK`, an ALLOC where the port has a BUFFER, and the
# ALLOC/BUFFER split would move every no-op row (`reshape_noop`, `permute_noop`,
# `pad_noop`, `shrink_noop`, `flip_noop`) because those rows return the BASE, whose root
# srcs ARE the storage node. `UOp.new_buffer("PYTHON", 256, float)` gives the two bases
# THE SAME ROOT -- `Ops.RESHAPE/2 Ops.BUFFER Ops.STACK` on both -- and THE SAME LENGTH
# UNTIL `72f98ffe0` ("move size from ParamArg to src"): upstream's base is 7 nodes and the
# port's is 6, because upstream's BUFFER carries its size as a CONST SRC and the port's
# carries it in the arg. THAT ONE NODE IS THIS GATE'S RESIDUAL; see THE RESIDUAL below.
# ("byte-identical", which this file claimed until 2026-10-17, was true of the PRE-`72f98ffe0`
# upstream and is not true of the vendored one.)
#
# THE PRINTER IS `O.Rng.sig` AND NOT `mxw_sig` -- `ops.bend`'s line numbers are cited by NAME
# here on purpose, because a unit is renumbering `uop/ops.bend` and every line number in it is
# a moving target. `mxw_sig` is the file's
# own `n=/op=/nsrc=/srcops=` string; the census format is the one the other three censuses
# use (`<toposort length> Ops.<TOP>/<nsrc> <src op sequence>`), so the CPython oracle can
# reproduce it with a `seq()`/`sig()` pair and the two lanes are comparable line-for-line.
#
# EVERY ROW IS DRIVEN THROUGH THE TENSOR-LEVEL METHOD (`MX.mxw_reshape`, `MX.mxw_pad`,
# ...) and not through the internal `.go`/`.of` helpers, for the reason the brief records:
# an oracle that calls a path the wrapper does not take agrees with a port that mirrors
# the wrong thing. The identity-test arm is a TENSOR-LEVEL branch (`mxw_pick`), so only
# the wrapper reaches it -- the four `*_noop` rows below are the ones that see it.
#
# ===========================================================================================
# THE RESIDUAL: 16 OF THE 17 ROWS CARRY delta=+1, AND `reshape_256`'s delta=0 IS ARITHMETIC.
#
# MEASURED on the vendored `tinygrad/` at `62319c8ae612` with this file's own fixtures, one
# arena per row (gates/mxgraph-fixture-rows.bend is the instrument; it prints the same rows plus
# the arena index and the shape):
#
#     row              upstream   port   delta   above-the-base-root: upstream / port
#     base                   7      6     -1     --  the cut is 6 upstream, 5 on the port
#     reshape_256            8      8      0                  2 / 3
#     pad_1_1               12     11     -1                  6 / 6
#     flip_01               34     33     -1                 28 / 28
#
# ABSOLUTE COUNTS hide the shape of it and the `cut` column shows it: counted RELATIVE TO THE
# BASE, `reshape_256` is the ONLY row in this file that still differs -- the port adds THREE
# nodes above the base where upstream adds TWO -- and the other sixteen agree exactly. So the
# seventeen absolute rows are ONE defect seen from two sides: upstream's BUFFER has a size
# CONST src that the port's does not (`72f98ffe0`; the port still has
# `size: Maybe<&2, U32>` in `ParamArg`, ops.bend:877-895, and `mxw_buf` (movement.bend:1236)
# builds `BUFFER` with `Nil{}` srcs), and for `reshape(256)` that same CONST is upstream's
# SHAPE ARG, so upstream's shape arg adds nothing to the toposort and the port's does.
# `gates/groupflip-oracle.py:63-70` and `gates/groupflip.bend:170-180` name this cause, pay for
# it with a `cut`, and are GREEN.
#
# **NO `cut` HERE, AND THAT IS A DECISION WITH A REASON.** A `cut` would take this gate from
# 16-of-17 red to 1-of-17 red and would look like the fixture fix landing. It is not, and it
# would be worse than the red, for the reason the next paragraph gives.
#
# **AND `flip_01` IS A ROW THAT WOULD GO GREEN ON A WRONG GRAPH.** Measured cut-relative it is
# 28 against upstream's 28, same op, same nsrc, same src ops -- while `mxw_dims_of` of the two
# results are (4,4,8,8) and (1,4,8,8). `mxf_compose` takes `tail`/`crop` from
# `mxw_dims_of(ret)[1:]` (movement.bend:1675-1676) where `movement.py:257-259` takes them from
# `x.shape[1:]` with `x = ret.transpose(0, axis)`, i.e. from `sh[1:]` WITH POSITION `axis`
# HOLDING `sh[0]`. The two lists are equal iff `shape[0] == shape[axis]`, so the port's flip is
# correct for axis 0 and wrong for every other axis, and MEASURED on this very base:
# `flip([0])` -> (1,4,8,8) correct, `flip([1])` -> (4,4,8,8), `flip([2])` and `flip([3])` ->
# (8,4,8,8), `flip([0,1])` -> (4,4,8,8); upstream's are all (1,4,8,8). The node COUNT is
# untouched by the error, which is why `mx_graph_census`'s row -- a length, a root op, an nsrc
# and a src op SEQUENCE -- cannot see a wrong shape at all. A `cut` would make that row GREEN.
# `gates/groupflip.bend`'s (4,4,4,4) base cannot see it either, for the same `shape[0] ==
# shape[axis]` reason: on `mxw_reshape(base, [2,4,4,8])` -- the same 256 elements, dim 0 not
# dim 1 -- `flip([1])` answers (4,4,4,8) against upstream's (2,4,4,8) (mxgraph-fixture-rows.bend,
# `shape_asym_a1_on_2448`). SO: a red row here is worth more than a green one, and the defect
# is in `tinybendygrad/mixin/movement.bend` and `tinybendygrad/uop/ops.bend`, which this edit
# does not touch.
# ===========================================================================================

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/mixin/movement.bend as MX

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# `O.Rng.sig` reads the arena and the node index. `+t` because both accessors read it.
def sg(+t: T.Tensor) -> String:
  O.Rng.sig(T.Tensor.ar(t), T.Tensor.u(t))

# --- the base, and the five wrappers, each with a real fixture and a no-op ----------
def sig_base() -> String:
  +t = MX.mxw_base()
  sg(t)

def sig_reshape_1_2_8_16() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_reshape(t, [1, 2, 8, 16]))

def sig_reshape_1_4_64() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_reshape(t, [1, 4, 64]))

def sig_reshape_noop() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_reshape(t, [1, 4, 8, 8]))

# THE ONE-ELEMENT SHAPE ARG, AND IT IS A LIVE PATH. `shape_to_shape_arg` (ops.py:106-110) is
# `src[0] if len(src) == 1 else UOp(Ops.STACK, src=src)`, so CPython builds a BARE CONST for a
# one-element shape; `mxw_stk` (:1254) is `G.mstack` UNCONDITIONALLY, so the port builds a
# `STACK`. `mixin/rand.bend` calls `MX.mxw_reshape(t, [])` and `MX.mxw_reshape(t, [1, ...])`
# on the `_pool` path and its own R3 records the same fact ("fixed for PAD and SHRINK, NOT for
# RESHAPE"). `256` is `prod((1,4,8,8))`, so the reshape is legal on both sides.
def sig_reshape_256() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_reshape(t, [256]))

def sig_permute_1_0_2_3() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_permute(t, [1, 0, 2, 3]))

def sig_permute_3_1_2_0() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_permute(t, [3, 1, 2, 0]))

def sig_permute_noop() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_permute(t, [0, 1, 2, 3]))

# `pad`'s second list is the ABSOLUTE END (`(x[0], s+x[0]+x[1])`, movement.py:189), which
# is what `mxw_pad`'s `his` already is: `pad(((0,0),(0,0),(1,1),(1,1)))` over (1,4,8,8)
# has marg `((0,1),(0,4),(1,10),(1,10))`, so `his = [1,4,10,10]`.
def sig_pad_1_1() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_pad(t, [0, 0, 1, 1], [1, 4, 10, 10]))

def sig_pad_asy() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_pad(t, [0, 0, 2, 1], [2, 6, 13, 9]))

def sig_pad_noop() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_pad(t, [0, 0, 0, 0], [1, 4, 8, 8]))

# `shrink`'s second list is the SIZE (`(x[0], x[1]-x[0])`, movement.py:211), so
# `shrink(((0,0),(0,0),(1,5),(1,5)))` is `offs=[0,0,1,1] sizes=[1,4,4,4]`.
def sig_shrink_1_1() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_shrink(t, [0, 0, 1, 1], [1, 4, 4, 4]))

def sig_shrink_asy() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_shrink(t, [0, 1, 2, 0], [1, 3, 5, 8]))

def sig_shrink_noop() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_shrink(t, [0, 0, 0, 0], [1, 4, 8, 8]))

# ===========================================================================================
# THE THREE FLIP FIXTURES ARE AXIS LISTS, AND BEFORE THIS REVISION THEY WERE FLAG VECTORS.
#
# `mxw_flip`'s second argument is upstream's `axis_arg` (`def mxw_flip(+t, +axes)`,
# movement.bend:1711, mirroring `movement.py:254`'s `for axis in axis_arg`). Upstream deleted
# `Ops.FLIP` (`900880433`, 2026-10-11) and reimplemented `Tensor.flip` as a PAD/SHRINK/TRANSPOSE
# LOOP, so the argument stopped being the 0/1 vector that fed `_mop(Ops.FLIP, arg=flip_arg)` and
# became the list of AXES, in the caller's order. The gate's oracle had already moved --
# `mx_graph_census-oracle.py:67-69` asks `flip(0)`, `flip(0, 1)` and `flip(())` -- and this file
# was still passing `[1,0,0,0]`, `[1,1,0,0]` and `[0,0,0,0]`, so for three rows the two lanes
# were answering different questions. MEASURED, same (1,4,8,8) base, one arena per row:
#
#     fixture                      this file (before)   the axis-list fixture   oracle
#     flip_0      flip(0)          69 Ops.RESHAPE/2     6 Ops.RESHAPE/2        7 Ops.RESHAPE/2
#                                 Ops.SHRINK Ops.STACK  Ops.BUFFER Ops.STACK   Ops.BUFFER Ops.STACK
#     flip_01     flip(0, 1)       71 Ops.RESHAPE/2     33 Ops.PERMUTE/1       34 Ops.PERMUTE/1
#                                 Ops.SHRINK Ops.STACK  Ops.RESHAPE            Ops.RESHAPE
#     flip_noop   flip(())         6 Ops.RESHAPE/2      6 Ops.RESHAPE/2         7 Ops.RESHAPE/2
#                                 Ops.BUFFER Ops.STACK  Ops.BUFFER Ops.STACK    Ops.BUFFER Ops.STACK
#
# so `[0]`, `[0, 1]` and `[]` put all three rows on the oracle's own questions, and each of the
# three now carries the SAME one-node shortfall as every other row of this file: the port is one
# node short of upstream, and THE RESIDUAL above says which node and whose defect it is.
#
# **`[0,0,0,0]` PASSED FOR A REASON THAT WAS NOT THE ORACLE'S, AND IT STILL PASSES FOR A REASON
# THAT IS NOT THE ORACLE'S.** It read `6 Ops.RESHAPE/2 Ops.BUFFER Ops.STACK`, the base's own
# signature, so it agreed with `flip(())` on the number and agreed for a different cause. MEASURED
# with `gates/mxgraph-fixture-rows.bend`: `flip([])`, `flip([0])`, `flip([0,0])` and `flip([0,0,0,0])`
# all return arena index **6**, and `mxw_base()` is index 6 -- so `flip([0,0,0,0])` returns THE BASE
# NODE, and it does so because axis 0 of (1,4,8,8) has SIZE 1 and `movement.py:255`'s
# `if resolve((n:=ret.shape[axis]) <= 1, False): continue` fires on every one of the four
# iterations. It is NOT an even number of flips cancelling. The parity story is REFUTED by the
# same file: `flip([1])` is 33 nodes, `flip([1,1])` is 47 and `flip([1,1,1,1])` is 75, so a
# repeated NON-degenerate axis composes every time, exactly as it must.
#
# THE THREE DISTINCT CAUSES THAT ALL PRINT THE BASE: `flip(())` never enters the loop, `flip([0])`
# enters it once and continues once, and `flip([0,0,0,0])` enters it four times and continues four
# times. Only the first is the oracle's `flip(())`. `[]` is the one that asks the same question.
# ===========================================================================================
def sig_flip_0() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, [0]))

def sig_flip_01() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, [0, 1]))

def sig_flip_noop() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, []))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("base", sig_base())
    b : Unit <- srow("reshape_1_2_8_16", sig_reshape_1_2_8_16())
    c : Unit <- srow("reshape_1_4_64", sig_reshape_1_4_64())
    d : Unit <- srow("reshape_noop", sig_reshape_noop())
    d2 : Unit <- srow("reshape_256", sig_reshape_256())
    e : Unit <- srow("permute_1_0_2_3", sig_permute_1_0_2_3())
    f : Unit <- srow("permute_3_1_2_0", sig_permute_3_1_2_0())
    g : Unit <- srow("permute_noop", sig_permute_noop())
    h : Unit <- srow("pad_1_1", sig_pad_1_1())
    i : Unit <- srow("pad_asy", sig_pad_asy())
    j : Unit <- srow("pad_noop", sig_pad_noop())
    k : Unit <- srow("shrink_1_1", sig_shrink_1_1())
    l : Unit <- srow("shrink_asy", sig_shrink_asy())
    m : Unit <- srow("shrink_noop", sig_shrink_noop())
    n : Unit <- srow("flip_0", sig_flip_0())
    o : Unit <- srow("flip_01", sig_flip_01())
    p : Unit <- srow("flip_noop", sig_flip_noop())
    return Unit{}
