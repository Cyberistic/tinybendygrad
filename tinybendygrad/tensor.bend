import Base
import ./helpers.bend as H
import ./LAWS/spec.bend as S
import ./uop/ops.bend as O
import ./uop/fold.bend as F
import ./mixin/gradient.bend as G
# tensor.bend -- tinygrad/tensor.py. The user-facing Tensor: lazy op
# construction, the method surface, and the `realize` entry.
#
# THE SPLIT IN THIS FILE is the split the unit has in Python. Everything that
# BUILDS THE GRAPH is here and is portable: `__init__`'s data dispatch,
# `_apply_uop`'s tail, `alu`, the three readers, `__repr__`, `replace`, `_mop`,
# `_rop`, the `assign` spine, and `backward`'s scope filter. Everything that
# TOUCHES DEVICE STATE is a seam, and a seam in Bend is a HANDLE TAKEN AS A
# PARAMETER or a `TODO(p3)` naming the Python line and the wall.
#
# FOUR WALLS, and they are the same four for every method that hits them.
#
#   1. `all_tensors` (tensor.py:17) is a module-global `dict[weakref.ref, None]`.
#      Bend has no globals, no weakrefs and no `__del__`, so the registry is a
#      threaded value -- `Tensors{ts: List<&2, U32>}` is the live set of in-scope
#      uop indices, and the methods that read it take it as a parameter. The
#      REGISTRATION (tensor.py:112) has no counterpart and does not need one: the
#      registry is only ever READ, and what it is read for is "does some live
#      Tensor hold this uop", which `Tensors.holds` answers from the same list.
#   2. A `Buffer` (tensor.py:250, :283, :422) is device state. `new_buffer`
#      (ops.py:853) and `_frompy` (ops.py:870) build a BUFFER node PLUS an opaque
#      allocation, and only the NODE is a graph fact. So `__init__`'s
#      list/tuple/bytes arm takes the already-built uop, and `_buffer`, `data`,
#      `clone`, `to` and `from_blob` are `TODO(p3)`.
#   3. `UOp.substitute` (ops.py:532) is `graph_rewrite`, which is P3 and lives in
#      another module. `_apply_map_to_tensors` (tensor.py:27) needs it, so the
#      SCOPE WALK is ported and the substitution is not.
#   4. The schedule cluster. `linear_with_vars` (tensor.py:167) is 44 lines of
#      `create_linear_with_vars`, `contiguous_mops_to_view`, `is_store_after`,
#      `pm_drop_after` and `UOp.new_buffer`; `realize` (tensor.py:219) needs
#      `needs_storage` and `run_linear`. None of that is built, so the whole
#      realize path is a named seam and this file's gate does not touch it.
#
# A FIFTH WALL is not device state but arithmetic, and it is the one that cost the
# most gate rows: `UOp._shape`'s RESHAPE arm (fold.bend's documented gap,
# `t_gap_ok`) does not answer a movement op's shape, and `mixin/movement.py:185` is
# `return self if ret.shape == self.shape else ret` -- a SHAPE comparison on a node
# the fold cannot answer. `tn_rop` therefore gates on 1-D fixtures whose source is a
# BUFFER, and the multi-dimensional `_rop` cases are on the wall list. `tn_rop_gap`
# is the row that REPORTS this and it prints False.
#
# WHAT I NEED FROM THE SCHEDULE CLUSTER (`tinybendygrad/schedule/`, READ-ONLY to
# me, five files in flight), named so the hand-off is unambiguous:
#   * `create_linear_with_vars(sink) -> (UOp, var_vals)` -- tensor.py:210. The
#     return is a pair, so it is a two-field `Data`, and `var_vals` is read by
#     `realize`.
#   * `contiguous_mops_to_view(uop, src) -> Maybe<UOp>` -- tensor.py:194.
#   * `is_store_after(uop) -> Bool` -- tensor.py:205.
#   * `run_linear(linear, var_vals)` -- tensor.py:224, an effect.
#   * from `tinybendygrad/engine/`, `capturing` -- tensor.py:278.
# My gate is built so it needs NONE of them: every row is a graph SHAPE, which is
# what tensor.py decides, not what the schedule does with it.
#
# TWO DIVERGENCES, both forced by Bend and both load-bearing for the gate.
#
#   * A `Data` record is immutable, so every method Python spells as in-place mutation
#     (`self.uop = ...` at :232, `self.is_param = ...` at :125, `t.uop = ns` at :32)
#     RETURNS A NEW TENSOR here. The two halves of that are two rows: `tn_param` is the
#     half both lanes can answer ("the flag is now False") and `tn_param_old` is the
#     BEND-ONLY half -- that the ORIGINAL still reads True -- which is the whole cost of
#     the divergence and which Python has no way to be asked about.
#   * `grad: Tensor|None` is a `Maybe`, and Python's `None` is the arena's reserved index
#     0 (the BOTTOM sentinel ops.bend parks there), so `grad` is a `U32` whose 0 is
#     `None`. Same convention movement.bend uses for `Hop`.
#
# A THIRD DIVERGENCE, and it is a wall rather than a choice: `__hash__` is `id(self)` in
# Python, so two Tensor OBJECTS over one uop hash differently, while an arena index is the
# node's identity here and two Tensors over one uop hash the same. `tn_hash` states the
# PORT's rule on both sides, because the two rules are not comparable and pretending
# otherwise would make the row assert something false about Python.
#
# DEPS ON THE SUBSTRATE, and what each one costs:
#   * `uop/ops.bend` -- the arena, `UOp.new`/`alu`/`sink`/`after`/`const`,
#     `Ops.name.of`, `GroupOp.movement`, `op_in`, `eq_u32`, `UOp.toposort`,
#     `Arena.budget`, `Arena.src0`, `eq_dt`. Note what is NOT among them: an `F32`
#     LITERAL. `F32` is `F32{data: Word(32n)}` and `Word` is not exported, and
#     `U32.to_f32` is an unfilled LAW, which live code may not call. So every CONST
#     fixture here is an INT or a BOOL, and `Tensor(1.0)` is a `TODO(p3)`.
#   * `uop/fold.bend` -- `UOp.dtype`/`shape`/`device`, `sint_of`, `sint_one`,
#     `eq_sints`, `bcast_dim.is_uop_or_ne_1`. Answering ONE of those readers IS the
#     fold over the whole arena, so `Tensor.__repr__` is O(n^2) in arena size.
#     Accepted: it is the accepted cost fold.bend's own header records.
#   * `LAWS/spec.bend` -- `Dt`, whose `nm` is what `str(dtype)[7:]` prints, and
#     `Dev`. A `Dev` is an interned TAG, not a name, so the device column of
#     `__repr__` cannot be the string Python prints. The gate uses a device-LESS
#     tensor, where both sides print `None`.
#   * `mixin/elementwise.py` -- `_binop` (:36), `_broadcasted` (:24) and the twelve
#     ops the dunders name. NOT MINE, NOT BUILT, so every `__i*__` here is a named
#     `TODO(p3)` with the op it resolves to written down.
#   * `mixin/movement.py` -- `reshape` (:164), `permute` (:214), `_broadcast_to`
#     (:128). NOT MINE. `tn_rop` hoists the two IDENTITY tests it needs, because
#     without them `_rop` builds a PERMUTE where Python returns `self`; the hoist
#     is marked at the def.
#   * `mixin/gradient.py` -- `compute_gradient` and its `Grads` table. WAS "NOT MINE", and
#     that was the seam that left `backward` half-ported; `backward`'s zip now calls it, so
#     `tensor.bend` imports `./mixin/gradient.bend as G`. THE IMPORT CLOSURE IS UNCHANGED --
#     `gradient.bend` imports the same five files this one already did -- so the closure's
#     root (`uop/ops.bend`) has no new leaf under it.
#
# FIVE BEND RULES THIS FILE LEARNS THE HARD WAY, between them about twenty compile
# cycles, and every def below obeys all five. They are in `.agents/slop/notes/
# bend2-constraints.md` too; what is here is the shape each one took IN THIS FILE.
#
#   1. A def may only call defs DECLARED ABOVE IT, and the diagnostic for a violation is
#      "an unfilled law is a dead claim", which names the CALLEE and not the call site.
#      Every `.of`/`.go` split is therefore written callee-first, and the gate's `t_row`
#      and `tn_sig` sit above the rows that print with them.
#   2. A `Data` record parameter needs `+` for TWO READS IN ONE EXPRESSION, and a `U32` or
#      `O.Arena` parameter needs it for two reads in one BODY: `tn_alu.of` reads its
#      arena twice and says `+ar`.
#   3. A `.go`/`.step` pair over the same list is MUTUAL RECURSION and is refused, so a
#      walk that needs both a choice and a descent puts the self-call in an ARGUMENT of
#      `Bool.pick` (`tn_rop.ins`, `tn_rop.ne1`) and makes the LIST the first parameter so
#      the tail is the self-call's first argument. There is no `|>` in Bend 2.0.34.
#   4. `case 1n+p:` is a PREFIX MATCH and claims every n >= 1, so the arm after it is
#      DEAD CODE. `bend2-constraints` records this for `case 0n:`; it is equally true of
#      `1n+p` and it is the more dangerous of the two, because the arm reads like a test
#      for "one or more" and silently eats the rest. `tn_shape_arg.n` is the casualty.
#   5. THE ARENA A BUILD RETURNS IS NOT THE ARENA THAT WENT IN. `UOp.new`/`alu`/`const`
#      return a `Found` because the arena grew, and passing the INCOMING `ar` on builds
#      a node whose index points into the arena as it was BEFORE the node was interned.
#      It typechecks. It prints `NOOP/0`, and an empty toposort, and a five-src PAD, and
#      `replace`'s two rows backwards -- three of the four movement-arm bugs and three
#      gate fixtures, all one cause. Every def that builds carries a `Found` forward for
#      exactly this reason (`tn_alu.put`, `tn_mop.dims2`, `tn_mop.pairs2`).
#
# `.agents/slop/tools/reorder.py` is the driver that got the DECLARATION ORDER right
# mechanically (rule 1), and `.agents/slop/tools/share.py` is the one that adds the `+`s
# (rule 2). Both are drivers, neither invents a body, and the file re-runs both clean.


# ===========================================================================
# all_tensors -- tensor.py:17. See WALL 1 in the header.
# ===========================================================================

type Tensors is Data:
  Tensors{ts: List<&2, U32>}

def Tensors.of() -> Tensors:
  Tensors{Nil{}}

def Tensors.of_list(ts: List<&2, U32>) -> Tensors:
  Tensors{ts}

def Tensors.ts(xs: Tensors) -> List<&2, U32>:
  match xs:
    case Tensors{ts}: ts

# `t.uop is u` -- tensor.py:34's `_tensor_holds`, and tensor.py:511's
# `t.uop is not ...`. An index identity in this port, so it is a walk.
#
# ONE def and not a `.of`/`.go` pair, because the pair would be mutual recursion and
# Bend refuses that. `Bool.pick` IS the short-circuit, so the two arms are its two
# arguments and the walk is the self-call -- and the self-call passes a list TAIL,
# which is the descent the whole port rests on. `+u` for the two reads in one body.
def Tensors.holds.go(+u: U32, +ts: List<&2, U32>) -> Bool:
  match ts:
    case Nil{}: False{}
    case t <> rest: Bool.pick(Bool, U32.is_eq(u, t), True{}, Tensors.holds.go(u, rest))

def Tensors.holds(xs: Tensors, +u: U32) -> Bool:
  Tensors.holds.go(u, Tensors.ts(xs))

# `u in all_uops` -- tensor.py:488's `t.uop in all_uops`. The same walk, and it is
# the same def on purpose: `Tensors` is the registry and `all_uops` is a list of
# indices in the same arena, so there is nothing to abstract over.
def Tensors.member(+u: U32, xs: List<&2, U32>) -> Bool:
  Tensors.holds.go(u, xs)

# ===========================================================================
# THE TENSOR -- tensor.py:44, `__slots__ = "uop", "is_param", "grad"` (:55).
#
# It carries the ARENA as well, which Python gets for free: an arena index is only
# meaningful in the arena that produced it and every op in this file grows it. So
# `Tensor` is `Found` plus the two flags.
# ===========================================================================
# THE READERS -- tensor.py:143-149. `self.uop.device`, `self.uop.shape`,
# `self.uop.dtype`. All three are fold properties, so all three are a `Maybe`: the
# OUTER `None` is "this fold cannot answer this node" (fold.bend's rule, and the
# arena's own `ABad` bottom) and the INNER one is Python's own `None`.
# ===========================================================================

type Tensor is Data:
  Tensor{ar: O.Arena, uop: U32, is_param: Bool, grad: U32}

def Tensor.ar(+t: Tensor) -> O.Arena:
  match t:
    case Tensor{ar, uop, is_param, grad}: ar

# `_uop` -- tensor.py:118. The `uop` FIELD, and it is what every graph-building
# method here reads in place of `self.uop`.
def Tensor.u(+t: Tensor) -> U32:
  match t:
    case Tensor{ar, uop, is_param, grad}: uop

def tn_device(+t: Tensor) -> Maybe<&2, Maybe<&2, S.Dev>>:
  F.UOp.device(Tensor.ar(t), F.UOp.fold(Tensor.ar(t)), Tensor.u(t))

def tn_shape(+t: Tensor) -> Maybe<&2, Maybe<&2, List<&2, O.Sint>>>:
  F.UOp.shape(Tensor.ar(t), F.UOp.fold(Tensor.ar(t)), Tensor.u(t))

def tn_dtype(+t: Tensor) -> Maybe<&2, S.Dt>:
  F.UOp.dtype(Tensor.ar(t), F.UOp.fold(Tensor.ar(t)), Tensor.u(t))

# the shape with the fold's OUTER `None` already dropped, so a caller that wants the
# dims has one unwrap instead of two.

def tn_dims.put(m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case Some{ds}: Some{ds}
    case _: None{}
def tn_dims.go(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case Some{ds}: tn_dims.put(ds)
    case _: None{}
def tn_dims.of(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  tn_dims.go(m)

# the fold's answer is a DOUBLE `Maybe`: the outer is "this fold cannot answer the
# node" and the inner is Python's own `None`, so dropping the outer one is a second
# unwrap and not a rename.

def tn_dims(+t: Tensor) -> Maybe<&2, List<&2, O.Sint>>:
  tn_dims.of(tn_shape(t))

# the device, likewise, and `None` is Python's `None`. The fold's answer is a DOUBLE
# `Maybe` here too, for `tn_dims`'s reason: the outer is the fold and the inner is
# Python.

def tn_dev.put(m: Maybe<&2, S.Dev>) -> Maybe<&2, S.Dev>:
  match m:
    case Some{d}: Some{d}
    case _: None{}

def tn_dev.go(m: Maybe<&2, Maybe<&2, S.Dev>>) -> Maybe<&2, S.Dev>:
  match m:
    case Some{d}: tn_dev.put(d)
    case _: None{}
def tn_dev.of(m: Maybe<&2, Maybe<&2, S.Dev>>) -> Maybe<&2, S.Dev>:
  tn_dev.go(m)

def tn_dev(+t: Tensor) -> Maybe<&2, S.Dev>:
  tn_dev.of(tn_device(t))


# `alu` -- tensor.py:116. `self._apply_uop(lambda *u: u[0].alu(op, *u[1:]), *src)`
# and `UOp.alu` is `UOp(op, src=(self, *src))` (ops.py:630), which ops.bend has.
#
# `alu` is a def here and not a call to `O.UOp.alu` at each site for the reason the
# header's WALL list does not mention: the arena is the store the index lives in, so
# a method that reads `self.uop` has to read `self`'s arena too. `+ar` because
# `O.UOp.alu` grows it and `tn_new` keeps it.
def tn_new(+ar: O.Arena, uop: U32) -> Tensor:
  Tensor{ar, uop, True{}, 0}
def tn_alu.put(+f: O.Found) -> Tensor:
  tn_new(O.Found.ar(f), O.Found.i(f))

# ===========================================================================
def tn_alu.of(+ar: O.Arena, uop: U32, +op: O.Op, srcs: List<&2, U32>) -> Tensor:
  tn_alu.put(O.UOp.alu(ar, op, List.append(&2, U32, [uop], srcs)))

# THE ARENA RULE IN ONE SPELLING, AND NOW IT IS TOTAL. `Arena` is an IMMUTABLE `Data` VALUE
# (`ops.bend:1255`, `type Arena is Data: Arena{nodes, shp}`), so a `Found` SNAPSHOTS the
# arena it was built in and an index is legal only in an arena DESCENDING FROM the one that
# minted it -- append-only, so a prefix's indices still name the same nodes. `O.Arena.merge`
# (`ops.bend`, beside `UOp.new`) is what makes the rule total: it re-interns `other`'s nodes
# into `base` and returns the map, so two SIBLING arenas get a common descendant and
# `other`'s index is re-minted in `base.ar` before it is read there.
#
# When `other` ALREADY descends from `base` the merge is the identity: every node is found
# by interning and `map[i]` is `i`, so the merged arena IS `other.ar`. That is why this one
# def serves both the chain case and the sibling case, and why it costs O(1) on the chain.
def tn_binop(+base: Tensor, +other: Tensor, +op: O.Op) -> Tensor:
  +m = O.Arena.merge(Tensor.ar(base), Tensor.ar(other))
  tn_alu.of(O.Merge.ar(m), Tensor.u(base), op, [O.Merge.at(m, Tensor.u(other))])

# THE GATE-SIDE ASSERTION, and it lives beside the merge because it IS the merge. A binop
# driver cannot compare `r.srcs` to `[c.u, d.u]` any more: `d.u` is an index in `d`'s OWN
# arena and the node was built in the MERGED one, so `d` has been RE-MINTED. Comparing the
# raw indices is exactly the coincidence `gates/tn_binop_arena-gate.py` exists to expose.
# One def, so the six binop gates do not each re-derive the remap.
def tn_srcs_are(+r: Tensor, +c: Tensor, +d: Tensor) -> Bool:
  +m = O.Arena.merge(Tensor.ar(c), Tensor.ar(d))
  O.eq_u32(O.Arena.srcs(Tensor.ar(r), Tensor.u(r)), [Tensor.u(c), O.Merge.at(m, Tensor.u(d))])

# THE THREE-OPERAND FORM of the same assertion. It replays `tn_where`'s two merges rather
# than sharing them, because `Arena.merge` returns the node MAP and not the src list, so a
# driver cannot recover the order the operands were re-minted in without replaying it. This
# is the ONE place in the tree that replays it, and it is a gate -- so a driver comparing raw
# indices across arenas cannot.
def tn_where_srcs_are(+r: Tensor, +cond: Tensor, +x: Tensor, +y: Tensor) -> Bool:
  +mx = O.Arena.merge(Tensor.ar(cond), Tensor.ar(x))
  +my = O.Arena.merge(O.Merge.ar(mx), Tensor.ar(y))
  O.eq_u32(O.Arena.srcs(Tensor.ar(r), Tensor.u(r)),
    [Tensor.u(cond), O.Merge.at(mx, Tensor.u(x)), O.Merge.at(my, Tensor.u(y))])

# SIBLING ARENAS: WAS A WALL, NOW CLOSED. The 18 reverse-dispatch binops (`tn_mul.go`,
# `tn_add.go`, `tn_sub.go`, `tn_cmplt.go`, `tn_cmpne.go`, `tn_and.go`, `tn_or.go`,
# `tn_xor.go`, `tn_maximum.go`, `tn_lshift.go`, `tn_rshift.go`, `tn_shl.go`, `tn_shr.go`,
# `tn_pow.go`, `tn_fdiv.go`, `tn_mod.go`) and `tn_max` used to build with
# `tn_alu(lhs, OP, [Tensor.u(rhs)])`, which builds in `lhs.ar` and reads `rhs.u` THERE.
# MEASURED, `O.Rng.sig` (`ops.bend:5857`) on `tn_add` with `lhs` a bare `CInt{3}` and `rhs`
# derived to depth N in its OWN arena:
#
#   rhs depth 0 (a bare const)   ok=True   sig `2 Ops.ADD/2 Ops.CONST Ops.CONST`
#   rhs depth 1 (one `tn_neg`)   ok=False  sig `1 Ops.ADD/2 Ops.CONST Ops.ADD`
#   rhs depth 2 (two `tn_neg`)   ok=False  sig `3 Ops.ADD/2 Ops.CONST Ops.NOOP`
#
# Depth 0 WAS RIGHT BY COINCIDENCE: `rhs.u` was a legal index in `lhs.ar` that happened to
# hold `lhs`'s own CONST. Depth 1 was SELF-REFERENTIAL and depth 2 read the `NOOP` bottom.
# No gate saw it: every `mk_tensor` in `gates/*.bend` makes each operand a bare const from
# `O.Arena.empty()`, so the depth was always 0. `gates/tn_binop_arena-gate.py` is the gate
# that varies the depth, and it now answers 1 at 0, 1 and 2 with ZERO divergences -- the
# three it used to declare are gone.
#
# THE CLOSURE IS `O.Arena.merge` (`ops.bend`, beside `UOp.new`): it re-interns the right
# operand's nodes into the left one's and returns the map, so the sibling case gets a common
# descendant and the index is re-minted before it is read. There was no such primitive
# before -- VERIFIED at the time: `grep -nE "def [a-zA-Z_.]*\(.*ar: Arena.*,.*ar2?: Arena"`
# over `ops.bend` and `tensor.bend` answered exactly one hit, `UOp.group.of`, a GROUP fold.
#
# AND ONE CONSEQUENCE FOR THE GATES. A driver can no longer compare `r.srcs` to
# `[c.u, d.u]`: `d.u` is an index in `d`'s OWN arena and the node lives in the merged one.
# That comparison is `tn_srcs_are`, below, and it recomputes the merge rather than guessing.

# THE ARENA IS THE ONE THE BUILD RETURNED, and that is the whole of the second rule
# this file learns. `UOp.alu` RETURNS a `Found` because the arena grew, and the `Found`
# carries the grown arena; passing the INCOMING `ar` on to `tn_new` builds a Tensor
# whose index points into the arena as it was BEFORE the node was interned, and every
# read of it then answers the `ABad` bottom. It typechecks, it prints `NOOP/0`, and the
# fold answers `None` -- and all three were the SAME bug.

def Tensor.flag(+t: Tensor) -> Bool:
  match t:
    case Tensor{ar, uop, is_param, grad}: is_param

def Tensor.grad_of(+t: Tensor) -> U32:
  match t:
    case Tensor{ar, uop, is_param, grad}: grad

def Tensor.grad_set(+t: Tensor, g: U32) -> Tensor:
  Tensor{Tensor.ar(t), Tensor.u(t), Tensor.flag(t), g}

# `_apply_uop`'s tail -- tensor.py:500-113. `ret = Tensor.__new__(Tensor); ret.uop,
# ret.grad, ret.is_param = new_uop, None, True`. The `__new__` and the `all_tensors`
# insert are WALL 1; `grad=None` is the reserved 0.

def tn_alu(+t: Tensor, +op: O.Op, srcs: List<&2, U32>) -> Tensor:
  tn_alu.of(Tensor.ar(t), Tensor.u(t), op, srcs)

# `sqrt` -- elementwise.py:480. `return self.alu(Ops.SQRT)`. The body is a single
# `UOp.alu` over the empty src list (SQRT is a unary op, and `self` is the implicit
# src[0] from `tn_alu`'s `List.append(&2, U32, [uop], srcs)`). ONE LINE in CPython and
# ONE LINE here -- the call to `tn_alu` IS the port, and the wall `nn/__init__.bend:241`
# that named `Tensor.sqrt` as missing is the wall this def closes.
def tn_sqrt(+t: Tensor) -> Tensor:
  tn_alu(t, O.OpsSQRT{}, Nil{})

# `detach` -- elementwise.py:43. `return self.alu(Ops.DETACH)`. Same shape as `sqrt`:
# a single `tn_alu` call, with `OpsDETACH{}` as the op and an empty src list.
# Closes the second of the four walls `nn/__init__.bend:241` named (the others --
# `where` and `square` -- have separate deps; see the wall text).
def tn_detach(+t: Tensor) -> Tensor:
  tn_alu(t, O.OpsDETACH{}, Nil{})

# `contiguous_backward` -- elementwise.py:68. `return self.alu(Ops.CONTIGUOUS_BACKWARD)`.
# Same shape as `tn_detach` and `tn_sqrt`: a single `tn_alu` call. CPython's `contiguous`
# (elementwise.py:59) is NOT ported here because its body is three lines, the first
# two of which read `self.dtype in dtypes.weaks` and `self._uop` (a fold read), so it
# sits behind the same fold seam the `tc_ptx.bend` walls name. `contiguous_backward`
# is the sibling that is the one-liner.
def tn_contiguous_backward(+t: Tensor) -> Tensor:
  tn_alu(t, O.OpsCONTIGUOUS_BACKWARD{}, Nil{})

# `trunc` -- elementwise.py:474. `return self.alu(Ops.TRUNC)`. Same shape as
# `tn_contiguous_backward`: a single `tn_alu` call, with `OpsTRUNC{}` as the op and
# an empty src list.
def tn_trunc(+t: Tensor) -> Tensor:
  tn_alu(t, O.OpsTRUNC{}, Nil{})

# `reciprocal` -- elementwise.py:460. `return self.alu(Ops.RECIPROCAL)`. Same shape
# as `tn_trunc` and `tn_contiguous_backward`.
def tn_reciprocal(+t: Tensor) -> Tensor:
  tn_alu(t, O.OpsRECIPROCAL{}, Nil{})

# `threefry` -- elementwise.py:457. `return self.alu(Ops.THREEFRY, seed)`. The seed
# is a Tensor (not a constant), so the body is `tn_alu(t, O.OpsTHREEFRY{}, [seed_uop])`
# -- the SAME `tn_alu` builder, with `seed`'s uop appended to the src list. CPython's
# `seed` is `Self` (a Tensor); the port reads `Tensor.u(seed)` to extract the uop.
def tn_threefry(+t: Tensor, +seed: Tensor) -> Tensor:
  +m = O.Arena.merge(Tensor.ar(t), Tensor.ar(seed))
  tn_alu.of(O.Merge.ar(m), Tensor.u(t), O.OpsTHREEFRY{}, [O.Merge.at(m, Tensor.u(seed))])

# `sin` -- elementwise.py:494. `return self.alu(Ops.SIN)`. Same shape as `tn_trunc`.
def tn_sin(+t: Tensor) -> Tensor:
  tn_alu(t, O.OpsSIN{}, Nil{})

# `log2` -- elementwise.py:531. `return self.alu(Ops.LOG2)`. Same shape.
def tn_log2(+t: Tensor) -> Tensor:
  tn_alu(t, O.OpsLOG2{}, Nil{})

# `exp2` -- elementwise.py:543. `return self.alu(Ops.EXP2)`. Same shape.
def tn_exp2(+t: Tensor) -> Tensor:
  tn_alu(t, O.OpsEXP2{}, Nil{})

# `rsqrt` -- elementwise.py:820. `return self.sqrt().reciprocal()`. The wall text
# at `mixin/elementwise.bend:859` calls this "free of literals; blocked on sqrt's
# own fold, not on a constant". `tn_sqrt` and `tn_reciprocal` are both ported (gated
# `tn_sqrt-gate.py` 5/5, `tn_trunc_reciprocal_threefry-gate.py` 9/9), so the COMBINED
# shape is portable. The result is a LINEAR chain (sqrt, then reciprocal) which
# grows the arena by one. The SECOND `tn_alu` is on the SQRT node, not on `t`:
# `reciprocal` reads its `self` as the implicit first src, and `self` IS the
# sqrt result, not the original input. The dev's note "blocked on sqrt's own fold"
# is now stale: the chain is built by `tn_alu`, not by a fold.
def tn_rsqrt(+t: Tensor) -> Tensor:
  +sqrt = tn_sqrt(t)
  tn_alu(sqrt, O.OpsRECIPROCAL{}, Nil{})

# `where` -- elementwise.py:426. `x, y = self.ufix(x)._broadcasted(y); return
# self.alu(Ops.WHERE, x, y)`. The wall at `nn/__init__.bend:241` calls the
# `_broadcasted` step the blocker. The no-broadcasting case (both x and y are
# already Tensors of the same shape) is portable: the body reduces to
# `tn_alu(cond, O.OpsWHERE{}, [Tensor.u(x), Tensor.u(y)])`, the same `tn_alu`
# builder with three src nodes. `O.UOp.where` (ops.bend:2767) is the primitive
# this delegates to. `tn_where` is what CPython's `Tensor.where` does in the
# no-broadcasting case; the broadcasting case stays walled on `_broadcasted`
# (mixin/movement.py:24, fold reads and a `least_upper_dtype` helper).
#
# THREE OPERANDS, THREE ARENAS, TWO MERGES. `tn_binop` covers the two-operand node and this
# is the shape it cannot reach: `x` and `y` are re-minted in TURN and the accumulator is
# read at the end, so both indices are minted in a PREFIX of the arena the WHERE is built in.
# The one-line version this replaces read `x.u` and `y.u` in `cond.ar`, and was MEASURED
# answering `Ops.NOOP` -- the bottom -- for `src[2]` whenever `y` was not at index 0.
def tn_where(+cond: Tensor, +x: Tensor, +y: Tensor) -> Tensor:
  +mx = O.Arena.merge(Tensor.ar(cond), Tensor.ar(x))
  +my = O.Arena.merge(O.Merge.ar(mx), Tensor.ar(y))
  tn_alu.of(O.Merge.ar(my), Tensor.u(cond), O.OpsWHERE{},
    [O.Merge.at(mx, Tensor.u(x)), O.Merge.at(my, Tensor.u(y))])

# `bitwise_not` -- elementwise.py:145. The Python body is THREE WORDS, and they are
# three arms: `if self.dtype == dtypes.bool: return self.logical_not(); return
# self ^ self.dtype.max if dtypes.is_unsigned(self.dtype) else self ^ -1`. Only the
# BOOL ARM is ported here, because `self.dtype` is a FOLD property (ops.py:247
# `dtype_from_uop`, fold.bend:4443 `UOp.dtype`) and reading it from a method body
# needs a fold context the port does not carry; `mixin/elementwise.bend:530`'s
# `ew_bitwise_not` answers the same body under the fold context `ew_fx` builds.
# HERE, the bool arm is `self.logical_not()`, which is `self.cast(dtypes.bool).ne(True)`
# (elementwise.py:49, :333) -- a CAST and a CMPNE, both already deps (`UOp.cast` at
# ops.bend:2880, gate rc=0; CMPNE built via `UOp.new`). The def builds the two-node
# graph and returns its Tensor.
#
# THE ARITH ARMS (`self ^ self.dtype.max` when UNSIGNED, `self ^ -1` otherwise) stay
# WALL, and the wall is ONE THING: `self.dtype` is a FOLD property and the method body
# has no fold context. The other deps are PORTED:
#   * `DType.max` is `S.Dt.max` (LAWS/spec.bend:221), which reads a `Dt` directly --
#     VERIFIED: `grep -rE "^ *def [A-Za-z_.]*(Dt\.max|DType\.max|dt\.max)" tinybendygrad/`
#     returns ONE row, `Dt.max` at spec.bend:221. NOT WALL.
#   * `dtypes.is_unsigned` is `S.Dt.is_unsigned` (LAWS/spec.bend:170) -- VERIFIED:
#     same grep shape, one row at spec.bend:170. NOT WALL.
#   * `-1` literal is `CInt{H.i64_of_i32(4294967295)}` (two's complement; `H.i64_of_i32`
#     sign-EXTENDS a U32), the same `tn_neg.arith` (line 373) builds. NOT WALL.
#   * `^` (`Ops.XOR`) is `O.OpsXOR{}`, and the call shape is `tn_alu(t, O.OpsXOR{}, [c])`,
#     the same shape `tn_sqrt` (line 298) uses. NOT WALL.
# So the wall is NOT the deps but THE FOLD: the dispatch needs to read `self.dtype`, and
# reading it from `tensor.bend`'s method body needs a fold context. `mixin/elementwise.bend`'s
# `ew_fx` carries one. Both arms close when the fold is threaded in.
def tn_bitwise_not.cast(+ar: O.Arena, +u: U32) -> O.Found:
  O.UOp.new(ar, O.OpsCAST{}, [u], O.ADt{S.boolean()}, O.TNone{})

def tn_bitwise_not(+t: Tensor) -> Tensor:
  +cast = tn_bitwise_not.cast(Tensor.ar(t), Tensor.u(t))
  +true_ = O.UOp.const(O.Found.ar(cast), O.CBool{True{}})
  tn_alu.of(O.Found.ar(true_), O.Found.i(cast), O.OpsCMPNE{}, [O.Found.i(true_)])

# `logical_not` -- elementwise.py:49. `return self.cast(dtypes.bool).ne(True)`.
# The graph is CAST(self, bool) -> CMPNE(cast, CONST(True)), and the three deps are
# PORTED: `O.UOp.cast` (ops.bend:2880, gate rc=0), `OpsCMPNE{}` (the auto-generated
# constructor used as `OpsSQRT{}` and `OpsDETACH{}` are), and `O.UOp.const`. Same
# shape as the BOOL ARM of `tn_bitwise_not` above -- the two graphs ARE equal for a
# bool self, and CPython's `logical_not` always builds them (the `.cast(dtypes.bool)`
# half is not a fold-around the same graph). One new def, mirroring `tn_bitwise_not`,
# because `logical_not` and `bitwise_not` are sibling elementwise methods (`:49`, `:145`)
# and the port holds the two apart.
# `Arena` is an IMMUTABLE `Data` VALUE (`ops.bend:1255`: `type Arena is Data: Arena{nodes,
# shp}`), so a `Found` SNAPSHOTS the arena at its own construction and every index is
# only meaningful in the arena value that index was minted in. `true_c.ar` has the
# CAST AND the CONST (3 slots); `cast.ar` has the CAST only (2 slots). Building the
# CMPNE in `cast.ar` therefore APPENDS it at the slot `O.Found.i(true_c)` already names
# -- the node becomes its own `src[1]`. MEASURED, `./bin/bend` on a `CInt` input, with
# `O.Rng.sig` (ops.bend:5857) as the instrument: `CMPNE/2 Ops.CAST Ops.CMPNE` (src[1]
# IS the top node) where CPython answers `CMPNE(CAST(CONST()), CONST())`
# (`/tmp/cp_shape.py`, `tinygrad`). So the CMPNE is built in `true_c.ar`, the newest.
def tn_logical_not.cmpne(+cast: O.Found, +true_c: O.Found) -> Tensor:
  tn_alu.of(O.Found.ar(true_c), O.Found.i(cast), O.OpsCMPNE{}, [O.Found.i(true_c)])

def tn_logical_not(+t: Tensor) -> Tensor:
  +cast = O.UOp.cast(Tensor.ar(t), Tensor.u(t), S.boolean())
  +true_c = O.UOp.const(O.Found.ar(cast), O.CBool{True{}})
  tn_logical_not.cmpne(cast, true_c)

# `neg` -- elementwise.py:74. `return self.logical_not() if self.dtype == dtypes.bool
# else self * (-1)`. TWO ARMS, and BOTH are ported here. The bool arm IS
# `tn_logical_not`; the arith arm is `self * (-1)` = `MUL(self, -1)`, and `OpsMUL{}`
# is the same auto-generated constructor family `tn_sqrt` uses. The `-1` literal is
# `H.i64_of_i32(4294967295)` -- the two's complement pair, because `i64_of_i32`
# SIGN-EXTENDS a U32 (`mixin/elementwise.bend:484`'s `ew_neg.go` builds the same).
# `tn_alu` handles the binary op with `self` at src[0], so the call is
# `tn_alu(t, O.OpsMUL{}, [c])` for a CONST `c`. The dtype gate is `tn_dtype` -- a
# fold property (`UOp.dtype`, fold.bend:4443), and the `None{}` arm falls through
# to the arith branch as the conservative answer (the fold cannot answer, the dtype
# is NOT bool by elimination, and the value is whatever `self * (-1)` is). The two
# arms are split into helper defs because a `match` arm body is a single expression.
def tn_neg.arith(+t: Tensor) -> Tensor:
  +m1 = O.UOp.const(Tensor.ar(t), O.CInt{H.i64_of_i32(4294967295)})
  tn_alu.of(O.Found.ar(m1), Tensor.u(t), O.OpsMUL{}, [O.Found.i(m1)])

def tn_neg.go(is_bool: Bool, +t: Tensor) -> Tensor:
  match is_bool:
    case True{}: tn_logical_not(t)
    case False{}: tn_neg.arith(t)

def tn_neg.is_bool.of(m: Maybe<&2, S.Dt>) -> Bool:
  match m:
    case Some{dt}: S.Dt.is_bool(dt)
    case None{}: False{}

def tn_neg(+t: Tensor) -> Tensor:
  tn_neg.go(tn_neg.is_bool.of(tn_dtype(t)), t)

# `__neg__` -- elementwise.py:261. `return self.neg()`. The dunder is a ONE-LINE
# DELEGATION to `Tensor.neg`, and `tn_neg` is fully ported (both arms), so the
# port IS `tn_neg`. This def gives the dunder a name in the port and closes the
# implicit wall on `Tensor.__neg__`. The graph IS `tn_neg`'s graph -- a CMPNE for
# bool inputs (via `tn_logical_not`) and a MUL for arith inputs (via `tn_neg.arith`).
# NO new graph nodes; the dunder port is documentation + reachability.
def tn_dunder_neg(+t: Tensor) -> Tensor:
  tn_neg(t)

# `__invert__` -- elementwise.py:264. `return self.bitwise_not()`. `bitwise_not`'s
# BOOL ARM is ported (`tn_logical_not`, which is `self.cast(bool).ne(True)` at
# elementwise.py:49 -- gated 4/4 at gates/tn_logical_not-gate.py). The arith
# arms (`self ^ dtype.max` for unsigned, `self ^ -1` for signed, elementwise.py:157)
# stay walled on the dtype fold + arith ops (tensor.bend:385 -- `self.dtype` is a
# FOLD property and `tn_bitwise_not`'s arith arms are a `None` here). So
# `__invert__` is ONE-ARM PORTABLE: the BOOL arm returns `tn_logical_not(t)`, the
# arith arm is `None`. Returns `Maybe<&2, Tensor>` and lets the caller decide; the
# port convention (`tn_replace`, `tn_as_param`) is the same shape -- a refusal is
# a `None`, not a `TODO(p3)`.
def tn_dunder_invert.is_bool.of(m: Maybe<&2, S.Dt>) -> Bool:
  match m:
    case Some{dt}: S.Dt.is_bool(dt)
    case None{}: False{}

def tn_dunder_invert.go(is_bool: Bool, +t: Tensor) -> Maybe<&2, Tensor>:
  match is_bool:
    case True{}: Some{tn_logical_not(t)}
    case False{}: None{}

def tn_dunder_invert(+t: Tensor) -> Maybe<&2, Tensor>:
  tn_dunder_invert.go(tn_dunder_invert.is_bool.of(tn_dtype(t)), t)

# `__mul__` -- elementwise.py:125. `return self._binop(Ops.MUL, x, reverse)`. The wall
# text at `nn/__init__.bend:241` said the `__mul__` method is a separate wall. The body
# is the same `tn_alu` builder with `OpsMUL{}` and the rhs's uop as the second src. For
# a TENSOR rhs (the only case the gate covers), `_binop`'s `_broadcasted` is the
# identity, so the port is `tn_alu(self, MUL, [Tensor.u(rhs)])`. The `reverse` flag is
# CPython's -- when True, the rhs becomes the implicit first src and `self` is the second
# -- and the port covers both arms the same way `tn_neg.go` covers its two arms.
def tn_mul.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsMUL{})
    case False{}: tn_binop(lhs, rhs, O.OpsMUL{})

def tn_mul(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_mul.go(False{}, lhs, rhs)

def tn_rmul(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_mul.go(True{}, lhs, rhs)

# `square` -- elementwise.py:575. `return self * self`. The body is `tn_mul(self, self)`.
# The wall text at `nn/__init__.bend:241` cited `__mul__` as the blocker; with that
# ported, the square body is a single `tn_mul(self, self)` call. CPython's `*`
# is `__mul__` (not `__rmul__`) because `self` is the LHS.
def tn_square(+t: Tensor) -> Tensor:
  tn_mul(t, t)

# `__add__` -- elementwise.py:267. `return self.add(x)`. The wall text at
# `nn/__init__.bend:241` cited the `_broadcasted` step as the blocker. The
# no-broadcasting case (both `self` and `x` are Tensors of the same shape) is
# the body reduced to `tn_alu(self, ADD, [x.uop])` if `not reverse`, or
# `tn_alu(x, ADD, [self.uop])` if `reverse` -- CPython's `add` writes it as
# `a.alu(Ops.ADD, -b)` (elementwise.py:84, :123) for the dtype-promotion case,
# but the `-b` is a CONST trap: for a TENSOR `b`, `-b` is `-self` (also walled),
# so the no-broadcasting pure-TENSOR case collapses to `_binop`'s body
# (`lhs.alu(MUL, rhs)`, elementwise.py:36) with `MUL` replaced by `ADD`, and
# `_binop`'s `_broadcasted` is the identity for two same-shape Tensors. The
# dispatch is a `Bool` flag the same way `tn_mul.go` and `tn_neg.go` are.
def tn_add.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsADD{})
    case False{}: tn_binop(lhs, rhs, O.OpsADD{})

def tn_add(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_add.go(False{}, lhs, rhs)

def tn_radd(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_add.go(True{}, lhs, rhs)

# `__sub__` -- elementwise.py:270. `return self.sub(x)`. The wall text at
# `nn/__init__.bend:241` cited the `_broadcasted` step as the blocker. The
# no-broadcasting case is portable: `_binop`'s body with `Ops.SUB` instead of
# `Ops.MUL`, and `_broadcasted` is the identity for two same-shape Tensors.
# CPython's `sub` (elementwise.py:103) also writes `a.alu(Ops.ADD, -b)` --
# `-SUB` is `+ADD-NEG`, and the dtype-promotion trap is the same one `add` has.
# The `reverse` flag flips the order, the same way `tn_mul.go` covers it.
# THE `-1` LITERAL, interned in the operand's own arena and wrapped as a Tensor so `tn_binop`
# can merge it. `H.i64_of_i32(4294967295)` is two's complement -1 and `i64_of_i32`
# sign-EXTENDS, the same literal `tn_neg.arith` uses.
def tn_sub.m1(+b: Tensor) -> Tensor:
  +c = O.UOp.const(Tensor.ar(b), O.CInt{H.i64_of_i32(4294967295)})
  tn_new(O.Found.ar(c), O.Found.i(c))

def tn_sub.neg(+b: Tensor) -> Tensor:
  +c = tn_sub.m1(b)
  tn_binop(b, c, O.OpsMUL{})

# CPython'S `sub` IS NOT `alu(SUB)`. `elementwise.py:103` reads, with the docstring stripped,
# `a, b = self._broadcasted(x, reverse)` then `return a.alu(Ops.ADD, -b)` -- so `-` builds
# `ADD(a, MUL(b, -1))` and `Ops.SUB` IS NEVER BUILT BY IT. MEASURED on CPython for
# `Tensor(3) - Tensor(7)`: `ADD(CONST(), MUL(CONST(), CONST()))`. VERIFIED that the name is
# not merely unused here: `grep -rn "Ops\.SUB" tinygrad/ | grep "\.py:"` answers 24 and 23
# of them are `X86Ops.SUB`, a different enum; the one graph-level hit is an x86 rewrite
# pattern at `renderer/isa/x86.py:119`, not a Tensor method.
#
# SO THIS BODY WAS WRONG AND THE GATE THAT SHOULD HAVE CAUGHT IT WAS COMPARING THE WRONG
# THING. `gates/tn_add_sub-oracle.py` called `c.alu(Ops.SUB, d)` -- a path CPython's `sub`
# never takes -- so `sub_srcs_are_self_and_x` agreed with the port while both were wrong.
# The oracle now calls the DUNDER.
def tn_sub.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, tn_sub.neg(lhs), O.OpsADD{})
    case False{}: tn_binop(lhs, tn_sub.neg(rhs), O.OpsADD{})

def tn_sub(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_sub.go(False{}, lhs, rhs)

def tn_rsub(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_sub.go(True{}, lhs, rhs)

# `__lt__` -- elementwise.py:321. `return self._binop(Ops.CMPLT, x, False)`. The
# no-broadcasting case (two same-shape Tensors): `_binop`'s `_broadcasted` is the
# identity, so the body collapses to `tn_alu(self, CMPLT, [Tensor.u(x)])` -- the
# same `tn_alu` builder with `OpsCMPLT{}` and the rhs's uop as the second src.
# The `reverse` flag covers `__gt__` (elementwise.py:324, `self._binop(Ops.CMPLT, x,
# True)`), which swaps the order, the same way `tn_mul.go`/`tn_add.go` do. The
# broadcasting case stays walled on `_broadcasted` (mixin/movement.py:24).
def tn_cmplt.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsCMPLT{})
    case False{}: tn_binop(lhs, rhs, O.OpsCMPLT{})

def tn_cmplt(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_cmplt.go(False{}, lhs, rhs)

# `relu` -- elementwise.py:674. `(self > 0).where(self, 0)`. The wall text at
# `nn/__init__.bend:241` cited `_broadcasted` as the blocker for `where`, which
# this composition depends on. The `(self > 0)` is `tn_rcmplt(self, c0)` where
# `c0` is a CONST 0. The `where(self, 0)` is `tn_where(rcmplt, self, c0)`. Both
# parts are ported, so `relu` is a chain of two `tn_alu`-ish calls. Placed AFTER
# `tn_rcmplt` so the forward reference is filled.
def tn_rcmplt(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_cmplt.go(True{}, lhs, rhs)

# `relu` -- elementwise.py:674. `(self > 0).where(self, 0)`. The wall text at
# `nn/__init__.bend:241` cited `_broadcasted` as the blocker for `where`, which
# this composition depends on. The `(self > 0)` is `tn_rcmplt(self, c0)` where
# `c0` is a CONST 0. The `where(self, 0)` is `tn_where(rcmplt, self, c0)`. Both
# parts are ported, so `relu` is a chain of two `tn_alu`-ish calls. Placed AFTER
# `tn_rcmplt` so the forward reference is filled.
def tn_relu.c0(+t: Tensor) -> O.Found:
  O.UOp.const(Tensor.ar(t), O.CInt{H.i64_of_i32(0)})

def tn_relu.c0t(+t: Tensor, +c0: O.Found) -> Tensor:
  tn_new(Tensor.ar(t), O.Found.i(c0))

def tn_relu.gt0(+t: Tensor, +c0: O.Found) -> Tensor:
  tn_rcmplt(t, tn_relu.c0t(t, c0))

def tn_relu.go(+t: Tensor, +gt0: Tensor, +c0: O.Found) -> Tensor:
  tn_where(gt0, t, tn_relu.c0t(t, c0))

def tn_relu(+t: Tensor) -> Tensor:
  +c0 = tn_relu.c0(t)
  tn_relu.go(t, tn_relu.gt0(t, c0), c0)

# `relu6` -- elementwise.py:697. `((r := self.relu()) < 6).where(r, 6)`. Same shape
# as `tn_relu`: a chain of `tn_rcmplt` and `tn_where`, with the only difference
# being the constant (6 instead of 0) and the `r` variable holding the relu
# result. The two `tn_where`s are the same def (`tn_relu.go`); `tn_relu6.go`
# reuses the pattern with a different `c6`. CPython's `relu6` keeps the
# intermediate `r` alive for the gradient path; the port builds the same graph
# (WHERE with srcs = (cond, r, c6)) and drops the `r` variable after the
# where, which is fine for a non-gradient port.
def tn_relu6.c6(+t: Tensor) -> O.Found:
  O.UOp.const(Tensor.ar(t), O.CInt{H.i64_of_i32(6)})

def tn_relu6.c6t(+t: Tensor, +c6: O.Found) -> Tensor:
  tn_new(Tensor.ar(t), O.Found.i(c6))

def tn_relu6.lt6(+t: Tensor, +r: Tensor, +c6: O.Found) -> Tensor:
  tn_rcmplt(r, tn_relu6.c6t(t, c6))

def tn_relu6.go(+t: Tensor, +r: Tensor, +lt6: Tensor, +c6: O.Found) -> Tensor:
  tn_where(lt6, r, tn_relu6.c6t(t, c6))

def tn_relu6(+t: Tensor) -> Tensor:
  +c6 = tn_relu6.c6(t)
  +r = tn_relu(t)
  tn_relu6.go(t, r, tn_relu6.lt6(t, r, c6), c6)

# `ceil` -- elementwise.py:656. `(self > (b := self.trunc())).where(b+1, b)`. The
# `+1` is a CONST added to the trunc'd tensor `b`, and the wall at
# `nn/__init__.bend:241` cited `b+1` (Tensor `+` Tensor arith) and `tn_trunc` as
# the blockers. `tn_trunc` is ported (tensor.bend:320), and the arith is
# `tn_add(b, c1t)` -- `tn_add` is ported (tensor.bend:523), the CONST 1 is
# `tn_ceil.c1` (a `O.UOp.const`, ported at ops.bend:2922), and `c1t` is a
# Tensor wrapping the CONST, the same `tn_new(Tensor.ar(t), O.Found.i(c1))`
# shape `tn_relu.c0t` (tensor.bend:580) uses. The cond `(self > b)` is
# `tn_rcmplt(self, b)` (tensor.bend:568, the `reverse=True` arm of `tn_cmplt`),
# the `where(cond, b+1, b)` is `tn_where` (tensor.bend:369). The body is a
# 4-step chain built in the same shape `tn_relu` / `tn_relu6` use: `b :=
# tn_trunc(self)`, `gt := tn_rcmplt(self, b)`, `bp1 := tn_add(b, c1t)`, and
# the final `tn_where(gt, bp1, b)`. The defs are placed AFTER `tn_rcmplt`,
# `tn_add` and `tn_where` so the forward references are filled.
def tn_ceil.b(+t: Tensor) -> Tensor:
  tn_trunc(t)

def tn_ceil.gt(+t: Tensor, +b: Tensor) -> Tensor:
  tn_rcmplt(t, b)

def tn_ceil.c1(+t: Tensor) -> O.Found:
  O.UOp.const(Tensor.ar(t), O.CInt{H.i64_of_i32(1)})

def tn_ceil.c1t(+t: Tensor, +c1: O.Found) -> Tensor:
  tn_new(Tensor.ar(t), O.Found.i(c1))

def tn_ceil.bp1(+t: Tensor, +b: Tensor, +c1: O.Found) -> Tensor:
  tn_add(b, tn_ceil.c1t(t, c1))

def tn_ceil.go(+t: Tensor, +gt: Tensor, +bp1: Tensor, +b: Tensor) -> Tensor:
  tn_where(gt, bp1, b)

def tn_ceil(+t: Tensor) -> Tensor:
  +c1 = tn_ceil.c1(t)
  +b = tn_ceil.b(t)
  tn_ceil.go(t, tn_ceil.gt(t, b), tn_ceil.bp1(t, b, c1), b)

# `floor` -- elementwise.py:662. `(self < (b := self.trunc())).where(b-1, b)`.
# Same shape as `tn_ceil` with `b-1` (a CONST SUB via `tn_sub`, tensor.bend:541,
# instead of `tn_add`) and `tn_cmplt` (the forward CMPLT, tensor.bend:559,
# instead of the reverse). The `b-1` is `tn_sub(b, c1t)` -- `tn_sub` builds
# `SUB(b, c1)` (the same shape `tn_ceil.bp1` builds `ADD(b, c1)`, with `OpsSUB`
# instead of `OpsADD`). The cond is `tn_cmplt(self, b)` (NOT `tn_rcmplt` --
# the FLOOR inequality is the forward `<`). The defs are placed AFTER `tn_sub`
# and `tn_cmplt` so the forward references are filled, and they mirror
# `tn_ceil`'s structure.
def tn_floor.b(+t: Tensor) -> Tensor:
  tn_trunc(t)

def tn_floor.lt(+t: Tensor, +b: Tensor) -> Tensor:
  tn_cmplt(t, b)

def tn_floor.c1(+t: Tensor) -> O.Found:
  O.UOp.const(Tensor.ar(t), O.CInt{H.i64_of_i32(1)})

def tn_floor.c1t(+t: Tensor, +c1: O.Found) -> Tensor:
  tn_new(Tensor.ar(t), O.Found.i(c1))

def tn_floor.bm1(+t: Tensor, +b: Tensor, +c1: O.Found) -> Tensor:
  tn_sub(b, tn_floor.c1t(t, c1))

def tn_floor.go(+t: Tensor, +lt: Tensor, +bm1: Tensor, +b: Tensor) -> Tensor:
  tn_where(lt, bm1, b)

def tn_floor(+t: Tensor) -> Tensor:
  +c1 = tn_floor.c1(t)
  +b = tn_floor.b(t)
  tn_floor.go(t, tn_floor.lt(t, b), tn_floor.bm1(t, b, c1), b)

# `maximum` -- elementwise.py:378. `self._binop(Ops.MAX, x, False)`. Same shape as
# `tn_add` / `tn_mul` with `OpsMAX{}` instead of `OpsMUL{}`. The no-broadcasting
# case is `self.alu(MAX, x.uop)`, the broadcasting case stays walled on
# `_broadcasted`.
def tn_maximum.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsMAX{})
    case False{}: tn_binop(lhs, rhs, O.OpsMAX{})

def tn_maximum(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_maximum.go(False{}, lhs, rhs)

def tn_rmaximum(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_maximum.go(True{}, lhs, rhs)

# `lshift` -- elementwise.py:347. `self._binop(Ops.SHL, x, False)`. Same shape as
# `tn_maximum` with `OpsSHL{}` instead of `OpsMAX{}`. The reverse arm is
# `__rlshift__` (elementwise.py:361). The broadcasting case stays walled on
# `_broadcasted`.
def tn_lshift.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsSHL{})
    case False{}: tn_binop(lhs, rhs, O.OpsSHL{})

def tn_lshift(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_lshift.go(False{}, lhs, rhs)

def tn_rlshift(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_lshift.go(True{}, lhs, rhs)

# `rshift` -- elementwise.py:355. Same shape with `OpsSHR{}` instead.
def tn_rshift.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsSHR{})
    case False{}: tn_binop(lhs, rhs, O.OpsSHR{})

def tn_rshift(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_rshift.go(False{}, lhs, rhs)

def tn_rrshift(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_rshift.go(True{}, lhs, rhs)

# `minimum` is NOT ported: CPython's `Tensor.minimum` (elementwise.py:387) has
# dtype promotion (the int `^k` trick at elementwise.py:390 and the float arm
# `-(-t).alu(MAX, -x)`), and `OpsMIN{}` IS NOT IN THE SUBSTRATE (verified:
# `grep -c OpsMIN tinybendygrad/uop/ops.bend` -> 0). The no-broadcasting case
# would need `OpsMIN{}` to build `self.alu(MIN, x.uop)`, and the port has no
# such constructor. Stays walled on the MIN-op + the dtype-promotion seam.

# `__ne__` -- elementwise.py:339, via `ne` at elementwise.py:333
# (`self._binop(Ops.CMPNE, x, False)`). Same shape as `tn_cmplt` with `Ops.CMPNE`
# instead of `Ops.CMPLT`. The `reverse` arm is unused upstream (`ne` has no
# `__rne__`) but `tn_rne` exists by symmetry with `tn_cmplt`'s `tn_rcmplt`, so the
# shape of the dispatcher matches. The broadcasting case stays walled on
# `_broadcasted`.
def tn_cmpne.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsCMPNE{})
    case False{}: tn_binop(lhs, rhs, O.OpsCMPNE{})

def tn_cmpne(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_cmpne.go(False{}, lhs, rhs)

def tn_rne(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_cmpne.go(True{}, lhs, rhs)

# `__and__` -- elementwise.py:285, via `bitwise_and` at elementwise.py:159
# (`self._binop(Ops.AND, x, reverse)`). Same shape as `tn_cmplt` with `Ops.AND`.
# The `reverse` arm is `__rand__` (elementwise.py:309). The broadcasting case
# stays walled on `_broadcasted`.
def tn_and.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsAND{})
    case False{}: tn_binop(lhs, rhs, O.OpsAND{})

def tn_and(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_and.go(False{}, lhs, rhs)

def tn_rand(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_and.go(True{}, lhs, rhs)

# `__or__` -- elementwise.py:288, via `bitwise_or` at elementwise.py:173
# (`self._binop(Ops.OR, x, reverse)`). Same shape as `tn_and` with `Ops.OR`.
# The `reverse` arm is `__ror__` (elementwise.py:312). The broadcasting case
# stays walled on `_broadcasted`.
def tn_or.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsOR{})
    case False{}: tn_binop(lhs, rhs, O.OpsOR{})

def tn_or(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_or.go(False{}, lhs, rhs)

def tn_ror(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_or.go(True{}, lhs, rhs)

# `__xor__` -- elementwise.py:291, via `bitwise_xor` at elementwise.py:187
# (`self._binop(Ops.XOR, x, reverse)`). Same shape as `tn_and` with `Ops.XOR`.
# The `reverse` arm is `__rxor__` (elementwise.py:315). The broadcasting case
# stays walled on `_broadcasted`.
def tn_xor.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsXOR{})
    case False{}: tn_binop(lhs, rhs, O.OpsXOR{})

def tn_xor(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_xor.go(False{}, lhs, rhs)

def tn_rxor(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_xor.go(True{}, lhs, rhs)

# `maximum` -- elementwise.py:378. `return self._binop(Ops.MAX, x, False)`. The
# no-broadcasting case is `tn_binop(self, x, MAX)`. `maximum` has no
# `reverse` arm upstream, so there is no `tn_rmax` and the dispatcher is
# unnecessary -- `tn_max` IS the body. The broadcasting case stays walled on
# `_broadcasted`.
def tn_max(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_binop(lhs, rhs, O.OpsMAX{})

# `__lshift__` -- elementwise.py:366, via `lshift` at elementwise.py:344
# (`self._binop(Ops.SHL, x, reverse)`). Same shape as `tn_and` with `Ops.SHL`.
# The `reverse` arm is `__rlshift__` (elementwise.py:372). The broadcasting case
# stays walled on `_broadcasted`.
def tn_shl.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsSHL{})
    case False{}: tn_binop(lhs, rhs, O.OpsSHL{})

def tn_shl(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_shl.go(False{}, lhs, rhs)

def tn_rshl(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_shl.go(True{}, lhs, rhs)

# `__rshift__` -- elementwise.py:369, via `rshift` at elementwise.py:355
# (`self._binop(Ops.SHR, x, reverse)`). Same shape as `tn_shl` with `Ops.SHR`.
# The `reverse` arm is `__rrshift__` (elementwise.py:375). The broadcasting case
# stays walled on `_broadcasted`.
def tn_shr.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsSHR{})
    case False{}: tn_binop(lhs, rhs, O.OpsSHR{})

def tn_shr(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_shr.go(False{}, lhs, rhs)

def tn_rshr(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_shr.go(True{}, lhs, rhs)

# `__pow__` -- elementwise.py:569, via `pow` at elementwise.py:548 (`base, exponent
# = self._broadcasted(x, reverse=reverse); ...; return base.alu(Ops.POW, exponent)`).
# For two Tensors of the same shape (the no-broadcasting case the gate covers),
# `_broadcasted` is the identity and the body is `tn_alu(self, POW, [Tensor.u(x)])`.
# CPython's raise on `not dtypes.is_float(...)` (elementwise.py:565) only fires
# for a `ConstType` rhs that isn't a non-negative int, which is unreachable for
# two Tensors. The `reverse` arm is `__rpow__` (elementwise.py:572). The
# broadcasting case stays walled on `_broadcasted`.
def tn_pow.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsPOW{})
    case False{}: tn_binop(lhs, rhs, O.OpsPOW{})

def tn_pow(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_pow.go(False{}, lhs, rhs)

def tn_rpow(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_pow.go(True{}, lhs, rhs)

# `__floordiv__` -- elementwise.py:279. `return self.div(x, rounding_mode="floor")`,
# and `div` (elementwise.py:229) is `a, b = self._broadcasted(x, reverse); if
# dtypes.is_int(a.dtype) and dtypes.is_int(b.dtype): ... if rounding_mode == "floor":
# return a.alu(Ops.FLOORDIV, b)`. For two Tensors of the same shape with int dtypes
# the no-broadcasting case: `_broadcasted` is the identity, and the body collapses
# to `_binop`'s shape (elementwise.py:36) with `MUL` replaced by `FLOORDIV`:
# `tn_alu(self, FLOORDIV, [Tensor.u(x)])` for `__floordiv__` (srcs `(self, x)`),
# `tn_alu(x, FLOORDIV, [Tensor.u(self)])` for `__rfloordiv__` (srcs `(x, self)`).
# The `__truediv__` arm (`self.div(x)` with `rounding_mode=None`) is NOT ported:
# its body is `cast(self, default_float).alu(FDIV, b)` past the int-arm guard, and
# `cast` plus the `default_float` constant need fold reads the port does not carry.
# `__floordiv__` IS the integer path, and the FLOORDIV op is the one CPython's
# `div(x, rounding_mode="floor")` builds for int inputs (elementwise.py:252, gated
# below). The `reverse` flag covers `__rfloordiv__` (the `reverse=True` arm of the
# same `_binop`). The broadcasting case stays walled on `_broadcasted` (same wall
# as the rest of the binop defs).
def tn_fdiv.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsFLOORDIV{})
    case False{}: tn_binop(lhs, rhs, O.OpsFLOORDIV{})

def tn_fdiv(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_fdiv.go(False{}, lhs, rhs)

def tn_rfdiv(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_fdiv.go(True{}, lhs, rhs)

# `__mod__` -- elementwise.py:282, via `mod` at elementwise.py:202
# (`self._binop(Ops.FLOORMOD, x, reverse)`). Same shape as `tn_pow.go` with
# `Ops.FLOORMOD` instead of `Ops.POW`: for two Tensors of the same shape,
# `_binop`'s `_broadcasted` is the identity and the body is
# `tn_alu(self, FLOORMOD, [Tensor.u(x)])`. The `mod` body at elementwise.py:213
# is `if dtypes.is_int(a.dtype) and dtypes.is_int(b.dtype): return a.alu(Ops.FLOORMOD, b)`
# -- the same op the port covers. The float arm (`return a - a.div(b,
# rounding_mode="floor") * b`, elementwise.py:214) stays walled on the dtype fold
# (the same wall `tn_bitwise_not`'s arith arms name at tensor.bend:385) and on
# `div`'s float arm. The `reverse` arm is the `__rmod__` shape, mirroring
# `tn_pow.go`'s `reverse` arm. The broadcasting case stays walled on `_broadcasted`.
def tn_mod.go(reverse: Bool, +lhs: Tensor, +rhs: Tensor) -> Tensor:
  match reverse:
    case True{}: tn_binop(rhs, lhs, O.OpsFLOORMOD{})
    case False{}: tn_binop(lhs, rhs, O.OpsFLOORMOD{})

def tn_mod(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_mod.go(False{}, lhs, rhs)

def tn_rmod(+lhs: Tensor, +rhs: Tensor) -> Tensor:
  tn_mod.go(True{}, lhs, rhs)

# `__ge__` -- elementwise.py:327. `return (self < x).logical_not()`. The result of
# `<` is a bool Tensor; `logical_not` (elementwise.py:49) IS `self.cast(bool).ne(True)`,
# which `tn_logical_not` builds (`CAST(bool) -> CMPNE(cast, CONST(True))` -- gated
# 8/8, gates/tn_logical_not-gate.py). So the composition
# `tn_logical_not(tn_cmplt(t, x))` is a fully-portable chain. The no-broadcast case
# is the only one `tn_cmplt`'s row covers; the broadcasting case of `__lt__` stays
# walled on `_broadcasted`.
def tn_dunder_ge(+t: Tensor, +x: Tensor) -> Tensor:
  tn_logical_not(tn_cmplt(t, x))

# `__le__` -- elementwise.py:330. `return (self > x).logical_not()`. The chain
# `tn_logical_not(tn_rcmplt(t, x))` is the no-broadcast case. `__gt__` is
# `tn_rcmplt`, the `reverse=True` arm of `tn_cmplt.go`. The broadcasting case
# stays walled on `_broadcasted`.
def tn_dunder_le(+t: Tensor, +x: Tensor) -> Tensor:
  tn_logical_not(tn_rcmplt(t, x))

# `eq` -- elementwise.py:336. `return self.ne(x).logical_not()`. The chain
# `tn_logical_not(tn_cmpne(t, x))` is the no-broadcast case. The broadcasting
# case stays walled on `_broadcasted`.
def tn_eq(+t: Tensor, +x: Tensor) -> Tensor:
  tn_logical_not(tn_cmpne(t, x))

# `isnan` -- elementwise.py:603. `return self != self`. The CMPNE node has the
# SAME tensor on both srcs, and a NaN is the only float where `x == x` is false,
# so CMPNE against self IS the NaN test. The graph is one node (CMPNE), the
# `mo_isnan` (`mixin/op.bend:986`) calls `mo_neq(t, t)` -- the same shape at the
# reduction layer. Gated at `gates/tn_isnan-gate.py` 5/5 rows.
def tn_isnan(+t: Tensor) -> Tensor:
  tn_cmpne(t, t)

# `isfinite` -- elementwise.py:623. `(self.isinf() | self.isnan()).logical_not()`.
# `isinf` itself is `self.eq(inf) + self.eq(-inf)` with the default `detect_*=True`
# (the bool arm collapses to a plain `+` of two bool-eq results); inlined here in
# the same shape as `mo_isfinite` (`mixin/op.bend:1008`) because the `tn_*` layer
# has no `tn_isinf` to call. The four CONSTs (`+inf`, `-inf`, two `True`s) are
# built off the NEWEST arena each time -- the same `mo_arena` rule
# (`mixin/op.bend:460`) `mo_isfinite` was written against. The dtype stays bool
# throughout: `+` of two bools is `xor` (bool), `or` of two bools is bool,
# `logical_not` of a bool is `cast(bool).cmpne(True)`. Gated at
# `gates/tn_isfinite-gate.py` 4/4 rows.
def tn_isfinite.cinf(+ar: O.Arena) -> O.Found:
  O.UOp.const(ar, O.CFloat{F32.mul(1.0e30, 1.0e30)})
def tn_isfinite.cneginf(+ar: O.Arena) -> O.Found:
  O.UOp.const(ar, O.CFloat{F32.neg(F32.mul(1.0e30, 1.0e30))})
def tn_isfinite.ct(+c: O.Found) -> Tensor:
  tn_new(O.Found.ar(c), O.Found.i(c))
# `self.eq(inf)` -- `tn_eq` is `logical_not(cmpne)`, and `logical_not` builds in the arena
# its CAST grew, so the CMPNE has to be built in `c`'s arena: `c` DESCENDS from `t`'s.
def tn_isfinite.eqarm(+t: Tensor, +c: Tensor) -> Tensor:
  tn_logical_not(tn_binop(t, c, O.OpsCMPNE{}))
# `eq * detect_positive`, and `detect_positive` is the CONST `True`, which is interned in
# `eq`'s own arena -- so the MUL is built in `tc.ar` and `eq.u` reads as an ancestor index.
def tn_isfinite.armul(+eq: Tensor) -> Tensor:
  +tc = O.UOp.const(Tensor.ar(eq), O.CBool{True{}})
  tn_alu.of(O.Found.ar(tc), Tensor.u(eq), O.OpsMUL{}, [O.Found.i(tc)])
# `ep` is the positive arm AND the arena the negative arm grows FROM, so `en` is a strict
# DESCENDANT of `ep` and `en.u` is legal in `en.ar`. Building the ADD in `ep.ar` instead
# would name the slot the ADD itself is about to take -- MEASURED, see `tn_binop`.
def tn_isfinite.isinf_part(+t: Tensor) -> Tensor:
  +ep = tn_isfinite.armul(tn_isfinite.eqarm(t, tn_isfinite.ct(tn_isfinite.cinf(Tensor.ar(t)))))
  +en = tn_isfinite.armul(tn_isfinite.eqarm(ep, tn_isfinite.ct(tn_isfinite.cneginf(Tensor.ar(ep)))))
  tn_alu.of(Tensor.ar(en), Tensor.u(ep), O.OpsADD{}, [Tensor.u(en)])
# `isnan` is a SIBLING of `isinf_part` off `t`, so it is REBUILT on `inf_part`'s arena --
# `tn_new` over the ORIGINAL const index, which append-only keeps valid -- and the OR is
# built in `isnan`'s (the newer) arena.
def tn_isfinite.nan_in(+ar: O.Arena, uop: U32) -> Tensor:
  tn_isnan(tn_new(ar, uop))
def tn_isfinite(+t: Tensor) -> Tensor:
  +inf_part = tn_isfinite.isinf_part(t)
  tn_logical_not(tn_binop(inf_part, tn_isfinite.nan_in(Tensor.ar(inf_part), Tensor.u(t)), O.OpsOR{}))

# `_apply_uop` -- tensor.py:104-113. `new_uop: UOp = fxn(*[t.uop for t in srcs],
# **kwargs)` is a CALLBACK, and Bend has no function values, so every op in this
# file is its own def that builds the node and then calls `tn_new`. The wall is the
# one `uop/upat.bend` records for `upat_compile`: the closure cannot be stored, so
# the call is inlined at each site.
#
# TODO(p3) tensor.py:104  _apply_uop's `fxn` -- no function values, so the twelve
# `__i*__` and `__eq__` below each inline `O.UOp.alu` + `assign`.

# `_wrap_uop` -- tensor.py:120. `cls(u)`: the UOp arm of `__init__` with no dtype and
# no device postlude, which is all of it.
def tn_wrap_uop(+ar: O.Arena, uop: U32) -> Tensor:
  tn_new(ar, uop)

# `const` -- tensor.py:122. `Tensor(UOp.const(b, dtype))`.
# TODO(p3) tensor.py:122  const's `dtype` -- ops.bend's `UOp.const` is the BARE
# CONST, because `dtypes.from_py` and `truncate` are P3 (ops.py:632). A CONST of a
# CONCRETE dtype is ONE node here and `CONST`+`CAST` in Python; the value arrives
# already truncated and the dtype is the CONST's own.
# TODO(p3) tensor.py:74  a float `ConstType` -- `F32{data: Word(32n)}` has no
# reachable constructor (`Word` is not exported and `U32.to_f32` is a LAW), so
# `Tensor(1.0)` has no constant to intern. INT and BOOL do.
def tn_const(+ar: O.Arena, v: O.Const) -> Tensor:
  tn_alu.put(O.UOp.const(ar, v))

# `is_param_` -- tensor.py:124-126. `self.is_param = is_param; return self` is
# IN-PLACE in Python and a NEW RECORD here; the `tn_param` row pins the old one.
def tn_is_param_(+t: Tensor, is_param: Bool) -> Tensor:
  Tensor{Tensor.ar(t), Tensor.u(t), is_param, Tensor.grad_of(t)}

# `__hash__` -- tensor.py:134. `return id(self)`, and an arena index IS a graph
# node's identity in this port, so `__hash__` is the uop. THE DIFFERENCE, and it is
# why `_tensor_holds` reads the uop rather than a hash: Python's `id` separates two
# Tensor OBJECTS over one uop and this does not.
def tn_hash(+t: Tensor) -> U32:
  Tensor.u(t)

# `__bool__` -- tensor.py:136. `raise TypeError("__bool__ on Tensor is not defined")`.
# TODO(p3) tensor.py:136  __bool__ -- a pure Bend def cannot raise and there is no
# exception form to defer to. A def that must NOT be called is not a def that can be
# written; the refusal is the absence, and `tn_len` below is the shape of the same
# refusal made expressible as a `Maybe`.

# `__len__` -- tensor.py:138-140. `if not self.shape: raise TypeError; return
# self.shape[0]`. The raise is `__bool__`'s wall, so the answer is a `Maybe` and
# `None` is Python's `TypeError`.
def tn_len.first(ds: List<&2, O.Sint>) -> Maybe<&2, U32>:
  match ds:
    case Nil{}: None{}
    case d <> _: Some{O.SInt.u(d)}

def tn_len.of(m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, U32>:
  match m:
    case Some{ds}: tn_len.first(ds)
    case None{}: None{}

def tn_len(+t: Tensor) -> Maybe<&2, U32>:
  tn_len.of(tn_dims(t))

# ===========================================================================
# `__repr__` -- tensor.py:128-131.
# `f"<UOp {ld.device} {ld.shape} {str(ld.dtype)[7:]}>"`, and all three interpolations
# are a reader above. `str(dtypes.weakint)` is `"dtypes.weakint"`, so `[7:]` is the
# bare name, which is `S.Dt.nm`. THE DEVICE COLUMN is the divergence the header
# records: a `Dev` is an interned tag, so it prints as its tag, and the gate
# therefore uses a device-LESS tensor where both sides print `None`. The grad column
# is `self.grad.uop if self.grad is not None else None` and 0 is the reserved `None`,
# so it prints `None` on every device-LESS fixture and `0` never -- `tn_grad` is the
# row that would see a wrong 0-test.
#
# The whole thing is FOUR defs and not one, because each of the three fold reads is
# a separate fold over the whole arena and folding three times is what the record was
# for: one `Tensor` in, one `String` out, and the three readers are computed in the
# order the f-string interpolates them.
# ===========================================================================

def dt_name.of(dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}: nm

def dt_name(dt: S.Dt) -> String:
  dt_name.of(dt)

# `SInt` is `SI{i: I64}` for a concrete dim and `SU{u: U32}` for a bound variable,
# and `O.SInt.u` answers 0 for an `SI`, so a concrete dim prints through its `i64`.
# Every dim this file gates is concrete.
def sint_text.of(s: O.Sint) -> String:
  match s:
    case O.SI{i}: H.i64_text(i)
    case _: "0"

def sint_text(s: O.Sint) -> String:
  sint_text.of(s)

def tn_repr.dims.go(ds: List<&2, O.Sint>, +acc: String) -> String:
  match ds:
    case Nil{}: acc
    case d <> t: tn_repr.dims.go(t, String.concat([acc, sint_text(d), ", "]))

# the shape as a Python TUPLE prints, so `()` and `(3,)` and `(2, 2)`. It is a
# `Maybe` in the middle because `str(None)` is the string `None` and so is a 0-d
# shape's `()` -- the two are DIFFERENT and `()` is not None.
def tn_repr.dims(shape: Maybe<&2, List<&2, O.Sint>>) -> String:
  match shape:
    case Some{ds}: String.concat(["(", tn_repr.dims.go(ds, ""), ")"])
    case _: "()"

def tn_repr.devname(+dev: Maybe<&2, S.Dev>) -> String:
  match dev:
    case Some{S.D1{tag}}: U32.show(tag)
    case _: "None"

def tn_repr.grad.of(none: Bool) -> String:
  match none:
    case True{}: "None"
    case _: "0"

def tn_repr.grad(g: U32) -> String:
  tn_repr.grad.of(U32.is_zero(g))

def tn_repr.dt.of(m: Maybe<&2, S.Dt>) -> S.Dt:
  match m:
    case Some{d}: d
    case None{}: S.void()

def tn_repr.dt(+t: Tensor) -> S.Dt:
  tn_repr.dt.of(tn_dtype(t))

def tn_repr.of(+dev: Maybe<&2, S.Dev>, shape: Maybe<&2, List<&2, O.Sint>>, dt: S.Dt, g: U32) -> String:
  String.concat(["<Tensor <UOp ", tn_repr.devname(dev), " ", tn_repr.dims(shape), " ", dt_name(dt),
    "> on ", tn_repr.devname(dev), " with grad ", tn_repr.grad(g), ">"])

def tn_repr(+t: Tensor) -> String:
  tn_repr.of(tn_dev(t), tn_dims(t), tn_repr.dt(t), Tensor.grad_of(t))

# ===========================================================================
# __init__ -- tensor.py:57-99. The dispatch over what `data` IS, which is the only
# part of this method that is a Tensor fact: every arm names a different way of
# turning a Python value into a UOp, and only two of them are graph construction.
#
# The isinstance ladder over six types becomes a `Data` union, which is the honest
# reading: `isinstance(data, get_args(ConstType))` is a membership test over a set of
# scalar types and a `Data` union is a set of tags. The two raises (tensor.py:79 and
# :91) become `None`, fold.bend's rule.
# ===========================================================================

type Data1 is Data:
  DNone{}                    # data is None                     -- tensor.py:72
  DConst{v: O.Const}         # isinstance(data, ConstType)      -- tensor.py:74
  DMade{i: O.Found}          # list/tuple/bytes/ndarray/Path: the uop the maker already
                             # built, because the makers are WALL 2 (ops.py:870
                             # `_frompy`, tensor.py:38 `_fromnp`, ops.py:853
                             # `new_buffer`)

# `data is None` -> `UOp.const(0.0, _dtype)`. The `0.0` is an `F32` and no `F32`
# literal is constructible, so this def answers the `None` DATA only through a value
# the caller supplies, and the `DNone` arm is the one row of `__init__` the gate
# cannot pin.
# TODO(p3) tensor.py:73  UOp.const(0.0, _dtype) -- an F32 literal.
def tn_init.none() -> Maybe<&2, O.Found>:
  None{}

def tn_init.arm(+d: Data1) -> Maybe<&2, O.Found>:
  match d:
    case DNone{}: tn_init.none()
    case DConst{v}: Some{O.UOp.const(O.Arena.empty(), v)}
    case DMade{i}: Some{i}

def tn_init.keep(+i: O.Found) -> Maybe<&2, U32>:
  Some{O.Found.i(i)}

# `if self.match_dtype == (dtype,): return self` (ops.py:1512) -- the early-out IS
# `UOp.cast`, and for a concrete dtype it is the whole of `UOp.cast`'s semantics, so
# this is one comparison and not a `Maybe`.
def tn_cast.dt_is.of(m: Maybe<&2, S.Dt>, +d: S.Dt) -> Bool:
  match m:
    case Some{got}: O.eq_dt(got, d)
    case None{}: False{}

def tn_cast.dt_is(+i: U32, +d: S.Dt) -> Bool:
  tn_cast.dt_is.of(tn_dtype(tn_wrap_uop(O.Arena.empty(), i)), d)

# the CAST node, on the arena the value came from.
def tn_cast.node2(+ar: O.Arena, +i: U32, +d: S.Dt) -> Tensor:
  tn_new(ar, O.Found.i(O.UOp.new(ar, O.OpsCAST{}, [i], O.ADt{d}, O.TNone{})))

def tn_cast.node(+i: U32, +d: S.Dt) -> Tensor:
  tn_cast.node2(O.Arena.empty(), i, d)

def tn_cast.put.of(same: Bool, +i: U32, +d: S.Dt) -> Maybe<&2, Tensor>:
  match same:
    case True{}: Some{tn_wrap_uop(O.Arena.empty(), i)}
    case _: Some{tn_cast.node(i, d)}

def tn_cast.put(+i: U32, +d: S.Dt) -> Maybe<&2, Tensor>:
  tn_cast.put.of(tn_cast.dt_is(i, d), i, d)

def tn_cast.go(i: U32, dt: Maybe<&2, S.Dt>) -> Maybe<&2, Tensor>:
  match dt:
    case Some{d}: tn_cast.put(i, d)
    case _: Some{tn_wrap_uop(O.Arena.empty(), i)}

def tn_cast.of(m: Maybe<&2, U32>, dt: Maybe<&2, S.Dt>) -> Maybe<&2, Tensor>:
  match m:
    case Some{i}: tn_cast.go(i, dt)
    case None{}: None{}

# `self.uop = data if data.device is None or data.device == _device else
# data.copy_to_device(_device)` (tensor.py:94) is WALL 2 (`copy_to_device` is
# ops.py:761). `if _dtype is not None: self.uop = self.uop.cast(_dtype)`
# (tensor.py:96) IS ported, and it is the only part of `__init__` after the dispatch
# that is a graph fact.
def tn_init.of(m: Maybe<&2, O.Found>, dt: Maybe<&2, S.Dt>) -> Maybe<&2, Tensor>:
  match m:
    case Some{i}: tn_cast.of(tn_init.keep(i), dt)
    case None{}: None{}

def tn_init(d: Data1, dt: Maybe<&2, S.Dt>) -> Maybe<&2, Tensor>:
  tn_init.of(tn_init.arm(d), dt)

# ===========================================================================
# `replace` -- tensor.py:227-234. `assert self.shape == x.shape, f"replace shape
# mismatch ..."; self.uop = x.uop; return self`. The mutation is a new record and the
# `assert` is a `None`, so this def is TOTAL: it answers the new Tensor or Python's
# AssertionError. `tn_replace` and `tn_replace_bad` are the two sides, and a `replace`
# that ignored the assert would make the second one move and not the first.
# ===========================================================================

def tn_replace.same.go(xs: List<&2, O.Sint>, b: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  match b:
    case Some{ys}: F.eq_sints(xs, ys)
    case None{}: False{}

def tn_replace.same.of(+a: Maybe<&2, List<&2, O.Sint>>, b: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  match a:
    case Some{xs}: tn_replace.same.go(xs, b)
    case None{}: False{}

def tn_replace.same(+t: Tensor, +x: Tensor) -> Bool:
  tn_replace.same.of(tn_dims(t), tn_dims(x))

def tn_replace.of(same: Bool, +t: Tensor, +x: Tensor) -> Maybe<&2, Tensor>:
  match same:
    case True{}: Some{tn_new(Tensor.ar(t), Tensor.u(x))}
    case _: None{}

def tn_replace(+t: Tensor, +x: Tensor) -> Maybe<&2, Tensor>:
  tn_replace.of(tn_replace.same(t, x), t, x)

# ===========================================================================
# `as_param` -- tensor.py:153-154. `def as_param(self, slot): return
# Tensor(self.uop.param_like(slot))`. TWO LINES, and the whole of it is a rename of a
# live value into a numbered SLOT.
#
# `UOp.param_like` (ops.py:1241) is THREE arms and this ports the third:
#   1. `self.op is Ops.PARAM and self.addrspace is AddrSpace.ALU` -- re-slot an ALU
#      scalar, which CLEARS the bound value (`val=None`). Needs `replace` on `ParamArg`
#      and an ALU addrspace the port does not build.
#   2. `self.axis is not None and isinstance(self.device, tuple)` -- a SHARDED value
#      becomes a per-shard sized PARAM wrapped in UNSHARD. Needs shard, which is
#      WALL 2's neighbour and a named TODO at :1157.
#   3. `UOp.param(slot, self.dtype, self._shape, self.device, name=None)` -- THE ONE.
# It is `UOp(Ops.PARAM, src=(), arg=ParamArg(slot, dtype, size=shape, device=device))`
# with `name` left `None` (ops.py:1018), and for a single device `device_range_src` is
# `()` (ops.py:851) -- the same fact `g_buf` already relies on and states. So arm 3 is
# BUILDABLE, and this is the only method in tensor.py's device half that is: the others
# in that block all need a `Buffer` or a fetch or mutable class state, and this one
# needs a dtype and a shape, which are fold answers.
#
# WHY `as_param` IS NOT TRIVIAL AND THE ROWS PROVE IT. A toposort signature prints the
# op and the arity and NEVER THE ARG -- this file's own mutation M5 is that lesson, and
# it is why `tn_rop_arg` exists as a separate row. So `tn_asparam` (the signature) is
# BLIND to a dropped or wrong `slot`, and `tn_asparam_slot` (the arg) is the row that
# closes it. Neither is enough alone: the arg row cannot see a missing SRC and the
# signature row cannot see a wrong SLOT. That pair is the gate.
# ===========================================================================

# arm 3's `ParamArg(slot, dtype, size=shape, device=device)`. Field names and order are
# ops.bend's `ParamArg`, not a hand-written list, and the three facts are READ OFF THE
# SOURCE'S OWN `ParamArg` rather than recomputed: for every node kind that can be
# `as_param`'d here -- BUFFER, ALLOC, PARAM -- `_shape` IS `ParamArg.size`, `dtype` IS
# `ParamArg.dtype` and `device` IS `ParamArg.device`, which is exactly what `UOp.param`
# reads at ops.py:1018 and exactly what the fold answers (`fold.bend:2222 param_ds`). So a
# source whose arg is not an `AParam` is a source this def DECLINES, and it says so with
# a `None` instead of inventing a size. `name=None` because `param_like` is called with
# only a slot; `addrspace=AGLOBAL` because `UOp.param` derives it from the device and this
# file's `g_buf` already writes that value for a buffer.
def tn_as_param.of(slot: U32, +src: O.ParamArg) -> O.ParamArg:
  # slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image,
  # buffer, bind_on_realize, val. `buffer=None` and `val=None`: a PARAM carries no Buffer
  # (that is WALL 2, and `ParamArg.buffer` is its one device field, as `g_buf` already
  # states), and `param_like` CLEARS `val` upstream (ops.py:1300) so re-slotting a bound
  # Variable drops its binding -- arm 1, a named TODO, and `tn_asparam_slot` is the row
  # that would move if it were ported.
  O.ParamArg{slot, O.ParamArg.dtype(src), O.ParamArg.size(src), None{}, None{}, None{},
    S.AGlobal{}, O.ParamArg.device(src), False{}, None{}, None{}, False{}, None{}}

# `Tensor(self.uop.param_like(slot))`. The `Maybe` is the port's `tn_len` convention: a
# `None` is a source this def declines, which is Python's first `param_like` arm. The
# scrutinee gets its own def because a match cannot scrutinize a computed value, and
# `tn_rop_arg.go` is the same split for the same reason.
def tn_as_param.go(pa: O.ParamArg, +ar: O.Arena, slot: U32) -> Maybe<&2, Tensor>:
  +ns = O.UOp.new(ar, O.OpsPARAM{}, Nil{},
    O.AParam{tn_as_param.of(slot, pa)}, O.TNone{})
  Some{tn_new(O.Found.ar(ns), O.Found.i(ns))}

def tn_as_param.src(arg: O.Arg, +ar: O.Arena, slot: U32) -> Maybe<&2, Tensor>:
  match arg:
    case O.AParam{pa}: tn_as_param.go(pa, ar, slot)
    case _: None{}

def tn_as_param(+ar: O.Arena, +t: Tensor, slot: U32) -> Maybe<&2, Tensor>:
  tn_as_param.src(O.Arena.arg(ar, Tensor.u(t)), ar, slot)

# ===========================================================================
# `shape_to_shape_arg` -- ops.py:104. `src = tuple(x if isinstance(x, UOp) else
# UOp.const(x) for x in arg); return src[0] if len(src) == 1 else UOp(Ops.STACK,
# src=src)`. THREE arms, and the middle one is the one that matters: ONE element is
# the CONST ITSELF and more than one is a STACK, which is why `(2, 2)` is a STACK and
# `(4,)` is a CONST.
#
# A `Data` record because a fold step must carry the arena it is growing AND the
# indices it has interned, and a bare `List` is spent when it is read.
# ===========================================================================

type SArg is Data:
  SArg{ar: O.Arena, ys: List<&2, U32>}

def SArg.ar(+a: SArg) -> O.Arena:
  match a:
    case SArg{ar, ys}: ar

def SArg.ys(+a: SArg) -> List<&2, U32>:
  match a:
    case SArg{ar, ys}: ys

def tn_sarg.push(+a: SArg, c: O.Const) -> SArg:
  +k = O.UOp.const(SArg.ar(a), c)
  SArg{O.Found.ar(k), List.append(&2, U32, SArg.ys(a), [O.Found.i(k)])}

def tn_sarg.acc(ds: List<&2, O.Const>, +a: SArg) -> SArg:
  match ds:
    case Nil{}: a
    case c <> t: tn_sarg.acc(t, tn_sarg.push(a, c))

# THE COUNT DECIDES AND THE LIST IS PASSED WHOLE, and the `Bool` is a PARAMETER
# because a numeric countdown is a PREFIX MATCH. Two rules meet here and both were
# measured the hard way:
#
#   * A `match` on a list DESTRUCTURES its scrutinee, so `case s <> t:` spends `ys` and
#     the arm cannot re-wrap the tail: `[s] ++ v` after a SECOND destructuring
#     `case u <> v:` silently DROPS `u`. The count is computed BEFORE the match and `ys`
#     is handed on whole, which is also what makes the duplicate case correct: a shape
#     arg of `[2, 2]` is a TWO-src STACK whose srcs are the same interned index twice, and
#     hash-consing keys on the src tuple, so it is a different node from a one-src STACK.
#   * `case 1n+p:` is a PREFIX match, so it claims 2, 3, 4, ... and everything after it
#     is DEAD CODE. `bend2-constraints` records this for `case 0n:`; it is equally true
#     of `1n+p`, and it is the more dangerous of the two because the arm looks like a
#     test for "one or more" and silently eats the rest. So the "is it exactly one" test
#     is a `Bool` computed by `Nat.is_eq` and passed in, which is the idiom every other
#     dispatch in this file uses.
def tn_shape_arg.k(+ys: List<&2, U32>, +ar: O.Arena, one: Bool) -> O.Found:
  match one:
    case True{}: O.Found{ar, Maybe.default(&2, U32, List.get(&2, U32, ys, 0n), 0)}
    case _: O.UOp.new(ar, O.OpsSTACK{}, ys, O.ANone{}, O.TNone{})

def tn_shape_arg.n(+ys: List<&2, U32>, +ar: O.Arena, n: Nat) -> O.Found:
  match n:
    case 0n: O.UOp.new(ar, O.OpsSTACK{}, ys, O.ANone{}, O.TNone{})
    case _: tn_shape_arg.k(ys, ar, Nat.is_eq(n, 1n))

def tn_shape_arg.of(+ys: List<&2, U32>, +ar: O.Arena) -> O.Found:
  tn_shape_arg.n(ys, ar, List.length(&2, U32, ys))

def tn_shape_arg(+a: SArg) -> O.Found:
  tn_shape_arg.of(SArg.ys(a), SArg.ar(a))

# ===========================================================================
# THE MOVEMENT DISPATCH. `_mop` (tensor.py:499) is
# `self._apply_uop(UOp._mop, op=op, arg=arg)` and `_rop` (tensor.py:500) is
# `self._apply_uop(UOp._rop, op=op, axis=axis)`: ONE LINE each, and the node
# construction they forward to is `ops.py:821` and `ops.py:655`.
#
# HOISTED, WITH A NOTICE, and the notice is fold.bend's: ops.bend is READ-ONLY to
# this file and carries both as `TODO(p3) ops.py:821` and `TODO(p3) ops.py:655`. A
# one-line def whose callee does not exist cannot be gated at all, and the movement
# dispatch is the largest share of this file that builds a graph, so the body is
# written here. When ops.bend lands it, `tn_mop` and `tn_rop` become the one-liners
# Python has and nothing else in this file changes.
#
# PORTED: the two early NOOPs (ops.py:823-826), the `src_args` split (:827-830),
# `shape_to_shape_arg` (ops.py:106), and the final
# `UOp(op, src=(self,)+UOp.sink(*usrcs).simplify().src)` (:835).
#
# THE `.simplify()` IS A WALL: it is `graph_rewrite` (P3). MEASURED for the six
# movement args this file gates, it is the IDENTITY -- `UOp.sink(x).simplify().src` is
# `(x,)`, `UOp.sink(x, y).simplify().src` is `(x, y)`, and `UOp.sink(c).simplify()` is
# still a SINK -- so the port builds the SINK and reads its srcs. `tn_sink1` and
# `tn_sink2` are the rows that would move if a rewrite ever did reach a shape arg.
#
# THE `Ops.STACK` ARM (ops.py:831-834) needs `dtype_from_uop` and `ccast`, both P3, so
# `MopArg` has no `Ops.STACK` case and a STACK arg is a `TODO(p3)`.
# ===========================================================================

# `arg` is one of three shapes and `op` says which, which is exactly what
# ops.py:827-830 decides after Python has already made `arg` a heterogeneous tuple.
# `APairs` is the TRANSPOSE Python computes with `list(zip(*arg))`: `arg` is a tuple
# of (lo, hi) pairs, one per dim, and the transpose is the list of los and the list of
# his.
type MopArg is Data:
  ADims{ds: List<&2, O.Const>}                 # RESHAPE / EXPAND: `src_args = [arg]`
  APairs{lo: List<&2, O.Const>, hi: List<&2, O.Const>}  # PAD / SHRINK: `list(zip(*arg))`
  AOrder{ys: List<&2, U32>}                    # PERMUTE / FLIP: `src_args = []`

# `if op is Ops.EXPAND and len(arg) == 0: return self` and `if op in {Ops.SHRINK,
# Ops.PAD} and len(arg) == 0: assert len(self.shape) == 0; return self`
# (ops.py:823-826). The `assert` is the fold's RESHAPE gap again, so the LENGTH is
# what is tested and the shape is not: an arm that can only fire on a 0-d source
# cannot change the answer for any source whose shape the fold cannot answer, because
# those are exactly the sources where Python's own `assert` is the only thing that
# would have complained.
def tn_mop.noop.of(+op: O.Op, n: Nat) -> Bool:
  match n:
    case 0n: O.op_in([O.OpsEXPAND{}, O.OpsSHRINK{}, O.OpsPAD{}], op)
    case _: False{}

def tn_mop.arg_len.of(+arg: MopArg) -> Nat:
  match arg:
    case ADims{ds}: List.length(&2, O.Const, ds)
    case APairs{lo, hi}: List.length(&2, O.Const, lo)
    case AOrder{ys}: List.length(&2, U32, ys)

def tn_mop.arg_len(+arg: MopArg) -> Nat:
  tn_mop.arg_len.of(arg)

def tn_mop.noop(+op: O.Op, +arg: MopArg) -> Bool:
  tn_mop.noop.of(op, tn_mop.arg_len(arg))

# RESHAPE / EXPAND: one shape arg, so `usrcs` has one element and the node is
# `UOp(op, src=(self, STACK-or-CONST))`.
def tn_mop.usr1(+ar: O.Arena, ds: List<&2, O.Const>) -> O.Found:
  tn_shape_arg(tn_sarg.acc(ds, SArg{ar, Nil{}}))

# `(self,)+tuple(...)` IS SELF FIRST and `List.append` is `xs ++ ys`, so the head goes
# on the LEFT. Getting it backwards is a silent bug with teeth: `src[0]` is the data, and
# every fold arm, `base`, `marg` and the codegen read it there. `tn_mop_resh` printed
# `CONST STACK BUFFER RESHAPE` where the oracle prints `BUFFER CONST STACK RESHAPE` --
# the same four nodes, the same arities, and the WRONG GRAPH, and NO count row could see
# it. Only the ORDER of the signature catches it, which is the argument for printing the
# toposort and not a set of op names. See the mutation table.
def tn_mop.node2(+ar: O.Arena, +self: U32, +op: O.Op, srcs: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, op, List.append(&2, U32, [self], srcs), O.ANone{}, O.TNone{})

# `UOp(op, src=(self,)+UOp.sink(*usrcs).simplify().src)` (ops.py:835), and it takes
# the whole `usrcs` LIST because the count is what selects the two arms of ops.py:834.
# The SINK is BUILT, because Python builds it too and interns it, so the arena here
# holds the same orphan SINK Python's ucache does; what Python reads off it is its srcs.

def tn_mop.node.of(+ar: O.Arena, +self: U32, +op: O.Op, +usrcs: List<&2, U32>, +sk: O.Found) -> O.Found:
  tn_mop.node2(O.Found.ar(sk), self, op, O.Arena.srcs(O.Found.ar(sk), O.Found.i(sk)))
def tn_mop.node(+ar: O.Arena, +self: U32, +op: O.Op, +usrcs: List<&2, U32>) -> O.Found:
  tn_mop.node.of(ar, self, op, usrcs, O.UOp.sink(ar, usrcs))
def tn_mop.dims2(+self: U32, +op: O.Op, +f: O.Found) -> O.Found:
  tn_mop.node(O.Found.ar(f), self, op, [O.Found.i(f)])

# PAD / SHRINK: two shape args, `list(zip(*arg))`, so the node is
# `UOp(op, src=(self, STACK, STACK))`.
# `tn_shape_arg` ONCE PER HALF, which is the whole of `list(zip(*arg))` followed by
# `[shape_to_shape_arg(a) for a in src_args]` (ops.py:832-834). Concatenating the raw
# CONST indices instead is a real bug and not a cosmetic one: `((0,0),(0,1))` has a
# DUPLICATE 0 in its first half, and Python's `UOp(Ops.STACK, src=(c0, c0))` is a
# two-src node, so the halves are `STACK(0,0)` and `STACK(0,1)` -- two nodes -- and a
# port that concatenated the CONST lists built a FIVE-src PAD.

def tn_mop.dims(+ar: O.Arena, +self: U32, +op: O.Op, ds: List<&2, O.Const>) -> O.Found:
  tn_mop.dims2(self, op, tn_mop.usr1(ar, ds))

# `tn_alu.put`'s rule AGAIN, and this is the second place it bites. `usr1` interns the
# shape arg's CONSTs, so the arena it RETURNS is the one the movement node has to be
# built in; passing `ar` on builds the node in the arena as it was BEFORE the shape arg
# existed, and the node then interns at an index that arena does not have.

def tn_mop.pairs2(+ar: O.Arena, +self: U32, +op: O.Op, usrcs: List<&2, U32>) -> O.Found:
  tn_mop.node(ar, self, op, usrcs)

# `if len(usrcs) == 0: return UOp(op, src=(self,), arg=arg)` (ops.py:834) -- `arg` is
# the order tuple, and `Arg` spells that `ATuple` (ops.py:731).
def tn_mop.pairs(+ar: O.Arena, +self: U32, +op: O.Op, lo: List<&2, O.Const>, hi: List<&2, O.Const>) -> O.Found:
  +a = tn_shape_arg(tn_sarg.acc(lo, SArg{ar, Nil{}}))
  +b = tn_shape_arg(tn_sarg.acc(hi, SArg{O.Found.ar(a), Nil{}}))
  tn_mop.pairs2(O.Found.ar(b), self, op, [O.Found.i(a), O.Found.i(b)])
def tn_mop.order(+ar: O.Arena, +self: U32, +op: O.Op, ys: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, op, [self], O.ATuple{ys}, O.TNone{})

def tn_mop.usr(+ar: O.Arena, +self: U32, +op: O.Op, +arg: MopArg) -> O.Found:
  match arg:
    case ADims{ds}: tn_mop.dims(ar, self, op, ds)
    case APairs{lo, hi}: tn_mop.pairs(ar, self, op, lo, hi)
    case AOrder{ys}: tn_mop.order(ar, self, op, ys)

def tn_mop.of(noop: Bool, +ar: O.Arena, +self: U32, +op: O.Op, +arg: MopArg) -> O.Found:
  match noop:
    case True{}: O.Found{ar, self}
    case _: tn_mop.usr(ar, self, op, arg)

def tn_mop(+ar: O.Arena, +self: U32, +op: O.Op, +arg: MopArg) -> O.Found:
  tn_mop.of(tn_mop.noop(op, arg), ar, self, op, arg)

# ===========================================================================
# `_rop` -- ops.py:655, hoisted. Six steps:
#   axis = tuple(sorted(axis))
#   reduce_axis = tuple(x for x in axis if resolve(self.shape[x] != 1))
#   if not len(reduce_axis): return self.reshape(kept)
#   perm = reduce_axis + tuple(i for i in range(len(self.shape)) if i not in reduce_axis)
#   ret = UOp(Ops.REDUCE, src=(self.permute(perm),), arg=(op, len(reduce_axis)))
#   return ret.reshape(kept) if axis != reduce_axis else ret
#
# HOISTED FROM mixin/movement.py, and the hoist is load-bearing rather than
# convenient: `permute` (:214) ends `return self._mop(Ops.PERMUTE, arg=order_arg) if
# order_arg != tuple(range(self.ndim)) else self` and `reshape` (:185) ends `return
# self if ret.shape == self.shape else ret`. Without those two identity tests `_rop`
# builds a PERMUTE where Python returns `self` and a RESHAPE where Python returns
# `self`, and every fixture disagrees. They are movement.py's lines and they move back
# with movement.bend.
#
# `resolve` (ops.py:445) is symbolic and a concrete dim is already resolved, so the
# `!= 1` test is `fold.bend`'s `bcast_dim.is_uop_or_ne_1`, which is the same predicate
# with the same two cases.
#
# WHAT IS NOT PORTED, and `tn_rop_gap` reports it: the `reduce_axis` filter reads
# `self.shape[x]`, and for a source that is a RESHAPE the fold has no answer
# (fold.bend's `t_gap_ok`). So `tn_rop.ne1` answers `None` there, `tn_rop.reduce` reads
# that as "the filter could not run" and falls back to the empty arm, and the
# multi-dimensional `_rop` fixtures -- which Python builds over a RESHAPE, because
# `Tensor([[1,2],[3,4]])` IS one -- are on the wall list rather than in the gate. The
# 1-D fixtures are BUFFER-rooted and their shape folds, so they are in.
# ===========================================================================

# ONE def and not a `.go`/`.of` split. The pair would call `ins` and be called by it,
# and Bend refuses mutual recursion; a self-call must be IN the def that owns it, so
# `Bool.pick` carries both branches and the self-call is the FALSE one. `Bool.pick` and
# not a `match` because a `match` may not scrutinise `U32.is_lt(x, y)`, which is a call.
def tn_rop.ins(+x: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match acc:
    case Nil{}: [x]
    case y <> t: List.append(&2, U32, [Bool.pick(U32, U32.is_lt(x, y), x, y)],
      Bool.pick(List<&2, U32>, U32.is_lt(x, y), acc, tn_rop.ins(x, t)))

# `axis = tuple(sorted(axis))`, an insertion pass, which is `sorted` for a U32 key. Not
# a general sort: the caller is `_rop` and the axis is `range(ndim)`.
# ONE def and not a three-way split, because `ins.go` and `ins` call each other and
# Bend refuses mutual recursion. `Bool.pick` is the short-circuit: it takes BOTH
# branches as arguments, so the recursive call is an argument and the descent is the
# list TAIL `t`, which is what makes this terminate.

def tn_rop.sorted.go(+axis: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match axis:
    case Nil{}: acc
    case x <> t: tn_rop.sorted.go(t, tn_rop.ins(x, acc))

def tn_rop.sorted(+axis: List<&2, U32>) -> List<&2, U32>:
  tn_rop.sorted.go(axis, Nil{})

def tn_rop.len(+axis: List<&2, U32>) -> Nat:
  List.length(&2, U32, axis)

# `self.shape[x]`, and out of range is Python's `IndexError`, which ops.bend's
# `Arena.src` answers as 0 -- so a 1 is the honest default for "not reducible".
def tn_rop.dim.of(m: Maybe<&2, O.Sint>) -> O.Sint:
  match m:
    case Some{s}: s
    case _: F.sint_of(1)

def tn_rop.dim(+k: List<&2, O.Sint>, +x: U32) -> O.Sint:
  tn_rop.dim.of(List.get(&2, O.Sint, k, U32.to_nat(x)))

# `tuple(x for x in axis if resolve(self.shape[x] != 1))`, and `None` when the fold
# cannot answer the shape at all.
#
# THE ORDER OF THE PARAMETERS IS THE WHOLE TRICK, and it took four compile cycles to
# find. A def may only call defs declared above it, a `.go`/`.step` pair would be
# MUTUAL RECURSION (refused), a def body is ONE EXPRESSION (no statements, no `|>` in
# Bend 2.0.34), and a self-call must read LEFT TO RIGHT with the SHRINKING argument
# first. All four together mean the self-call must be the arm's entire expression, which
# means the `Bool.pick` that appends has to be an ARGUMENT of the self-call. So the list
# is the FIRST parameter -- `ne1(axis, acc, k)` -- the tail `t` is the self-call's first
# argument, and `acc` is the computed one.
#
# `Bool.pick` is strict, so BOTH branches are evaluated: the self-call runs whether or
# not `x` is kept. That is harmless here and it is what makes the walk terminate -- the
# tail is consumed exactly once per element -- but it does mean the filter walks the
# whole axis even when it keeps nothing, which is the same cost Python's generator pays.
#
# The `Maybe` is `tn_rop.ne1.of`'s and not the walk's: the walk is total, and an early
# return from the middle of a self-call would need a second def, and that second def is
# the mutual recursion. So "the fold cannot answer" is decided by the CALLER, which is
# the honest place for it -- the walk does not know about folds.
def tn_rop.ne1(+axis: List<&2, U32>, +acc: List<&2, U32>, +k: List<&2, O.Sint>) -> List<&2, U32>:
  match axis:
    case Nil{}: acc
    case +x <> t: tn_rop.ne1(t, Bool.pick(List<&2, U32>, F.bcast_dim.is_uop_or_ne_1(tn_rop.dim(k, x)),
      List.append(&2, U32, acc, [x]), acc), k)

def tn_rop.ne1.of(ds: Maybe<&2, List<&2, O.Sint>>, +axis: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match ds:
    case Some{k}: Some{tn_rop.ne1(axis, Nil{}, k)}
    case _: None{}

def tn_rop.red2.of(src: U32, +ar: O.Arena, op: O.Op, +rn: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, O.OpsREDUCE{}, [src], O.AReduce{op, U32.from_nat(tn_rop.len(rn))}, O.TNone{})

# `self.permute(perm)` where `perm = reduce_axis + the axes not in reduce_axis`, and
# mixin/movement.py:229's identity test `sorted(order_arg) != list(range(self.ndim))`
# hoisted. It is the
# test that decides whether a PERMUTE node exists at all, so both arms answer `self`:
# the hoist is the TEST, and building the PERMUTE is `tn_mop.order` above.
def tn_rop.perm.of(is_id: Bool, +self: U32) -> U32:
  match is_id:
    case True{}: self
    case _: self

def tn_rop.perm(+ar: O.Arena, +self: U32, +axis: List<&2, U32>, +rn: List<&2, U32>) -> U32:
  tn_rop.perm.of(O.eq_u32(rn, axis), self)

def tn_rop.red2(+ar: O.Arena, +self: U32, op: O.Op, +axis: List<&2, U32>, +rn: List<&2, U32>) -> O.Found:
  tn_rop.red2.of(tn_rop.perm(ar, self, axis, rn), ar, op, rn)

def tn_rop.reduce.of(r: Maybe<&2, List<&2, U32>>, +ar: O.Arena, +self: U32, op: O.Op, +axis: List<&2, U32>) -> O.Found:
  match r:
    case Some{rn}: tn_rop.red2(ar, self, op, axis, rn)
    case None{}: O.Found{ar, self}

def tn_rop.reduce(+ar: O.Arena, +self: U32, op: O.Op, +axis: List<&2, U32>) -> O.Found:
  tn_rop.reduce.of(tn_rop.ne1.of(tn_dims(tn_new(ar, self)), axis), ar, self, op, axis)

# `if not len(reduce_axis): return self.reshape(kept)`. The `kept` is
# `tuple(s for i, s in enumerate(self.shape) if i not in axis)`, and `axis` is EMPTY on
# this arm, so `kept` IS the shape and `reshape` is the identity: this arm returns
# `self`, which is what `rop()` measures on 1-D (`is self` is True).
def tn_rop.of(saxis: List<&2, U32>, n: Nat, +ar: O.Arena, +self: U32, op: O.Op) -> O.Found:
  match n:
    case 0n: O.Found{ar, self}
    case _: tn_rop.reduce(ar, self, op, saxis)

def tn_rop(+ar: O.Arena, +self: U32, op: O.Op, +axis: List<&2, U32>) -> O.Found:
  tn_rop.of(tn_rop.sorted(axis), tn_rop.len(axis), ar, self, op)

# ===========================================================================
# `assign` -- tensor.py:236-274. NINE branches, and the SPINE is the only one that
# builds a graph without device state:
#
#   assign = self.uop.after(store := self.uop.store(x.uop))              -- :259
#   ib = self.uop
#   while ib.op in GroupOp.Movement|{Ops.BITCAST, Ops.DETACH} and not (ib.
#     has_buffer_identity() and _tensor_holds(ib)): ib = ib.src[0]        -- :261
#
# and the other eight arms all want a `Buffer` (WALL 2), `has_buffer_identity` (P3),
# `is_realized` (P3), `UOp.clone` (P3), `least_upper_dtype` on a weak dtype (P4's
# dtype.bend) or `substitute` (WALL 3). So the SPINE is ported and the rest is one
# `TODO(p3)`.
# ===========================================================================

# `UOp.after(self, *src)` is ops.py:621 and ops.bend HAS it (`O.UOp.after`); the STORE
# it wraps is ops.py:616, `UOp(Ops.STORE, src=(self,)+src)`, and ops.bend carries it
# as `TODO(p3) ops.py:616` -- written here for the same reason `tn_mop` is.
def tn_assign_store(+ar: O.Arena, +self: U32, +x: U32) -> O.Found:
  +st = O.UOp.new(ar, O.OpsSTORE{}, [self, x], O.ANone{}, O.TNone{})
  O.UOp.after(O.Found.ar(st), self, [O.Found.i(st)])

# the `ib` walk, tensor.py:261. `GroupOp.movement` IS ported, so the op test is ported
# and the walk is the graph half of `assign` that does not need a Buffer. The
# `has_buffer_identity() and _tensor_holds(ib)` half of the guard is P3 plus WALL 1,
# so `tn_ib_walk` STOPS at the first movement op and `tn_assign` is the `TODO(p3)`
# that needs the full loop. Read the other way: a walk that descends one hop too far
# names a different node, and `tn_ib_walk` is the row that would see it.
def tn_ib_walk.of(mv: Bool, +ar: O.Arena, +self: U32) -> U32:
  match mv:
    case True{}: O.Arena.src0(ar, self)
    case _: self

def tn_ib_walk(+ar: O.Arena, +self: U32) -> U32:
  tn_ib_walk.of(O.GroupOp.movement(O.Arena.op(ar, self)), ar, self)

# TODO(p3) tensor.py:236  assign's other eight arms -- WALL 2 (`_buffer`,
# `on_disk`), P3 (`has_buffer_identity`, `is_realized`, `UOp.clone`), WALL 3
# (`substitute`) and P4's dtype (`least_upper_dtype` on a weak dtype).

# ===========================================================================
# `backward` -- tensor.py:475-495. BOTH halves are ported. The SCOPE FILTER is the
# first: `all_uops = self.uop.toposort()` and then
# `t.uop in all_uops and t.is_floating_point() and t.device is not None`.
# `is_floating_point` is `self.dtype.is_float` and `Cls.is_float` is ported. The zip
# that follows is below, and its callee is `mixin/gradient.bend`'s `compute_gradient`,
# so the DEPS header's "`mixin/gradient.py` -- NOT MINE" is no longer true of the walk.
# ===========================================================================

def tn_need_grad.is_float.go(m: Maybe<&2, S.Dt>) -> Bool:
  match m:
    case Some{dt}: S.Dt.is_float(dt)
    case None{}: False{}

def tn_need_grad.wanted.of(in_graph: Bool, m: Maybe<&2, S.Dt>) -> Bool:
  match in_graph:
    case True{}: tn_need_grad.is_float.go(m)
    case _: False{}

def tn_need_grad.wanted(+all_uops: List<&2, U32>, +ar: O.Arena, +u: U32) -> Bool:
  tn_need_grad.wanted.of(Tensors.member(u, all_uops), tn_dtype(tn_new(ar, u)))

def tn_need_grad.put.of(keep: Bool, +u: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match keep:
    case True{}: List.append(&2, U32, acc, [u])
    case _: acc

def tn_need_grad.put(+all_uops: List<&2, U32>, +ar: O.Arena, +u: U32, acc: List<&2, U32>) -> List<&2, U32>:
  tn_need_grad.put.of(tn_need_grad.wanted(all_uops, ar, u), u, acc)

# the arena rides in the loop, not in the record: every scope entry is an index into
# the SAME arena, which is the invariant that makes `Tensors` a list of `U32` at all.
def tn_need_grad.go(+all_uops: List<&2, U32>, +ar: O.Arena, +ts: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ts:
    case Nil{}: acc
    case u <> t: tn_need_grad.go(all_uops, ar, t, tn_need_grad.put(all_uops, ar, u, acc))

def tn_need_grad(+ar: O.Arena, self: U32, scope: Tensors) -> List<&2, U32>:
  tn_need_grad.go(O.UOp.toposort(O.Arena.budget(ar), ar, self), ar, Tensors.ts(scope), Nil{})

# ===========================================================================
# THE ZIP -- tensor.py:490-494. `zip(tensors_need_grad, self.gradient(*tensors_need_grad,
# gradient=gradient))` is TWO facts and the row keeps them apart, because a row that
# cannot tell them apart cannot fail:
#
#   `mixin/op.py:471`  `[self._wrap_uop(grads[x] if x in grads else x.const_like(0))
#                        for x in target_uops]`  -- the ANSWER: one slot per target, in
#                        TARGET ORDER, and a target with no entry in `grads` gets the
#                        ZERO SUBSTITUTE rather than a hole. This is `Bwd.gs`.
#   `tensor.py:493`    `if t.grad is None: t.grad = g` -- the WRITE, and the number of
#                        writes is what `Bwd.ts` LENGTHS. This is `Tensor.grad_set`, which
#                        until now had no caller in the tree.
#
# WHY TWO INSTEAD OF ONE. `const_like(0)` is the substitute that makes the two halves
# DISJOINT: a port that skipped the target instead of substituting it produces the SAME
# `Bwd.gs` (the answer is unchanged) and ONE FEWER write, so a row that printed only the
# answer could not see it. And a port that walked the two lists in the other order produces
# the SAME COUNT and a PERMUTED answer. Neither half sees the other's bug; the row is the
# pair. Measured on the `t_bwd` fixture: see `.agents/slop/BACKWARD-WALK.md`.
# ===========================================================================

# `grads[x] if x in grads else x.const_like(0)` -- mixin/op.py:471, one slot per target.
# `G.gslot` IS the `x in grads` half and `G.GSlot.v_of` the `grads[x]` half, so the ONLY
# thing this def adds is the ELSE. `x.const_like(0)` (ops.py:600) is `CONST(0)._mop(EXPAND,
# x._shape)` and the CONST is a FLOAT literal, which is the DEPS header's second wall
# THE CLAIM IS FALSE AND NOTHING HERE IS MISSING BUT A CALL: a decimal literal IS
# an `F32` (MEASURED: `F32.bits(0.044715)` is CPython's f32 of 0.044715), so
# `O.CFloat{0.044715}` is a legal constant with no exported `Word` in sight, and
# `nn/optim.bend` already constructs `CFloat{...}` NINE TIMES. What is missing is
# the ONE call in THIS file that interns a float literal into a CONST tensor --
# intern). So the substitute is the arena's RESERVED INDEX 0 -- the same `None` convention
# `grad` already carries -- and the gate prints `ZERO` for that slot rather than printing a
# node that would claim to be a float. NAMED DIVERGENCE, and it is the SUBSTITUTE's value
# only: CPython's own decision (`in grads` or not) is what both lanes print.
def tn_bwd_slot(hit: Maybe<&2, G.GSlot>) -> U32:
  match hit:
    case Some{sl}: G.GSlot.v_of(sl)
    case _: 0

# THE ANSWER LIST, one slot per target, in TARGET ORDER. `List.append(a, A, acc, [x])` is
# `acc ++ [x]`, so this APPENDS; a version that prepended would be the same list reversed,
# and over two equal-length lists that reverses WHICH TARGET each gradient lands on without
# changing the count. That is the mutant that separates the two halves of the row.
def tn_bwd_gs.go(+g: G.Grads, ts: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ts:
    case Nil{}: acc
    case u <> t: List.append(&2, U32, [tn_bwd_slot(G.gslot(g, u))], tn_bwd_gs.go(g, t, acc))

def tn_bwd_gs(+g: G.Grads, ts: List<&2, U32>) -> List<&2, U32>:
  tn_bwd_gs.go(g, ts, Nil{})

# THE WRITE. `grads` starts EMPTY, so Python's `grad` is `None` for every target here and
# `if t.grad is None: t.grad = g` is the arm taken. It IS `Tensor.grad_set`, which had no
# caller in the tree until now. The `:494` arm (`t.grad.assign(t.grad + g.to(...))`) needs
# `__add__` and `assign`'s other eight arms, and `:492`'s `g.clone(device=t.device)` is
# WALL 2 -- all three named at the `TODO` below. THE LENGTH of this list is the write COUNT.
def tn_bwd_write.go(+ar: O.Arena, +t: Tensor, g: U32, acc: List<&2, Tensor>) -> List<&2, Tensor>:
  List.append(&2, Tensor, [Tensor.grad_set(t, g)], acc)

# THE ZIP, and it is a TWO-SCRUTINEE match over TWO lists because that is what `zip` is: a
# step exists only where BOTH lists have an element. The scrutinees are in PARAMETER ORDER
# (notes, BACKWARD-WALK's fifth item), so `ts` then `gs`. Three terminating arms because
# `zip` stops at the shorter list, and ONE of the three is the answer's whole length here.
def tn_bwd_pair.go(+ar: O.Arena, ts: List<&2, U32>, gs: List<&2, U32>, acc: List<&2, Tensor>) -> List<&2, Tensor>:
  match ts gs:
    case Nil{} _: acc
    case Nil{} _ <> _: acc
    case _ <> _ Nil{}: acc
    case u <> t g <> r: tn_bwd_write.go(ar, tn_new(ar, u), g, tn_bwd_pair.go(ar, t, r, acc))

def tn_bwd_pair(+ar: O.Arena, ts: List<&2, U32>, gs: List<&2, U32>) -> List<&2, Tensor>:
  tn_bwd_pair.go(ar, ts, gs, Nil{})

# `Bwd` is the pair the ROW prints, and it holds THREE things and not two: the arena
# `compute_gradient` GROWN (this file's rule 5 -- the answer's indices live in the arena
# the walk produced, not the one that went in), the answer, and the written tensors.
type Bwd is Data:
  Bwd{ar: O.Arena, gs: List<&2, U32>, ts: List<&2, Tensor>}

# `backward`'s zip -- tensor.py:490-494. `ts` is `tensors_need_grad` (the filter above, in
# scope order, which is `all_tensors` order upstream), and `root_grad` is upstream's
# `gradient=` argument. `gradient=None` -> `self.const_like(1.0)` (mixin/op.py:468) is the
# FLOAT CONST wall, so the seed is a PARAMETER here and the row supplies one; and the three
# guards at mixin/op.py:465-467 are the refusals `tn_len` already models as a `Maybe`.
def tn_backward.of(+ar: O.Arena, +ts: List<&2, U32>, +root: U32, root_grad: U32) -> Bwd:
  +cs = G.compute_gradient(root, root_grad, ts, ar)
  +ga = G.CState.ar_of(cs)
  Bwd{ga, tn_bwd_gs(G.CState.g_of(cs), ts), tn_bwd_pair(ga, ts, tn_bwd_gs(G.CState.g_of(cs), ts))}

def tn_backward(+ar: O.Arena, +root: U32, scope: Tensors, root_grad: U32) -> Bwd:
  tn_backward.of(ar, tn_need_grad(ar, root, scope), root, root_grad)

# TODO(p3) tensor.py:492  backward's other three arms -- `g.clone(device=t.device)` is
# WALL 2 (`UOp.clone` is ops.py:882), `:493`'s `else` is `assign` plus `__add__`, and
# `mixin/op.py:468`'s `const_like(1.0)` seed needs the float CONST MINTED HERE. The
# PORT CAN: a literal is an `F32` and `nn/optim.bend` builds `CFloat{...}` nine
# times, so this is a missing CALL and not a missing type.

# ===========================================================================
# THE `__i*__` TWELVE AND `__eq__` -- tensor.py:536-549. Twelve methods, each
# `return self.assign(self.<op>(x))`, and the reason they are not here is NOT operator
# overloading -- BEND HAS IT (`bend guide:630`: inside `(.. : T)` the operators call `T.add`
# through `T.mod`). It is the ASSIGNMENT half: `self.assign(...)` MUTATES, and Bend is affine.
# THIS HEADER SAID "Bend has none" AND WAS WRONG; corrected by measurement, not preference. Each is named here
# with the op its sugar resolves to, because that is the part of the line that is
# tensor.py's; the other two thirds are `assign` (above, itself a wall) and
# `mixin/elementwise.py`'s `<op>`, which is not mine.
#
#   tensor.py:536  __iadd__        -> elementwise.py:101  add          Ops.ADD
#   tensor.py:537  __isub__        -> elementwise.py     sub          Ops.SUB
#   tensor.py:538  __imul__        -> elementwise.py:143  mul          Ops.MUL
#   tensor.py:539  __itruediv__    -> elementwise.py     div          Ops.FDIV
#   tensor.py:540  __ifloordiv__   -> elementwise.py     floordiv     Ops.FLOORDIV
#   tensor.py:541  __ipow__        -> elementwise.py     pow          Ops.POW
#   tensor.py:542  __iand__        -> elementwise.py:171  bitwise_and  Ops.AND
#   tensor.py:543  __ior__         -> elementwise.py:185  bitwise_or   Ops.OR
#   tensor.py:544  __ixor__        -> elementwise.py:200  bitwise_xor  Ops.XOR
#   tensor.py:545  __ilshift__     -> elementwise.py:353  lshift       Ops.SHL
#   tensor.py:546  __irshift__     -> elementwise.py:364  rshift       Ops.SHR
#   tensor.py:547  __imatmul__     -> mixin/op.py:394      matmul       -- a WMMA, not an alu
#   tensor.py:549  __eq__          -> elementwise.py     eq           Ops.CMPEQ
#
# The `Ops` each names is the whole of the port that is tensor.py's, and it is here as
# a table rather than as twelve defs because twelve defs that each call a `TODO` wall
# would be twelve lines that say the same thing. `_binop` (elementwise.py:36) is
# `lhs, rhs = self._broadcasted(x, reverse); return lhs.alu(op, rhs)`, and fold.bend
# already has `least_upper_dtypes` and `bcast_shape`, so the ONE line that is missing
# is `_broadcast_to` (mixin/movement.py:128) -- which is why the `__i*__` are not
# ported even though `alu` is.
# TODO(p3) tensor.py:536  __iadd__        assign + elementwise.py:101 (Ops.ADD)
#   -- BLOCKED. IN-PLACE MUTATION, and Bend HAS NO SUCH FORM: the operator is
#   fine (bend guide:630 -- `(a + b : T)` calls `T.add`), but `+=` needs a mutable target.
#   Bend is affine, a `let` rebinds without mutating, and `-x = v` DELETES. So Python's
#   `self.assign(self.add(x))` has no counterpart to overload.
# TODO(p3) tensor.py:537  __isub__        assign + elementwise.py sub (Ops.SUB)
#   -- BLOCKED. IN-PLACE MUTATION, and Bend HAS NO SUCH FORM: the operator is
#   fine (bend guide:630 -- `(a + b : T)` calls `T.add`), but `+=` needs a mutable target.
#   Bend is affine, a `let` rebinds without mutating, and `-x = v` DELETES. So Python's
#   `self.assign(self.add(x))` has no counterpart to overload.
# TODO(p3) tensor.py:538  __imul__        assign + elementwise.py:143 (Ops.MUL)
#   -- BLOCKED. IN-PLACE MUTATION, and Bend HAS NO SUCH FORM: the operator is
#   fine (bend guide:630 -- `(a + b : T)` calls `T.add`), but `+=` needs a mutable target.
#   Bend is affine, a `let` rebinds without mutating, and `-x = v` DELETES. So Python's
#   `self.assign(self.add(x))` has no counterpart to overload.
# TODO(p3) tensor.py:539  __itruediv__    assign + elementwise.py div (Ops.FDIV)
#   -- BLOCKED. IN-PLACE MUTATION, and Bend HAS NO SUCH FORM: the operator is
#   fine (bend guide:630 -- `(a + b : T)` calls `T.add`), but `+=` needs a mutable target.
#   Bend is affine, a `let` rebinds without mutating, and `-x = v` DELETES. So Python's
#   `self.assign(self.add(x))` has no counterpart to overload.
# TODO(p3) tensor.py:540  __ifloordiv__   assign + elementwise.py floordiv
#   -- BLOCKED. IN-PLACE MUTATION, and Bend HAS NO SUCH FORM: the operator is
#   fine (bend guide:630 -- `(a + b : T)` calls `T.add`), but `+=` needs a mutable target.
#   Bend is affine, a `let` rebinds without mutating, and `-x = v` DELETES. So Python's
#   `self.assign(self.add(x))` has no counterpart to overload.
# TODO(p3) tensor.py:541  __ipow__        assign + elementwise.py pow (Ops.POW)
#   -- BLOCKED. IN-PLACE MUTATION, and Bend HAS NO SUCH FORM: the operator is
#   fine (bend guide:630 -- `(a + b : T)` calls `T.add`), but `+=` needs a mutable target.
#   Bend is affine, a `let` rebinds without mutating, and `-x = v` DELETES. So Python's
#   `self.assign(self.add(x))` has no counterpart to overload.
# TODO(p3) tensor.py:542  __iand__        assign + elementwise.py:171 (Ops.AND)
#   -- BLOCKED. IN-PLACE MUTATION, and Bend HAS NO SUCH FORM: the operator is
#   fine (bend guide:630 -- `(a + b : T)` calls `T.add`), but `+=` needs a mutable target.
#   Bend is affine, a `let` rebinds without mutating, and `-x = v` DELETES. So Python's
#   `self.assign(self.add(x))` has no counterpart to overload.
# TODO(p3) tensor.py:543  __ior__         assign + elementwise.py:185 (Ops.OR)
#   -- BLOCKED. IN-PLACE MUTATION, and Bend HAS NO SUCH FORM: the operator is
#   fine (bend guide:630 -- `(a + b : T)` calls `T.add`), but `+=` needs a mutable target.
#   Bend is affine, a `let` rebinds without mutating, and `-x = v` DELETES. So Python's
#   `self.assign(self.add(x))` has no counterpart to overload.
# TODO(p3) tensor.py:544  __ixor__        assign + elementwise.py:200 (Ops.XOR)
#   -- BLOCKED. IN-PLACE MUTATION, and Bend HAS NO SUCH FORM: the operator is
#   fine (bend guide:630 -- `(a + b : T)` calls `T.add`), but `+=` needs a mutable target.
#   Bend is affine, a `let` rebinds without mutating, and `-x = v` DELETES. So Python's
#   `self.assign(self.add(x))` has no counterpart to overload.
# TODO(p3) tensor.py:545  __ilshift__     assign + elementwise.py:353 (Ops.SHL)
#   -- BLOCKED. IN-PLACE MUTATION, and Bend HAS NO SUCH FORM: the operator is
#   fine (bend guide:630 -- `(a + b : T)` calls `T.add`), but `+=` needs a mutable target.
#   Bend is affine, a `let` rebinds without mutating, and `-x = v` DELETES. So Python's
#   `self.assign(self.add(x))` has no counterpart to overload.
# TODO(p3) tensor.py:546  __irshift__     assign + elementwise.py:364 (Ops.SHR)
#   -- BLOCKED. IN-PLACE MUTATION, and Bend HAS NO SUCH FORM: the operator is
#   fine (bend guide:630 -- `(a + b : T)` calls `T.add`), but `+=` needs a mutable target.
#   Bend is affine, a `let` rebinds without mutating, and `-x = v` DELETES. So Python's
#   `self.assign(self.add(x))` has no counterpart to overload.
# TODO(p3) tensor.py:547  __imatmul__     assign + mixin/op.py:394 -- a WMMA, not an alu
# TODO(p3) tensor.py:549  __eq__          elementwise.py eq (Ops.CMPEQ)
#   -- BLOCKED. `==` IS THE TYPE COMPARISON IN BEND, NOT A VALUE ONE: bend guide:632 --
#   "Equality of values is a call, `T.is_eq(a, b)`; `==` is only the type." So `__eq__` has no
#   operator to be, and the port names `T.is_eq` where it needs the comparison. This is NOT the
#   `__i*__` blocker: there the operator exists and the assignment does not; here it is reversed.
# ===========================================================================

# ===========================================================================
# THE REALIZE PATH -- tensor.py:167-225. THE FOREIGN SEAM, and the whole of it is
# three `TODO(p3)`s. They are here, in Python's order and with the wall each CALL
# names, because "the realize path is a wall" is only useful if the next reader can see
# which call in each body is the wall.
#
# `linear_with_vars` (tensor.py:167-210), 44 lines, the calls in order:
#   :167 `@rewrite_group(...)`                              P3, WALL 3
#   :171 `graph_rewrite(sink, PatternMatcher([]))`         P3, WALL 3
#   :173 `u.dtype in dtypes.weaks and u.device is not None` PORTED (fold)
#   :176 `{x.base for x in sink.src}`                        PORTED (fold)
#   :178 `x.op in {STAGE, DETACH, CONTIGUOUS_BACKWARD}`      PORTED (op_in)
#   :179 `x.storage_base`                                   P3, ops.py:801
#   :184 `x.replace(src=...)`                                P3, ops.py:310
#   :185 `UOp.new_buffer`                                    WALL 2
#   :186 `u.needs_storage()`                                 P3, ops.py:780
#   :192 `src.is_virtual or src.on_disk() or src.has_buffer_identity()`   P3
#   :194 `contiguous_mops_to_view(None, u, src)`             SCHEDULE
#   :196 `UOp.new_buffer(...).reshape(...).shrink_to(...)`   WALL 2
#   :197 `src.axis`                                          P3, ops.py:718
#   :198 `buf.unshard(src.axis)`                             P3, ops.py:692
#   :204 `graph_rewrite(u.src[0], pm_drop_after)`            P3, WALL 3
#   :207 `UOp.sink(...).substitute(becomes_map, walk=True)`  P3, WALL 3
#   :210 `create_linear_with_vars(sink)`                     SCHEDULE
# TODO(p3) tensor.py:167  linear_with_vars -- SCHEDULE (`create_linear_with_vars`,
# `contiguous_mops_to_view`, `is_store_after`) + WALL 3 + WALL 2 + P3's
# `storage_base`, `needs_storage`, `is_virtual`, `on_disk`, `has_buffer_identity`,
# `max_shard_shape`, `axis`, `replace`, `unshard`.
#
# `schedule_linear` (tensor.py:212-216) is three lines on top of it -- the sink, the
# `assert len(var_vals) == 0`, and the linear -- so it is the SAME wall and not a
# second one.
# TODO(p3) tensor.py:212  schedule_linear -- `linear_with_vars`, unchanged.
#
# `realize` (tensor.py:219-225) is `to_realize = [x for x in (self,)+lst if
# x.uop.base.needs_storage()]`, then `run_linear`. The filter is P3 (`needs_storage`,
# ops.py:780) and the run is the engine.
# TODO(p3) tensor.py:219  realize -- P3's `needs_storage` and `engine/realize.py`'s
# `run_linear`. The `@disable_gc()` decorator is `contextlib`, a P6 effect, and is not
# a def.
# ===========================================================================

# ===========================================================================
# THE DEVICE HALF. Every one of these is WALL 2, and they are listed rather than left
# out because THE LIST IS THE DELIVERABLE: this is the exact set of tensor.py's methods
# that a Tensor-shaped port cannot have until there is a `Buffer`.
# ===========================================================================

# TODO(p3) tensor.py:38   _fromnp      -- `UOp.new_buffer` + `buffer.allocate`
# TODO(p3) tensor.py:153  as_param     -- `UOp.param_like` is ops.py:1239, P3
# TODO(p3) tensor.py:156  call         -- `UOp.call_with_output` + a `grad_fxn` kwarg
# TODO(p3) tensor.py:159  custom_kernel -- `UOp.custom_kernel`
# TODO(p3) tensor.py:276  _buffer      -- `x.realize().uop.buffer`
# TODO(p3) tensor.py:285  _data        -- `memoryview`
# TODO(p3) tensor.py:287  data         -- WALL 2, and `dtypes.fmt` with it
# TODO(p3) tensor.py:306  tolist       -- WALL 2, and the `_tolist` recursion is a
#                                         nested-forward tree printer, which
#                                         bend2-constraints records as refused
# TODO(p3) tensor.py:328  numpy        -- WALL 2, and numpy is a foreign module
# TODO(p3) tensor.py:344  clone        -- `UOp.clone` is ops.py:882, `empty_like` plus
#                                         `after(store(src.cast))`, so the AFTER/STORE
#                                         spine is ported above and only the
#                                         `empty_like` is missing
# TODO(p3) tensor.py:353  to           -- `canonicalize_device`, `is_disk_device`,
#                                         `empty_like`, `clone`, `copy_to_device`
# TODO(p3) tensor.py:369  to_          -- `to` + `replace`
# TODO(p3) tensor.py:377  shard        -- `UOp.shard` is ops.py:757 and `_resolve_dim`
#                                         is mixin/movement.py
# TODO(p3) tensor.py:395  shard_       -- `shard` + `replace`
# TODO(p3) tensor.py:401  shard_like   -- `shard` + `to`
# TODO(p3) tensor.py:411  from_blob    -- an external pointer
# TODO(p3) tensor.py:425  from_url     -- `helpers.fetch`
# TODO(p3) tensor.py:441  manual_seed  -- class-level mutable state
# TODO(p3) tensor.py:459  _next_counter -- the same, plus slicing and `assign`
# TODO(p3) tensor.py:502  __setitem__  -- `backward_slice`, `is_realized`,
#                                         `_base_buffer_is_realized` and
#                                         mixin/elementwise.py's `_getitem`
# TODO(p3) tensor.py:530  __delitem__  -- `raise TypeError`, and `__bool__`'s wall
# TODO(p3) tensor.py:553  decode_hevc_frame -- `Variable.unbound` and
#                                         `Ops.CUSTOM_FUNCTION`
#
# AND THE METADATA HALF, which is a third thing: tensor.py:570-591 is a
# `contextvars`-free mutable class (`_ContextVar`), a decorator (`_metadata_wrapper`)
# and a REFLECTION loop that wraps every Tensor method with it. Bend has no `setattr`,
# no `inspect` and no mutable class state, and the metadata itself is
# `all_metadata[new_uop] = (metadata,)` at :107, which is the `Maybe<&2, Metadata>`
# ops.bend already carries on a `Found` (ops.bend:1996) and never populates.
# TODO(p3) tensor.py:107  all_metadata     -- ops.bend has the reader and no writer,
#                                             because the writer needs a scope threaded
#                                             through `_apply_uop`
# TODO(p3) tensor.py:570  _ContextVar      -- mutable class state
# TODO(p3) tensor.py:578  _metadata_wrapper -- a closure, so a def it RETURNS
# TODO(p3) tensor.py:588  the TRACEMETA loop -- `inspect.getmembers` + `setattr`

# ===========================================================================
# THE GATE.
#
# EVERY ROW IS A GRAPH SHAPE, and the shape is the SIGNATURE of the toposort:
# `n=<count> OP/<nsrc> OP/<nsrc> ...` in DFS-postorder, with the BARE enum name
# (`O.Ops.name.of`, which is `Enum.name`, not `str(enum)`). The oracle is CPython:
# `.agents/slop/tensor-oracle.py` prints the same string for the same expression, and
# the two files' outputs are diffed. NOTHING is executed, because the point is that
# tensor.py's oracle runs without hardware.
#
# The `n=` COUNT is in every signature row on purpose. A boolean row that says "the ADD
# is there" cannot see a missing CONST, and `tn_alu3` exists because `tn_alu2` would
# pass against a `tn_alu` that dropped the third src.
#
# A COUNT row of its own, `tn_arena`, is the arena size after `tn_mop_pad` -- the
# BEND-only number, since Python's ucache is global and shared and its length depends on
# every fixture that ran before it. It pins the orphan SINK that `tn_mop.node` builds, so
# a `tn_mop` that stopped building the SINK would still pass all seven movement rows and
# move this one.
#
# The `tn_alu*` rows call `tn_alu` and not `O.UOp.alu`, and the `tn_mop*`/`tn_rop*` rows
# call `tn_mop`/`tn_rop`, because a gate row that calls the SUBSTRATE is a row about
# ops.bend and not about this file.
# ===========================================================================

# the fixture BUFFER. `UOp.new_buffer(device, size, dtype, num)` is ops.py:853 and is
# WALL 2, but the NODE it builds is not device state -- it is `UOp(Ops.BUFFER,
# src=UOp.device_range_src(device), arg=ParamArg(slot, dtype, size=size,
# device=device, buffer=buf))`, and for a single device `device_range_src` is `()`
# (ops.py:851). So the node is buildable and the `buffer=buf` field is left `None`,
# which is the ONE field of `ParamArg` that needs a device. These are the gate's
# fixtures, not the port's, and the header says so.
def g_buf.arg(slot: U32, size: U32, dt: S.Dt) -> O.ParamArg:
  # slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image,
  # buffer, bind_on_realize, val -- ops.bend's `ParamArg`, in its order.
  O.ParamArg{slot, dt, Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

def g_buf(+ar: O.Arena, slot: U32, size: U32, dt: S.Dt) -> O.Found:
  O.UOp.new(ar, O.OpsBUFFER{}, Nil{}, O.AParam{g_buf.arg(slot, size, dt)}, O.TNone{})

# a `Tensor([1, 2, 3, 4], device='PYTHON')`: one BUFFER, int32, size 4.
def g_t4() -> O.Found:
  g_buf(O.Arena.empty(), 0, 4, S.int32())

def g_t4a(+ar: O.Found) -> O.Found:
  g_buf(O.Found.ar(ar), 0, 4, S.int32())

# A SCALAR `float32` BUFFER -- `ParamArg(slot, f32)` with NO size, which is what
# `oracle-cg.py:36`'s `ParamArg(0, dtypes.float32)` builds and what answers shape `()`.
# `g_buf` cannot build one: its `size` is a `U32` and every row above needs a sized buffer.
# THE REASON the `backward` fixture is scalar and not `(4,)`: `gradient.py:132-133` sums a
# SHAPED edge's gradient to its source's shape, and that needs `broadcast_axes` (ops.py:89)
# -- which is the port's named wall AND a place CPython ITSELF raises on a scalar seed over
# a shaped graph (`RuntimeError: cannot broadcast (4,) into ()`, MEASURED, not reasoned).
# Scalar shapes are the only place BOTH lanes answer, so scalar shapes are what the row is
# built on.
def g_sbuf(+ar: O.Arena, slot: U32) -> O.Found:
  O.UOp.new(ar, O.OpsBUFFER{}, Nil{},
    O.AParam{O.ParamArg{slot, S.single(), None{}, None{}, None{}, None{}, S.AGlobal{},
      Some{S.D1{0}}, False{}, None{}, None{}, False{}, None{}}}, O.TNone{})

# EVERY FIXTURE TAKES THE INCOMING ARENA. Two `Found`s from two `Arena.empty()`s are two
# arenas, and an index means nothing outside its own, so a fixture that built its lhs and
# rhs from separate empties would silently intern the ADD over the SAME index twice. It
# typechecks, and it prints `CONST/0 ADD/2` where Python prints two CONSTs -- so the `n=`
# in the signature is what caught it, and that is the argument for a COUNT in every row.
def g_c5(ar: O.Arena) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(5)})

def g_c2a() -> O.Found:
  O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(2)})

def g_c3(+f: O.Found) -> O.Found:
  O.UOp.const(O.Found.ar(f), O.CInt{H.i64_of_i32(3)})

def g_c2(+f: O.Found) -> O.Found:
  O.UOp.const(O.Found.ar(f), O.CInt{H.i64_of_i32(2)})

def g_c1(+f: O.Found) -> O.Found:
  O.UOp.const(O.Found.ar(f), O.CInt{H.i64_of_i32(1)})

# --- the printers, and they are ABOVE every row that uses them (see the header) ---

def t_row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

# `t_row` is a BOOL row and `tn_sig` prints a name and a signature together, so a row that
# prints a STRING needs the third spelling. `mixin/gradient.bend`'s gate calls it `srow`.
def t_srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# `Maybe` has no `is_none`, and the two rows that need one are the two that report a
# RAISE (`__len__`'s `TypeError` and `replace`'s `assert`), so the predicate is written
# once here rather than at each.
def tn_none(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{x}: False{}
    case _: True{}

def tn_none_t(m: Maybe<&2, Tensor>) -> Bool:
  match m:
    case Some{x}: False{}
    case _: True{}

def tn_sig.go(xs: List<&2, U32>, +ar: O.Arena, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +u <> t: tn_sig.go(t, ar,
      String.concat([acc, O.Ops.name.of(O.Arena.op(ar, u)), "/", U32.show(O.Arena.nsrc(ar, u)), " "]))

def tn_sig.print(nm: String, +xs: List<&2, U32>, +ar: O.Arena) -> IO(Unit):
  IO.print(String.concat([nm, "=", tn_sig.go(xs, ar,
    String.concat([U32.show(U32.from_nat(List.length(&2, U32, xs))), " "]))]))

def tn_sig(nm: String, +ar: O.Arena, i: U32) -> IO(Unit):
  tn_sig.print(nm, O.UOp.toposort(O.Arena.budget(ar), ar, i), ar)

# --- 1-5: the const and alu rows -------------------------------------------------

def t_const5() -> IO(Unit):
  +f = tn_const(O.Arena.empty(), O.CInt{H.i64_of_i32(5)})
  tn_sig("tn_const5", Tensor.ar(f), Tensor.u(f))

def t_constT() -> IO(Unit):
  +c = g_c5(O.Arena.empty())
  +f = tn_const(O.Found.ar(c), O.CBool{True{}})
  tn_sig("tn_constT", Tensor.ar(f), Tensor.u(f))

# `Tensor(5).alu(Ops.ADD, Tensor(3))`.
def t_alu2() -> IO(Unit):
  +a = g_c5(O.Arena.empty())
  +b = g_c3(a)
  +t = tn_alu(tn_new(O.Found.ar(b), O.Found.i(a)), O.OpsADD{}, [O.Found.i(b)])
  tn_sig("tn_alu2", Tensor.ar(t), Tensor.u(t))

# THE SRC-ORDER ROW, and it exists because `tn_alu2` CANNOT see the order: its two srcs
# are both `CONST`, so `src=(self, other)` and `src=(other, self)` print the SAME
# signature and a `tn_alu` that put `self` LAST passed every other alu row. M15 measured
# that. This row's srcs are a `BUFFER` and a `CONST`, so the two orders print differently
# and `tn_alu` has to be right about `UOp.alu`'s `(self, *src)` (ops.py:630).
def t_alu_ord() -> IO(Unit):
  +a = g_buf(O.Arena.empty(), 0, 2, S.single())
  +k = g_c5(O.Found.ar(a))
  +t = tn_alu(tn_new(O.Found.ar(k), O.Found.i(a)), O.OpsADD{}, [O.Found.i(k)])
  tn_sig("tn_alu_ord", Tensor.ar(t), Tensor.u(t))

# THREE srcs. `tn_alu2` would pass against a `tn_alu` that dropped the third, and the
# COUNT in the signature is what sees it.
def t_alu3() -> IO(Unit):
  +a = g_c5(O.Arena.empty())
  +b = g_c3(a)
  +c = g_c2(b)
  +t = tn_alu(tn_new(O.Found.ar(c), O.Found.i(a)), O.OpsMUL{}, [O.Found.i(b), O.Found.i(c)])
  tn_sig("tn_alu3", Tensor.ar(t), Tensor.u(t))

# a ONE-src alu, which is `alu(Ops.DETACH)` and is the only unary in this file.
def t_alu_det() -> IO(Unit):
  +a = g_c5(O.Arena.empty())
  +t = tn_alu(tn_new(O.Found.ar(a), O.Found.i(a)), O.OpsDETACH{}, Nil{})
  tn_sig("tn_alu_det", Tensor.ar(t), Tensor.u(t))

# --- 6-12: the movement dispatch, six `arg`s and the two early NOOPs --------------

def tn_mop.k(n: U32) -> O.Const:
  O.CInt{H.i64_of_i32(n)}

def t_mop_resh() -> IO(Unit):
  +b = g_t4()
  +f = tn_mop(O.Found.ar(b), O.Found.i(b), O.OpsRESHAPE{}, ADims{[tn_mop.k(2), tn_mop.k(2)]})
  tn_sig("tn_mop_resh", O.Found.ar(f), O.Found.i(f))

# `len(arg) == 0` on an EXPAND: `return self`, and the row is the ONE that can see an
# early NOOP that was not taken, because every other movement row has a non-empty `arg`
# and would not move.
def t_mop_exp0() -> IO(Unit):
  +b = g_t4()
  +f = tn_mop(O.Found.ar(b), O.Found.i(b), O.OpsEXPAND{}, ADims{Nil{}})
  tn_sig("tn_mop_exp0", O.Found.ar(f), O.Found.i(f))

# a ONE-element ADims, and it is the row that sees `shape_to_shape_arg`'s middle arm:
# one element is the CONST ITSELF and NOT a STACK.
def t_mop_exp() -> IO(Unit):
  +b = g_t4()
  +f = tn_mop(O.Found.ar(b), O.Found.i(b), O.OpsEXPAND{}, ADims{[tn_mop.k(0)]})
  tn_sig("tn_mop_exp", O.Found.ar(f), O.Found.i(f))

# PAD, the two-shape-arg arm: `list(zip(*arg))` of `((0,0),(0,1))` is `([0,0],[0,1])`, so
# the node is `PAD(self, STACK, STACK)`. This is the row that sees the transpose.

def t_mop.pair(lo: U32, hi: U32) -> List<&2, O.Const>:
  [tn_mop.k(lo), tn_mop.k(hi)]

# SHRINK `((0, 2),)`, and THE ROW THAT TEACHES THE TRANSPOSE, because `list(zip(*arg))`
# means TWO DIFFERENT THINGS at ndim 1 and at ndim 2 and both are in this file:
#   * ndim 2, `arg = ((0,0),(0,1))`: `*arg` is TWO tuples, so `zip` pairs them and the
#     transpose is `[(0,0), (0,1)]` -- two 2-element lists, and each is a STACK. That is
#     `tn_mop_pad`.
#   * ndim 1, `arg = ((0,2),)`: `*arg` is the SINGLE tuple `(0,2)`, so `zip` iterates it
#     as a sequence of two INTS and the transpose is `[(0,), (2,)]` -- two 1-element
#     lists, and each is a bare CONST. That is this row, and it is why `tn_mop_shr` is
#     `SHRINK(self, CONST, CONST)` and NOT `SHRINK(self, STACK)`.
# A fixture that passed `lo=[0,0], hi=[0,2]` here -- the ndim-2 shape -- builds a
# two-src STACK on each side and prints `SHRINK/3` over four CONSTs and two STACKs. The
# COUNT catches that and the arity alone does not. See the mutation table, M8.
def t_mop_pad() -> IO(Unit):
  +b = g_t4()
  +f = tn_mop(O.Found.ar(b), O.Found.i(b), O.OpsPAD{}, APairs{t_mop.pair(0, 0), t_mop.pair(0, 1)})
  tn_sig("tn_mop_pad", O.Found.ar(f), O.Found.i(f))
def t_mop_shr() -> IO(Unit):
  +b = g_t4()
  +f = tn_mop(O.Found.ar(b), O.Found.i(b), O.OpsSHRINK{}, APairs{[tn_mop.k(0)], [tn_mop.k(2)]})
  tn_sig("tn_mop_shr", O.Found.ar(f), O.Found.i(f))

# FLIP and PERMUTE, the `src_args = []` arm: no shape arg at all, and the ORDER tuple
# rides in the node's `arg` as `ATuple`. These two rows are the only ones that see
# `tn_mop.order`.
def t_mop_flip() -> IO(Unit):
  +b = g_t4()
  +f = tn_mop(O.Found.ar(b), O.Found.i(b), O.OpsFLIP{}, AOrder{[0]})
  tn_sig("tn_mop_flip", O.Found.ar(f), O.Found.i(f))

def t_mop_perm0() -> IO(Unit):
  +b = g_t4()
  +f = tn_mop(O.Found.ar(b), O.Found.i(b), O.OpsPERMUTE{}, AOrder{Nil{}})
  tn_sig("tn_mop_perm0", O.Found.ar(f), O.Found.i(f))

# --- 13-15: `_rop`, and 16-17 the SINK identity rows -----------------------------

def t_rop0() -> IO(Unit):
  +b = g_t4()
  +f = tn_rop(O.Found.ar(b), O.Found.i(b), O.OpsADD{}, [0])
  tn_sig("tn_rop0", O.Found.ar(f), O.Found.i(f))

# a different `op` and the SAME shape, so a REDUCE that hardcoded `Ops.ADD` would pass
# `tn_rop0` and fail this.
def t_ropmax() -> IO(Unit):
  +b = g_t4()
  +f = tn_rop(O.Found.ar(b), O.Found.i(b), O.OpsMAX{}, [0])
  tn_sig("tn_ropmax", O.Found.ar(f), O.Found.i(f))

# `axis=()` on a 1-D source: `reduce_axis` is empty, so the arm is `self.reshape(kept)`,
# `kept` IS the shape, and the answer is `self`. Python says `is self` is True, so the
# row is the SOURCE and not a new node.
def t_rop_none() -> IO(Unit):
  +b = g_t4()
  +f = tn_rop(O.Found.ar(b), O.Found.i(b), O.OpsADD{}, Nil{})
  tn_sig("tn_rop_none", O.Found.ar(f), O.Found.i(f))

# THE ARG ROW, and it exists because a SIGNATURE PRINTS THE OP AND THE ARITY AND NEVER
# THE ARG -- which is a real hole and mutation M5 measured it: a `_rop` that forwarded
# `OpsMAX` into every REDUCE left all thirteen signature rows untouched, because the node
# is still `REDUCE/1` either way. Python's own `u.arg` is `(Ops.ADD, 1)`, so the oracle
# reads the arg and so does this: `tn_rop_arg=Ops.ADD/1`.

def tn_rop_arg.put(rop: O.Op, num_axes: U32) -> IO(Unit):
  IO.print(String.concat(["tn_rop_arg=", O.Ops.name.of(rop), "/", U32.show(num_axes)]))

def tn_rop_arg.go(arg: O.Arg) -> IO(Unit):
  match arg:
    case O.AReduce{rop, num_axes}: tn_rop_arg.put(rop, num_axes)
    case _: IO.print("tn_rop_arg=not-a-reduce")
def tn_rop_arg.of(ar: O.Arena, i: U32) -> IO(Unit):
  tn_rop_arg.go(O.Arena.arg(ar, i))

def t_rop_arg() -> IO(Unit):
  +b = g_t4()
  +f = tn_rop(O.Found.ar(b), O.Found.i(b), O.OpsADD{}, [0])
  tn_rop_arg.of(O.Found.ar(f), O.Found.i(f))

# THE `.simplify()` WALL, as two rows. `UOp.sink(x).simplify().src == (x,)` and
# `UOp.sink(x, y).simplify().src == (x, y)` in CPython, MEASURED, and these two rows are
# what a rewrite that reached a shape arg would move.
def t_sink1() -> IO(Unit):
  +a = g_c2a()
  +sk = O.UOp.sink(O.Found.ar(a), [O.Found.i(a)])
  tn_sig("tn_sink1", O.Found.ar(sk), O.Found.i(sk))

def t_sink2() -> IO(Unit):
  +a = g_c2a()
  +b = g_c1(a)
  +sk = O.UOp.sink(O.Found.ar(b), [O.Found.i(a), O.Found.i(b)])
  tn_sig("tn_sink2", O.Found.ar(sk), O.Found.i(sk))

# THE `_rop` GAP, and it PRINTS FALSE. `tn_rop` over a RESHAPE cannot read the shape,
# because fold.bend does not answer a movement op's shape, so the `reduce_axis` filter
# cannot run. Python reduces it; this port returns `self`. That is the honest state of
# WALL 5 and the row exists so it cannot be forgotten.
# the row is "DID THE PORT REDUCE", and Python's answer over a RESHAPE source is
# REDUCE, so False here IS the gap. It is a row that must print False: a `tn_rop` that
# somehow learned to fold a RESHAPE's shape would make it True, and that would be a
# change to fold.bend, not to this file.
def tn_rop_gap.of(got: U32, self: U32) -> Bool:
  Bool.not(U32.is_eq(got, self))

def t_rop_gap() -> IO(Unit):
  +b = g_t4()
  +m = tn_mop(O.Found.ar(b), O.Found.i(b), O.OpsRESHAPE{}, ADims{[tn_mop.k(2), tn_mop.k(2)]})
  +f = tn_rop(O.Found.ar(m), O.Found.i(m), O.OpsADD{}, [0])
  t_row("tn_rop_gap", tn_rop_gap.of(O.Found.i(f), O.Found.i(m)))

# --- 18: the assign spine -------------------------------------------------------

def t_assign() -> IO(Unit):
  +h = g_buf(O.Arena.empty(), 0, 2, S.single())
  +h2 = g_buf(O.Found.ar(h), 1, 2, S.single())
  +f = tn_assign_store(O.Found.ar(h2), O.Found.i(h), O.Found.i(h2))
  tn_sig("tn_assign", O.Found.ar(f), O.Found.i(f))

# --- 19-28: the Tensor-level rows, which are not graph shapes --------------------

# `repr(Tensor(5))` and `repr(Tensor(True))`, EXACTLY, including the device column and
# the grad column. Python's strings are the oracle.
def t_repr5() -> IO(Unit):
  +f = tn_const(O.Arena.empty(), O.CInt{H.i64_of_i32(5)})
  IO.print(String.concat(["tn_repr5=", tn_repr(f)]))

def t_reprT() -> IO(Unit):
  +c = g_c5(O.Arena.empty())
  +f = tn_const(O.Found.ar(c), O.CBool{True{}})
  IO.print(String.concat(["tn_reprT=", tn_repr(f)]))

# `len(Tensor(5))` is a TypeError and `len(Tensor([1,2,3]))` is 3, so the two rows are
# the two sides and a `__len__` that never raised would fail the first.
def t_len0() -> IO(Unit):
  +f = tn_const(O.Arena.empty(), O.CInt{H.i64_of_i32(5)})
  t_row("tn_len0", tn_none(tn_len(f)))

def t_len3() -> IO(Unit):
  +b = g_buf(O.Arena.empty(), 0, 3, S.int32())
  t_row("tn_len3", Bool.not(tn_none(tn_len(tn_new(O.Found.ar(b), O.Found.i(b))))))

# THE IMMUTABILITY DIVERGENCE. Python's `is_param_` mutates in place; this returns a new
# record. The row pins BOTH halves -- the new one flipped and the old one still True --
# because a `tn_is_param_` that mutated through a shared arena would pass the first half
# and fail this one.
def tn_param.of(+t: Tensor) -> Bool:
  Bool.and(Bool.not(Tensor.flag(tn_is_param_(t, False{}))), Tensor.flag(t))

def t_param() -> IO(Unit):
  +f = tn_const(O.Arena.empty(), O.CInt{H.i64_of_i32(5)})
  t_row("tn_param", tn_param.of(f))

# `__hash__` is the uop, so two Tensors over one uop agree and one over another does not.
# The test is two-sided on purpose: a `__hash__` that returned the arena size would pass a
# one-sided test.
def tn_hash.of(+x: Tensor, y: Tensor, z: Tensor) -> Bool:
  Bool.and(U32.is_eq(tn_hash(x), tn_hash(y)), Bool.not(U32.is_eq(tn_hash(x), tn_hash(z))))

def t_hash() -> IO(Unit):
  +a = g_c5(O.Arena.empty())
  +b = g_c3(a)
  t_row("tn_hash", tn_hash.of(tn_new(O.Found.ar(b), O.Found.i(a)),
    tn_new(O.Found.ar(b), O.Found.i(a)), tn_new(O.Found.ar(b), O.Found.i(b))))

# `replace` is an `assert` and a mutation: `tn_replace` is the SAME shape (Some) and
# `tn_replace_bad` a different one (None). A `replace` that ignored the assert would move
# the second and not the first.
#
# BOTH ROWS READ `O.Found.ar(b)`, the arena AFTER the second buffer, and that is the
# third time in this file the pre-growth arena has bitten: `O.Found.i(b)` is 2, and
# index 2 does not exist in an arena whose `next` is 2, so `tn_dims` answers `None` and
# `replace` reports the shape mismatch. A `tn_replace` that read `O.Found.ar(a)` printed
# the two rows BACKWARDS -- `tn_replace=False` and `tn_replace_bad=True` -- which is the
# one outcome a two-sided row pair is for.
def t_replace() -> IO(Unit):
  +a = g_buf(O.Arena.empty(), 0, 3, S.int32())
  +b = g_buf(O.Found.ar(a), 1, 3, S.int32())
  t_row("tn_replace", Bool.not(tn_none_t(tn_replace(tn_new(O.Found.ar(b), O.Found.i(a)),
    tn_new(O.Found.ar(b), O.Found.i(b))))))

def t_replace_bad() -> IO(Unit):
  +a = g_buf(O.Arena.empty(), 0, 3, S.int32())
  +b = g_buf(O.Found.ar(a), 1, 4, S.int32())
  t_row("tn_replace_bad", Bool.not(tn_none_t(tn_replace(tn_new(O.Found.ar(b), O.Found.i(a)),
    tn_new(O.Found.ar(b), O.Found.i(b))))))

# --- `as_param` -- tensor.py:153-154. TWO ROWS, and neither is enough alone. ---------
#
# `tn_asparam` is the SIGNATURE: `n=1 PARAM/0`, CPython's `Tensor([1.,2.],
# device='PYTHON').as_param(3).uop.toposort()`. It moves if the op is wrong or if a src
# is added. It is BLIND to the slot, because a signature prints the op and the arity and
# never the arg -- this file's own mutation M5 is that lesson and `tn_rop_arg` exists for
# the same reason.
#
# `tn_asparam_slot` is the ARG: the PARAM's own `ParamArg.slot`, `3`. It moves if the slot
# is dropped or if the SOURCE's slot leaks through (`g_buf`'s is 0, the param's is 3, and
# those two differ -- so a `tn_as_param` that forwarded `O.ParamArg.slot(src)` prints 0
# here). `tn_asparam_src` is the matching NEGATIVE: the SOURCE's slot, still 0, so a port
# that re-slotted in place rather than building a new node would move one row and not the
# other.
def tn_param_slot.of(arg: O.Arg) -> U32:
  match arg:
    case O.AParam{pa}: O.ParamArg.slot(pa)
    case _: O.ParamArg.no_slot()

def tn_asparam_sig.slot(m: Maybe<&2, Tensor>) -> String:
  match m:
    case Some{+t}:
      String.concat(["tn_asparam_slot=",
        U32.show(tn_param_slot.of(O.Arena.arg(Tensor.ar(t), Tensor.u(t))))])
    case None{}: "tn_asparam_slot=declined"

def tn_asparam_sig.ne(m: Maybe<&2, Tensor>, src: U32) -> String:
  match m:
    case Some{+t}: String.concat(["tn_asparam_ne=",
      Bool.show(Bool.not(U32.is_eq(tn_param_slot.of(O.Arena.arg(Tensor.ar(t), Tensor.u(t))), src)))])
    case None{}: "tn_asparam_ne=declined"

def tn_asparam_sig.sig(+ar: O.Arena, i: U32) -> String:
  +xs = O.UOp.toposort(O.Arena.budget(ar), ar, i)
  tn_sig.go(xs, ar, String.concat([U32.show(U32.from_nat(List.length(&2, U32, xs))), " "]))

def tn_asparam_sig.of(m: Maybe<&2, Tensor>) -> String:
  match m:
    case Some{+t}: String.concat(["tn_asparam=", tn_asparam_sig.sig(Tensor.ar(t), Tensor.u(t))])
    case None{}: "tn_asparam=declined"

def tn_asparam_pair(+m: Maybe<&2, Tensor>, src: U32) -> String:
  String.concat([tn_asparam_sig.of(m), " ", tn_asparam_sig.slot(m), " ",
    tn_asparam_sig.ne(m, src)])

def t_asparam.go(ar: O.Arena) -> String:
  +a = g_buf(ar, 0, 2, S.single())
  tn_asparam_pair(tn_as_param(O.Found.ar(a), tn_new(O.Found.ar(a), O.Found.i(a)), 3),
    tn_param_slot.of(O.Arena.arg(O.Found.ar(a), O.Found.i(a))))

def t_asparam() -> IO(Unit):
  IO.print(t_asparam.go(O.Arena.empty()))

# `backward`'s scope filter, as a COUNT. `Tensor([1.0, 2.0])` is float32, so it is in
# scope of `x.sum()` and `t.uop in all_uops` is True for it; the scope also holds a
# CONST, which is `weakint` and so `is_floating_point` is False. The row is the count,
# because "the filter kept the right one" is a boolean that an all-True fixture passes.
def tn_need_grad.n.of(xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat(["tn_needgrad=", U32.show(U32.from_nat(List.length(&2, U32, xs)))]))

def tn_need_grad.n(ar: O.Arena, self: U32, scope: Tensors) -> IO(Unit):
  tn_need_grad.n.of(tn_need_grad(ar, self, scope))

# The scope holds a `float32` BUFFER and a `weakint` CONST, and BOTH ARE IN THE
# TOPOSORT -- the CONST is the REDUCE's operand, so the two `and` terms are separable
# for the first time. A first cut of this fixture put the CONST OUTSIDE the graph, and
# `t.uop in all_uops` was then False for it, so the `is_floating_point` term was
# UNFALSIFIABLE and mutation M12 moved nothing. A scope filter needs a member that fails
# the SECOND term, not one that fails the first; that is the fixture rule this row exists
# to record.
def t_needgrad() -> IO(Unit):
  +a = g_buf(O.Arena.empty(), 0, 2, S.single())
  +k = g_c5(O.Found.ar(a))
  +ad = O.UOp.new(O.Found.ar(k), O.OpsADD{}, [O.Found.i(a), O.Found.i(k)], O.ANone{}, O.TNone{})
  +r = O.UOp.new(O.Found.ar(ad), O.OpsREDUCE{}, [O.Found.i(ad)], O.AReduce{O.OpsADD{}, 1}, O.TNone{})
  tn_need_grad.n(O.Found.ar(r), O.Found.i(r),
    Tensors.of_list([O.Found.i(a), O.Found.i(k), O.Found.i(ad)]))

def tn_bwd_slot_sig(zero: Bool, +ar: O.Arena, g: U32) -> String:
  match zero:
    case True{}: "ZERO "
    case _: tn_sig.go(O.UOp.toposort(O.Arena.budget(ar), ar, g), ar, "")

def tn_bwd_sig.go(gs: List<&2, U32>, +ar: O.Arena, acc: String) -> String:
  match gs:
    case Nil{}: acc
    case +g <> t: tn_bwd_sig.go(t, ar, String.concat([acc, tn_bwd_slot_sig(U32.is_zero(g), ar, g)]))

# `tn_sig.go` is NOT reusable for a slot: it prints a COUNT and takes a toposort, and a slot
# is ONE node. `ZERO` is the substitute, and WHICH slots are substitutes is CPython's own
# `in grads` decision (mixin/op.py:471's else arm) -- the CPython lane prints `ZERO` for the
# same reason, so the token is not a port invention.
def tn_bwd_row.of(b: Bwd) -> String:
  match b:
    case Bwd{ar, gs, ts}: String.concat([tn_bwd_sig.go(gs, ar, ""),
      "| writes=", U32.show(U32.from_nat(List.length(&2, Tensor, ts)))])

# `Tensor.grad_set` READ BACK OUT OF THE TENSOR. `tn_bwd_row`'s `writes` says the writer was
# CALLED; this says WHAT IT WROTE, and it is the only row in this file that can see a
# `grad_set` that stores the wrong index or stores nothing at all -- the writer was DEAD
# until this row's fixture gave it a caller, so nothing else in 35 rows looked at it. The
# LAST written slot is target 1, the DETACH, which is the one with a real gradient.
def tn_bwd_last.go(ws: List<&2, Tensor>, acc: U32) -> U32:
  match ws:
    case Nil{}: acc
    case w <> t: tn_bwd_last.go(t, Tensor.grad_of(w))

def tn_bwd_last.sig(+ws: List<&2, Tensor>, +ar: O.Arena) -> String:
  tn_bwd_slot_sig(U32.is_zero(tn_bwd_last.go(ws, 0)), ar, tn_bwd_last.go(ws, 0))

def tn_bwd_grad.of(b: Bwd) -> String:
  match b:
    case Bwd{ar, gs, ts}: tn_bwd_last.sig(ts, ar)

# THE FIXTURE, and ONE def because `compute_gradient` GROWS the arena and every row below
# must read the GROWN one -- this file's rule 5, and the reason `Bwd` carries an arena.
# It is `(x*3).sum()`, and the SCOPE holds the f32 BUFFER, the REDUCE and the weakint
# CONST, so the filter's second term is falsifiable here too (the CONST is in the
# toposort as the MUL's operand and is still dropped).
def tn_bwd_fix() -> Bwd:
  +a = g_sbuf(O.Arena.empty(), 0)
  +b = g_sbuf(O.Found.ar(a), 1)
  +c = g_sbuf(O.Found.ar(b), 2)
  +k = g_c3(c)
  +mu = tn_alu(tn_new(O.Found.ar(k), O.Found.i(a)), O.OpsMUL{}, [O.Found.i(b)])
  +in = tn_alu(tn_new(Tensor.ar(mu), O.Found.i(a)), O.OpsADD{}, [O.Found.i(c)])
  +ad = tn_alu(tn_new(Tensor.ar(in), Tensor.u(in)), O.OpsADD{}, [O.Found.i(k)])
  +rt = tn_alu(tn_new(Tensor.ar(ad), Tensor.u(mu)), O.OpsADD{}, [Tensor.u(ad)])
  +sd = O.UOp.const(Tensor.ar(rt), O.CInt{H.i64_of_i32(1)})
  tn_backward(O.Found.ar(sd), Tensor.u(rt),
    Tensors.of_list([O.Found.i(a), O.Found.i(b), O.Found.i(c), O.Found.i(k)]), O.Found.i(sd))

def t_bwd_row() -> String:
  +b = tn_bwd_fix()
  tn_bwd_row.of(b)

def t_bwd_grad() -> String:
  +b = tn_bwd_fix()
  tn_bwd_grad.of(b)

# THE BEND-ONLY ARENA COUNT, and it exists for the orphan SINK. Seven signature rows
# would all still pass against a `tn_mop` that never built the SINK, and this is the row
# that sees it.
def t_arena() -> IO(Unit):
  +b = g_t4()
  +f = tn_mop(O.Found.ar(b), O.Found.i(b), O.OpsPAD{}, APairs{t_mop.pair(0, 0), t_mop.pair(0, 1)})
  IO.print(String.concat(["tn_arena=", U32.show(O.Arena.next(O.Found.ar(f)))]))

# `Tensors.holds` and `Tensors.member` are the two registry readers, and this row is
# two-sided: a `holds` that always answered True would pass the first half and fail the
# second.
def tn_holds.of(+x: O.Found, y: O.Found) -> Bool:
  Bool.and(Tensors.holds(Tensors.of_list([O.Found.i(x)]), O.Found.i(x)),
    Bool.not(Tensors.holds(Tensors.of_list([O.Found.i(x)]), O.Found.i(y))))

def t_holds() -> IO(Unit):
  +a = g_c5(O.Arena.empty())
  +b = g_c3(a)
  t_row("tn_holds", tn_holds.of(a, b))


def t_param_old() -> IO(Unit):
  +f = tn_const(O.Arena.empty(), O.CInt{H.i64_of_i32(5)})
  t_row("tn_param_old", Tensor.flag(f))


def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_const5()
    b : Unit <- t_constT()
    c : Unit <- t_alu2()
    d : Unit <- t_alu3()
    d2 : Unit <- t_alu_ord()
    e : Unit <- t_alu_det()
    f : Unit <- t_mop_resh()
    g : Unit <- t_mop_exp0()
    h : Unit <- t_mop_exp()
    i : Unit <- t_mop_pad()
    j : Unit <- t_mop_shr()
    k : Unit <- t_mop_flip()
    l : Unit <- t_mop_perm0()
    m : Unit <- t_rop0()
    n : Unit <- t_ropmax()
    o : Unit <- t_rop_none()
    o2 : Unit <- t_rop_arg()
    p : Unit <- t_sink1()
    q : Unit <- t_sink2()
    r : Unit <- t_rop_gap()
    s : Unit <- t_assign()
    u : Unit <- t_repr5()
    v : Unit <- t_reprT()
    w : Unit <- t_len0()
    x : Unit <- t_len3()
    y : Unit <- t_param()
    z : Unit <- t_hash()
    aa : Unit <- t_replace()
    ab : Unit <- t_replace_bad()
    ac : Unit <- t_needgrad()
    ap : Unit <- t_asparam()
    ad : Unit <- t_arena()
    ae : Unit <- t_param_old()
    t_holds()
    t_srow("tn_bwd_row", t_bwd_row())
    t_srow("tn_bwd_grad", t_bwd_grad())


# ===========================================================================
# THE MUTATION TABLE, MEASURED, and re-runnable:
#
#     .venv/bin/python .agents/slop/tensor-mutate.py
#
# Seventeen one-token edits, each applied, run, and reverted. 15 of the 17 move at
# least one row; the two that move NOTHING are reported below rather than quietly
# dropped, because a mutation that moves nothing is a measurement of what the gate does
# NOT see and it is the most useful line in the table.
#
# M18-M20 ARE NOT IN `tensor-mutate.py`: they are measured by
#     sh .agents/slop/backward/bwd-mutate.sh <arm>
# because that harness is the one with the CLOSURE HASH LEDGER and the BYTE ASSERTION, and
# `backward`'s zip spans two files (`tensor.bend` and `mixin/gradient.bend`), so a plant
# there needs a substrate check that `tensor-mutate.py` does not have.
#
# THE GATE ITSELF, and the 29 SHARED ROWS:
#     sh .agents/slop/tensor-gate.sh
# `--check-only` is `ALL PROOFS CHECK`, the interpreted and native lanes are byte
# identical, and the 29 rows both lanes can print are byte identical to CPython. The one
# DESIGNED disagreement is `tn_rop_gap` (WALL 5) and the three BEND-ONLY rows are
# `tn_arena`, `tn_param_old` and `tn_holds`; the script lists all four rather than
# filtering them silently.
#
# | mutation | the edit | rows that MOVED | what it is testing |
# | --- | --- | --- | --- |
# | M1 | `tn_mop.node2`: `[self] ++ srcs` -> `srcs ++ [self]` | `tn_mop_resh` `tn_mop_exp` `tn_mop_pad` `tn_mop_shr` | `(self,)+srcs` is SELF FIRST (ops.py:835). THE ROW THIS FILE WAS BUILT ON: the buggy version had the same four nodes and the same arities and the WRONG GRAPH, and no COUNT could see it. Only the ORDER of the signature does, which is why the gate prints a toposort and not a set of op names. |
# | M2 | `tn_shape_arg.n`: `Nat.is_eq(n, 1n)` -> `False{}` | `tn_mop_exp` `tn_mop_shr` | `shape_to_shape_arg`'s middle arm: ONE element is the CONST ITSELF and not a STACK (ops.py:110). Also the `1n+p` prefix-match trap, which is why the test is a `Bool` parameter. |
# | M3 | `tn_mop.noop.of`: drop `OpsEXPAND{}` from the op set | `tn_mop_exp0` | the early NOOP `if op is Ops.EXPAND and len(arg) == 0` (ops.py:823). LOCALISED: every other movement row has a non-empty `arg` and does not move, so this row is the only thing that can see a NOOP that was not taken. |
# | M4 | `tn_rop.ins`: `U32.is_lt` -> `U32.is_le` | **NOTHING** | a NEGATIVE, and the gate's limit. Every `_rop` fixture has a ONE-element axis, and one element never compares, so `sorted`'s strictness is unobservable here. It is a real hole and it is not closed: the fix is a two-element `axis` fixture, which needs a two-dimensional source, which needs a RESHAPE, which is WALL 5. |
# | M5 | `tn_rop.red2.of`: `AReduce{op,..}` -> `AReduce{OpsMAX{},..}` | `tn_rop_arg` | the `op` `_rop` forwards into the REDUCE arg (tensor.py:500). This row was ADDED because M5 originally moved NOTHING: a signature prints the op and the arity and NEVER THE ARG, so a wrong reduce-op is invisible to all thirteen signature rows. The hole was real and the row closes it. |
# | M6 | `tn_assign_store`: drop the `AFTER` | `tn_assign` | the `self.uop.after(store := ...)` half of the assign spine (tensor.py:259). |
# | M7 | `tn_is_param_`: read `Tensor.flag(t)` instead of the parameter | `tn_param` | `is_param_(self, is_param)` (tensor.py:125). |
# | M8 | the SHRINK FIXTURE: `APairs{[0],[2]}` -> `APairs{[0,0],[0,2]}` | `tn_mop_shr` | the `zip(*arg)` transpose, which means two DIFFERENT things at ndim 1 and ndim 2. The COUNT catches it; the arity alone would not, because both fixtures give `SHRINK/3`. |
# | M9 | `tn_repr.grad.of`: swap the two arms | `tn_repr5` `tn_reprT` | `__repr__`'s grad column and the reserved-index-0 `None` (tensor.py:131). Two rows because the repr is a STRING and both fixtures print it. |
# | M10 | `tn_len.first`: the `Nil{}` arm returns `Some{0}` | `tn_len0` | `__len__`'s `if not self.shape: raise TypeError` (tensor.py:139). LOCALISED: `tn_len3` has a non-empty shape and does not move. |
# | M11 | `tn_replace.same.go`: always `True{}` | `tn_replace_bad` | `replace`'s `assert self.shape == x.shape` (tensor.py:232). The PAIR is the point: `tn_replace` does not move, so a `replace` that ignored the assert entirely would pass one row and fail the other. |
# | M12 | `tn_need_grad.is_float.go`: always `True{}` | `tn_needgrad` | `backward`'s `is_floating_point` term (tensor.py:487). This row was REWRITTEN because M12 originally moved NOTHING: the first fixture put the `weakint` CONST outside the graph, so `t.uop in all_uops` was already False for it and the second term was unfalsifiable. A scope filter needs a member that fails the SECOND term. |
# | M13 | `tn_mop.node`: build the SINK in a FRESH arena | `tn_mop_resh` `tn_mop_exp` `tn_mop_pad` `tn_mop_shr` `tn_arena` | the orphan SINK of `UOp.sink(*usrcs).simplify().src` (ops.py:835), and a CORRECTION to a claim this file made earlier. `tn_arena` was written to be the LOCALISED row that sees the SINK; measured, it does NOT: a fresh arena also breaks the indices, so all five move together. `tn_arena` is an ARENA count and not a toposort count, and what it actually pins is that the arena does not grow where Python's ucache does not either. |
# | M14 | `tn_rop.reduce.of`: reduce anyway when the fold cannot answer | `tn_rop_gap` | the `_rop` GAP arm (WALL 5). A one-sided row on purpose: it PRINTS FALSE and M14 is the only mutation that makes it print True. |
# | M15 | `tn_alu.of`: `[uop] ++ srcs` -> `srcs ++ [uop]` | `tn_alu_ord` | `UOp.alu`'s `src=(self, *src)` (ops.py:630). `tn_alu_ord` was ADDED for this: its srcs are a BUFFER and a CONST, so the two orders print DIFFERENT signatures, while `tn_alu2`'s two CONSTs print the same one either way round. |
# | M16 | `tn_rop.of`: drop the `case 0n` arm | `tn_rop_none` | `if not len(reduce_axis): return self.reshape(kept)` (ops.py:659). LOCALISED: `tn_rop0` and `tn_ropmax` have a non-empty axis. |
# | M17 | a no-op edit | **NOTHING** | a control. A mutation table with no row that CANNOT move is a table of coincidences. |
# | M18 | `tn_bwd_gs.go`: `[slot] ++ tail` -> `tail ++ [slot]` | `tn_bwd_row` `tn_bwd_grad` | the ANSWER LIST's ORDER, `mixin/op.py:471`'s `for x in target_uops`. `writes` is UNCHANGED and the signature PERMUTES, so this is the arm that proves `tn_bwd_row`'s COUNT half is blind. |
# | M19 | `tn_bwd_write.go`: drop the `grad_set` answer | `tn_bwd_row` `tn_bwd_grad` | the `.grad` WRITER. `writes` goes 3 -> 0 and the signature is UNCHANGED (the answer is built before the zip), so this is the arm that proves `tn_bwd_row`'s SIGNATURE half is blind. **This is the state the file shipped in all session: a `grad_set` with no caller and nothing to read it.** |
# | M18/M19 are the SEPARATION, and it is measured per half by
# `.agents/slop/backward/bwd-mutate.sh`, which prints each half's verdict separately. A
# one-part row would have called one of them green. |
#
# THREE OF THESE FOUND REAL BUGS IN THIS FILE, and all three are the same bug wearing
# different clothes: AN ARENA IS THE ONE A BUILD RETURNED, not the one that went in.
# `tn_alu.of`, `tn_mop.dims` and three gate fixtures each built a node in the arena as it
# was BEFORE the node was interned, and every symptom was a plausible-looking number --
# `NOOP/0`, an empty toposort, a five-src PAD, and `tn_replace`'s two rows BACKWARDS. The
# reason the gate caught all of them is that every row is DERIVED FROM PYTHON rather than
# restated from this file, and the reason two of them survived a first pass is that the
# COUNT was the only thing that saw them.
# ===========================================================================