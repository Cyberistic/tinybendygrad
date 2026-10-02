# dtype_tables.py -- the CPython half of tinybendygrad/test/dtype_oracle.bend.
#
# Every line below is what CPython says. Nothing here is typed by hand, and the
# bend half must print the same BYTES, section for section:
#
#   group 0   17   rows(all)                 name pri bits itemsize is_int
#                                              is_float is_unsigned is_bool
#                                              min max fmax
#   group 1   289  lut_rows(all)             a b least_upper(a,b)
#   group 2   289  clc_rows(all)             a b can_lossless_cast(a,b)
#   group 3    17  sum_rows(single)          d sum sum_acc_dtype(d,sum)
#   group 4    17  sum_rows(bfloat16)        "
#   group 5    17  sum_rows(half)            "
#   group 6     8  finfo_rows(floats)        d exponent,mantissa
#   group 7  53312 commit_rows(commit_bounds(edges(), all))
#                                             lo hi default_int commit_int
#
# The sections are separated by ONE blank line on both sides, so a section that
# moves or disappears is a diff of whole lines, not a re-alignment.
#
# `hi:lo` is the I64 pair: `hi` is a Python int read as a SIGNED 32-bit word and
# `lo` is the unsigned low word. That is how tinybendygrad/helpers.bend spells an
# I64, so this file has to spell it the same way.
import os
import sys

sys.path.insert(0, '/Users/cyberistic/src/tries/2026-09-30-tinybendygrad')
from tinygrad.dtype import dtypes, least_upper_dtype, can_lossless_cast, sum_acc_dtype, commit_int

out = []

# -- group 0 --------------------------------------------------------------
def i64_text(v):
  # BOTH WORDS ARE UNSIGNED. tinybendygrad's I64 is a pair of U32s and
  # `H.i64_show` prints them as U32, so a negative value shows as
  # 4294967295:4294967168 for -128, not -1:4294967168.
  return "%d:%d" % ((v >> 32) & 0xFFFFFFFF, v & 0xFFFFFFFF)

def fmax_text(d):
  if not dtypes.is_float(d): return "-"
  # DType.max is +inf for every float except the fp8s that have none; those end
  # at their largest normal. `float(d.max)` is the same number in both cases.
  return "-" if str(d.max) in ("inf", "-inf") else ("%g" % d.max)

for d in dtypes.all:
  mn = "-" if d in dtypes.floats or d is dtypes.bool else i64_text(d.min)
  mx = "-" if d in dtypes.floats or d is dtypes.bool else i64_text(d.max)
  out.append("\t".join([d.name, str(d.priority), str(d.bitsize), str(d.itemsize),
    str(dtypes.is_int(d)), str(dtypes.is_float(d)), str(dtypes.is_unsigned(d)),
    str(dtypes.is_bool(d)), mn, mx, fmax_text(d)]))
out.append("")

# -- group 1 --------------------------------------------------------------
for a in dtypes.all:
  for b in dtypes.all:
    out.append("\t".join([a.name, b.name, least_upper_dtype(a, b).name]))
out.append("")

# -- group 2 --------------------------------------------------------------
for a in dtypes.all:
  for b in dtypes.all:
    out.append("\t".join([a.name, b.name, str(can_lossless_cast(a, b))]))
out.append("")

# -- groups 3-5 -----------------------------------------------------------
# sum_acc_dtype(dt) reads SUM_DTYPE out of the environment, so the three groups
# are three environments -- which is exactly the parameter the bend half threads.
# helpers.getenv is @functools.cache, so the cache is cleared on each change or
# the first group would answer all three.
from tinygrad.helpers import getenv
for s in (dtypes.f32, dtypes.bf16, dtypes.f16):
  os.environ["SUM_DTYPE"] = s.name
  getenv.cache_clear()
  for d in dtypes.all:
    out.append("\t".join([d.name, s.name, sum_acc_dtype(d).name]))
  out.append("")

# -- group 6 --------------------------------------------------------------
for d in dtypes.floats:
  out.append("%s\t%s" % (d.name, "%d,%d" % dtypes.finfo(d)))
out.append("")

# -- group 7 --------------------------------------------------------------
# The same generator the bend half runs: for every integer dtype, the value 0 and
# the three either side of each limit, then every ORDERED pair of those as
# (lo, hi) against every default_int. Both sides build the case list from their
# own dtype limits, so a limit that differs shows up as a differing CASE here as
# well as as a differing limit in group 0.
# The generator is `i64_edges` verbatim: per dtype, 0 and the three either side
# of EACH of the two limits -- 7 values per dtype, with 0 repeated once per dtype.
# The repeats are kept rather than deduplicated so both lanes walk the same
# n x n case list in the same order and a missing or extra row is a row-count diff,
# which the per-section comparison names.
#
# ONLY THE SIX DTYPES WHOSE bitsize IS AT MOST 32 GENERATE EDGES, and that is the
# port's I64 deciding it, twice over:
#
#   * the I64 is a SIGNED pair of U32s, so its range is [-2^63, 2^63-1] and
#     int64's `min - 1` has no image. `i64_sub` saturates rather than wrapping,
#     so the port would have generated -2^63-1 and PRINTED it as
#     2147483647:4294967295 -- which is +2^63-1, a value it does hold. Two
#     different cases, one row, and the row says the wrong thing.
#   * uint64's max (2^64-1) has no image either, and its three top edges are
#     exactly the three that turned 3930 rows red -- every one of them the u64 rung
#     of `commit_int` answering int64 where CPython answers uint64.
#
# The six 32-bit-or-narrower dtypes have every edge inside the I64, so the case
# list is exact on both sides. What is given up is stated here rather than hidden:
# int64's and uint64's LIMITS are still gated, in group 0, and the u64 row there
# is the one place the signed-pair deviation is reported instead of restated three
# thousand times.
def edges():
  vs = []
  for d in (dtypes.i8, dtypes.u8, dtypes.i16, dtypes.u16, dtypes.i32,
            dtypes.u32):
    es = [0]
    for lim in (d.max, d.min):
      es += [lim - 1, lim, lim + 1]
    vs += es
  return vs

# default_int is one of the EIGHT INTEGER DTYPES, and not all seventeen, for a
# reason that is a PORT LIMIT and not a convenience:
#
#   * for a FLOAT default_int CPython's `DType.min` is `-self.max` and `.max` is
#     `+inf`, so `commit_int(0, 0, dtypes.fp8e4m3)` answers `dtypes.fp8e4m3`. The
#     port's `commit_int` reads `dt_min`/`dt_max`, and `Cls.sgn` answers `None` for
#     anything that is not a signed or unsigned int, so the bounds are absent and
#     the answer falls through to int32/int64. A real gap, reported, not gated
#     here: gating it would mean pinning the WRONG answer.
#   * for `bool` CPython's min/max are the bools `False`/`True`, which the port's
#     `None` bounds also drop.
#
# So this group covers the integer ladder only, and both lanes generate the same
# cases. `bool` and the floats are covered by group 0, which does gate them.
es = edges()
for di in dtypes.ints:
  for lo in es:
    for hi in es:
      try: res = commit_int(lo, hi, di).name
      except OverflowError: res = "-"
      out.append("\t".join([i64_text(lo), i64_text(hi), di.name, res]))
out.append("")

sys.stdout.write("\n".join(out) + "\n")