<!-- FROM: tinybendygrad/codegen/decomp/dtype.bend:16 -->
# BLOCK:
# THE INVENTORY TABLE AND THE SIX dd-fix-ROUND-2 DEFECTS.
# (The prose of this block was cut in the source; the DATA is here.)
#
# THE INVENTORY, def by def, against dtype.py's 224 lines.
#
#   #  PY        KIND    STATE
#   1  12        data    l2i_dt                     PORTED IN FULL
#   2  13        graph   unpack32                   PORTED IN FULL
#   3  14-18     graph   reindex                    PORTED IN FULL
#   4  21-81     graph   l2i                        15 of 17 arms, every arm shape
#   5  83-86     graph   l2i_define                 PORTED IN FULL
#   6  88-92     rewrite split_l2i                 PORTED IN SHAPE
#   7  94        rewrite l2i_rewrite_idx           PORTED IN SHAPE
#   8  97        data    f2f_dt                     PORTED IN FULL
#   9  99        graph   rne                        PORTED IN FULL
#  10  101-125   graph   f2f                        both branches, both raises
#  11  127-134   graph   f2f_clamp                  7 of 8 targets
#  12  136-139   rewrite f2f_load                   PORTED IN SHAPE
#  13  141-143   rewrite f2f_store                  PORTED IN SHAPE
#  14  145       rewrite f2f_rewrite                PORTED IN SHAPE
#  15  148-178   table   pm_long_decomp             PORTED, 13 rules, both reject sets
#  16  181-206   table   pm_float_decomp            PORTED, 10 rules, both reject sets
#  17  208-216   rewrite do_dtype_decomps          PORTED IN SHAPE
#  18  218-224   table   pm_dtype_decomps           PORTED, 2 rules
#
# how the dtype questions are asked. a `match` arm on a dtype name is a silent
# fall-through after a rename, so this file arms on `Cls` and `bits` and `pri`
# everywhere it can, and on the NAME only where nothing else can work.
#
#   `dt in (long, ulong)`    Cls.is_int AND bits == 64. Renaming `dtypes.long`
#                            cannot change this answer.
#
# FIVE DIVERGENCES, stated rather than hidden.
#
# A. `UOp.const(v, dt)` IS A PAIR. `ops.py:630` is
# `UOp(Ops.CONST, arg=dt.const(v), src=()).cast(dt)`, and the cast folds only
# when the CONST's own dtype already IS `dt`. A CONST's dtype is read off its
# ARG (`ops.py:246`), so it is `dtypes.from_py(arg)`, and `from_py`
# (`dtype.py:30-34`) returns ONLY `bool`, `weakint` or `weakfloat`. So for
# every CONCRETE `dt` the cast cannot fold and the pair is what Python builds:
# `UOp.const(0, dtypes.uint)` is TWO nodes. `UOp.const(v)` with no dtype folds
# and is ONE, which is every constant `shl`/`shr` and every bare `(1 << k) - 1`
# in the file. `ops.bend`'s `UOp.const` drops the cast (its own TODO), so
# `dd_const` here builds the pair itself.
#
# B. `_broadcasted`'s PROMOTION CAST AND `logical_not`'s `cast(bool)` ARE NOT
# BUILT. `mixin/elementwise.py` is not ported, so `a + b`, `a & b`, `a == b`,
# `a < b` and `a.where(x, y)` build the bare ALU node here. The oracle deletes
# exactly those two CASTs and keeps every CAST dtype.py writes -- and two of
# those are load-bearing (`.bitcast(uint).cast(cdt)` reinterprets bits as a
# float), which is why `op.bend`'s delete-every-CAST rule cannot be reused.
#
# C. THE FLOAT-TARGET `CAST` ARM OF `l2i` IS NOT PORTED (dtype.py:35-38). It is
# unreachable through `pm_long_decomp`, because every `dt` that table passes to
# `split_l2i` is `l2i_dt[x.dtype]`, an integer. It is also the one place in the
# file where `_broadcasted`'s weak-CONST REMINT (`elementwise.py:31-32`) turns
# `2**32` from an integer constant into a FLOAT constant, and that remint is not
# modelled, so the arm is absent rather than wrong. The gate row is `lgu` and it
# prints `refused:unported`. CPython does not raise: the answer is
# `WHERE(OR(AND,AND),Pf320,ADD(MUL,CAST))` (dtype.py:35-38, two f32 words).
#
# D. NO `float16`, `bfloat16` OR `float64` SOURCE FOR `f2f` / `f2f_clamp`.
# `f2f_clamp` mints `mx` with `val.const_like(...)` and `val` is `v.bitcast(fr)`,
# so `mx` is a CONST at the SOURCE's width: CPython truncates it with
# `float_to_fp16` / `float_to_bf16` / `float_to_fp8` (`tinygrad/dtype.py:219/223/238`,
# all `struct` and bit-twiddling C code) and this file has none of them. THE
# WIDENING BRANCH HAS NO `f2f_clamp` AND NO FLOAT CONSTANT, so an fp8 source IS
# gated there: the four widening fixtures are the fnuz arm and the `fp8e4m3`
# arm of `is_nan`, which are otherwise dead defs.
#
# E. `float64` AS AN `f2f_clamp` TARGET IS NOT PORTED, because `mx` is
# `2**1023 * (2 - 2-52)` = the `float64` maximum and the port's only float
# type is `F32`. Its CPython value is in the oracle (`c7=F(ovf)`) and the
# fixture is absent rather than gated wrong.
#
# THE `graph_rewrite` WALL. `split_l2i`, `l2i_rewrite_idx`, `f2f_load`,
# `f2f_store`, `f2f_rewrite` and `do_dtype_decomps` all call `graph_rewrite`
# (ops.py:1611), which no file here ports: a bottom-up rewrite to fixpoint over
# an APPEND-ONLY arena is a map from one arena to another, and `uop/fold.bend`'s
# header names the cycle `dtype_from_uop <-> _shape <-> simplify() ->
# graph_rewrite -> the rules -> dtype`. Each of those six is PORTED IN SHAPE:
# the arguments, the guard that picks `pm_long_decomp` over `pm_float_decomp`,
# `bottom_up=True` and the `ctx` are all here, and the rewrite call itself
# answers "no node". `uop/ops.bend` DOES own what they need -- the `PMEntrys`
# table, the `UPat` compiler and `pm_rewrite`'s first-wins scan -- so WHAT THE
# RULES MATCH is gated even though WHAT THEY REWRITE is not.
#
# CONTROL, dd-fix round 1 (2026-10-04): this comment block is a comment and nothing
# else, and the gate is required to read the SAME 172 rows byte for byte. Recorded
# because the THREE arena-aliasing defects fixed this round -- `l2i_shl.hi`
# (dtype.py:47-50), `l2i_cdiv.abs` (dtype.py:47-50) and `l2i_cdiv.signed`
# (dtype.py:69-72) -- are the kind a green gate cannot tell from a fixed one: each read
# as a plausible string, and `--check-only` said `ALL PROOFS CHECK` on every one of
# them. See `.agents/slop/notes/bend2-constraints.md` at the end.
#
# CONTROL, dd-fix round 2 (2026-10-04): this comment block is a comment and nothing else,
# and the gate is required to read the SAME 182 rows byte for byte. Recorded because the
# SIX defects closed this round are the same SPECIES as round 1's -- each read as a
# plausible string and `--check-only` said `ALL PROOFS CHECK` on every one of them -- and
# three of the six were not operand errors at all:
#
#   1. the port's `l2i_cdiv.step` built `AND` over the SHL
#      result's low word and over
#      the ARENA INDEX of `C(1)` where upstream's `l2i` says the SHR result's low word
#      and the
#      literal `1`. The SHR subtree was built, dead, and off the cone.
#      upstream's `l2i` -- tinygrad/codegen/decomp/dtype.py:64 symbol=l2i
#   2. `l2i_cdiv.step` (dtype.py:21) handed `l2i(SUB, ...)` the CMPLT ARM'S ANSWER where
#      dtype.py:66 and :67 spell the SAME `*r`.
#   3. `l2i_cdiv.abs.c` (dtype.py:60) handed the B-side `.where` pair the A-SIDE
#      negation's words, so `nb`'s own low word was built and never read.
#   4. the port's `l2i_cdiv.abs` minted four BITCASTs that
#      upstream's `Ops.BITCAST` folds
#      on a `u32` source, which is why `xdt` is a parameter of `abs`, `sign`, `cdiv`.
#      upstream's `l2i` -- tinygrad/codegen/decomp/dtype.py:59 symbol=l2i
#      upstream's `Ops.BITCAST` -- tinygrad/mixin/dtype.py:53 symbol=bitcast
#   5. `dd_fuel` was `32 * (to - from)` -- the CREATION WINDOW -- so a fixture that
#      interns NOTHING got fuel 64 and `lgtsig`/`lgrsig` read 57 and 112 nodes against
#      CPython's 2184 and 2218. A TRUNCATED WALK, not a small graph.
#   6. the port's `l2i_cast1.quo` did not model
#      upstream's `remint`'s weak-CONST
#      REMINT, so `2**32` stayed the integer `C(1:0)` instead of `F(1333788672)` and
#      `x < 0` reused the `C(0)` that `lo.ne(0)` owns.
#      upstream's `l2i` -- tinygrad/codegen/decomp/dtype.py:21 symbol=l2i
#      upstream's `remint` -- tinygrad/mixin/elementwise.py:12 symbol=remint
#
# WHAT IS STILL RED AND WHY, so the next reader does not re-derive it: `c7`, `lgu` and
# `lgun` are DECLARED refusals (`refused:unported`), and `lg1n`/`lg6n`/`lg9n`/`lgqn` are
# not port defects at all. `<nm>n=` is the SLOTS MINTED, a property of
# `UOpMetaClass.ucache` and so of the SESSION, and dd-oracle.py's `main()` MINTS UOPS
# before the first `l2i` row: it prints
# `u32n=len(L2I()) + ... + len(IDX()) + len(defines())` and `IDX()` builds
# `UOp.const(0, dtypes.u32)`, `UOp.const(1, dtypes.u32)` and a `t` PARAM. The port's
# `fixtures()` builds dd-oracle's module-level `WORD` then `WPOOL` and nothing else.
# MEASURED, `.agents/slop/dd-slotprobe.bend` with its `pre` switch ON and NOTHING in this
# file changed: `lg1n` 11 -> 10, `lg6n` 5 -> 4, `lg9n` 18 -> 17, i.e. all three agree
# exactly. `lgqn` goes 2495 -> 2494 against CPython's 2496, and that residue is
# divergence B: this file does not build `_broadcasted`'s promotion CASTs, so its `lg1`
# interns `MUL(Pu320, C(-1))` where CPython interns `MUL(<promo cast>, C(-1))` -- a
# DIFFERENT node -- and `lgq` then reuses the port's. Closing that would need 69 more
# nodes per window and would break every `*sig` row.
#
# WHY `l2i` NEEDS NO FUEL. Every recursive step of `l2i` lands on a DIFFERENT
# op -- `NEG` calls `SUB`, `MUL` calls `ADD`, `MAX` calls `CMPLT` and `WHERE`,
# `TRUNCDIV` calls `NEG`/`SHL`/`SHR`/`CMPLT`/`SUB`/`WHERE`/`BITCAST` -- and none of
# those calls `l2i` again. So `l2i` is a `match` with no self-call, which is why
# the 64-iteration `TRUNCDIV` loop can be its own def: Bend refuses MUTUAL recursion,
# and this loop's body calls only arms that are themselves leaves.
#
# the order of this file is a topological sort, not an accident. bend 2.0.34
# refuses a forward reference, and `.agents/slop/dd-sort.py` reads the call
# graph off this file and rewrites it; run it after adding a def.
