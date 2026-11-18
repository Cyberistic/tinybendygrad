<!-- FROM: tinybendygrad/mixin/dtype.bend:290 -->
# BLOCK:
# commit_dtype -- tinygrad/dtype.py:16-17.
#
#   return commit_int(self._uop.vmin, self._uop.vmax, default_int) \
#     if self.dtype is dtypes.weakint else strong_dtype(self.dtype)
#
# BOTH BRANCHES ARE PORTED. The weakint branch is dtype.py's own `commit_int`, hoisted
# above, which walks the ladder `(default_int, int, long, ulong)` and falls off the end
# at `long` -- the ladder's uint64 rung is unreachable because every I64 is inside
# int64's range, and dtype.py returns `long` off the end anyway, so the answers agree.
#
# `lo`/`hi` are the parameters `commit_dtype` cannot compute for itself. That is the
# whole wall and it is ONE def: `UOp._min_max` (ops.py:1104-1163). The refusal is a
# `Maybe` rather than a sentinel dtype because a wrong dtype here is not a crash, it is
# a silently wrong `commit_int` answer three rules downstream in weak.py.
# A PARAM WITH NO `vmin_vmax` -- the `cd_none` row of `gates/wk-cd-gate.py`. The bound
# reads as `Bnd{NInf}` / `Bnd{PInf}` (a saturation, since `weakint`'s bits == 800 has no
# 64-bit magnitude), and `wk_bnd_i64` cannot convert infinity to an I64, so `m`/`m2` are
# `None`. CPython's `commit_int` would answer `long` for this case: the no-bounds PARAM's
# interval is `[NInf, PInf]`, which is wider than int32 (and wider than the ladder's
# `default_int` rung), so the ladder falls off the end at `long`. THE PORT'S HONEST ANSWER
# IS THE SAME -- supply the WIDEST int range we can represent, which `commit_int` sees as
# "does not fit int32" and answers `int64`. The earlier version returned `None`, which is
# what `wk-cd-gate.py`'s `cd_none` row was pinned as a divergence on; the fix closes it.
# END BLOCK

# commit_dtype -- tinygrad/dtype.py:16-17.
#
#   return commit_int(self._uop.vmin, self._uop.vmax, default_int) \
#     if self.dtype is dtypes.weakint else strong_dtype(self.dtype)
#
# BOTH BRANCHES ARE PORTED. The weakint branch is dtype.py's own `commit_int`, hoisted
# above, which walks the ladder `(default_int, int, long, ulong)` and falls off the end
# at `long` -- the ladder's uint64 rung is unreachable because every I64 is inside
# int64's range, and dtype.py returns `long` off the end anyway, so the answers agree.
#
# `lo`/`hi` are the parameters `commit_dtype` cannot compute for itself. That is the
# whole wall and it is ONE def: `UOp._min_max` (ops.py:1104-1163). The refusal is a
# `Maybe` rather than a sentinel dtype because a wrong dtype here is not a crash, it is
# a silently wrong `commit_int` answer three rules downstream in weak.py.
# A PARAM WITH NO `vmin_vmax` -- the `cd_none` row of `gates/wk-cd-gate.py`. The bound
# reads as `Bnd{NInf}` / `Bnd{PInf}` (a saturation, since `weakint`'s bits == 800 has no
# 64-bit magnitude), and `wk_bnd_i64` cannot convert infinity to an I64, so `m`/`m2` are
# `None`. CPython's `commit_int` would answer `long` for this case: the no-bounds PARAM's
# interval is `[NInf, PInf]`, which is wider than int32 (and wider than the ladder's
# `default_int` rung), so the ladder falls off the end at `long`. THE PORT'S HONEST ANSWER
# IS THE SAME -- supply the WIDEST int range we can represent, which `commit_int` sees as
# "does not fit int32" and answers `int64`. The earlier version returned `None`, which is
# what `wk-cd-gate.py`'s `cd_none` row was pinned as a divergence on; the fix closes it.
