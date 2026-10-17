# mxgraph-fixture-rows.bend -- WHAT `mxw_flip` DOES WITH AN AXIS LIST, AND WHICH OF THE PORT'S
# FLIP ROWS CAN SEE THE ANSWER.
#
#   DEV=CPU SPEC=1 ./bin/bend gates/mxgraph-fixture-rows.bend
#
# (It is `-rows.bend` and not `-probe.bend` on purpose: `.gitignore:51`'s `*probe.bend` is a
# scratch rule, and this file is the only record of a fixture change whose effect the gate's own
# verdict cannot show -- `gates/mx_graph_census-gate.py` reads `DISAGREE (bd): n=16 of 17 rows`
# both before and after, so the row TEXTS are the evidence and a scratch file is not evidence.)
#
# WHY THIS FILE EXISTS. `gates/mx_graph_census.bend:136,140,144` fed the OLD flag vector
# `[1,0,0,0]` / `[1,1,0,0]` / `[0,0,0,0]` to `MX.mxw_flip`, which since upstream deleted `Ops.FLIP`
# (`900880433`) takes an AXIS LIST -- `def mxw_flip(+t, +axes)`, movement.bend:1711, mirroring
# `movement.py:254`'s `for axis in axis_arg`. A flag vector is a SET; an axis list is a SEQUENCE.
# This file is the measurement behind the fixture change: what each of the three OLD fixtures does,
# what each of the three NEW ones does, and -- the question the census's summary row CANNOT ask --
# whether the two agree on the SHAPE, which is what tells a composition that returns the right
# answer from one that returns a wrong answer with the right node count.
#
# EVERY ROW HERE IS ONE `def` WITH ITS OWN `mxw_base()`, i.e. its own arena, and that is the
# census's shape too -- `gates/mx_graph_census.bend` builds the base inside each `sig_*`, so a
# row-for-row comparison is only a comparison if this file matches it. Interning is PER ARENA,
# so a block of rows sharing one arena is not the same measurement: MEASURED, `flip([1])` reads
# 33 nodes on a shared arena and 33 on a fresh one, while `flip([1,1])` reads 47 on a shared one
# because the first compose's CONSTs are already interned. Both readings are recorded nowhere
# else, so the rows below are all fresh and only the fresh reading is reported.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/mixin/movement.bend as MX

def sg(+t: T.Tensor) -> String:
  O.Rng.sig(T.Tensor.ar(t), T.Tensor.u(t))

def ix(+t: T.Tensor) -> String:
  U32.show(T.Tensor.u(t))

def sh(+t: T.Tensor) -> String:
  MX.mx_show(MX.mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t)))

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# --- (1) THE THREE STALE FIXTURES, MEASURED, ON THE CENSUS'S OWN (1,4,8,8) BASE ---------
def old_flip_0() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, [1, 0, 0, 0]))

def old_flip_01() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, [1, 1, 0, 0]))

def old_flip_noop() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, [0, 0, 0, 0]))

# --- (2) THE THREE FIXTURES THAT MATCH `movement.py`'s OWN CALLS ------------------------
# `flip(0)`, `flip(0, 1)`, `flip(())` -- the calls the CPython oracle already makes, so the two
# lanes are asking the same question of two implementations of one signature.
def new_flip_0() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, [0]))

def new_flip_01() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, [0, 1]))

def new_flip_noop() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, []))

# --- (3) IS `old_flip_noop` THE BASE, OR A DIFFERENT NODE WITH THE BASE'S SIGNATURE? ------
# `sg` is a SUMMARY: `<len> Ops.<TOP>/<nsrc> <src ops>`. `flip([])` and `flip([0,0,0,0])` both
# print `6 Ops.RESHAPE/2 Ops.BUFFER Ops.STACK`, and a summary cannot tell "the loop never ran"
# from "the loop ran and returned its input". The arena INDEX settles it: the base is index 6 and
# a node built by a compose is never 6. `u=` is the whole reason this file has a third column.
def new_flip_noop_u() -> String:
  +t = MX.mxw_base()
  String.concat([sg(MX.mxw_flip(t, [])), " u=", ix(MX.mxw_flip(t, []))])

def new_flip_0_u() -> String:
  +t = MX.mxw_base()
  String.concat([sg(MX.mxw_flip(t, [0])), " u=", ix(MX.mxw_flip(t, [0]))])

def old_flip_noop_u() -> String:
  +t = MX.mxw_base()
  String.concat([sg(MX.mxw_flip(t, [0, 0, 0, 0])), " u=", ix(MX.mxw_flip(t, [0, 0, 0, 0]))])

# --- (4) THE PARITY CONTROL. A REPEATED AXIS MUST NOT CANCEL ----------------------------
# The claim under test is "`[0,0,0,0]` is an EVEN number of flips of axis 0, so it lands on the
# base". A parity story predicts `flip([1,1])` is also the base, and axis 1 of `mxw_base()` has
# size 4 -- not 1 -- so `movement.py:255`'s `if resolve((n:=ret.shape[axis]) <= 1, False):
# continue` CANNOT fire for it. `[1,1]` is the row that separates the two stories.
def one() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, [1]))

def two() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, [1, 1]))

def four() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, [1, 1, 1, 1]))

# --- (5) THE SHAPE, WHICH THE SUMMARY ROW CANNOT PRINT ----------------------------------
# `mxf_axis` reads `mxw_dims_of(ret)` and `mxf_compose` derives `tail`/`crop` from `sh[1:]`.
# `movement.py:257-259` derives both from `x.shape[1:]` where `x = ret.transpose(0, axis)`. Those
# are the same list only when `shape[0] == shape[axis]`, and `mxw_base()` is (1,4,8,8), so every
# axis except 0 separates them. The rows print `mxw_dims_of` of the RESULT, because a wrong tail
# propagates into the final reshape and a wrong final reshape is a wrong SHAPE -- which the
# census's `<n> Ops.<TOP>/<nsrc> <srcops>` row cannot see, since it prints a count and not a size.
def shape_base() -> String: sh(MX.mxw_base())
def shape_a0() -> String:
  +t = MX.mxw_base()
  sh(MX.mxw_flip(t, [0]))
def shape_a1() -> String:
  +t = MX.mxw_base()
  sh(MX.mxw_flip(t, [1]))
def shape_a2() -> String:
  +t = MX.mxw_base()
  sh(MX.mxw_flip(t, [2]))
def shape_a3() -> String:
  +t = MX.mxw_base()
  sh(MX.mxw_flip(t, [3]))
def shape_a01() -> String:
  +t = MX.mxw_base()
  sh(MX.mxw_flip(t, [0, 1]))

# --- (6) THE BASE `gates/groupflip.bend` USES, FOR THE SAME QUESTION ---------------------
# groupflip's `gf_fbase` is `mxw_reshape(mxw_base(), [4,4,4,4])`, and 4 == 4 makes `sh[1:]` and
# `x.shape[1:]` the same list on every axis that gate flips. These two rows are (2,4,4,8) --
# the same 256 elements, and dim 0 (2) is not dim 1 (4) -- so the same list is NOT the same list.
# A gate on (4,4,4,4) cannot see the difference; these two rows can.
def gf_fbase() -> T.Tensor:
  +t = MX.mxw_base()
  MX.mxw_reshape(t, [4, 4, 4, 4])

def asym_fbase() -> T.Tensor:
  +t = MX.mxw_base()
  MX.mxw_reshape(t, [2, 4, 4, 8])

def shape_asym_a1() -> String:
  +t = asym_fbase()
  sh(MX.mxw_flip(t, [1]))

def shape_sym_a1() -> String:
  +t = gf_fbase()
  sh(MX.mxw_flip(t, [1]))

# --- (7) THE RESIDUAL, MEASURED RELATIVE TO THE BASE -------------------------------------
# Sixteen of this gate's seventeen rows carry delta=+1 and `reshape_256` carries delta=0, which
# reads like agreement. `gates/groupflip-oracle.py:63-70` and `gates/groupflip.bend:170-180` name
# the cause -- upstream moved a BUFFER's size out of `ParamArg` into a size CONST src
# (`72f98ffe0`), so upstream's base is `BUFFERx1[CONST]` and the port's is `BUFFERx0[]` -- and
# they pay for it with a `cut` of `len(base.toposort()) - 1`, computed on EACH side. The cut turns
# the absolute counts into "nodes this wrapper ADDED", and THIS is the pair of numbers that shows
# what `reshape_256`'s zero really is: whether the port's extra CONST and upstream's missing size
# CONST are the same node.
def cut_of(+t: T.Tensor) -> Nat:
  Nat.sub(List.length(&2, U32, O.UOp.toposort(O.Arena.budget(T.Tensor.ar(t)), T.Tensor.ar(t), T.Tensor.u(t))), 1n)

def n_nodes(+t: T.Tensor) -> U32:
  U32.from_nat(List.length(&2, U32, O.UOp.toposort(O.Arena.budget(T.Tensor.ar(t)), T.Tensor.ar(t), T.Tensor.u(t))))

def c_base_cut() -> String: U32.show(U32.from_nat(cut_of(MX.mxw_base())))
def c_resh256_cut() -> String:
  +t = MX.mxw_base()
  +m = MX.mxw_reshape(t, [256])
  U32.show(U32.sub(n_nodes(m), U32.from_nat(cut_of(t))))
def c_flip01_cut() -> String:
  +t = MX.mxw_base()
  +m = MX.mxw_flip(t, [0, 1])
  U32.show(U32.sub(n_nodes(m), U32.from_nat(cut_of(t))))
def c_pad11_cut() -> String:
  +t = MX.mxw_base()
  +m = MX.mxw_pad(t, [0, 0, 1, 1], [1, 4, 10, 10])
  U32.show(U32.sub(n_nodes(m), U32.from_nat(cut_of(t))))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("old_flip_0", old_flip_0())
    b : Unit <- srow("old_flip_01", old_flip_01())
    c : Unit <- srow("old_flip_noop", old_flip_noop())
    d : Unit <- srow("new_flip_0", new_flip_0())
    e : Unit <- srow("new_flip_01", new_flip_01())
    f : Unit <- srow("new_flip_noop", new_flip_noop())
    g : Unit <- srow("ctl_a1", one())
    h : Unit <- srow("ctl_a1x2", two())
    i : Unit <- srow("ctl_a1x4", four())
    j : Unit <- srow("shape_base", shape_base())
    k : Unit <- srow("shape_a0", shape_a0())
    l : Unit <- srow("shape_a1", shape_a1())
    m : Unit <- srow("shape_a2", shape_a2())
    n : Unit <- srow("shape_a3", shape_a3())
    o : Unit <- srow("shape_a01", shape_a01())
    p : Unit <- srow("shape_sym_a1_on_4444", shape_sym_a1())
    q : Unit <- srow("shape_asym_a1_on_2448", shape_asym_a1())
    r : Unit <- srow("base_index_u", ix(MX.mxw_base()))
    s : Unit <- srow("new_flip_noop_u", new_flip_noop_u())
    t2 : Unit <- srow("new_flip_0_u", new_flip_0_u())
    u : Unit <- srow("old_flip_noop_u", old_flip_noop_u())
    v : Unit <- srow("cut_base", c_base_cut())
    w : Unit <- srow("cut_reshape_256_above_base", c_resh256_cut())
    x : Unit <- srow("cut_flip01_above_base", c_flip01_cut())
    y : Unit <- srow("cut_pad11_above_base", c_pad11_cut())
    return Unit{}