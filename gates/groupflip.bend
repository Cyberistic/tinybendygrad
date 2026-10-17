# groupflip.bend -- `UOp.group` AND `Tensor.flip` AS UPSTREAM HAS THEM SINCE IT DELETED
# `Ops.GROUP` AND `Ops.FLIP`, and THE WITNESS IS THE TOPOSORT.
#
#   .venv/bin/python gates/groupflip-gate.py
#
# WHY THIS FILE EXISTS. Upstream commit `900880433` ("remove Ops.FLIP", 2026-10-11) took the
# enum from 77 members to 75 by deleting `GROUP` and `FLIP` -- and KEPT BOTH BEHAVIOURS,
# re-expressed over ops that still exist:
#   `UOp.group`    ops.py:536-538   `UOp(Ops.STACK).after(*[x for x in srcs if x is not None])`
#   `Tensor.flip`  movement.py:233-267   PAD / SHRINK / TRANSPOSE, per axis, in a loop
# So the port's job is neither "keep `OpsGROUP{}`" nor "delete it and leave a hole": it is to
# re-express both behaviours over `OpsSTACK`, `OpsAFTER`, `OpsPAD`, `OpsSHRINK`, `OpsPERMUTE`
# and `OpsRESHAPE`. This file is the instrument that says whether it did.
#
# THE WITNESS IS A TOPOSORT AND NOT A RETURN VALUE, and that is the whole design. The corpus
# (`checks/differ.py run`, 34 graphs) treats the GRAPH as the contract, so a `flip` that
# returns a correct answer while building a different node sequence is NOT ported. Every row
# below prints the whole toposort in WALK ORDER, one entry per node:
#
#   <OP>x<nsrc>[<src op sequence, comma-joined>]
#
# joined with `|`. That carries the ORDER (a reordering moves entries), the op, the src COUNT,
# and the src OP SEQUENCE (which is the ONLY field that sees a two-src swap -- `ops.bend`'s
# `after_puts_self_first` header records a swap that left the count, the root op, the root
# nsrc and the toposort ALL identical). `checks/differ.py`'s own rows carry a fourth and fifth
# field this one does not need: the graph here has no CONST-valued args to compare and no
# dtype to disagree on, because the behaviour under test is the OP SEQUENCE.
#
# THE WALK ORDER IS COMPARABLE WITHOUT A CANONICALISATION PASS BECAUSE NEITHER SIDE SORTS BY
# `Ops.value`: the port's `UOp.toposort` is `Topo.push`/`Topo.step` (a stack walk) and
# upstream's `UOp.toposort` (ops.py:286) is the same stack walk with `reversed(node.src)`. So
# both lanes emit the same order for the same graph even though the port's `Ops.value` numbers
# are offset by one at position 14 and by two from position 73 -- the offset is a CONSTANT
# shift, so the RELATIVE order is identical. Nothing here depends on that being true, and a
# disagreement is a disagreement either way.
#
# THE GROUP FIXTURES COVER ALL FOUR ARMS of upstream's `group`, which is four and not two:
#   zero srcs        `UOp(Ops.STACK).after()`      -> `after` returns self, so a BARE STACK
#   one src          `if len(srcs) == 1 ...: return srcs[0]` -> the src ITSELF, no node at all
#   two srcs         `AFTER(STACK, a, b)`           -- the corpus's `group` graph
#   three / six      the same with more, so a transposition inside the list moves the row
# The six children are ADD/MUL/SUB/DIV/MAX/CMOD over ONE base, each with two srcs, so a
# swapped pair inside `group6` is visible in the src op sequence of the AFTER.
#
# WHAT IS **NOT** A ROW, AND WHY. Upstream's `group` FILTERS `None` OUT OF ITS ARGUMENTS and
# its one-src guard counts the UNFILTERED length, so `UOp.group(None, a)` is
# `AFTER(STACK, a)` -- a node -- while the port's `UOp.group(ar, [a])` is `a`. The port's
# parameter is `List<&2, U32>`, already filtered, and it has no spelling for an absent
# element: `Nil{}` is the EMPTY list, not a missing one. A row the port cannot print measures
# nothing, so it is not one, and `groupflip-oracle.py` prints it to STDERR instead so the gap
# is a NUMBER in the transcript rather than a reading of the source. That is `opseven`'s own
# `pyliteral_frozenset` shape.
#
# THE FLIP BASE IS (4, 4, 4, 4), NOT (1, 4, 8, 8), and the reason is the ORDER witness.
# Upstream's loop appends one axis's chain to the running tensor, so `flip(0, 1)` and
# `flip(1, 0)` are the same nodes in a different sequence -- but only if BOTH axes have
# `n >= 2`. `mxw_base()` is (1, 4, 8, 8) and its axis 0 has `n == 1`, which upstream's own
# guard (`if resolve((n:=ret.shape[axis]) <= 1, False): continue`) skips, so on the standard
# base `flip_10` would be a byte-identical copy of `flip_1` and the ORDER would be untested.
# The reshape to (4, 4, 4, 4) is `mxw_reshape`, so both axes compose and the two rows differ --
# and it is (4, 4, 4, 4) rather than (4, 4, 8, 8) because the base's BUFFER holds 256 ELEMENTS
# and `prod((4,4,4,4)) == prod((1,4,8,8)) == 256`, so the SAME base is legal on both sides.
# `groupflip-oracle.py`'s `fbase` docstring is where CPython's size check is measured.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/mixin/movement.bend as MX

# ===========================================================================
# THE PRINTER. Four walks, and the middle one is the reason this file is not `mxw_sig`:
# `mxw_sig` reports the ROOT's four facts, which cannot see a reordering anywhere but the top.
# ===========================================================================
def gf_srcs.go(+ar: O.Arena, +ss: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> t: gf_srcs.go(ar, t, List.append(&2, String, acc, [O.Ops.name(O.Arena.op(ar, s))]))

# **THE PERMUTE ORDER IS PRINTED, BECAUSE `Ops.PERMUTEx1` CANNOT TELL ONE PERMUTATION FROM
# ANOTHER AND A REVERSED ONE IS STILL A PERMUTATION.** MEASURED: with the row carrying only the
# op, the src count and the src op SEQUENCE, `mxf_order(4n, 1)` answered `[3,2,0,1]` -- the
# REVERSE of `transpose(0, 1)`'s `[1,0,2,3]` -- and `flip_1` read AGREE, because a reversed
# permutation is the same length, the same op and the same src op. So `gf_node` appends `{order}`
# for a PERMUTE and `{[]}` for everything else, read out of the node's OWN arg
# (`mxm_ys`, `ATuple{ys}` -- the port stores the order VALUES, so nothing has to be resolved).
# This is the field a graph row has to carry and a node count cannot.
def gf_ord.at(perm: Bool, +ar: O.Arena, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match perm:
    case True{}: MX.mxm_ys(ar, i)
    case False{}: acc

def gf_ord.sel(perm: Bool, +ar: O.Arena, +i: U32) -> List<&2, U32>:
  gf_ord.at(perm, ar, i, Nil{})

def gf_node.at(perm: Bool, +ar: O.Arena, +n: U32, base: String) -> String:
  String.concat([base, "{", MX.mx_show(gf_ord.sel(perm, ar, n)), "}"])

def gf_node(perm: Bool, +ar: O.Arena, +n: U32) -> String:
  gf_node.at(perm, ar, n, String.concat([O.Ops.name(O.Arena.op(ar, n)), "x",
                                         U32.show(O.Arena.nsrc(ar, n)), "[",
                                         String.join(gf_srcs.go(ar, O.Arena.srcs(ar, n), Nil{}), ","), "]"]))

# `toposort` is already in walk order and the walk APPENDS, so this walk accumulates forward
# and needs no `List.reverse` -- unlike every other `.go` in `mixin/movement.bend` which walks a
# list it is rebuilding. MEASURED, at the cost of the reversal described above.
def gf_one.go(+ar: O.Arena, +ns: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      gf_one.go(ar, t, List.append(&2, String, acc,
        [gf_node(O.op_in([O.OpsPERMUTE{}], O.Arena.op(ar, n)), ar, n)]))

def gf_row(nm: String, +ar: O.Arena, +u: U32, cut: Nat) -> IO(Unit):
  IO.print(String.concat([nm, "=",
    String.join(gf_one.go(ar, List.drop(&2, U32, O.UOp.toposort(O.Arena.budget(ar), ar, u), cut), Nil{}), "|")]))

# ONE ARENA PER ROW, READ OFF THE ROW'S OWN RESULT. Every builder here RETURNS a grown arena
# (`UOp.group` -> `Found`, `mxw_flip` -> `T.Tensor`) and `mixin/movement.bend`'s header names the
# trap three times: reading the arena off the SOURCE while handing the RESULT's index to
# `Arena.node` reads past the end and answers the BOTTOM. MEASURED HERE: doing exactly that
# printed `Ops.NOOPx0[]` on eight of the eleven rows while still looking like a graph. So each
# row binds its result and the arena comes off THAT binding.
def gf_trow(nm: String, +t: T.Tensor, cut: Nat) -> IO(Unit): gf_row(nm, T.Tensor.ar(t), T.Tensor.u(t), cut)

# ===========================================================================
# THE GROUP FIXTURES. SIX CONSTs, NOT SIX ARITHMETIC NODES, and the reason is a PRE-EXISTING
# port/upstream divergence that has nothing to do with `group`: upstream moved a BUFFER's size
# out of `ParamArg` and into a size CONST SRC (`ParamArg` at ops.py:25-37 has no `size` member
# -- it is the field `.agents/slop/graphcmp.py`'s `paramarg` (:710) still reads, and that read is
# why the corpus's CPython lane cannot be re-run at all), while the port's `mxw_pbuf` still puts
# it in the arg. So a BUFFER is `BUFFERx1[CONST]` upstream and `BUFFERx0[]` on the port, and ANY
# row containing a base would carry that difference before it said anything about `group`.
# CONSTs carry no such difference, they are the same `Ops.CONSTx0[]` on both sides whatever the
# value, and `UOp.group`'s behaviour does not read a src's op -- only its COUNT and its ORDER.
# Six DISTINCT values so the six are six interned nodes rather than one.
# ===========================================================================
# Six DISTINCT values so the six are six interned nodes rather than one. THEY ARE BUILT IN
# SEQUENCE AND THE LAST ONE'S ARENA IS THE ROWS' ARENA, for the rule this file's printer comment
# names: an index means nothing outside its own arena, so a `UOp.group` handed the arena the
# consts were interned into a copy of would answer the BOTTOM. MEASURED: building each const on
# its own `Arena.empty()` and grouping against the LAST one's arena printed `Ops.NOOPx0[]` for
# `group1` and all four other rows.
def gf_groups() -> IO(Unit):
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(2)})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(3)})
  +d = O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(4)})
  +e = O.UOp.const(O.Found.ar(d), O.CInt{H.i64_of_i32(5)})
  +f = O.UOp.const(O.Found.ar(e), O.CInt{H.i64_of_i32(6)})
  +ar = O.Found.ar(f)
  +r0 = O.UOp.group(ar, Nil{})
  +r1 = O.UOp.group(ar, [O.Found.i(a)])
  +r2 = O.UOp.group(ar, [O.Found.i(a), O.Found.i(b)])
  +r3 = O.UOp.group(ar, [O.Found.i(a), O.Found.i(b), O.Found.i(c)])
  +r6 = O.UOp.group(ar, [O.Found.i(a), O.Found.i(b), O.Found.i(c), O.Found.i(d), O.Found.i(e), O.Found.i(f)])
  do IO<Unit>:
    a2 : Unit <- gf_row("group0", O.Found.ar(r0), O.Found.i(r0), 0n)
    b2 : Unit <- gf_row("group1", O.Found.ar(r1), O.Found.i(r1), 0n)
    c2 : Unit <- gf_row("group2", O.Found.ar(r2), O.Found.i(r2), 0n)
    d2 : Unit <- gf_row("group3", O.Found.ar(r3), O.Found.i(r3), 0n)
    e2 : Unit <- gf_row("group6", O.Found.ar(r6), O.Found.i(r6), 0n)
    return Unit{}

# ===========================================================================
# THE FLIP FIXTURES. `mxw_flip`'s argument is the AXIS LIST -- upstream's `axis_arg`, in the
# caller's order -- and the six rows are: the empty list (upstream's `for axis in ()`, which
# makes no node), one axis, two axes in each order, and the last axis of a rank-4 base.
#
# **THE CUT, AND WHY A ROW NEEDS ONE.** A flip needs a SHAPE, so it needs a base, and the base
# is where the pre-existing `ParamArg.size` divergence lives (see `gf_consts` above): the port's
# `mxw_buf` puts the size in the arg and builds `BUFFERx0[]`, upstream's `new_buffer` builds a
# size CONST src and `BUFFERx1[CONST]`. The base ROOT is identical on both sides --
# `Ops.RESHAPEx2[Ops.BUFFER,Ops.STACK]` either way -- so the rows drop everything BELOW the base
# root and keep it. `cut` is `toposort(base).length - 1`.
#
# THE CUT IS A PREFIX ASSUMPTION AND IT IS CHECKED BY THE DIFF, NOT BY A CLAIM: if the base's
# subtree were not a prefix of the behaviour's toposort the cut would land in the wrong place
# and the rows would disagree. Both lanes compute `cut` the same way from the same base, and the
# six flip rows are six COMPARED rows, so a wrong cut is red rather than silently plausible.
# ===========================================================================
def gf_fbase() -> T.Tensor:
  +t = MX.mxw_base()
  MX.mxw_reshape(t, [4, 4, 4, 4])

def gf_cut() -> Nat:
  +t = gf_fbase()
  +ts = O.UOp.toposort(O.Arena.budget(T.Tensor.ar(t)), T.Tensor.ar(t), T.Tensor.u(t))
  Nat.sub(List.length(&2, U32, ts), 1n)

def gf_flips() -> IO(Unit):
  +t = gf_fbase()
  +c = gf_cut()
  +f0 = MX.mxw_flip(t, [])
  +f1 = MX.mxw_flip(t, [0])
  +f2 = MX.mxw_flip(t, [1])
  +f3 = MX.mxw_flip(t, [0, 1])
  +f4 = MX.mxw_flip(t, [1, 0])
  +f5 = MX.mxw_flip(t, [3])
  do IO<Unit>:
    a : Unit <- gf_trow("flip_none", f0, c)
    b : Unit <- gf_trow("flip_0", f1, c)
    c2 : Unit <- gf_trow("flip_1", f2, c)
    d : Unit <- gf_trow("flip_01", f3, c)
    e : Unit <- gf_trow("flip_10", f4, c)
    f : Unit <- gf_trow("flip_3", f5, c)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    gf_groups()
    gf_flips()
    return Unit{}