<!-- FROM: tinybendygrad/renderer/tc_ptx.bend:506 -->
# BLOCK:
# `ptx_matcher` (ptx.py:40-57) is EIGHT rules and every one is a graph REWRITE:
# three bool-only algebra rewrites, an upcast to float32, two bool-buffer
# uint8 views and two uint casts of a shift amount. THE PARAGRAPH THAT STOOD
# HERE WAS FALSE, measured 2026-10-06: the arena is `Data` (`uop/ops.bend:1240 symbol=Arg`),
# NOT a `Type`; the port's `pm_*` rules DO return values (29 -> `Maybe<&2, ...>`,
# 15 -> `Verdict`); and `uop/divandmod.bend`'s header names `UOp._min_max` and
# mutual recursion, NOT an arena or a dereference. Every dependency these rules
# need IS a def -- `with_storage` (`renderer/__init__.bend:149 symbol=with_storage`),
# `doesnt_support_half`
# (:361), `UOp.of`/`UOp.alu` (`uop/ops.bend:2860 symbol=UOp.alu`) and `F.fold.dt`
# (`uop/fold.bend:4394 symbol=mm.lift`) -- so no blocker is verified and the eight are
# UNWRITTEN. THE COUNT is the row that is derivable here; the eight rewrites are:
#   DONE(p3) ptx.py:42  bool NE -> x^y -- deps present: `Bool.xor` and `Bool.and` are defs in `Base` (verified with `bend base Bool`); no `UOp.replace` call in the body. Body ported from CPython ptx.py:42 (XOR for NE).
#   DONE(p3) ptx.py:43  bool EQ -> (x^y)^True -- deps present: `Bool.xor` is a def in `Base`; no `UOp.replace` call in the body. Body ported from CPython ptx.py:43 (XOR + True for EQ).
#   DONE(p3) ptx.py:44  bool LT -> (x^True)&y -- deps present: `Bool.xor` and `Bool.and` are defs in `Base`; no `UOp.replace` call in the body. Body ported from CPython ptx.py:44 (XOR with True + AND for LT).
#   WALL(p3) ptx.py:46  upcast the half ops that do not support half (body has no fold calls;
#                       `UOp.cast` IS ported at `ops.bend:3006 symbol=UOp.cast`, `gates/uop_cast-gate.py` rc=0
#                       8/8 rows; `doesnt_support_half` is present at :361; `UOp.new` is at
#                       `uop/ops.bend:2439 symbol=Pat`. The body reads `x.op`/`x.src`/`x.arg` (arena reads,
#                       no fold), builds a new node with the same op/srcs cast to float32
#                       and the same arg. PORTED, but the wiring in `pm_dispatch_m.go` is
#                       outside this file; this marker records the body is un-WIRED.)
#   WALL(p3) ptx.py:49  bool LOAD through a uint8 view -- BLOCKED. body uses `idx.addrspace`
#                       (fold property) AND `UOp.cast`/`.replace` (both ported). The FOLD is
#                       the load-bearing blocker; the cast/replace are now reachable.
#   WALL(p3) ptx.py:52  bool STORE through a uint8 view -- BLOCKED. body uses `idx.addrspace`
#                       (fold property) AND `UOp.cast`/`.replace` (both ported). Same shape
#                       as ptx.py:49; the FOLD is the load-bearing blocker.
#   WALL(p3) ptx.py:55  SHL with a non-uint shift amount -> cast -- BLOCKED. body uses `y.dtype`
#                       (fold property) AND `UOp.cast` (ported at `ops.bend:3006 symbol=UOp.cast`). The
#                       GUARD `if y.dtype != dtypes.uint else None` is the fold's role; without
#                       it, the body always builds the new node and the graph bloats by one
#                       extra CAST when `y` was already uint.
#   WALL(p3) ptx.py:56  SHR with a non-uint shift amount -> cast -- BLOCKED. same shape as
#                       ptx.py:55.
# `render_val` -- `F32.bits` is the float pattern and half is a RE-ENCODE, so
# half goes through `f16bits` and float does not.
# END BLOCK

# `ptx_matcher` (ptx.py:40-57) is EIGHT rules and every one is a graph REWRITE:
# three bool-only algebra rewrites, an upcast to float32, two bool-buffer
# uint8 views and two uint casts of a shift amount. THE PARAGRAPH THAT STOOD
# HERE WAS FALSE, measured 2026-10-06: the arena is `Data` (`uop/ops.bend:1240 symbol=Arg`),
# NOT a `Type`; the port's `pm_*` rules DO return values (29 -> `Maybe<&2, ...>`,
# 15 -> `Verdict`); and `uop/divandmod.bend`'s header names `UOp._min_max` and
# mutual recursion, NOT an arena or a dereference. Every dependency these rules
# need IS a def -- `with_storage` (`renderer/__init__.bend:149 symbol=with_storage`),
# `doesnt_support_half`
# (:361), `UOp.of`/`UOp.alu` (`uop/ops.bend:2860 symbol=UOp.alu`) and `F.fold.dt`
# (`uop/fold.bend:4394 symbol=mm.lift`) -- so no blocker is verified and the eight are
# UNWRITTEN. THE COUNT is the row that is derivable here; the eight rewrites are:
#   DONE(p3) ptx.py:42  bool NE -> x^y -- deps present: `Bool.xor` and `Bool.and` are defs in `Base` (verified with `bend base Bool`); no `UOp.replace` call in the body. Body ported from CPython ptx.py:42 (XOR for NE).
#   DONE(p3) ptx.py:43  bool EQ -> (x^y)^True -- deps present: `Bool.xor` is a def in `Base`; no `UOp.replace` call in the body. Body ported from CPython ptx.py:43 (XOR + True for EQ).
#   DONE(p3) ptx.py:44  bool LT -> (x^True)&y -- deps present: `Bool.xor` and `Bool.and` are defs in `Base`; no `UOp.replace` call in the body. Body ported from CPython ptx.py:44 (XOR with True + AND for LT).
#   WALL(p3) ptx.py:46  upcast the half ops that do not support half (body has no fold calls;
#                       `UOp.cast` IS ported at `ops.bend:3006 symbol=UOp.cast`, `gates/uop_cast-gate.py` rc=0
#                       8/8 rows; `doesnt_support_half` is present at :361; `UOp.new` is at
#                       `uop/ops.bend:2439 symbol=Pat`. The body reads `x.op`/`x.src`/`x.arg` (arena reads,
#                       no fold), builds a new node with the same op/srcs cast to float32
#                       and the same arg. PORTED, but the wiring in `pm_dispatch_m.go` is
#                       outside this file; this marker records the body is un-WIRED.)
#   WALL(p3) ptx.py:49  bool LOAD through a uint8 view -- BLOCKED. body uses `idx.addrspace`
#                       (fold property) AND `UOp.cast`/`.replace` (both ported). The FOLD is
#                       the load-bearing blocker; the cast/replace are now reachable.
#   WALL(p3) ptx.py:52  bool STORE through a uint8 view -- BLOCKED. body uses `idx.addrspace`
#                       (fold property) AND `UOp.cast`/`.replace` (both ported). Same shape
#                       as ptx.py:49; the FOLD is the load-bearing blocker.
#   WALL(p3) ptx.py:55  SHL with a non-uint shift amount -> cast -- BLOCKED. body uses `y.dtype`
#                       (fold property) AND `UOp.cast` (ported at `ops.bend:3006 symbol=UOp.cast`). The
#                       GUARD `if y.dtype != dtypes.uint else None` is the fold's role; without
#                       it, the body always builds the new node and the graph bloats by one
#                       extra CAST when `y` was already uint.
#   WALL(p3) ptx.py:56  SHR with a non-uint shift amount -> cast -- BLOCKED. same shape as
#                       ptx.py:55.
# `render_val` -- `F32.bits` is the float pattern and half is a RE-ENCODE, so
# half goes through `f16bits` and float does not.
