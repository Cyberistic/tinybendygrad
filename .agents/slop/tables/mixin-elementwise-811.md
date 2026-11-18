<!-- FROM: tinybendygrad/mixin/elementwise.bend:811 -->
# BLOCK:
# THE `F32` CONST WALL WAS REFUTED. It read: "no float literal anywhere in the
# port, because `F32` is `F32{data: Word(32n)}`, `Word` is not exported, and
# `U32.to_f32` is an unfilled LAW which live code may not call".
#
# ALL THREE HALVES ARE FALSE, and the measurement is `.agents/slop/ew-consts-gate.sh`:
# 21 constants, three lanes, byte-identical on the f32 BIT PATTERNS. What the gate
# established, in the order it established it:
#
#   A LITERAL WORKS. `0.044715` compiles, and its `F32.bits` is the f32 CPython's
#   `struct.pack('f', 0.044715)` gives. So the "no float literal" claim needs no
#   `Word` and no `U32.to_f32`: a literal is not a constructor call.
#   `F32.pi()` IS A CONSTANT, spelled `3.14159265` in base.bend -- a TRUNCATION -- and it
#   is still bit-equal to f32(pi) = 0x40490FDB, because the truncation is under half
#   an ulp. `F32.div(F32.pi(), 2.0)` is therefore exactly f32(pi/2), halving a normal
#   f32 being exact.
#   `U32.to_f32` IS a `law`, and a base law is callable: `F32.from_nat` calls it. "An
#   unfilled law which live code may not call" describes a law someone left EMPTY, and
#   this one is not that.
#   EVEN INF IS PRODUCIBLE, which the `isinf` marker below had as its own reason:
#   `F32.div(1.0, 0.0)` is 0x7F800000. So `float("inf")` is not a wall either.
#
# and three of the obvious spellings measured wrong, which is the part worth keeping:
#   `0.30102999` for log10(2) is one ulp LOW and `0.30103` -- FIVE digits -- is right.
#   `1.0507009` for selu's gamma is wrong and `1.050701` is right. More digits is not
#   more accurate in f32, and the intuition that it is is what wrote the first two.
#   `F32.sqrt(F32.div(2.0, F32.pi()))` is one ulp off, because it rounds twice where
#   CPython rounds once. A LITERAL cannot double-round, so that constant is a literal.
#
# left, and where that is "undiagnosed" it says THAT rather than borrowing the old
# excuse -- refuting a stated reason is not the same as landing the method, and a
# marker that keeps a reason which has been measured false is worse than no marker.
#
# `H.f32_show` IS A SIX-DECIMAL-PLACE FORMATTER where CPython's `repr` is a
# shortest-round-trip one, so f32(log 2) prints `0.693147` here and
# `0.6931471824645996` there. That is a real difference about a different def and it
# is NOT gated here; it is its own unit.
# TODO(p3) elementwise.py:500  cos  -- math.pi/2 is `F32.div(F32.pi(), 2.0)`, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:511  exp  -- 1/math.log(2) is `ew_k.inv_log2()`, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:838  log  -- math.log(2) is `ew_k.log2()`, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:850  log10  -- math.log10(2) is `ew_k.log10_2()` = 0.30103, bit-exact -- NOT 0.30102999, which is one ulp low
# TODO(p3) elementwise.py:611  isinf  -- float("inf") is PRODUCIBLE: `F32.div(1.0, 0.0)` is 0x7F800000.
#   `mo_eqmul` is one arm (mixin/op.bend:1057 symbol=mo_eqmul); the second arm + add is the
#   remainder, and a `tn_isinf` would still need the same `isinf` body. UNDIAGNOSED
# TODO(p3) elementwise.py:633  isclose  -- rtol=1e-05 and atol=1e-08 are literals, bit-exact. the rule body is the remainder; UNDIAGNOSED
# TODO(p3) elementwise.py:654  ceil  -- b+1 is fine and was always fine -- the marker said so. `round` is the remainder; see 890
# TODO(p3) elementwise.py:709  hardswish  -- (1/6) is `F32.div(1.0, 6.0)`, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:721  hardsigmoid  -- alpha=1/6 and beta=0.5 are both available, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:744  leaky_relu  -- neg_slope=0.01 is a literal, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:854  atanh        -- .log()
# TODO(p3) elementwise.py:866  asinh        -- .log()
# TODO(p3) elementwise.py:878  acosh        -- .log()
# TODO(p3) elementwise.py:890  round  -- 0.5 and 2.0 are available. THE REMAINDER IS NOT A CONSTANT: it is the rounding mode, and it still is
# TODO(p3) elementwise.py:921  tan          -- .cos()
# TODO(p3) elementwise.py:1000 softplus     -- beta=1.0
# TODO(p3) elementwise.py:1010 mish         -- softplus()
# TODO(p3) elementwise.py:1022 logsigmoid   -- softplus()
# TODO(p3) elementwise.py:1034 sinh         -- exp()
# TODO(p3) elementwise.py:1046 cosh         -- exp()
# TODO(p3) elementwise.py:1058 erf          -- polyN, 0.3275911
# TODO(p3) elementwise.py:410  copysign     -- -(mag := a.abs()) with a float 0 path
# TODO(p3) elementwise.py:418  logaddexp    -- .isfinite(), 0
# PORTED. `rsqrt` is elementwise.py:820, `return self.sqrt().reciprocal()`. The
# old text said "blocked on sqrt's own fold, not on a constant" -- which was true
# when `tn_sqrt` was a fold call, but `tn_sqrt` is now a `tn_alu` over an empty src
# list, and `tn_reciprocal` is the same shape, so the chain `self.sqrt().reciprocal()`
# is portable as `tn_alu(sqrt, O.OpsRECIP{}, Nil{})` (the reciprocal's implicit
# first src is the sqrt result, not the original input). Gated at
# `gates/tn_sin_log2_exp2_rsqrt-gate.py` 11/11 rows.
# PORTED. `isnan` is elementwise.py:603, `return self != self`, the single
# `CMPNE` whose two srcs are the same tensor. NaN is the only float where
# `x == x` is false, so `cmpne(t, t)` IS the NaN test. The port at
# `tensor.bend:tn_isnan` is one line: `tn_cmpne(t, t)`. The mo-layer peer is
# `mo_isnan` (`mixin/op.bend:1045 symbol=mo_isnan`), the same shape. Gated at
# `gates/tn_isnan-gate.py` 5/5 rows.
#
# PORTED with two carve-outs. `isfinite` is elementwise.py:623,
# `(self.isinf() | self.isnan()).logical_not()`. The `tn_*` layer has no
# `tn_isinf`, so the `isinf` body is inlined: `eq(inf)*True + eq(-inf)*True` is
# `self.eq(+inf) + self.eq(-inf)` (the `True` arms are the identity and the
# default-args case collapses). The chain is then `OR(ADD, isnan) -> cmpne(True)`,
# built by `tn_isfinite` (`tensor.bend:tn_isfinite`). The mo-layer peer is
# `mo_isfinite` (`mixin/op.bend:1067 symbol=mo_isfinite`). Gated at `gates/tn_isfinite-gate.py`
# 6/6 rows.
#
# what the gate does not assert, and why:
#   * `src[0]` of the top is OR in CPython, CAST in the port. The port's
#     `tn_logical_not` keeps the explicit `cast(bool)` and CPython folds it
#     out on a bool-typed `or`, so the row `or_or_cast` is an OR-vs-CAST
#     call. Both graphs are correct; the fold is the only difference.
#     MEASURED: the port reaches 17 nodes from the top and CPython reaches 15,
#     and the three missing nodes are the identity bool cast (`eqarm` twice,
#     `logical_not` once).
#   * The `tn_isfinite.armul` fix is NOT gated. It builds its MUL in the arena
#     the CONST grew rather than in `eq`'s, and reverting it leaves all six
#     rows green -- the row that would see it walks four hops down the graph
#     and `bend` answers `a declared datatype (unknown: IO)` past about two.
#     Stated here because a fix nobody can see is not a gate.
#
# a defect that was here and is not any more. `tn_logical_not` and
# `tn_bitwise_not` both built their CMPNE as
# `tn_alu(tn_alu.put(cast), CMPNE, [Found.i(true_c)])`: the const index is minted
# in `true_c.ar`, which is one node LONGER than the `cast.ar` the CMPNE was built
# in, so the CMPNE landed on the slot the const index names and became its own
# `src[1]`. `Arena` is an immutable `Data` value (`ops.bend:1305 symbol=Arena`), so `Found.ar`
# SNAPSHOTS, and an index is legal only in an arena DESCENDING FROM the one that
# minted it. MEASURED with `O.Rng.sig` (`uop/ops.bend:5978 symbol=Rng.sig`) as the instrument on a
# `CInt` input: `CMPNE/2 Ops.CAST Ops.CMPNE` against CPython's
# `CMPNE(CAST(CONST()), CONST())`. The rule and the helper that states it are
# `tensor.bend:tn_binop`; the two ports are `tn_logical_not.cmpne` and
# `tn_bitwise_not`. The rows that catch it are `gates/tn_logical_not-gate.py`'s
# four `int_input_*` ones -- the pre-existing four seeded the arena with
# `CBool{True{}}` and `O.UOp.const` interns, so the const was already at slot 0
# and the defect was invisible. A `CBool` input cannot see this bug.
# WALLS THAT ARE NOT CONSTANTS.
# `usum` / `uprod` -- elementwise.py:40-41 -- are `functools.reduce(op, argfix(*uops),
# self)` over a VARIADIC, and `argfix` is helpers.py's. The reduce itself is a
# self-recursive fold with the fuel first and is one def; the variadic is not
# expressible and is the whole of the wall.
# TODO(p3) elementwise.py:40  usum   -- functools.reduce + argfix + *uops
# TODO(p3) elementwise.py:41  uprod  -- ditto
#
# `contiguous` -- elementwise.py:59-66 -- tests `uop.has_buffer_identity()` (ops.py:952,
# P3), `self.device is None` and `uop.op is Ops.STAGE`, so its three arms need P3's
# buffer reader before the STAGE arm is reachable.
# TODO(p3) elementwise.py:59  contiguous -- has_buffer_identity + device
#
# `clamp` / `clip` -- elementwise.py:586-601 -- are `(self < min_).where(min_, self)`
# twice, and the two `is not None` tests are a `Maybe`. Both bounds arriving as
# `Maybe<&2, Ew>` rather than as two `Ew`s is a signature change rather than an
# algorithmic one, and it is not written rather than half-written.
# TODO(p3) elementwise.py:586  clamp   -- min_/max_ are `DTypeLike|None`
# TODO(p3) elementwise.py:599  clip    -- clamp's alias
#
# `relu` / `relu6` / `hardtanh` / `abs` / `sign` / `sqr` are all `where`/`ne`
# compositions of methods already here and are NOT deferred: they are three
# lines each and they gate. `rsqrt` USED TO be deferred on the SQRT fold
# ("SQRT's fold, not a constant"), but `tn_sqrt` is now a `tn_alu` over an empty
# src list and `tn_reciprocal` is the same shape, so the chain is portable.
# Closed at `tensor.bend:tn_rsqrt` and gated at `gates/tn_sin_log2_exp2_rsqrt-gate.py`
# 11/11 rows. `isnan` (elementwise.py:603) and `isfinite` (elementwise.py:623)
# closed the same way and are PORTED -- see the two blocks at line 866.
#
# `usum`'s `operator.or_ if self.dtype is dtypes.bool else operator.add` is the
# only place the unit chooses BETWEEN TWO OPS on a dtype, and it is the reason
# `weak.bend`'s promotion matters here rather than only downstream: a bool reduce
# must answer an `Ops.OR` and an int reduce an `Ops.ADD`, and the two have different
# `dtype_from_uop` arms.
# THE GATE.
#
# EVERY ROW IS A GRAPH SHAPE, and the shape is the SIGNATURE of the toposort --
# `n=<count> OP/<nsrc> ...` in DFS-postorder with the BARE enum name -- so the
# oracle runs without hardware and the lanes diff byte for byte. `ew-gate.py` is
# the AUTHORITY: it is derived from CPython and this file is not, so a difference
# is a bug in THIS file unless the row is one of the named unfalsifiable ones at
# the head (currently exactly one, `ew_promo_nc`).
#     .venv/bin/python .agents/slop/ew-gate.py > /tmp/py.txt
#     ./bin/bend tinybendygrad/mixin/elementwise.bend > /tmp/bd.txt
#     wc -l /tmp/py.txt /tmp/bd.txt        # 71 vs 72 -- counts first: a clean
#                                          # `diff` over two empty files is clean
#     diff /tmp/py.txt /tmp/bd.txt
#
# The `n=` is in every signature on purpose. A boolean row that says "the ADD is
# there" cannot see a dropped CONST, and gradient.bend records two mutations that
# produced the RIGHT COUNT and the wrong graph.
#
# THREE KINDS OF ROW, because the three kinds of bug are blind to each other:
#   * COUNT rows, and the count in every signature -- a dropped or duplicated node.
#   * INDEX / OP rows (`ew_src0_*`, `ew_op_*`, `ew_dt_*`) -- a swapped op or a
#     swapped operand. Two CONSTs print the SAME signature in either operand order
#     (tensor.bend's mutation M15 is exactly that hole), and `promote` changes a
#     node's DTYPE and nothing else it is printed for, so the entire promotion
#     matrix is invisible without the `ew_dt_*` rows.
#   * `ew_both` -- the node BOTH promotions build, hash-consed to ONE node. A
#     first-wins / conjunction bug is invisible unless the two answers disagree, so
#     this asks for the node COUNT and not for an index.
#
# THE SHAPE OF A ROW: a PURE `g_*` builder returns a `Tensor`, and the row is one
# line that prints it. A `do IO<Unit>` block can only bind an `IO`
# (bend2-constraints, weak.py rule 8), so a row that prints twice calls its pure
# builder twice -- which is free, because the builder is pure and the fixture is
# three nodes.
# END BLOCK

# THE `F32` CONST WALL WAS REFUTED. It read: "no float literal anywhere in the
# port, because `F32` is `F32{data: Word(32n)}`, `Word` is not exported, and
# `U32.to_f32` is an unfilled LAW which live code may not call".
#
# ALL THREE HALVES ARE FALSE, and the measurement is `.agents/slop/ew-consts-gate.sh`:
# 21 constants, three lanes, byte-identical on the f32 BIT PATTERNS. What the gate
# established, in the order it established it:
#
#   A LITERAL WORKS. `0.044715` compiles, and its `F32.bits` is the f32 CPython's
#   `struct.pack('f', 0.044715)` gives. So the "no float literal" claim needs no
#   `Word` and no `U32.to_f32`: a literal is not a constructor call.
#   `F32.pi()` IS A CONSTANT, spelled `3.14159265` in base.bend -- a TRUNCATION -- and it
#   is still bit-equal to f32(pi) = 0x40490FDB, because the truncation is under half
#   an ulp. `F32.div(F32.pi(), 2.0)` is therefore exactly f32(pi/2), halving a normal
#   f32 being exact.
#   `U32.to_f32` IS a `law`, and a base law is callable: `F32.from_nat` calls it. "An
#   unfilled law which live code may not call" describes a law someone left EMPTY, and
#   this one is not that.
#   EVEN INF IS PRODUCIBLE, which the `isinf` marker below had as its own reason:
#   `F32.div(1.0, 0.0)` is 0x7F800000. So `float("inf")` is not a wall either.
#
# and three of the obvious spellings measured wrong, which is the part worth keeping:
#   `0.30102999` for log10(2) is one ulp LOW and `0.30103` -- FIVE digits -- is right.
#   `1.0507009` for selu's gamma is wrong and `1.050701` is right. More digits is not
#   more accurate in f32, and the intuition that it is is what wrote the first two.
#   `F32.sqrt(F32.div(2.0, F32.pi()))` is one ulp off, because it rounds twice where
#   CPython rounds once. A LITERAL cannot double-round, so that constant is a literal.
#
# left, and where that is "undiagnosed" it says THAT rather than borrowing the old
# excuse -- refuting a stated reason is not the same as landing the method, and a
# marker that keeps a reason which has been measured false is worse than no marker.
#
# `H.f32_show` IS A SIX-DECIMAL-PLACE FORMATTER where CPython's `repr` is a
# shortest-round-trip one, so f32(log 2) prints `0.693147` here and
# `0.6931471824645996` there. That is a real difference about a different def and it
# is NOT gated here; it is its own unit.
# TODO(p3) elementwise.py:500  cos  -- math.pi/2 is `F32.div(F32.pi(), 2.0)`, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:511  exp  -- 1/math.log(2) is `ew_k.inv_log2()`, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:838  log  -- math.log(2) is `ew_k.log2()`, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:850  log10  -- math.log10(2) is `ew_k.log10_2()` = 0.30103, bit-exact -- NOT 0.30102999, which is one ulp low
# TODO(p3) elementwise.py:611  isinf  -- float("inf") is PRODUCIBLE: `F32.div(1.0, 0.0)` is 0x7F800000.
#   `mo_eqmul` is one arm (mixin/op.bend:1057 symbol=mo_eqmul); the second arm + add is the
#   remainder, and a `tn_isinf` would still need the same `isinf` body. UNDIAGNOSED
# TODO(p3) elementwise.py:633  isclose  -- rtol=1e-05 and atol=1e-08 are literals, bit-exact. the rule body is the remainder; UNDIAGNOSED
# TODO(p3) elementwise.py:654  ceil  -- b+1 is fine and was always fine -- the marker said so. `round` is the remainder; see 890
# TODO(p3) elementwise.py:709  hardswish  -- (1/6) is `F32.div(1.0, 6.0)`, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:721  hardsigmoid  -- alpha=1/6 and beta=0.5 are both available, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:744  leaky_relu  -- neg_slope=0.01 is a literal, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:854  atanh        -- .log()
# TODO(p3) elementwise.py:866  asinh        -- .log()
# TODO(p3) elementwise.py:878  acosh        -- .log()
# TODO(p3) elementwise.py:890  round  -- 0.5 and 2.0 are available. THE REMAINDER IS NOT A CONSTANT: it is the rounding mode, and it still is
# TODO(p3) elementwise.py:921  tan          -- .cos()
# TODO(p3) elementwise.py:1000 softplus     -- beta=1.0
# TODO(p3) elementwise.py:1010 mish         -- softplus()
# TODO(p3) elementwise.py:1022 logsigmoid   -- softplus()
# TODO(p3) elementwise.py:1034 sinh         -- exp()
# TODO(p3) elementwise.py:1046 cosh         -- exp()
# TODO(p3) elementwise.py:1058 erf          -- polyN, 0.3275911
# TODO(p3) elementwise.py:410  copysign     -- -(mag := a.abs()) with a float 0 path
# TODO(p3) elementwise.py:418  logaddexp    -- .isfinite(), 0
# PORTED. `rsqrt` is elementwise.py:820, `return self.sqrt().reciprocal()`. The
# old text said "blocked on sqrt's own fold, not on a constant" -- which was true
# when `tn_sqrt` was a fold call, but `tn_sqrt` is now a `tn_alu` over an empty src
# list, and `tn_reciprocal` is the same shape, so the chain `self.sqrt().reciprocal()`
# is portable as `tn_alu(sqrt, O.OpsRECIP{}, Nil{})` (the reciprocal's implicit
# first src is the sqrt result, not the original input). Gated at
# `gates/tn_sin_log2_exp2_rsqrt-gate.py` 11/11 rows.
# PORTED. `isnan` is elementwise.py:603, `return self != self`, the single
# `CMPNE` whose two srcs are the same tensor. NaN is the only float where
# `x == x` is false, so `cmpne(t, t)` IS the NaN test. The port at
# `tensor.bend:tn_isnan` is one line: `tn_cmpne(t, t)`. The mo-layer peer is
# `mo_isnan` (`mixin/op.bend:1045 symbol=mo_isnan`), the same shape. Gated at
# `gates/tn_isnan-gate.py` 5/5 rows.
#
# PORTED with two carve-outs. `isfinite` is elementwise.py:623,
# `(self.isinf() | self.isnan()).logical_not()`. The `tn_*` layer has no
# `tn_isinf`, so the `isinf` body is inlined: `eq(inf)*True + eq(-inf)*True` is
# `self.eq(+inf) + self.eq(-inf)` (the `True` arms are the identity and the
# default-args case collapses). The chain is then `OR(ADD, isnan) -> cmpne(True)`,
# built by `tn_isfinite` (`tensor.bend:tn_isfinite`). The mo-layer peer is
# `mo_isfinite` (`mixin/op.bend:1067 symbol=mo_isfinite`). Gated at `gates/tn_isfinite-gate.py`
# 6/6 rows.
#
# what the gate does not assert, and why:
#   * `src[0]` of the top is OR in CPython, CAST in the port. The port's
#     `tn_logical_not` keeps the explicit `cast(bool)` and CPython folds it
#     out on a bool-typed `or`, so the row `or_or_cast` is an OR-vs-CAST
#     call. Both graphs are correct; the fold is the only difference.
#     MEASURED: the port reaches 17 nodes from the top and CPython reaches 15,
#     and the three missing nodes are the identity bool cast (`eqarm` twice,
#     `logical_not` once).
#   * The `tn_isfinite.armul` fix is NOT gated. It builds its MUL in the arena
#     the CONST grew rather than in `eq`'s, and reverting it leaves all six
#     rows green -- the row that would see it walks four hops down the graph
#     and `bend` answers `a declared datatype (unknown: IO)` past about two.
#     Stated here because a fix nobody can see is not a gate.
#
# a defect that was here and is not any more. `tn_logical_not` and
# `tn_bitwise_not` both built their CMPNE as
# `tn_alu(tn_alu.put(cast), CMPNE, [Found.i(true_c)])`: the const index is minted
# in `true_c.ar`, which is one node LONGER than the `cast.ar` the CMPNE was built
# in, so the CMPNE landed on the slot the const index names and became its own
# `src[1]`. `Arena` is an immutable `Data` value (`ops.bend:1305 symbol=Arena`), so `Found.ar`
# SNAPSHOTS, and an index is legal only in an arena DESCENDING FROM the one that
# minted it. MEASURED with `O.Rng.sig` (`uop/ops.bend:5978 symbol=Rng.sig`) as the instrument on a
# `CInt` input: `CMPNE/2 Ops.CAST Ops.CMPNE` against CPython's
# `CMPNE(CAST(CONST()), CONST())`. The rule and the helper that states it are
# `tensor.bend:tn_binop`; the two ports are `tn_logical_not.cmpne` and
# `tn_bitwise_not`. The rows that catch it are `gates/tn_logical_not-gate.py`'s
# four `int_input_*` ones -- the pre-existing four seeded the arena with
# `CBool{True{}}` and `O.UOp.const` interns, so the const was already at slot 0
# and the defect was invisible. A `CBool` input cannot see this bug.
# WALLS THAT ARE NOT CONSTANTS.
# `usum` / `uprod` -- elementwise.py:40-41 -- are `functools.reduce(op, argfix(*uops),
# self)` over a VARIADIC, and `argfix` is helpers.py's. The reduce itself is a
# self-recursive fold with the fuel first and is one def; the variadic is not
# expressible and is the whole of the wall.
# TODO(p3) elementwise.py:40  usum   -- functools.reduce + argfix + *uops
# TODO(p3) elementwise.py:41  uprod  -- ditto
#
# `contiguous` -- elementwise.py:59-66 -- tests `uop.has_buffer_identity()` (ops.py:952,
# P3), `self.device is None` and `uop.op is Ops.STAGE`, so its three arms need P3's
# buffer reader before the STAGE arm is reachable.
# TODO(p3) elementwise.py:59  contiguous -- has_buffer_identity + device
#
# `clamp` / `clip` -- elementwise.py:586-601 -- are `(self < min_).where(min_, self)`
# twice, and the two `is not None` tests are a `Maybe`. Both bounds arriving as
# `Maybe<&2, Ew>` rather than as two `Ew`s is a signature change rather than an
# algorithmic one, and it is not written rather than half-written.
# TODO(p3) elementwise.py:586  clamp   -- min_/max_ are `DTypeLike|None`
# TODO(p3) elementwise.py:599  clip    -- clamp's alias
#
# `relu` / `relu6` / `hardtanh` / `abs` / `sign` / `sqr` are all `where`/`ne`
# compositions of methods already here and are NOT deferred: they are three
# lines each and they gate. `rsqrt` USED TO be deferred on the SQRT fold
# ("SQRT's fold, not a constant"), but `tn_sqrt` is now a `tn_alu` over an empty
# src list and `tn_reciprocal` is the same shape, so the chain is portable.
# Closed at `tensor.bend:tn_rsqrt` and gated at `gates/tn_sin_log2_exp2_rsqrt-gate.py`
# 11/11 rows. `isnan` (elementwise.py:603) and `isfinite` (elementwise.py:623)
# closed the same way and are PORTED -- see the two blocks at line 866.
#
# `usum`'s `operator.or_ if self.dtype is dtypes.bool else operator.add` is the
# only place the unit chooses BETWEEN TWO OPS on a dtype, and it is the reason
# `weak.bend`'s promotion matters here rather than only downstream: a bool reduce
# must answer an `Ops.OR` and an int reduce an `Ops.ADD`, and the two have different
# `dtype_from_uop` arms.
# THE GATE.
#
# EVERY ROW IS A GRAPH SHAPE, and the shape is the SIGNATURE of the toposort --
# `n=<count> OP/<nsrc> ...` in DFS-postorder with the BARE enum name -- so the
# oracle runs without hardware and the lanes diff byte for byte. `ew-gate.py` is
# the AUTHORITY: it is derived from CPython and this file is not, so a difference
# is a bug in THIS file unless the row is one of the named unfalsifiable ones at
# the head (currently exactly one, `ew_promo_nc`).
#     .venv/bin/python .agents/slop/ew-gate.py > /tmp/py.txt
#     ./bin/bend tinybendygrad/mixin/elementwise.bend > /tmp/bd.txt
#     wc -l /tmp/py.txt /tmp/bd.txt        # 71 vs 72 -- counts first: a clean
#                                          # `diff` over two empty files is clean
#     diff /tmp/py.txt /tmp/bd.txt
#
# The `n=` is in every signature on purpose. A boolean row that says "the ADD is
# there" cannot see a dropped CONST, and gradient.bend records two mutations that
# produced the RIGHT COUNT and the wrong graph.
#
# THREE KINDS OF ROW, because the three kinds of bug are blind to each other:
#   * COUNT rows, and the count in every signature -- a dropped or duplicated node.
#   * INDEX / OP rows (`ew_src0_*`, `ew_op_*`, `ew_dt_*`) -- a swapped op or a
#     swapped operand. Two CONSTs print the SAME signature in either operand order
#     (tensor.bend's mutation M15 is exactly that hole), and `promote` changes a
#     node's DTYPE and nothing else it is printed for, so the entire promotion
#     matrix is invisible without the `ew_dt_*` rows.
#   * `ew_both` -- the node BOTH promotions build, hash-consed to ONE node. A
#     first-wins / conjunction bug is invisible unless the two answers disagree, so
#     this asks for the node COUNT and not for an index.
#
# THE SHAPE OF A ROW: a PURE `g_*` builder returns a `Tensor`, and the row is one
# line that prints it. A `do IO<Unit>` block can only bind an `IO`
# (bend2-constraints, weak.py rule 8), so a row that prints twice calls its pure
# builder twice -- which is free, because the builder is pure and the fixture is
# three nodes.
