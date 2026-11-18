<!-- FROM: tinybendygrad/mixin/dtype.bend:172 -->
# BLOCK:
# THE INTEGER LIMITS, and `commit_int` / `strong_dtype` with them. See the header:
# these three defs are hoisted out of `tinybendygrad/dtype.bend` under the notice
# that names them, because that file's fp16/bf16/fp8/i64 conversions are C effects
# and so ANY importer fails `--check-only` with "14 defs rely on unsafe or foreign
# code". Two of the constants are CORRECTED against CPython; the header names both.
#
# The bounds are I64 because dtype.py takes Python ints and the ladder's top rung is
# uint64, whose max has no U32 image. Two consequences, both facts rather than
# simplifications:
#
#   * every I64 is inside int64's range, so the ladder's int64 rung always fits and its
#     uint64 rung can never be reached. dtype.py returns `long` off the end anyway, so
#     the answers agree -- dtype.bend:471-474 records this and it is unchanged.
#   * the ladder starts at default_int, which may already be int32, so the int32 test
#     runs twice in that case. That is dtype.py's behaviour, kept.
# END BLOCK

# THE INTEGER LIMITS, and `commit_int` / `strong_dtype` with them. See the header:
# these three defs are hoisted out of `tinybendygrad/dtype.bend` under the notice
# that names them, because that file's fp16/bf16/fp8/i64 conversions are C effects
# and so ANY importer fails `--check-only` with "14 defs rely on unsafe or foreign
# code". Two of the constants are CORRECTED against CPython; the header names both.
#
# The bounds are I64 because dtype.py takes Python ints and the ladder's top rung is
# uint64, whose max has no U32 image. Two consequences, both facts rather than
# simplifications:
#
#   * every I64 is inside int64's range, so the ladder's int64 rung always fits and its
#     uint64 rung can never be reached. dtype.py returns `long` off the end anyway, so
#     the answers agree -- dtype.bend:471-474 records this and it is unchanged.
#   * the ladder starts at default_int, which may already be int32, so the int32 test
#     runs twice in that case. That is dtype.py's behaviour, kept.
