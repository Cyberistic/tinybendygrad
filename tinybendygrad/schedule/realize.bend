# schedule/realize.bend -- THE PORT's OWN REALIZE-TO-SINK DRIVER.
#
# WHAT THIS FILE IS. The link between the port's `Tensor` graph and the port's
# `schedule()`: it takes a program the port built and answers the SINK OF AFTERs
# that upstream's `prepare_rangeify` answers for the same program.
#
# THE CHAIN IT MIRRORS, and every hop's `file:line` ON BOTH SIDES:
#
#   1. THE PROGRAM. `Tensor.empty(4,5)`, `(4,3) @ (3,5)`, `t.assign(...)`.
#      upstream `tinygrad/mixin/op.py:386-392` (`dot`),
#      `tinygrad/tensor.py:420` (`Tensor.empty`), `tinygrad/tensor.py:271` (`assign`).
#      port: `mixin/movement.bend:1231` (`mxw_buf`), `mixin/movement.bend:1434` (`mxw_reshape`),
#      `mixin/movement.bend:1452` (`mxw_permute`), `tensor.bend:656` (`tn_mul`).
#   2. THE ALLOC -> BUFFER REBIND. upstream `tinygrad/tensor.py:184`
#      (`if x.op is Ops.ALLOC ... u = UOp.new_buffer(...)`).
#      **A NO-OP IN THE PORT**: MEASURED, `grep -n "def UOp.new_buffer"
#      tinybendygrad/uop/ops.bend` ANSWERS NOTHING (the port's `ops.bend:5332`
#      carries it as a `TODO(p3)`), and the port's `Tensor` path has no ALLOC --
#      `mxw_buf` builds the BUFFER (`mixin/movement.bend:1232`). The port's
#      BUFFER is the node upstream's `new_buffer` makes:
#      `UOp.new.param(ar, OpsBUFFER{}, Some{size}, AParam{...})`.
#   3. THE GLOBAL BUFFER -> PARAM REBIND. upstream
#      `tinygrad/schedule/__init__.py:244-254` (`replace_input_buffer` /
#      `pm_replace_buf`): a GLOBAL BUFFER becomes `b.param_like(slot)`, which is
#      `UOp(Ops.PARAM, src=(UOp.const(self.size),), arg=ParamArg(...))`.
#      port: `rz_rule.buf` below.
#   4. THE ADJACENT-RESHAPE MERGE. upstream `tinygrad/uop/movement.py:8`
#      (`mop_cleanup`'s "merge adjacent RESHAPES",
#      `x.replace(src=(x2.src[0], x.src[1]))`) -- UNCONDITIONAL, no shape test.
#      port: `rz_rule.reshape` below.
#   5. THE MOVEMENT-OP-OVER-AFTER MOVE. upstream
#      `tinygrad/schedule/prepare.py:85-86` (`pm_mops`'s
#      `r.after(a)` -> `UOp(r.op, src=(a.replace(src=(r.src[0],)+a.src[1:]),)+r.src[1:]))`
#      -- AND THEN, AT `tinygrad/schedule/prepare.py:273-274`,
#      (`earliest_rewrites`' "remove movement ops from SINK/AFTER", `walk_mop`).
#      The TWO rules' NET: the movement op moves ABOVE the AFTER and the SINK
#      then drops it, so the AFTER's `src[0]` BECOMES THE BASE and the SINK's
#      `src` is the AFTER.
#      **MEASURED, not assumed**: `.agents/slop/realize/probe3.py` prints
#      upstream's own graph at each stage, and the net is
#      `SINK(AFTER(PARAM, STORE(RESHAPE(PARAM, STACK), REDUCE)))`.
#      port: `rz_rule.after` below.
#
# THE COMPARISON. The oracle is `.agents/slop/engine/eng-oracle.py`, which
# SPIES ON UPSTREAM's OWN call to `get_kernel_graph` and prints the graph
# CPython hands the engine. MEASURED: `eng_py_in_nodes=23`, and that graph is
# `prepare_rangeify`'s OUTPUT -- the SINK OF AFTERs this file produces.
#
# THE SPELLING. The dump below is `op:argkey:srcops`, the ORACLE's spelling,
# and the CONST key is the ORACLE's rule (`const_key`, `eng-oracle.py:52`): a
# CONST's arg in this upstream is a BARE VALUE (MEASURED,
# `UOp.const(20).arg` is the int `20`), so it is NOT the three-tuple the rule
# looks for and the key is `cother` for EVERY CONST.
# **⇒ AND THAT IS A DIVERGENCE FROM THE PORT's OWN `eng_constkey`**
# (`schedule/rangeify.bend:3008`), which spells a CONST `c:hi:lo`. The two
# CANNOT both be right about the same graph, and the report names it.
# ⇒ AND THE CONST VALUES ARE NOT LOST: `rz_consts` and `rz_params` below carry
# them, and the comparator checks them as MULTISETS.
#
# WHY THE COMPARISON IS ORDER-FREE. MEASURED, the port's `eng_dump`
# (`schedule/rangeify.bend:3055`) is a BFS -- `List.concat(&2, U32, [t, srcs])`
# puts the srcs at the END of the worklist -- and the oracle's `dump`
# (`eng-oracle.py:79`) is a DFS -- `todo = list(u.src) + todo` puts them at the
# FRONT. The two orders CANNOT agree, so the comparison is over MULTISETS.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../tensor.bend as T
import ./../mixin/movement.bend as MX
import ./__init__.bend as SCH
import ./rangeify.bend as RG

# ===========================================================================
# 1. THE PROGRAM -- the port's own `Tensor` graph.
# ===========================================================================

# `Tensor.empty(shape)` -- upstream `tinygrad/tensor.py:88`: a BUFFER of
# `prod(shape)` RESHAPED to the shape. The port's `mxw_buf` is the BUFFER and
# `mxw_reshape.go` is the RESHAPE, and `.go` rather than `mxw_reshape` because
# the latter's identity test reads a fold that CANNOT answer a RESHAPE's shape
# (`tinybendygrad/tensor.bend:42-48`), so it would answer "identity" for a
# reshape that is not one.
def rz_input(+ar: O.Arena, slot: U32, size: U32, ds: List<&2, U32>) -> T.Tensor:
  MX.mxw_reshape.go(MX.mxw_buf(ar, slot, size), ds)

# `dot` -- upstream `tinygrad/mixin/op.py:390-392`:
#   x = x.reshape(*x.shape[0:-1], *[1]*min(dx-1, dw-1, 1), x.shape[-1])
#   w = w.reshape(*w.shape[0:-2], *[1]*min(dx-1, dw-1, 1), *w.shape[axis_w:]).transpose(-1, axis_w)
#   return (x*w).sum(-1, dtype=dtype)
# For the 2-D case `min(dx-1, dw-1, 1)` is 1, so the x-reshape is
# `(4,3) -> (4,1,3)` and the w-reshape is `(3,5) -> (1,3,5)` followed by
# `transpose(-1, -2)`, which is the PERMUTE `(0,2,1)`.
def rz_dot_x(+lhs: T.Tensor) -> T.Tensor:
  MX.mxw_reshape.go(lhs, [4, 1, 3])

def rz_dot_w(+rhs: T.Tensor) -> T.Tensor:
  MX.mxw_permute.go(MX.mxw_reshape.go(rhs, [1, 3, 5]), [0, 2, 1])

# `_rop` -- upstream `tinygrad/uop/ops.py:633-643`: the reduced axes move to the
# FRONT (`perm = reduce_axis + tuple(i for i in range(len(self.shape)) if i not
# in reduce_axis)`) and the REDUCE's arg is `(op, len(reduce_axis))` -- the
# NUMBER OF AXES, and the axes reduced are the FIRST ones.
# ⇒ The port's `O.UOp.reduce` (`uop/ops.bend:7440`) builds `AReduce{rop, 0}`
# -- `num_axes` HARDCODED to zero -- so this def builds the node with
# `O.UOp.new` and the RIGHT num_axes. **THAT IS A PORT DIVERGENCE AND IT IS
# NAMED: `uop/ops.bend:7435 symbol=UOp.reduce.arg` cannot spell `AReduce{op, 1}`.**
def rz_reduce(+t: T.Tensor) -> T.Tensor:
  +p = MX.mxw_permute.go(t, [2, 0, 1])
  +r = O.UOp.new(T.Tensor.ar(p), O.OpsREDUCE{}, [T.Tensor.u(p)],
                 O.AReduce{O.OpsADD{}, 1}, O.TNone{})
  T.tn_new(O.Found.ar(r), O.Found.i(r))

# THE ASSIGN -- upstream `tinygrad/tensor.py:271`:
#   self.uop = self.uop.after(self.uop.store(x.uop))
# **THE ARENA IS THE VALUE's, AND IT MUST BE.** An `Arena` is an IMMUTABLE
# `Data` VALUE and an index is only meaningful in the arena that minted it, so
# a STORE that holds `dst`'s index must be interned in an arena that HOLDS
# `dst`'s node. The VALUE's arena does -- it is the merge of the two operand
# arenas, and BOTH descend from the destination's -- and the DESTINATION's
# arena does NOT hold the value's nodes.
# ⇒ MEASURED, THE BUG THIS AVOIDS: interning the SINK in the destination's
# arena put the AFTER's index into a SIBLING arena, where it named whatever
# node sat at that index -- a BUFFER -- and the dump answered
# `SINK:none:BUFFER` over a THREE-node graph.
def rz_after(+dst: T.Tensor, +val: T.Tensor) -> O.Found:
  +ar = T.Tensor.ar(val)
  +st = O.UOp.store(ar, T.Tensor.u(dst), T.Tensor.u(val), None{})
  O.UOp.after(O.Found.ar(st), T.Tensor.u(dst), [O.Found.i(st)])

# THE SINK -- upstream `tinygrad/tensor.py:169`: `sink = UOp.sink(*[t.uop ...])`.
def rz_sink(+ar: O.Arena, u: U32) -> O.Found:
  O.UOp.sink(ar, [u])

# THE WHOLE PROGRAM, as ONE record so the arena and the root travel together.
type RZProg is Data:
  RZProg{ar: O.Arena, sink: U32}

def RZProg.ar(+p: RZProg) -> O.Arena:
  match p:
    case RZProg{ar, sink}: ar

def RZProg.sink(+p: RZProg) -> U32:
  match p:
    case RZProg{ar, sink}: sink

# `(4,5) = (4,3) @ (3,5)` -- the oracle's OWN program
# (`.agents/slop/engine/eng-oracle.py:112-114`).
def rz_program() -> RZProg:
  +dst = rz_input(O.Arena.empty(), 0, 20, [4, 5])
  +lhs = rz_input(T.Tensor.ar(dst), 1, 12, [4, 3])
  +rhs = rz_input(T.Tensor.ar(lhs), 2, 15, [3, 5])
  +val = T.tn_mul(rz_dot_x(lhs), rz_dot_w(rhs))
  +red = rz_reduce(val)
  +aft = rz_after(dst, red)
  # THE SINK IS INTERNED IN THE AFTER's ARENA. An index is only meaningful in
  # the arena that minted it, and the AFTER was interned in an arena that is
  # NEWER than the REDUCE's -- so a SINK interned in the REDUCE's arena reads
  # the AFTER's index OUT OF RANGE and answers the arena's bottom.
  +snk = rz_sink(O.Found.ar(aft), O.Found.i(aft))
  RZProg{O.Found.ar(snk), O.Found.i(snk)}

# ===========================================================================
# 2. THE REBUILD -- the port's own `tensor_map` loop.
#
# Upstream `tinygrad/tensor.py:182-198` rebuilds the graph in toposort order
# and `pm_replace_buf` (`tinygrad/schedule/__init__.py:248-255`) swaps the
# GLOBAL BUFFERs for PARAMs. The port has no `graph_rewrite` (it is a wall in
# `schedule/__init__.bend:5-13`), so the rebuild is ONE PASS over the arena's
# own toposort with an association list for the old-index -> new-index map.
#
# THE ORDER. The port's `UOp.toposort` (`uop/ops.bend:3366`) is a PRE-ORDER
# DFS (`Topo.push`, `uop/ops.bend:3309`) and upstream's is a POST-ORDER one
# (MEASURED, `.agents/slop/realize/probe.py` prints upstream's `toposort()`
# with the CONSTs FIRST and the SINK LAST). **⇒ THE PORT's toposort AND
# UPSTREAM's ARE NOT THE SAME ORDER, AND THE PORT's REBUILD NEEDS CHILDREN
# FIRST** -- so the rebuild walks `List.reverse` of the pre-order, which is
# children-first.
# ⇒ AND THE PARAM SLOTS ARE ASSIGNED IN THE PRE-ORDER, because upstream's
# `pm_replace_buf` visits the BUFFERs in upstream's POST-ORDER and the two
# orders pick the SAME buffer first (MEASURED: the destination is slot 0 in
# CPython -- `ParamArg(0, ...)` on the 20-element buffer).
# ===========================================================================
type RZPair is Data:
  RZPair{b: U32, v: U32}

type RZSt is Data:
  RZSt{ar: O.Arena, map: List<&2, RZPair>, idx: U32, slot: U32}

def RZSt.ar(+s: RZSt) -> O.Arena:
  match s:
    case RZSt{ar, map, idx, slot}: ar

def RZSt.map(+s: RZSt) -> List<&2, RZPair>:
  match s:
    case RZSt{ar, map, idx, slot}: map

def RZSt.idx(+s: RZSt) -> U32:
  match s:
    case RZSt{ar, map, idx, slot}: idx

def RZSt.slot(+s: RZSt) -> U32:
  match s:
    case RZSt{ar, map, idx, slot}: slot

def RZSt.of(+ar: O.Arena, +map: List<&2, RZPair>, idx: U32, slot: U32) -> RZSt:
  RZSt{ar, map, idx, slot}

# THE MAP LOOKUP. `Bool.pick` is the SHORT-CIRCUIT, because the other arm is
# the recursive call and Bend refuses an unbounded self-call.
def rz_lookup.go(+map: List<&2, RZPair>, +k: U32) -> Maybe<&2, U32>:
  match map:
    case Nil{}: None{}
    case RZPair{b, v} <> t:
      Bool.pick(Maybe<&2, U32>, U32.is_eq(b, k), Some{v}, rz_lookup.go(t, k))

def rz_lookup(+map: List<&2, RZPair>, k: U32) -> Maybe<&2, U32>:
  rz_lookup.go(map, k)

# THE MAP READ, with the identity default: upstream's
# `tensor_map.get(s, s)` (`tinygrad/tensor.py:183`).
def rz_get.of(m: Maybe<&2, U32>, s: U32) -> U32:
  match m:
    case Some{v}: v
    case None{}: s

def rz_get(+map: List<&2, RZPair>, +s: U32) -> U32:
  rz_get.of(rz_lookup(map, s), s)

# THE SUBSTITUTED SRCS.
def rz_srcs.go(+map: List<&2, RZPair>, ss: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case s <> t: rz_srcs.go(map, t, List.append(&2, U32, acc, [rz_get(map, s)]))

def rz_srcs(+map: List<&2, RZPair>, ss: List<&2, U32>) -> List<&2, U32>:
  rz_srcs.go(map, ss, Nil{})

# THE OP TESTS.
def rz_is_buf(+ar: O.Arena, u: U32) -> Bool:
  O.eq_op(O.Arena.op(ar, u), O.OpsBUFFER{})

def rz_is_after(+ar: O.Arena, u: U32) -> Bool:
  O.eq_op(O.Arena.op(ar, u), O.OpsAFTER{})

def rz_is_reshape(+ar: O.Arena, u: U32) -> Bool:
  O.eq_op(O.Arena.op(ar, u), O.OpsRESHAPE{})

def rz_is_mv(+ar: O.Arena, u: U32) -> Bool:
  O.GroupOp.movement(O.Arena.op(ar, u))

# RULE 1 -- THE GLOBAL BUFFER BECOMES A PARAM. upstream
# `tinygrad/schedule/__init__.py:244-246` (`replace_input_buffer`):
# `b.param_like(len(ctx.replacements)-1)`, and upstream's `param_like` is
# `UOp(Ops.PARAM, src=(UOp.const(self.size),), arg=ParamArg(...))`.
# The port's PARAM keeps the BUFFER's own size CONST as its `src[0]` -- the
# same node -- and takes a fresh `ParamArg` with the slot and no buffer.
def rz_rule.buf(+ar: O.Arena, +map: List<&2, RZPair>, +slot: U32, slot_off: Bool, +u: U32) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, [O.Arena.src0(ar, u)],
            O.AParam{MX.mxw_pbuf(Bool.pick(U32, slot_off, U32.add(slot, 1), slot))}, O.TNone{})

# RULE 2 -- MERGE ADJACENT RESHAPES. upstream `tinygrad/uop/movement.py:8`:
# `x.replace(src=(x2.src[0], x.src[1]))` -- UNCONDITIONAL.
def rz_rule.reshape(+ar: O.Arena, +map: List<&2, RZPair>, +u: U32) -> O.Found:
  +inner = O.Arena.src0(ar, u)
  O.UOp.new(ar, O.OpsRESHAPE{}, [rz_get(map, O.Arena.src0(ar, inner)),
                                rz_get(map, O.Arena.src(ar, u, 1))],
            O.Arena.arg(ar, u), O.Arena.tag(ar, u))

# RULE 3 -- THE AFTER's src0 BECOMES THE BASE. The NET of upstream's
# `prepare.py:85-86` and `prepare.py:273-274`; MEASURED by
# `.agents/slop/realize/probe3.py`.
def rz_rule.after(+ar: O.Arena, +map: List<&2, RZPair>, +u: U32) -> O.Found:
  +m = O.Arena.src0(ar, u)
  O.UOp.new(ar, O.OpsAFTER{}, [rz_get(map, O.Arena.src0(ar, m)),
                               rz_get(map, O.Arena.src(ar, u, 1))],
            O.Arena.arg(ar, u), O.Arena.tag(ar, u))

# THE DISPATCH. `match` MAY NOT SCRUTINIZE A COMPUTED VALUE, so each test is
# its own def and the choice is a `Bool.pick` chain.
def rz_rule(+ar: O.Arena, +map: List<&2, RZPair>, +slot: U32, no_merge: Bool, slot_off: Bool, +u: U32) -> O.Found:
  Bool.pick(O.Found, rz_is_buf(ar, u), rz_rule.buf(ar, map, slot, slot_off, u),
    Bool.pick(O.Found,
      Bool.and(Bool.not(no_merge), Bool.and(rz_is_reshape(ar, u), rz_is_reshape(ar, O.Arena.src0(ar, u)))),
      rz_rule.reshape(ar, map, u),
      Bool.pick(O.Found,
        Bool.and(rz_is_after(ar, u), rz_is_mv(ar, O.Arena.src0(ar, u))),
        rz_rule.after(ar, map, u),
        O.UOp.replace(ar, u, None{}, Some{rz_srcs(map, O.Arena.srcs(ar, u))}, None{}, None{}))))

# THE WALK. Children first, so a node's srcs are already rebuilt when it is.
def rz_go(+ar: O.Arena, ns: List<&2, U32>, +no_merge: Bool, +slot_off: Bool, +st: RZSt) -> RZSt:
  match ns:
    case Nil{}: st
    case +u <> t:
      # THE ARENA IS THE ONE THE LAST BUILD RETURNED. An `Arena` is an
      # IMMUTABLE `Data` VALUE, so interning into the ORIGINAL one would put
      # this node in a DIFFERENT arena from the node before it, and the map's
      # indices would name nothing. THE SAME RULE AS `tensor.bend`'s
      # "THE ARENA A BUILD RETURNS IS NOT THE ARENA THAT WENT IN".
      +f = rz_rule(RZSt.ar(st), RZSt.map(st), RZSt.slot(st), no_merge, slot_off, u)
      +st2 = RZSt.of(O.Found.ar(f),
                     List.append(&2, RZPair, RZSt.map(st), [RZPair{u, O.Found.i(f)}]),
                     O.Found.i(f),
                     Bool.pick(U32, rz_is_buf(ar, u), U32.add(RZSt.slot(st), 1), RZSt.slot(st)))
      rz_go(ar, t, no_merge, slot_off, st2)

# THE WHOLE REBUILD, and the answer is the new sink.
# `no_merge` AND `slot_off` ARE THE PLANTS. `no_merge` skips RULE 2 (the
# adjacent-RESHAPE merge), which makes the graph 27 nodes instead of 23 --
# the DIVERGENCE the node comparison must catch. `slot_off` shifts every PARAM
# slot by one, which leaves the NODE dump IDENTICAL and moves only the
# `(slot, size)` pairs -- so it is the control that proves the SECOND artifact
# is load-bearing and that the node dump alone would NOT catch it.
def rz_rebuild(+p: RZProg, no_merge: Bool, slot_off: Bool) -> RZProg:
  +ar = RZProg.ar(p)
  +pre = O.UOp.toposort(O.Arena.budget(ar), ar, RZProg.sink(p))
  +st = rz_go(ar, pre, no_merge, slot_off, RZSt.of(ar, Nil{}, RZProg.sink(p), 0))
  RZProg{RZSt.ar(st), RZSt.idx(st)}

# ===========================================================================
# 3. THE DUMP -- the ORACLE's spelling, `op:argkey:srcops`.
# ===========================================================================
def rz_op_name(op: O.Op) -> String:
  match op:
    case O.OpsCONST{}  : "CONST"
    case O.OpsPARAM{}  : "PARAM"
    case O.OpsBUFFER{} : "BUFFER"
    case O.OpsRESHAPE{}: "RESHAPE"
    case O.OpsPERMUTE{}: "PERMUTE"
    case O.OpsSTACK{}  : "STACK"
    case O.OpsMUL{}    : "MUL"
    case O.OpsADD{}    : "ADD"
    case O.OpsREDUCE{} : "REDUCE"
    case O.OpsSTORE{}  : "STORE"
    case O.OpsAFTER{}  : "AFTER"
    case O.OpsSINK{}   : "SINK"
    case _: "OTHER"

# THE ORACLE's `const_key` (`eng-oracle.py:52`): a three-tuple whose second
# element is the string "CONST". upstream's CONST arg is a BARE VALUE
# (MEASURED: `UOp.const(20).arg` is the int `20`), so the key is `cother` for
# every CONST.
def rz_constkey(a: O.Arg) -> String:
  match a:
    case O.APy{v} : "cother"
    case _: "cother"

# THE ORACLE's `arg_key` (`eng-oracle.py:64`): a CONST's key, `none` for a
# node with no arg, `other` for everything else.
def rz_argkey.arg(a: O.Arg) -> String:
  match a:
    case O.ANone{}: "none"
    case _: "other"

def rz_argkey.of(op: O.Op, +a: O.Arg) -> String:
  Bool.pick(String, O.eq_op(op, O.OpsCONST{}), rz_constkey(a), rz_argkey.arg(a))

def rz_argkey(+ar: O.Arena, +u: U32) -> String:
  rz_argkey.of(O.Arena.op(ar, u), O.Arena.arg(ar, u))

def rz_src_names.go(+ar: O.Arena, ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> t: rz_src_names.go(ar, t, List.append(&2, String, acc, [rz_op_name(O.Arena.op(ar, s))]))

def rz_node_str(+ar: O.Arena, +n: U32) -> String:
  String.concat([rz_op_name(O.Arena.op(ar, n)), ":", rz_argkey(ar, n), ":",
                 String.join(rz_src_names.go(ar, O.Arena.srcs(ar, n), Nil{}), ",")])

# THE DUMP. A DFS from the result root, each node ONCE -- the oracle's `dump`
# (`eng-oracle.py:79`) is a DFS and the port's `eng_dump`
# (`schedule/rangeify.bend:3055`) is a BFS, so the COMPARISON is over
# MULTISETS and this dump's ORDER is not the comparison's subject.
def rz_dump.go(fuel: Nat, todo: List<&2, U32>, +ar: O.Arena, +seen: List<&2, U32>, +n: U32,
               +acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+p:
      match todo:
        case Nil{}: acc
        case +x <> t:
          +s = List.contains(U32, U32.is_eq, seen, x)
          rz_dump.go(p, List.concat(&2, U32, [t, O.Arena.srcs(ar, x)]), ar,
                     Bool.pick(List<&2, U32>, s, seen, List.append(&2, U32, seen, [x])),
                     x,
                     Bool.pick(List<&2, String>, s, acc,
                       List.append(&2, String, acc, [rz_node_str(ar, x)])))

def rz_dump(+ar: O.Arena, +root: U32) -> String:
  String.join(rz_dump.go(O.Arena.budget(ar), [root], ar, Nil{}, root, Nil{}), ";")

# THE CONST VALUES AND THE PARAM SLOTS. The oracle's own key throws the
# CONST's value away (`cother`), so these two carry it, and the comparator
# checks them as MULTISETS.
def rz_const_val.of(a: O.Arg) -> Maybe<&2, U32>:
  match a:
    case O.APy{O.CInt{i}}: Some{H.lo32(i)}
    case _: None{}

def rz_const_val(+ar: O.Arena, +u: U32) -> Maybe<&2, U32>:
  rz_const_val.of(O.Arena.arg(ar, u))

def rz_param_slot.of(a: O.Arg) -> Maybe<&2, U32>:
  match a:
    case O.AParam{pa}: Some{O.ParamArg.slot(pa)}
    case _: None{}

def rz_param_slot(+ar: O.Arena, +u: U32) -> Maybe<&2, U32>:
  rz_param_slot.of(O.Arena.arg(ar, u))

def rz_is_some(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{v}: True{}
    case None{}: False{}

def rz_num(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case None{}: 0

# THE CONST VALUES, in the same DFS order as the dump.
def rz_consts.go(fuel: Nat, todo: List<&2, U32>, +ar: O.Arena, +seen: List<&2, U32>, +n: U32,
                 +acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+p:
      match todo:
        case Nil{}: acc
        case +x <> t:
          +s = List.contains(U32, U32.is_eq, seen, x)
          +v = rz_const_val(ar, x)
          rz_consts.go(p, List.concat(&2, U32, [t, O.Arena.srcs(ar, x)]), ar,
                       Bool.pick(List<&2, U32>, s, seen, List.append(&2, U32, seen, [x])), x,
                       Bool.pick(List<&2, String>, s, acc,
                         Bool.pick(List<&2, String>, rz_is_some(v),
                           List.append(&2, String, acc, [U32.show(rz_num(v))]), acc)))

# THE PARAM SLOTS, with the size each one carries, so the comparator can pin
# WHICH buffer got WHICH slot.
def rz_params.go(fuel: Nat, todo: List<&2, U32>, +ar: O.Arena, +seen: List<&2, U32>, +n: U32,
                 +acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+p:
      match todo:
        case Nil{}: acc
        case +x <> t:
          +s = List.contains(U32, U32.is_eq, seen, x)
          +v = rz_param_slot(ar, x)
          +sz = rz_const_val(ar, O.Arena.src0(ar, x))
          rz_params.go(p, List.concat(&2, U32, [t, O.Arena.srcs(ar, x)]), ar,
                       Bool.pick(List<&2, U32>, s, seen, List.append(&2, U32, seen, [x])), x,
                       Bool.pick(List<&2, String>, s, acc,
                         Bool.pick(List<&2, String>, rz_is_some(v),
                           List.append(&2, String, acc,
                             [String.concat([U32.show(rz_num(v)), ":", U32.show(rz_num(sz))])]),
                           acc)))

# ===========================================================================
# 4. THE ROWS.
# ===========================================================================
def rz_row.line(nm: String, got: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", got]))

def rz_nodes(+p: RZProg) -> U32:
  U32.from_nat(List.length(&2, U32, O.UOp.toposort(O.Arena.budget(RZProg.ar(p)),
                                                   RZProg.ar(p), RZProg.sink(p))))

# THE REBUILT PROGRAM, ONCE. Every row reads it, and it is PURE, so the rows
# cannot disagree with each other about which graph they are talking about.
def rz_built() -> RZProg:
  rz_rebuild(rz_program(), False{}, False{})

def rz_plant() -> RZProg:
  rz_rebuild(rz_program(), True{}, False{})

def rz_plant2() -> RZProg:
  rz_rebuild(rz_program(), False{}, True{})

def rz_row_dump() -> String:
  +q = rz_built()
  rz_dump(RZProg.ar(q), RZProg.sink(q))

def rz_row_consts() -> String:
  +q = rz_built()
  String.join(rz_consts.go(O.Arena.budget(RZProg.ar(q)), [RZProg.sink(q)], RZProg.ar(q),
                           Nil{}, RZProg.sink(q), Nil{}), ",")

def rz_row_params() -> String:
  +q = rz_built()
  String.join(rz_params.go(O.Arena.budget(RZProg.ar(q)), [RZProg.sink(q)], RZProg.ar(q),
                           Nil{}, RZProg.sink(q), Nil{}), ",")

def rz_row_plant() -> String:
  +q = rz_plant()
  rz_dump(RZProg.ar(q), RZProg.sink(q))

def rz_row_plant_params() -> String:
  +q = rz_plant2()
  String.join(rz_params.go(O.Arena.budget(RZProg.ar(q)), [RZProg.sink(q)], RZProg.ar(q),
                           Nil{}, RZProg.sink(q), Nil{}), ",")

def rz_row_nodes() -> String:
  +q = rz_built()
  U32.show(rz_nodes(q))

# THE PORT's OWN SCHEDULER, ON THE PORT's OWN SINK. `SCH.schedule` is
# `create_schedule` (`schedule/__init__.bend:1141`), and it wants a SINK OF
# AFTERs WHOSE SECOND SRC IS A KERNEL -- a CALL or an END -- because
# `_split_after` (`schedule/__init__.bend:465`) partitions the AFTER's srcs
# into kernels and dependencies.
def rz_row_lin() -> String:
  +q = rz_built()
  +l = SCH.schedule(RZProg.ar(q), RZProg.sink(q))
  U32.show(U32.from_nat(List.length(&2, U32, SCH.Lin.out(l))))

# THE PORT's OWN ENGINE, ON THE PORT's OWN SINK. `RG.eng_stages` is
# `get_kernel_graph`'s SEVEN rewrites (`schedule/rangeify.bend:2809`) and
# `RG.eng_drive` runs them in order.
def rz_row_eng() -> String:
  +q = rz_built()
  String.join(RG.eng_drive(RG.eng_stages(), RG.eng_fresh(RG.Eng{RZProg.ar(q), Nil{}}),
                            RZProg.sink(q), 0, "rz", Nil{}), "\n")

def rz_row_dump0() -> String:
  +p0 = rz_program()
  rz_dump(RZProg.ar(p0), RZProg.sink(p0))

def rz_pre_ops.go(+ar: O.Arena, ns: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case u <> t:
      rz_pre_ops.go(ar, t, List.append(&2, String, acc, [rz_op_name(O.Arena.op(ar, u))]))

def main() -> IO(Unit):
  do IO<Unit>:
    rz_row.line("rz_dump", rz_row_dump())
    rz_row.line("rz_consts", rz_row_consts())
    rz_row.line("rz_params", rz_row_params())
    rz_row.line("rz_nodes", rz_row_nodes())
    rz_row.line("rz_dump0", rz_row_dump0())
    rz_row.line("rz_lin_n", rz_row_lin())
    rz_row.line("rz_eng", rz_row_eng())
    rz_row.line("rz_plant_dump", rz_row_plant())
    rz_row.line("rz_plant_params", rz_row_plant_params())
