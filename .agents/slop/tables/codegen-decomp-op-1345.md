<!-- FROM: tinybendygrad/codegen/decomp/op.bend:1345 -->
# BLOCK:
# THE GATE, and what each row is FOR. Every row is a claim PYTHON FIXES, taken
# from `.agents/slop/dc-oracle.py`, which is the real `decomp.op` driven over the
# real `PatternMatcher`. Nothing here restates this file's own code.
#
#   nrules_s=4 / nrules_l=18 / nrules_l_noidiv=16   op.py:66 and op.py:81. THE
#                  COUNTS. `disable_fast_idiv` removes TWO rules and renumbers
#                  sixteen more, and a table that dropped the wrong one still has
#                  sixteen entries -- so `rejl6..rejl17` and `nrules_l_noidiv`
#                  are the pair that pins WHICH.
#   nrules_s_no3f=5   op.py:77's rule exists only when `Ops.THREEFRY not in ops`,
#                  so the five-rule variant is a DIFFERENT table and not this one
#                  plus a row.
#   rejN=...   the `early_reject` sets, MEASURED. A mis-spelled set shows up here
#                  and nowhere else, and rules 8/9's `[CMPLT, CONST]` and rule
#                  11's `[CONST, MUL]` are the two that a "the reject set is just
#                  the first src's op" simplification gets wrong.
#   on_<f>     did a rule fire. `0` IS Python's `None`.
#   tag_<f>    WHICH rule fired, so first-wins is observable and not just on/off.
#   out_<f>    the rewritten tree TWO LEVELS DEEP with CONST values printed.
#   grown_<f>  how many nodes the rewrite ADDED. PORT-INTERNAL (divergence A
#                  means Python's count differs) and here because it is the only
#                  NUMERIC discriminator between first-wins and last-wins.
#   tf_split   the 64-bit split `x.cast(uint32)` / `x >> 32` as DATA. `threefry2x32`
#                  is the largest arithmetic in the file and `out_s9` sees only
#                  its top two levels, so this is the row that says the halves
#                  were read in the right order.
#   nroots     how many roots the fixture arena holds. THE COUNT ROW: a fixture
#                  added or dropped moves it, and every `*_<f>` row is addressed
#                  THROUGH it, so a stale index cannot hide.
# END BLOCK

# THE GATE, and what each row is FOR. Every row is a claim PYTHON FIXES, taken
# from `.agents/slop/dc-oracle.py`, which is the real `decomp.op` driven over the
# real `PatternMatcher`. Nothing here restates this file's own code.
#
#   nrules_s=4 / nrules_l=18 / nrules_l_noidiv=16   op.py:66 and op.py:81. THE
#                  COUNTS. `disable_fast_idiv` removes TWO rules and renumbers
#                  sixteen more, and a table that dropped the wrong one still has
#                  sixteen entries -- so `rejl6..rejl17` and `nrules_l_noidiv`
#                  are the pair that pins WHICH.
#   nrules_s_no3f=5   op.py:77's rule exists only when `Ops.THREEFRY not in ops`,
#                  so the five-rule variant is a DIFFERENT table and not this one
#                  plus a row.
#   rejN=...   the `early_reject` sets, MEASURED. A mis-spelled set shows up here
#                  and nowhere else, and rules 8/9's `[CMPLT, CONST]` and rule
#                  11's `[CONST, MUL]` are the two that a "the reject set is just
#                  the first src's op" simplification gets wrong.
#   on_<f>     did a rule fire. `0` IS Python's `None`.
#   tag_<f>    WHICH rule fired, so first-wins is observable and not just on/off.
#   out_<f>    the rewritten tree TWO LEVELS DEEP with CONST values printed.
#   grown_<f>  how many nodes the rewrite ADDED. PORT-INTERNAL (divergence A
#                  means Python's count differs) and here because it is the only
#                  NUMERIC discriminator between first-wins and last-wins.
#   tf_split   the 64-bit split `x.cast(uint32)` / `x >> 32` as DATA. `threefry2x32`
#                  is the largest arithmetic in the file and `out_s9` sees only
#                  its top two levels, so this is the row that says the halves
#                  were read in the right order.
#   nroots     how many roots the fixture arena holds. THE COUNT ROW: a fixture
#                  added or dropped moves it, and every `*_<f>` row is addressed
#                  THROUGH it, so a stale index cannot hide.
