<!-- FROM: tinybendygrad/uop/symbolic.bend:7069 -->
# BLOCK:
# (THIS WAS A STACK OF 12 IDENTICAL SEPARATOR LINES -- MEASURED 2026-11-10 -- AND ONE
#  IS ENOUGH: A RUN OF IDENTICAL SEPARATORS CARRIES NOTHING THE ONE LINE DOES NOT.)
# the `nested_div` rows -- divandmod.py:23. and they are CPYTHON-confirmed against
# CPYTHON's own `nested_div` arm, and the rows read the answer's shape and its values
# AND NOT JUST "SOMETHING FIRED".
#
# AND THE MEASURED UPSTREAM ANSWERS (2026-11-09, ON CPYTHON AT `f5ac54685074`, BY
# EVALUATING UPSTREAM's OWN ARM TEXT `divandmod.py:23`):
#   `(floordiv (floormod x c8) c4)`  ->  `(mod (div x 4) 2)`
#   `(floordiv (floormod x n4) c4)`  ->  NOT REWRITTEN (THE `k = -1` AND `k.vmin > 0` FAILS)
#   `(floordiv (floormod x c2) c4)`  ->  NOT REWRITTEN (`2` DOES NOT DIVIDE `4`)
#
# - and the rows are here because the arm is, and `gates/ops-core.bend` imports this
# FILE AS `SY`.
#
# - and every INDEX is read once and every node is read once and every list is
# read once -- measured 2026-11-09, the three failures were "expected : nd / observed : nd
# (consumed more than once)", "expected : i / observed : i (consumed more than once)" AND "expected
# : s0 / observed : s0 (consumed more than once)".
# END BLOCK

# (THIS WAS A STACK OF 12 IDENTICAL SEPARATOR LINES -- MEASURED 2026-11-10 -- AND ONE
#  IS ENOUGH: A RUN OF IDENTICAL SEPARATORS CARRIES NOTHING THE ONE LINE DOES NOT.)
# the `nested_div` rows -- divandmod.py:23. and they are CPYTHON-confirmed against
# CPYTHON's own `nested_div` arm, and the rows read the answer's shape and its values
# AND NOT JUST "SOMETHING FIRED".
#
# AND THE MEASURED UPSTREAM ANSWERS (2026-11-09, ON CPYTHON AT `f5ac54685074`, BY
# EVALUATING UPSTREAM's OWN ARM TEXT `divandmod.py:23`):
#   `(floordiv (floormod x c8) c4)`  ->  `(mod (div x 4) 2)`
#   `(floordiv (floormod x n4) c4)`  ->  NOT REWRITTEN (THE `k = -1` AND `k.vmin > 0` FAILS)
#   `(floordiv (floormod x c2) c4)`  ->  NOT REWRITTEN (`2` DOES NOT DIVIDE `4`)
#
# - and the rows are here because the arm is, and `gates/ops-core.bend` imports this
# FILE AS `SY`.
#
# - and every INDEX is read once and every node is read once and every list is
# read once -- measured 2026-11-09, the three failures were "expected : nd / observed : nd
# (consumed more than once)", "expected : i / observed : i (consumed more than once)" AND "expected
# : s0 / observed : s0 (consumed more than once)".
