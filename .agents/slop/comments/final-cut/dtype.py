import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/codegen/decomp/dtype.bend"

EDITS = [
  # ---- THE HEADER (14 lines) -> 8.
  (1, 14, """# dtype.bend -- tinygrad/codegen/decomp/dtype.py (224 lines).
#
# THE LONG AND FLOAT DECOMPOSITIONS. `dtype.py` splits a 64-bit or an fp8/half/bfloat16
# arithmetic node into 32-bit words (`l2i`) or into a bit-level float conversion (`f2f`), and
# rewrites the graph so the 32-bit nodes reach the hardware. This file is the SPLIT half --
# `l2i`, `f2f`, `f2f_clamp`, `reindex`, `unpack32`, `rne`, `l2i_define` and the three pattern
# tables -- which is most of the 224 lines. The REWRITE half (`split_l2i`, `l2i_rewrite_idx`,
# `f2f_load`, `f2f_store`, `f2f_rewrite`, `do_dtype_decomps`) is PORTED IN SHAPE, and each
# def says so.
#
# `decomp/op.bend` is the sibling (`decomp/op.py`) and `decomp/transcendental.bend` is the
# other half of `decomp/transcendental.py`."""),

  # ---- THE INVENTORY BLOCK (149 lines) -> the INVENTORY TABLE moves out, the FIVE DIVERGENCES
  # stay, and the CONTROL rounds stay as ONE line each (they are bug records).
  (16, 164, """# THE INVENTORY, def by def, against dtype.py's 224 lines, IS IN
# `.agents/slop/tables/codegen-decomp-dtype-16.md`.
#
# how the dtype questions are asked. a `match` arm on a dtype name is a silent fall-through
# after a rename, so this file arms on `Cls` and `bits` and `pri` everywhere it can, and on
# the NAME only where nothing else can work.
#
#   `dt in (long, ulong)`    Cls.is_int AND bits == 64. Renaming `dtypes.long`
#                            cannot change this answer.
#
# FIVE DIVERGENCES, stated rather than hidden.
#
# A. `UOp.const(v, dt)` IS A PAIR. `ops.py:630` is `UOp(Ops.CONST, arg=dt.const(v),
# src=()).cast(dt)`, and the cast folds only when the CONST's own dtype already IS `dt`. A
# CONST's dtype is read off its ARG (`ops.py:246`), so it is `dtypes.from_py(arg)`, and
# `from_py` (`dtype.py:30-34`) returns ONLY `bool`, `weakint` or `weakfloat`. So for every
# CONCRETE `dt` the cast cannot fold and the pair is what Python builds: `UOp.const(0,
# dtypes.uint)` is TWO nodes. `UOp.const(v)` with no dtype folds and is ONE, which is every
# constant `shl`/`shr` and every bare `(1 << k) - 1` in the file. `ops.bend`'s `UOp.const`
# drops the cast (its own TODO), so `dd_const` here builds the pair itself.
#
# B. `_broadcasted`'s PROMOTION CAST AND `logical_not`'s `cast(bool)` ARE NOT BUILT.
# `mixin/elementwise.py` is not ported, so `a + b`, `a & b`, `a == b`, `a < b` and
# `a.where(x, y)` build the bare ALU node here. The oracle deletes exactly those two CASTs and
# keeps every CAST dtype.py writes -- and two of those are load-bearing
# (`.bitcast(uint).cast(cdt)` reinterprets bits as a float), which is why `op.bend`'s
# delete-every-CAST rule cannot be reused.
#
# C. THE FLOAT-TARGET `CAST` ARM OF `l2i` IS NOT PORTED (dtype.py:35-38). It is unreachable
# through `pm_long_decomp`, because every `dt` that table passes to `split_l2i` is
# `l2i_dt[x.dtype]`, an integer. It is also the one place in the file where `_broadcasted`'s
# weak-CONST REMINT (`elementwise.py:31-32`) turns `2**32` from an integer constant into a
# FLOAT constant, and that remint is not modelled, so the arm is absent rather than wrong.
# The gate row is `lgu` and it prints `refused:unported`. CPython does not raise: the answer
# is `WHERE(OR(AND,AND),Pf320,ADD(MUL,CAST))` (dtype.py:35-38, two f32 words).
#
# D. NO `float16`, `bfloat16` OR `float64` SOURCE FOR `f2f` / `f2f_clamp`. `f2f_clamp` mints
# `mx` with `val.const_like(...)` and `val` is `v.bitcast(fr)`, so `mx` is a CONST at the
# SOURCE's width: CPython truncates it with `float_to_fp16` / `float_to_bf16` /
# `float_to_fp8` (`tinygrad/dtype.py:219/223/238`, all `struct` and bit-twiddling C code) and
# this file has none of them. THE WIDENING BRANCH HAS NO `f2f_clamp` AND NO FLOAT CONSTANT, so
# an fp8 source IS gated there: the four widening fixtures are the fnuz arm and the `fp8e4m3`
# arm of `is_nan`, which are otherwise dead defs.
#
# E. `float64` AS AN `f2f_clamp` TARGET IS NOT PORTED, because `mx` is
# `2**1023 * (2 - 2-52)` = the `float64` maximum and the port's only float type is `F32`.
# Its CPython value is in the oracle (`c7=F(ovf)`) and the fixture is absent rather than
# gated wrong.
#
# THE `graph_rewrite` WALL. `split_l2i`, `l2i_rewrite_idx`, `f2f_load`, `f2f_store`,
# `f2f_rewrite` and `do_dtype_decomps` all call `graph_rewrite` (ops.py:1611), which no file
# here ports: a bottom-up rewrite to fixpoint over an APPEND-ONLY arena is a map from one
# arena to another, and `uop/fold.bend`'s header names the cycle `dtype_from_uop <-> _shape <->
# simplify() -> graph_rewrite -> the rules -> dtype`. Each of those six is PORTED IN SHAPE:
# the arguments, the guard that picks `pm_long_decomp` over `pm_float_decomp`, `bottom_up=True`
# and the `ctx` are all here, and the rewrite call itself answers "no node". `uop/ops.bend`
# DOES own what they need -- the `PMEntrys` table, the `UPat` compiler and `pm_rewrite`'s
# first-wins scan -- so WHAT THE RULES MATCH is gated even though WHAT THEY REWRITE is not.
#
# CONTROL, dd-fix rounds 1 and 2 (2026-10-04): this comment block is a comment and nothing
# else, and the gate is required to read the SAME rows byte for byte (172 in round 1, 182 in
# round 2). Recorded because the NINE arena-aliasing defects those rounds fixed are the kind
# a green gate cannot tell from a fixed one: each read as a plausible string, and
# `--check-only` said `ALL PROOFS CHECK` on every one of them. THE SIX IN ROUND 2 ARE IN
# `.agents/slop/tables/codegen-decomp-dtype-16.md`.
#
# WHAT IS STILL RED AND WHY, so the next reader does not re-derive it: `c7`, `lgu` and `lgun`
# are DECLARED refusals (`refused:unported`), and `lg1n`/`lg6n`/`lg9n`/`lgqn` are not port
# defects at all. `<nm>n=` is the SLOTS MINTED, a property of `UOpMetaClass.ucache` and so
# of the SESSION, and dd-oracle.py's `main()` MINTS UOPS before the first `l2i` row: it
# prints `u32n=len(L2I()) + ... + len(IDX()) + len(defines())` and `IDX()` builds
# `UOp.const(0, dtypes.u32)`, `UOp.const(1, dtypes.u32)` and a `t` PARAM. The port's
# `fixtures()` builds dd-oracle's module-level `WORD` then `WPOOL` and nothing else.
# MEASURED, `.agents/slop/dd-slotprobe.bend` with its `pre` switch ON and NOTHING in this file
# changed: `lg1n` 11 -> 10, `lg6n` 5 -> 4, `lg9n` 18 -> 17, i.e. all three agree exactly.
# `lgqn` goes 2495 -> 2494 against CPython's 2496, and that residue is divergence B: this
# file does not build `_broadcasted`'s promotion CASTs, so its `lg1` interns `MUL(Pu320, C(-1))`
# where CPython interns `MUL(<promo cast>, C(-1))` -- a DIFFERENT node -- and `lgq` then
# reuses the port's. Closing that would need 69 more nodes per window and would break every
# `*sig` row.
#
# WHY `l2i` NEEDS NO FUEL. Every recursive step of `l2i` lands on a DIFFERENT op -- `NEG`
# calls `SUB`, `MUL` calls `ADD`, `MAX` calls `CMPLT` and `WHERE`, `TRUNCDIV` calls
# `NEG`/`SHL`/`SHR`/`CMPLT`/`SUB`/`WHERE`/`BITCAST` -- and none of those calls `l2i` again.
# So `l2i` is a `match` with no self-call, which is why the 64-iteration `TRUNCDIV` loop can
# be its own def: Bend refuses MUTUAL recursion, and this loop's body calls only arms that
# are themselves leaves.
#
# the order of this file is a topological sort, not an accident. bend 2.0.34 refuses a forward
# reference, and `.agents/slop/dd-sort.py` reads the call graph off this file and rewrites
# it; run it after adding a def."""),

  # ---- the `UOp.const(v, dt)` integer path -- the MEASUREMENT and the BUG record.
  (285, 307, """# `UOp.const(v, dt)` -- divergence A. THE INTEGER PATH IS `int(val)` AND NOT A WIDTH WRAP,
# and that is the whole reason the word here is an `H.I64` and not a `U32`.
#
# MEASURED, not read off `truncate`: `DType.const` (tinygrad/dtype.py:79-84) ends `... else
# int(val)`, and `truncate` reaches only the FLOAT branch's `truncate.get(self, float)`.
# `UOp.const` (uop/ops.py:628-635) is `UOp(Ops.CONST, arg=dtype.const(b), src=()).cast(dtype)`,
# so the CONST's arg is the raw Python int whatever `dt` is.
#
# It is OBSERVABLE, and in both directions. `dd-probe-intern.py`:
#     UOp.const(-1, dtypes.uint32).src[0].arg   ->  -1
#     UOp.const(4294967295, dtypes.uint32)     ->  4294967295
# so dtype.py:32's `lo.const_like(-1)` (uop/ops.py:600-602 -> `UOp.const`) leaves `-1` in the
# arena even when `lo` is `u32`. A port that wraps to the width stores `4294967295` there,
# which is the same 32 bits and a DIFFERENT node: the gate reads the word, and `lg6k`/`lg6p`
# say `C(4294967295)` where CPython says `C(-1)`.
#
# `truncate` for the integer dtypes IS a width wrap (tinygrad/dtype.py:298-299,
# `ctypes.c_int32(x).value`), so a port that modelled IT would be right about the float
# dtypes and wrong about every integer one. The comment this replaced claimed the opposite."""),
]

apply(F, EDITS)
