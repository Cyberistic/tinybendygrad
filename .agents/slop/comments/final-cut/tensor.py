import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/tensor.bend"

EDITS = [
  # ---- THE HEADER (130 lines) -> 4 lines: what the file is, and the three differences.
  (9, 138, """# tensor.bend -- tinygrad/tensor.py. The user-facing Tensor: lazy op construction, the
# method surface, and the `realize` entry.
#
# THE DIFFERENCES FROM UPSTREAM, three of them: a `Data` record is immutable, so every method
# Python spells as in-place mutation RETURNS A NEW TENSOR; `grad: Tensor|None` is a `U32` whose 0
# is `None`; and `__hash__` is `id(self)` in Python, so two Tensor OBJECTS over one uop hash
# differently here, while an arena index is the node's identity.
#
# THE WALLS, each a named `TODO(p3)` below: device state (`all_tensors`, `Buffer`), `UOp.substitute`
# (`graph_rewrite`), and the schedule cluster (`linear_with_vars`, `realize`)."""),

  # ---- Tensors.holds.go
  (153, 159, """# `t.uop is u` -- tensor.py:34's `_tensor_holds`. An index identity in this port, so it is a
# walk, and `Bool.pick` IS the short-circuit because a `.of`/`.go` pair would be mutual
# recursion and Bend refuses that."""),

  # ---- THE TENSOR
  (174, 189, """# THE TENSOR -- tensor.py:44, `__slots__ = "uop", "is_param", "grad"` (:55). It carries the
# ARENA as well, which Python gets for free: an arena index is only meaningful in the arena that
# produced it and every op in this file grows it.
#
# tensor.py:65 -- "tensors can have gradients if you have called .backward". The flag is not
# "this tensor is differentiable" -- it is "a gradient has been computed for this tensor".
#
# THE READERS -- tensor.py:143-149. All three are fold properties, so all three are a DOUBLE
# `Maybe`: the OUTER `None` is "this fold cannot answer this node" and the INNER one is
# Python's own `None`."""),

  # ---- tn_new / tn_alu.put
  (253, 259, """# `alu` -- tensor.py:116, and `UOp.alu` is `UOp(op, src=(self, *src))` (ops.py:630), which
# ops.bend has. `alu` is a def here and not a call to `O.UOp.alu` at each site because the arena
# is the store the index lives in, so a method that reads `self.uop` has to read `self`'s arena
# too."""),

  # ---- tn_alu.put's warning (a BUG THAT WAS FOUND -- keep the one sentence)
  (265, 273, """# WRAP A `Found` AS A `Tensor`: `tn_alu.put` AND NOTHING ELSE. `Found.ar` is the arena the
# build RETURNED, so `O.Found.i(f)` is only meaningful in it, and writing `tn_new(Tensor.ar(t),
# O.Found.i(c))` by hand names the arena the CALLER had before `c` was interned -- the failure is
# quiet (a node that is its own src, a `NOOP` bottom read out of range, or a LEGAL but WRONG
# index) and no gate caught it. USE `tn_alu.put`. It cannot be written wrong."""),

  # ---- tn_binop's arena rule
  (278, 288, """# THE ARENA RULE, in one spelling. `Arena` is an immutable `Data` value, so a `Found`
# SNAPSHOTS the arena it was built in and an index is legal only in an arena DESCENDING FROM the
# one that minted it -- append-only, so a prefix's indices still name the same nodes.
# `O.Arena.merge` (`ops.bend`, beside `UOp.new`) re-interns `other`'s nodes into `base`, so two
# SIBLING arenas get a common descendant and `other`'s index is re-minted before it is read."""),

  # ---- the sibling-arena bug (a BUG THAT WAS FOUND -- keep the measurement)
  (312, 344, """# SIBLING ARENAS: WAS A WALL, NOW CLOSED. The binops used to build with `tn_alu(lhs, OP,
# [Tensor.u(rhs)])`, which builds in `lhs.ar` and reads `rhs.u` THERE. MEASURED, `O.Rng.sig`
# (`ops.bend:802`) on `tn_add` with `lhs` a bare `CInt{3}` and `rhs` derived to depth N in its
# OWN arena:
#
#   rhs depth 0 (a bare const)   ok=True   sig `2 Ops.ADD/2 Ops.CONST Ops.CONST`
#   rhs depth 1 (one `tn_neg`)   ok=False  sig `1 Ops.ADD/2 Ops.CONST Ops.ADD`
#   rhs depth 2 (two `tn_neg`)   ok=False  sig `3 Ops.ADD/2 Ops.CONST Ops.NOOP`
#
# Depth 0 WAS RIGHT BY COINCIDENCE: `rhs.u` was a legal index in `lhs.ar` that happened to hold
# `lhs`'s own CONST. Depth 1 was SELF-REFERENTIAL and depth 2 read the `NOOP` bottom. No gate saw
# it: every `mk_tensor` in `gates/*.bend` makes each operand a bare const from `O.Arena.empty()`,
# so the depth was always 0. `gates/tn_binop_arena-gate.py` varies the depth and now answers 1
# at 0, 1 and 2 with ZERO divergences.
#
# THE CLOSURE IS `O.Arena.merge`: it re-interns the right operand's nodes into the left one's, so
# the sibling case gets a common descendant and the index is re-minted before it is read. There
# was no such primitive before -- VERIFIED at the time: `grep -nE "def [a-zA-Z_.]*\\(.*ar: Arena.*,
# .*ar2?: Arena"` over `ops.bend` and `tensor.bend` answered exactly one hit, `UOp.group.of`.
#
# `UOp.alu` RETURNS a `Found` because the arena grew, and passing the INCOMING `ar` on to
# `tn_new` builds a Tensor whose index points into the arena as it was BEFORE the node was
# interned, and every read of it then answers the `ABad` bottom."""),

  # ---- tn_sqrt / rsqrt
  (419, 427, """# `rsqrt` -- elementwise.py:820. `return self.sqrt().reciprocal()`. The wall text calls this
# "free of literals; blocked on sqrt's own fold, not on a constant" -- that note is now STALE:
# the chain is built by `tn_alu`, not by a fold. The SECOND `tn_alu` is on the SQRT node, not on
# `t`: `reciprocal` reads its `self` as the implicit first src, and `self` IS the sqrt result."""),

  # ---- tn_where
  (432, 445, """# `where` -- elementwise.py:426. The no-broadcasting case (both x and y are already Tensors of
# the same shape) is portable: the body reduces to `tn_alu(cond, O.OpsWHERE{}, [Tensor.u(x),
# Tensor.u(y)])`, the same `tn_alu` builder with three src nodes, and `O.UOp.where`
# (uop/ops.bend:2865) is the primitive this delegates to. The broadcasting case stays walled on
# the SHAPE FOLD (mixin/movement.py:24).
#
# three operands, three arenas, two merges. `tn_binop` covers the two-operand node and this is
# the shape it cannot reach: `x` and `y` are re-minted in TURN and the accumulator is read at the
# end, so both indices are minted in a PREFIX of the arena the WHERE is built in."""),

  # ---- tn_bitwise_not
  (461, 496, """# `bitwise_not` -- elementwise.py:145, body at :156-157. three arms, and all three are
# PORTED. The BOOL arm is `tn_logical_not` ABOVE. The SIGNED arm is `self ^ -1` =
# `XOR(self, CONST(-1))`, and `-1` is `CInt{H.i64_of_i32(4294967295)}` -- two's complement,
# because `i64_of_i32` SIGN-EXTENDS a U32. The UNSIGNED arm is THE SAME GRAPH with `dtype.max`
# in place of `-1`: MEASURED in CPython the max stays a `CONST` of `weakint` and is NOT
# promoted, so the graph is `XOR(CAST u8, CONST weakint 255)` with no CAST of its own.
#
# `Maybe<&2, Tensor>` and not `Tensor`, and the `Maybe` is one dtype wide. CPython's `dtype.max`
# is a Python `int` with no width limit; `S.Dt.max` (LAWS/spec.bend:219) answers `None` past 32
# bits, so an unsigned dtype wider than `u32` is a REFUSAL here and not a wrong graph -- the
# graph it would have to build instead (`^ -1` on a `u64`) is WRONG.
#
# the dtype read is not a wall in this file, and the old header's reason for that claim was
# wrong: the fold is not a CONTEXT to be threaded but a READ of the arena the tensor already
# carries, so the fold handed in is `F.folded(Tensor.ar(t))`."""),

  # ---- tn_neg
  (540, 551, """# `neg` -- elementwise.py:74. TWO ARMS, and BOTH are ported here. The bool arm IS
# `tn_logical_not`; the arith arm is `self * (-1)` = `MUL(self, -1)`. The `-1` literal is
# `H.i64_of_i32(4294967295)` -- the two's complement pair, because `i64_of_i32` SIGN-EXTENDS a
# U32 (`mixin/elementwise.bend:474`'s `ew_neg.go` builds the same). The dtype gate is `tn_dtype`,
# a fold property, and the `None{}` arm falls through to the arith branch as the conservative
# answer."""),

  # ---- tn_invert
  (578, 587, """# `__invert__` -- elementwise.py:264. `return self.bitwise_not()`. The arith arms (`self ^
# dtype.max` for unsigned, `self ^ -1` for signed, elementwise.py:157) stay walled on the dtype
# fold + arith ops. So `__invert__` is ONE-ARM PORTABLE: the BOOL arm returns
# `tn_logical_not(t)`, the arith arm is `None`. A refusal is a `None`, not a `TODO(p3)`."""),

  # ---- tn_mul
  (601, 607, """# `__mul__` -- elementwise.py:125. `return self._binop(Ops.MUL, x, reverse)`. For a TENSOR rhs
# (the only case the gate covers), `_broadcasted` is the identity, so the port is `tn_alu(self,
# MUL, [Tensor.u(rhs)])`. The `reverse` flag is CPython's -- when True, the rhs becomes the
# implicit first src -- and the port covers both arms the same way `tn_neg.go` covers its two."""),

  # ---- tn_add
  (626, 636, """# `__add__` -- elementwise.py:267. `return self.add(x)`. The no-broadcasting case (both `self`
# and `x` are Tensors of the same shape) is the body reduced to `tn_alu(self, ADD, [x.uop])` if
# `not reverse`, or `tn_alu(x, ADD, [self.uop])` if `reverse`. CPython's `add` writes it as
# `a.alu(Ops.ADD, -b)` (elementwise.py:84, :123) for the dtype-promotion case, but the `-b` is
# a CONST trap: for a TENSOR `b`, `-b` is `-self` (also walled). The dispatch is a `Bool` flag
# the same way `tn_mul.go` and `tn_neg.go` are."""),

  # ---- tn_sub
  (648, 657, """# `__sub__` -- elementwise.py:270. `return self.sub(x)`. The no-broadcasting case is portable:
# `_binop`'s body with `Ops.SUB` instead of `Ops.MUL`. CPython's `sub` (elementwise.py:103) also
# writes `a.alu(Ops.ADD, -b)` -- the dtype-promotion trap is the same one `add` has.
#
# THE `-1` LITERAL, interned in the operand's own arena and wrapped as a Tensor so `tn_binop`
# can merge it. `H.i64_of_i32(4294967295)` is two's complement -1 and `i64_of_i32`
# sign-EXTENDS, the same literal `tn_neg.arith` uses."""),

  # ---- CPython's sub is NOT alu(SUB) -- a BUG THAT WAS FOUND
  (666, 676, """# CPYTHON'S `sub` IS NOT `alu(SUB)`. `elementwise.py:103` reads, with the docstring
# stripped, `a, b = self._broadcasted(x, reverse)` then `return a.alu(Ops.ADD, -b)` -- so `-`
# builds `ADD(a, MUL(b, -1))` and `Ops.SUB` IS NEVER BUILT BY IT. MEASURED on CPython for
# `Tensor(3) - Tensor(7)`: `ADD(CONST(), MUL(CONST(), CONST()))`. VERIFIED that the name is not
# merely unused here: `grep -rn "Ops\\.SUB" tinygrad/ | grep "\\.py:"` answers 24 and 23 of them
# are `X86Ops.SUB`, a different enum.
#
# `gates/tn_add_sub-oracle.py` called `c.alu(Ops.SUB, d)` -- a path CPython's `sub` never takes
# -- so the oracle agreed with the port while both were wrong. The oracle now calls the DUNDER."""),

  # ---- tn_cmplt
  (688, 694, """# `__lt__` -- elementwise.py:321. `return self._binop(Ops.CMPLT, x, False)`. The
# no-broadcasting case (two same-shape Tensors): the body collapses to `tn_alu(self, CMPLT,
# [Tensor.u(x)])`. The `reverse` flag covers `__gt__` (elementwise.py:324), which swaps the
# order. The broadcasting case stays walled on the SHAPE FOLD (mixin/movement.py:24)."""),

  # ---- tn_relu6
  (734, 741, """# `relu6` -- elementwise.py:697. `((r := self.relu()) < 6).where(r, 6)`. Same shape as
# `tn_relu`: a chain of `tn_rcmplt` and `tn_where`, with the only difference being the constant
# (6 instead of 0) and the `r` variable holding the relu result."""),

  # ---- tn_ceil
  (759, 772, """# `ceil` -- elementwise.py:656. `(self > (b := self.trunc())).where(b+1, b)`. `tn_trunc` is
# ported (tensor.bend:399), the arith is `tn_add(b, c1t)` -- `tn_add` is ported (tensor.bend:678)
# and the CONST 1 is `tn_ceil.c1` (a `O.UOp.const`, ported at uop/ops.bend:2984) wrapped by
# `tn_alu.put`, the one spelling that cannot name the wrong arena. The cond `(self > b)` is
# `tn_rcmplt(self, b)` and the `where(cond, b+1, b)` is `tn_where`."""),

  # ---- tn_floor
  (796, 804, """# `floor` -- elementwise.py:662. `(self < (b := self.trunc())).where(b-1, b)`. Same shape as
# `tn_ceil` with `b-1` (a CONST SUB via `tn_sub`) and `tn_cmplt` (the forward CMPLT) instead of
# `tn_rcmplt`. The cond is `tn_cmplt(self, b)` (NOT `tn_rcmplt` -- the FLOOR inequality is the
# forward `<`)."""),

  # ---- minimum / eq
  (867, 879, """# `minimum` is NOT ported, and NOT for a missing MIN op: CPython's `Tensor.minimum`
# (mixin/elementwise.py:393) has NO MIN -- it is `self._broadcasted(x)` then a dtype branch, and
# BOTH arms are built from `Ops.MAX`. `MIN` is not a member of CPython's `Ops` (verified:
# `.venv/bin/python -c "from tinygrad.uop.ops import Ops; print('MIN' in Ops.__members__)"`
# -> False), and the port's `Ops` and CPython's `Ops` are the SAME 77 members, so no constructor
# is missing. Stays walled on the dtype-promotion seam: even the no-broadcasting case branches
# on `least_upper_dtype(t.dtype, x.dtype)` and `tn_binop` does not promote.
#
# `eq`'s ONE `CMPEQ` NODE. `tn_cmplt`'s SHAPE with `Ops.CMPEQ` instead of `Ops.CMPLT`."""),

  # ---- tn_ne -- a BUG THAT WAS FOUND (the pre-pin spelling)
  (888, 907, """# `ne` -- elementwise.py:332 AT `f5ac54685074` -- is `self.eq(x).logical_not()`, and
# `eq` is `_binop(Ops.CMPEQ, x, False)` and `logical_not` is `cast(bool).eq(False)`. SO `ne` IS
# TWO NODES DEEP: `CMPEQ(CMPEQ(x, y), CONST(False))`.
#
# MEASURED 2026-11-10 ON CPYTHON AT THE PIN, IN BOTH DIRECTIONS:
#   `a != b`  ->  `CMPEQ(CMPEQ(a, b), CONST(False))`
#   `3 != a`  ->  `CMPEQ(CMPEQ(3, a), CONST(False))`
#
# THE PRE-PIN SPELLING WAS `self._binop(Ops.CMPNE, x, False)` -- ONE `CMPNE` NODE -- SO THE
# NAME DID NOT CHANGE AND THE NODE COUNT DID. AND UPSTREAM's OWN `symbolic.py:349` KEYS ITS
# NEGATION TEST ON `CMPEQ` WITH A `CONST 0` -- so a graph that says `CMPNE` is NOT upstream's
# graph."""),

  # ---- the shift/pow block
  (969, 984, """# `__lshift__` -- elementwise.py:366, via `lshift` at elementwise.py:344
# (`self._binop(Ops.SHL, x, reverse)`). Same shape as `tn_and` with `Ops.SHL`. The `reverse` arm
# is `__rlshift__` (elementwise.py:372). The broadcasting case stays walled on the SHAPE FOLD.
# `__rshift__` -- elementwise.py:369, via `rshift` at elementwise.py:355
# (`self._binop(Ops.SHR, x, reverse)`). Same shape as `tn_lshift` with `Ops.SHR`. The `reverse`
# arm is `__rrshift__` (elementwise.py:375). The broadcasting case stays walled on the SHAPE FOLD.
# `__pow__` -- elementwise.py:569, via `pow` at elementwise.py:548. For two Tensors of the same
# shape (the no-broadcasting case the gate covers), `_broadcasted` is the identity and the body is
# `tn_alu(self, POW, [Tensor.u(x)])`. The `reverse` arm is `__rpow__` (elementwise.py:572). The
# broadcasting case stays walled on the SHAPE FOLD."""),

  # ---- tn_floordiv
  (996, 1011, """# `__floordiv__` -- elementwise.py:279. `return self.div(x, rounding_mode="floor")`, and
# `div` (elementwise.py:229) ends in `return a.alu(Ops.DIV, b)` for int dtypes. For two Tensors
# of the same shape with int dtypes the no-broadcasting case: `_broadcasted` is the identity, and
# the body collapses to `tn_alu(self, DIV, [Tensor.u(x)])` for `__floordiv__` (srcs `(self, x)`)
# and `tn_alu(x, DIV, [Tensor.u(self)])` for `__rfloordiv__` (srcs `(x, self)`).
# The `__truediv__` arm is NOT ported: its body is `cast(self, default_float).alu(FDIV, b)` past
# the int-arm guard, and `cast` plus the `default_float` constant need fold reads the port does
# not carry."""),

  # ---- tn_mod
  (1023, 1033, """# `__mod__` -- elementwise.py:282, via `mod` at elementwise.py:202
# (`self._binop(Ops.MOD, x, reverse)`). Same shape as `tn_pow.go` with `Ops.MOD` instead of
# `Ops.POW`: for two Tensors of the same shape, `_broadcasted` is the identity and the body is
# `tn_alu(self, MOD, [Tensor.u(x)])`. The float arm (`return a - a.div(b, rounding_mode="floor")
# * b`, elementwise.py:214) stays walled on the dtype fold and on `div`'s float arm. The
# broadcasting case stays walled on the SHAPE FOLD."""),

  # ---- tn_ge
  (1045, 1051, """# `__ge__` -- elementwise.py:327. `return (self < x).logical_not()`. `logical_not`
# (elementwise.py:57) IS `self.cast(bool).eq(False)`, which `tn_logical_not` builds
# (`CAST(bool) -> CMPEQ(cast, CONST(False))` -- gated 8/8, gates/tn_logical_not-gate.py). So
# `tn_logical_not(tn_cmplt(t, x))` is a fully-portable chain."""),

  # ---- tn_eq -- a BUG THAT WAS FOUND
  (1062, 1076, """# `eq` -- elementwise.py:335 AT `f5ac54685074` -- is `self._binop(Ops.CMPEQ, x, False)`, so
# it is ONE `CMPEQ` NODE and NOT a negation of a `CMPNE`.
#
# THE NAME DID NOT CHANGE AND THE NODE DID: the pre-pin spelling was `self.ne(x).logical_not()`,
# which builds `CMPNE(CMPNE(x, y), CONST(True))`; at the pin it is `_binop(Ops.CMPEQ, x, False)`,
# which builds `CMPEQ(x, y)`. MEASURED 2026-11-10 ON CPYTHON AT THE PIN: `a.eq(b)` emits
# `CMPEQ(a, b)`.
#
# AND UPSTREAM's OWN `symbolic.py:349` KEYS ITS NEGATION TEST ON `CMPEQ` WITH A `CONST 0` -- so a
# graph that says `CMPNE` is NOT upstream's graph."""),

  # ---- tn_isfinite
  (1088, 1097, """# `isfinite` -- elementwise.py:623. `(self.isinf() | self.isnan()).logical_not()`.
# `isinf` itself is `self.eq(inf) + self.eq(-inf)`, inlined here in the same shape as
# `mo_isfinite` (`mixin/op.bend:1066`) because the `tn_*` layer has no `tn_isinf` to call. The
# four CONSTs are built off the NEWEST arena each time -- the same `mo_arena` rule
# `mo_isfinite` was written against. Gated at `gates/tn_isfinite-gate.py` 4/4 rows."""),

  # ---- tn_isinf's eq
  (1104, 1112, """# `self.eq(inf)` -- `eq` IS `_binop(Ops.CMPEQ, x, False)` (`mixin/elementwise.py:335-336` AT
# THE PIN `f5ac54685074`), SO THE NODE IS `CMPEQ(self, inf)` -- ONE NODE, AND NOT
# `logical_not(CMPNE(self, inf))`, WHICH IS WHAT THIS DEF USED TO BUILD."""),

  # ---- promote
  (1121, 1142, """# `promote` -- elementwise.py:29-33, `_broadcasted`'s inner closure, for `self` ALONE against
# the weakfloat `inf` const. `out_dtype` is therefore `least_upper_dtype(self.dtype, weakfloat)`
# and the arm that decides everything is `weak_dtype(out_dtype)`: weakfloat for a strong float,
# weakint for a concrete int, and for a WEAK self `weak_dtype(weakint) = weakint`, which is what
# makes a weakint `self` REMINT to `CONST weakfloat 4.0` while `self != self` -- whose
# `out_dtype` is `weakint` and whose weak arm is therefore the identity -- keeps
# `CONST weakint 4`. MEASURED in CPython, `.venv/bin/python` on
# `Tensor(UOp(Ops.CONST, arg=4)).isfinite()`: FIVE distinct CONST leaves,
# `weakint 4 | bool True | weakfloat 4.0 | inf | -inf`, 15 nodes.
#
# THE FOUR ARMS ARE `_broadcasted`'s FOUR, and each conjunct is borrowed rather than
# re-derived: `O.UOp.is_invalid` is ops.py:267, `W.wk_is_weak_const` is `op is CONST AND dtype in
# dtypes.weaks` (bool is NOT in it), `F.least_upper.of` is the hoisted lattice, `W.weak_dtype` is
# dtype.py:175, and `W.wk_remint` is `remint` -- WHICH LIVES IN `uop/weak.bend` BECAUSE OF THIS
# CALL."""),

  # ---- tn_binop's `p`
  (1162, 1171, """# `p` is the promoted `self`, and both `eq` halves read it -- not `t` and not `ep`. CPython's
# body is `self.eq(+inf)*True + self.eq(-inf)*True` with `self` on BOTH sides, and each
# `_broadcasted` remints it to the SAME hash-consed node; the old spelling compared `ep` (the
# positive arm's bool MUL) against `-inf`, which was `CMPNE(MUL, CONST)` where CPython has
# `CMPNE(CONST, CONST)`. Same node COUNT, wrong graph -- and NO row saw it, because every row in
# this file's two gates reads the TOP node or its SRC ops, and that CMPNE is a src of a src."""),

  # ---- _apply_uop
  (1189, 1196, """# `_apply_uop` -- tensor.py:104-113. `new_uop: UOp = fxn(*[t.uop for t in srcs], kwargs)`
# is a CALLBACK, and Bend has no function values, so every op in this file is its own def that
# builds the node and then calls `tn_new`. The wall is the one `uop/upat.bend` records for
# `upat_compile`: the closure cannot be stored, so the call is inlined at each site."""),

  # ---- const
  (1202, 1209, """# `const` -- tensor.py:122. `Tensor(UOp.const(b, dtype))`.
# TODO(p3) tensor.py:122  const's `dtype` -- ops.bend's `UOp.const` is the BARE CONST, because
# `dtypes.from_py` and `truncate` are P3 (ops.py:632). A CONST of a CONCRETE dtype is ONE node
# here and `CONST`+`CAST` in Python; the value arrives already truncated and the dtype is the
# CONST's own.
# TODO(p3) tinygrad/dtype.py:39  symbol=ConstType  -- a float `ConstType` --
# `F32{data: Word(32n)}` has no reachable constructor (`Word` is not exported and `U32.to_f32` is
# a LAW), so `Tensor(1.0)` has no constant to intern. INT and BOOL do."""),

  # ---- __hash__
  (1218, 1230, """# `__hash__` -- tensor.py:134. `return id(self)`, and an arena index IS a graph node's
# identity in this port, so `__hash__` is the uop. THE DIFFERENCE, and it is why `_tensor_holds`
# reads the uop rather than a hash: Python's `id` separates two Tensor OBJECTS over one uop and
# this does not.
#
# tensor.py:131 -- "Python has a non moving GC, so this should be okay". The comment is about
# `id(self)` being a STABLE identity: an address can be REUSED once the object is collected, so a
# hash keyed on `id` would be wrong if the GC MOVED objects. CPython's GC does not move objects,
# so `id` is stable for as long as the object lives -- a claim about the RUNTIME, not about the
# algorithm, and it is why the port's `tn_hash` may key on a graph node."""),

  # ---- __bool__
  (1234, 1241, """# `__bool__` -- tensor.py:136. `raise TypeError("__bool__ on Tensor is not defined")`.
# TODO(p3) tensor.py:136  __bool__ -- a pure Bend def cannot raise and there is no exception form
# to defer to. A def that must NOT be called is not a def that can be written; the refusal is the
# absence, and `tn_len` below is the shape of the same refusal made expressible as a `Maybe`."""),

  # ---- __repr__
  (1255, 1268, """# `__repr__` -- tinygrad/tensor.py:127-130. `f"<UOp {ld.device} {ld.shape}
# {str(ld.dtype)[7:]}>"`, and all three interpolations are a reader above. `str(dtypes.weakint)` is
# `"dtypes.weakint"`, so `[7:]` is the bare name, which is `S.Dt.nm`. THE DEVICE COLUMN is a
# divergence: a `Dev` is an interned tag, so it prints as its tag, and the gate therefore uses a
# device-LESS tensor where both sides print `None`. The grad column is `self.grad.uop if self.grad
# is not None else None` and 0 is the reserved `None`, so it prints `None` on every device-LESS
# fixture and `0` never.
#
# The whole thing is FOUR defs and not one, because each of the three fold reads is a separate
# fold over the whole arena and folding three times is what the record was for: one `Tensor` in,
# one `String` out, and the three readers are computed in the order the f-string interpolates."""),

  # ---- __init__
  (1329, 1336, """# __init__ -- tensor.py:57-99. The dispatch over what `data` IS. The isinstance ladder over
# six types becomes a `Data` union, which is the honest reading: `isinstance(data,
# get_args(ConstType))` is a membership test over a set of scalar types and a `Data` union is a
# set of tags. The two raises (tensor.py:79 and :91) become `None`, fold.bend's rule."""),

  # ---- the DNone arm
  (1342, 1349, """# `data is None` -> `UOp.const(0.0, _dtype)`. The `0.0` is an `F32` and no `F32` literal is
# constructible, so this def answers the `None` DATA only through a value the caller supplies, and
# the `DNone` arm is the one row of `__init__` the gate cannot pin.
# TODO(p3) ops.py:610  symbol=UOp.const  -- `UOp.const(0.0, _dtype)`, an F32 literal."""),

  # ---- as_param
  (1445, 1479, """# `as_param` -- tensor.py:153-154. `def as_param(self, slot): return
# Tensor(self.uop.param_like(slot))`. TWO LINES, and the whole of it is a rename of a live value
# into a numbered SLOT.
#
# `UOp.param_like` (ops.py:1241) is THREE arms and this ports the third:
# `UOp.param(slot, self.dtype, self._shape, self.device, name=None)` -- THE ONE. It is
# `UOp(Ops.PARAM, src=(), arg=ParamArg(slot, dtype, size=shape, device=device))` with `name` left
# `None` (ops.py:1018), and for a single device `device_range_src` is `()` (ops.py:851) -- the same
# fact `g_buf` already relies on. So arm 3 is BUILDABLE, and this is the only method in
# tensor.py's device half that is: the others all need a `Buffer` or a fetch or mutable class
# state, and this one needs a dtype and a shape, which are fold answers.
#
# why `as_param` is not trivial and the rows prove it. a toposort signature prints the op and the
# arity and NEVER THE ARG -- this file's own mutation M5 is that lesson, and it is why
# `tn_rop_arg` exists as a separate row. So `tn_asparam` (the signature) is BLIND to a dropped or
# wrong `slot`, and `tn_asparam_slot` (the arg) is the row that closes it. Neither is enough
# alone: the arg row cannot see a missing SRC and the signature row cannot see a wrong SLOT.
#
# arm 3's `ParamArg(slot, dtype, size=shape, device=device)`. Field names and order are ops.bend's
# `ParamArg`, not a hand-written list, and the three facts are READ OFF THE SOURCE'S OWN
# `ParamArg` rather than recomputed: for every node kind that can be `as_param`'d here -- BUFFER,
# ALLOC, PARAM -- `_shape` IS `ParamArg.size`, `dtype` IS `ParamArg.dtype` and `device` IS
# `ParamArg.device`, which is exactly what `UOp.param` reads at ops.py:1018. So a source whose
# arg is not an `AParam` is a source this def DECLINES, and it says so with a `None` instead of
# inventing a size."""),

  # ---- shape_to_shape_arg
  (1507, 1514, """# `shape_to_shape_arg` -- ops.py:104. `src = tuple(x if isinstance(x, UOp) else
# UOp.const(x) for x in arg); return src[0] if len(src) == 1 else UOp(Ops.STACK, src=src)`. The
# middle arm is the one that matters: ONE element is the CONST ITSELF and more than one is a
# STACK, which is why `(2, 2)` is a STACK and `(4,)` is a CONST.
#
# A `Data` record because a fold step must carry the arena it is growing AND the indices it has
# interned, and a bare `List` is spent when it is read."""),
]

apply(F, EDITS)
