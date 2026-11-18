<!-- FROM: tinybendygrad/codegen/decomp/dtype.bend:2159 -->
# BLOCK:
# `do_dtype_decomps` -- dtype.py:208-216. The one thing here that is NOT the
# wall is the TABLE CHOICE: `pm = pm_float_decomp if fr in dtypes.floats else
# pm_long_decomp`, which is the difference between decomposing a long and
# decomposing a float, so it is a `Bool` the gate reads.
#
# UPSTREAM'S TWO RULE COMMENTS NAME THE TWO PHASES OF THE TABLE:
#
#   "detect dtypes to decompose" (209)
#       so the FIRST rule does not decompose -- it DETECTS. It walks every
#       node and records the dtype that has to be emulated, and the SECOND
#       rule does the actual work. That is why the detection is a `set` in
#       the context and why the decomposition loop runs once per dtype.
#   "do the rewrites" (212)
#       and the decomposition is per-dtype and BOTTOM-UP: `fr in dtypes.floats`
#       picks the float table and everything else picks the long one, and the
#       dtype is decomposed into `int` for a long and into `float` for a
#       float.
# END BLOCK

# `do_dtype_decomps` -- dtype.py:208-216. The one thing here that is NOT the
# wall is the TABLE CHOICE: `pm = pm_float_decomp if fr in dtypes.floats else
# pm_long_decomp`, which is the difference between decomposing a long and
# decomposing a float, so it is a `Bool` the gate reads.
#
# UPSTREAM'S TWO RULE COMMENTS NAME THE TWO PHASES OF THE TABLE:
#
#   "detect dtypes to decompose" (209)
#       so the FIRST rule does not decompose -- it DETECTS. It walks every
#       node and records the dtype that has to be emulated, and the SECOND
#       rule does the actual work. That is why the detection is a `set` in
#       the context and why the decomposition loop runs once per dtype.
#   "do the rewrites" (212)
#       and the decomposition is per-dtype and BOTTOM-UP: `fr in dtypes.floats`
#       picks the float table and everything else picks the long one, and the
#       dtype is decomposed into `int` for a long and into `float` for a
#       float.
