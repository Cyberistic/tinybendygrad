<!-- FROM: tinybendygrad/tensor.bend:453 -->
# BLOCK:
# `logical_not` -- elementwise.py:57 AT `f5ac54685074`. `return
# self.cast(dtypes.bool).eq(False)`, and
# `.cast` is `self if self.dtype == (dt:=to_dtype(dtype)) else self._uop.alu(Ops.CAST,
# arg=dt)` (mixin/dtype.py:38) -- IT FOLDS ON AN IDENTITY CAST. So the graph is
# CAST(self, bool) -> CMPEQ(cast, CONST(False)) when self is NOT bool and NO CAST AT ALL when
# it is, and that is not a carve-out: it is the whole of `cast`.
#
# `O.UOp.cast` (ops.bend:2774) MINTS THE NODE UNCONDITIONALLY -- `UOp.new(ar, OpsCAST{}, ...)`.
# That was the one extra `CAST` on `tn_eq`, `tn_dunder_ge`, `tn_dunder_le`,
# `tn_dunder_invert` and `tn_isfinite`, every one of which is a `logical_not` over a node the
# fold already knows is `bool` (a CMPNE, a CMPLT or an OR -- uop/fold.bend:2644 symbol=dt_shape answers
# `bool` for the first two and `promo_dtype` for the third). The fold-aware cast is
# `D.cast_at` (dtype.bend:341), the same `cast_at.of` two-arm match `mixin/elementwise.bend`'s
# `ew_cast` reaches through `W.wk_cast_at`, and it is `D` rather than `W` because
# `wk_eq_dt` is stale (see the header). `F.folded(Tensor.ar(t))` is `ew_fx`'s exact call:
# the fold is taken from the tensor's OWN arena at the point of use, never handed down.
#
# It is declared BEFORE `tn_bitwise_not` because that def's BOOL arm calls it, and a Bend
# def may only call defs DECLARED ABOVE IT (rule 1 in the header). `bitwise_not`'s bool arm
# IS this graph, so the two graphs ARE equal for a bool self; they are held apart only
# because `logical_not` (:49) and `bitwise_not` (:145) are sibling methods with different
# bodies around the shared one.
# `Arena` is an IMMUTABLE `Data` VALUE (`ops.bend:1255`: `type Arena is Data: Arena{nodes,
# shp}`), so a `Found` SNAPSHOTS the arena at its own construction and every index is
# only meaningful in the arena value that index was minted in. `false_c.ar` has the
# CAST AND the CONST (3 slots); `cast.ar` has the CAST only (2 slots). Building the
# CMPEQ in `cast.ar` therefore APPENDS it at the slot `O.Found.i(false_c)` already names
# -- the node becomes its own `src[1]`. MEASURED, `./bin/bend` on a `CInt` input, with
# `O.Rng.sig` (uop/ops.bend:5978 symbol=Rng.sig) as the instrument: `CMPEQ/2 Ops.CAST
# Ops.CMPEQ` (src[1] IS the top node) where CPython answers `CMPEQ(CAST(CONST()),
# CONST(False))` (`/tmp/cp_shape.py`, `tinygrad`). So the CMPEQ is built in `false_c.ar`,
# the newest.
#
# `logical_not` -- elementwise.py:57 AT `f5ac54685074` -- is
# `self.cast(dtypes.bool).eq(False)`, so it is a CAST and a CMPEQ against the CONST
# `False`. THE NAME DID NOT CHANGE AND THE NODE DID: the pre-pin spelling was
# `self.cast(dtypes.bool).eq(False)`, which builds `CMPEQ(x, CONST(False))`.
# MEASURED 2026-11-10 ON CPYTHON AT THE PIN: `a.logical_not()` emits
# `CMPEQ(CAST(a), CONST(False))`.
#
# AND THIS IS NOT A STYLISTIC CHOICE: UPSTREAM's OWN `symbolic.py:349` KEYS ON IT --
# `neg = v.op is Ops.CMPEQ and v.src[1].op is Ops.CONST and v.src[1].val == 0` -- so a
# graph that says `CMPNE` is NOT upstream's graph. AND THE PORT's OWN
# `uop/symbolic.bend`'s `mint_not` ALREADY BUILDS THE `CMPEQ` SPELLING -- so THIS file was
# the only half on the pre-pin spelling.
# END BLOCK

# `logical_not` -- elementwise.py:57 AT `f5ac54685074`. `return
# self.cast(dtypes.bool).eq(False)`, and
# `.cast` is `self if self.dtype == (dt:=to_dtype(dtype)) else self._uop.alu(Ops.CAST,
# arg=dt)` (mixin/dtype.py:38) -- IT FOLDS ON AN IDENTITY CAST. So the graph is
# CAST(self, bool) -> CMPEQ(cast, CONST(False)) when self is NOT bool and NO CAST AT ALL when
# it is, and that is not a carve-out: it is the whole of `cast`.
#
# `O.UOp.cast` (ops.bend:2774) MINTS THE NODE UNCONDITIONALLY -- `UOp.new(ar, OpsCAST{}, ...)`.
# That was the one extra `CAST` on `tn_eq`, `tn_dunder_ge`, `tn_dunder_le`,
# `tn_dunder_invert` and `tn_isfinite`, every one of which is a `logical_not` over a node the
# fold already knows is `bool` (a CMPNE, a CMPLT or an OR -- uop/fold.bend:2644 symbol=dt_shape answers
# `bool` for the first two and `promo_dtype` for the third). The fold-aware cast is
# `D.cast_at` (dtype.bend:341), the same `cast_at.of` two-arm match `mixin/elementwise.bend`'s
# `ew_cast` reaches through `W.wk_cast_at`, and it is `D` rather than `W` because
# `wk_eq_dt` is stale (see the header). `F.folded(Tensor.ar(t))` is `ew_fx`'s exact call:
# the fold is taken from the tensor's OWN arena at the point of use, never handed down.
#
# It is declared BEFORE `tn_bitwise_not` because that def's BOOL arm calls it, and a Bend
# def may only call defs DECLARED ABOVE IT (rule 1 in the header). `bitwise_not`'s bool arm
# IS this graph, so the two graphs ARE equal for a bool self; they are held apart only
# because `logical_not` (:49) and `bitwise_not` (:145) are sibling methods with different
# bodies around the shared one.
# `Arena` is an IMMUTABLE `Data` VALUE (`ops.bend:1255`: `type Arena is Data: Arena{nodes,
# shp}`), so a `Found` SNAPSHOTS the arena at its own construction and every index is
# only meaningful in the arena value that index was minted in. `false_c.ar` has the
# CAST AND the CONST (3 slots); `cast.ar` has the CAST only (2 slots). Building the
# CMPEQ in `cast.ar` therefore APPENDS it at the slot `O.Found.i(false_c)` already names
# -- the node becomes its own `src[1]`. MEASURED, `./bin/bend` on a `CInt` input, with
# `O.Rng.sig` (uop/ops.bend:5978 symbol=Rng.sig) as the instrument: `CMPEQ/2 Ops.CAST
# Ops.CMPEQ` (src[1] IS the top node) where CPython answers `CMPEQ(CAST(CONST()),
# CONST(False))` (`/tmp/cp_shape.py`, `tinygrad`). So the CMPEQ is built in `false_c.ar`,
# the newest.
#
# `logical_not` -- elementwise.py:57 AT `f5ac54685074` -- is
# `self.cast(dtypes.bool).eq(False)`, so it is a CAST and a CMPEQ against the CONST
# `False`. THE NAME DID NOT CHANGE AND THE NODE DID: the pre-pin spelling was
# `self.cast(dtypes.bool).eq(False)`, which builds `CMPEQ(x, CONST(False))`.
# MEASURED 2026-11-10 ON CPYTHON AT THE PIN: `a.logical_not()` emits
# `CMPEQ(CAST(a), CONST(False))`.
#
# AND THIS IS NOT A STYLISTIC CHOICE: UPSTREAM's OWN `symbolic.py:349` KEYS ON IT --
# `neg = v.op is Ops.CMPEQ and v.src[1].op is Ops.CONST and v.src[1].val == 0` -- so a
# graph that says `CMPNE` is NOT upstream's graph. AND THE PORT's OWN
# `uop/symbolic.bend`'s `mint_not` ALREADY BUILDS THE `CMPEQ` SPELLING -- so THIS file was
# the only half on the pre-pin spelling.
