<!-- FROM: tinybendygrad/uop/validate.bend:124 at ba3f52b0a^; ba3f52b0a REPLACED the block -->
# BLOCK:
# `Z` -- A z3 TERM. Not a value: nothing in this file is ever evaluated, and
# that is the point. `ZLit.v` is TWO'S COMPLEMENT (`-4` is 4294967292) because
# `z3.IntVal` takes a Python int and `u.arg` carries negatives:
# `buf.index(r & -4)` is in tinygrad's own test, test_validate_oob.py:97.
# `is_b` is the z3 SORT, which is what `isinstance(a, z3.BoolRef)` asks in
# `z3_and`/`z3_or`/`z3_xor`; it is a field rather than a `Z.is_b` recursion
# because every constructor here knows its own sort except `ZIf`.
# the gate has an oracle, and it is green on 80 of 90 shared rows.
#
# There was none until now, and that is the whole reason three rows were able to move in an
# unadjudicated direction: `dv_and15`/`dv_and21`/`dv_and_neg4` went from `- 1` to `- 256` in a
# region with no CPython oracle anywhere in `.agents/slop/`, so no reader existed that could have
# said the new value was wrong. The oracle is `.agents/slop/validate-oracle.py`; it calls
# `uops_to_z3` live. The reader is `.agents/slop/validate-gate.py`; it uses
# `rebase-gate.py`'s `rows()` and reports the DENOMINATOR.
#
#     port 155 rows, oracle 364 rows, SHARED 138, agree 123, disagree 15   (MEASURED)
#
# ⚠ THE PRIOR PREMISE WAS FALSE. This header used to record, as the reason `dv_and*` could not be
# adjudicated: "`z3` IS NOT INSTALLED IN THIS ENVIRONMENT". z3 IS installed --
# `z3.get_version()` is `(4, 16, 0, 0)`, `validate.py`'s own version gate at line 8 passes, and
# `import tinygrad.uop.validate` gives a live `z3_bv`. Rows `z3_ok`, `z3_d3` and
# `validate_import` in the oracle exist so a reader can check that in one command instead of
# taking it on trust. The rows were never un-adjudicable; they were un-oracled.
#
# reading, and every one is a mutation in `.agents/slop/validate-mutate.py` that moves rows AWAY
# from CPython when reverted:
#
#   the arena `dv2` builds the SINK in -- `Found.ar(g)`, not `Found.ar(t)`. The gate is interned
#     AFTER `t`, so `Found.ar(t)` is the store without it, and the walk read a node that is not
#     the gate. M3: 34 rows, disagree 10 -> 33.
#   `vz_cint` could not read a `CBool` CONST, so rule 7 MISSED on every gate and nothing was ever
#     added to the solver. This was the real cause of the missing `True`, not the missing
#     `solver.add`. M5: 68 rows, disagree 10 -> 60.
#   `solver.add(z3_mask)` -- validate.py:95 -- now happens (`vz_add_mask`).
#   `pow2`'s `m > 0` was written as a sign-bit test, which is False for every positive power of
#     two. `r & 15` and `r & -4` therefore took the bit-blast arm. `m != 0` is the same predicate
#     (`m & (m-1) == 0` forces m positive), and the theorem is checked as `pow2_fn_agree`.
#     M4: 6 rows, disagree 10 -> 16.
#   `create_bounded` built `Le(vmin, sym)`. With `vmin` a Python `int`, validate.py:51 REFLECTS
#     and z3 receives `Ge(sym, vmin)`. M6: 24 rows, disagree 10 -> 29.
#   `Ops.MAX` was reaching the `k`-tag ladder as `k = 0` and being silently MODded. `dv_max`
#     is the row that found it. M7: 3 rows, disagree 10 -> 13.
#   `range_str` and the violation join both DROPPED their first element (a `Bool` flag that took
#     the accumulator arm on the head), which is why `dv_const_ok` printed `[]` where CPython
#     prints `[True]` and why `dv_unsup_stack` reported one violation with no message.
#   `Sol.put` appended every node's TERM to the assertion list. M8: 34 rows, 10 -> 33.
#   `z3_lt` -- z3 canonicalises `a < n` to `n > a` when `n` is a z3 numeral and NOT when it is a
#     Python `int`, and `python_alu[CMPLT]` is `operator.lt`. M9: 5 rows, 15 -> 18.
#   `Ops.TRUNCDIV` was `k = 2`, i.e. `z3_floordiv`, and those are DIFFERENT FUNCTIONS. Two `z3_alu`
#     keys on one tag, and for a POSITIVE divisor they agree on shape and disagree on nothing
#     visible -- which is why nothing caught it. `dv_cdiv4` caught it.
#   NO PARENTHESES AT ALL: `dv_xor_m1` printed `-r0 + 1` where CPython prints `-(r0 + 1)`, and
#     THOSE ARE DIFFERENT FUNCTIONS. The rule is 60 measured cases and it is in `Z.par`.
#
# what the eight new `z3_alu` rows found on their first run, which is the argument for adding them
# rather than only naming the gap: before them 4 of the 11 keys had a fixture that REACHED them
# and SEVEN did not, `n_z3_alu=11` passed throughout, and the first gate run over the new rows
# reported FOUR defects -- `Ops.TRUNCDIV` floormodded, the missing parentheses, and `z3_xor's` `-(x+1)`
# printing as `-x + 1`. A membership count is not coverage; eight rows found three real bugs the
# day they were written.
#
# WHAT IS STILL RED, and each is a NAMED remaining difference rather than an unexplained one:
#
#   dv_shr2*, dv_shl2*      z3's `FreshInt` appends a per-CONTEXT counter: `invalid_shift!0`. The
#                           port prints the bare name. The `_term_nb` rows are the same rows with
#                           the counter suffix removed on BOTH sides and THEY AGREE, so everything
#                           else about both terms is CPython-exact. M11 (the shift factor doubled)
#                           moves 6 rows AWAY, so `dv_shr2_term_nb` is a real gate and not a
#                           normalised-away comparison.
#   dv_cmod4*, and ONLY that ONE SPACE   the port prints `*4` and `_term` prints `* 4`. EVIDENCE,
#                           not assertion: oracle row `#raw_cmod4` is the raw z3 string and it
#                           ENDS `r0/4)*\n4` -- z3 put a NEWLINE where it printed no space, and
#                           collapsing the wrap to a space invents one. THE PORT IS RIGHT AND
#                           the oracle's own normalisation is wrong here. a second encoding
#                           (`_term_ns`, wrap deleted with nothing) was built to fix it and is
#                           ALSO unsound in the opposite direction -- z3 wraps after a comma too,
#                           so it disagreed on 5 rows where the port is right -- and was removed.
#                           Neither whitespace normalisation of z3 output is sound; one primary
#                           encoding plus a named residual with the raw text is the honest form.
#   dv_where, dv_where_cs   FIXED. The port emitted `And(v >= 0, v <= 15)` TWICE because
#                           `ops.py:302`'s THIRD branch (`if node in cache: continue`) was
#                           missing: `seen` was CPython's `visited` flag AND the cache
#                           membership at once, so an already-visited node was re-pushed and,
#                           `cache` being a LIST, appended twice. Located by COUNTING both
#                           arenas -- `arena_nodes=6` on both sides, so the arena was EXCLUDED as
#                           the cause -- and by NAMING the duplicate rather than counting it:
#                           `walk_ops` read `Ops.PARAM ... Ops.PARAM ...`. `vz_step.seen` is the
#                           restored branch and `dv_where_walk` is the row; see `vz_step.keep`.
#   dv_unsup_stack          CPython RAISES `NotImplementedError`; the port answers with a
#   dv_unsup_two            violation LIST. Same for `AssertionError` and `TypeError` below. This
#   dv_rank_shr1            is the declared design difference, not a mystery: the port cannot
#   dv_bad_dtype_bitcast    raise. `_msg` rows carry the message TEXT, which both sides share.
#
# THE `dv_bad_dtype_bitcast` FIXTURE IS NOW ADJUDICABLE, and the stated requirement was FALSE.
# -- so the row could never be adjudicated as written. The constructible spelling is
# `O.ADt{S.boolean()}`, and `ADt` is ALREADY an exported `Arg` -- `ops.bend`'s own `s5.arena`
# builds `Ops.BITCAST` with `ADt{S.single()}` at slot 8 -- so NO `ops.bend` CHANGE IS NEEDED
# and the "dtype-carrying Arg" the brief asked for already existed. MEASURED: the port's
# `dv_bad_dtype_bitcast_msg` is now byte-identical to CPython's `NotImplementedError` message,
# and the row's remaining redness is ONLY the raise-vs-list shape shared with the three above.
#
# ALSO CORRECTED BY CALLING, because the refusal is NOT where anybody said it was:
# `UOp(Ops.BITCAST, (r, r))` CONSTRUCTS with `arg=None` and prints fine. The assert fires on
# the first `.dtype` READ -- `ops.py:122` is `dtype_from_uop(op, src, arg)` and `UOp.__init__`
# never calls it eagerly. Oracle rows `dv_bad_dtype_bitcast_argless_construct=ok` and
# `dv_bad_dtype_bitcast_argless_dtype=RAISED AssertionError: CAST/BITCAST arg must be DType,
# got None`. "The constructor refuses" and "the dtype read refuses" are different facts and a
# row that collapses them is a row about neither.
#   * `dv_rank_shr1`'s header used to claim CPython raises `IndexError: tuple index out of range`.
#     It does not: `z3_alu[Ops.SHL]` is called as `(x, *srcs)` with ONE src, so it raises
#     `TypeError: z3_shift() missing 1 required positional argument: 'b'`.
# the gate is red. this is the measured defect list and it is not fitted away.
#
# Both lanes are byte-identical and `ALL PROOFS CHECK`. The gate is red against
# CPython, and the rows name the defects. The renderer, the walk, the ten-rule
# tag ladder, the term IR, the violation list, and `O.Ops.name` as the
# `NotImplementedError` text all WORK; the PRINTER and two FIXTURES do not.
#
# defect | rows | what the port prints | what CPython prints (MEASURED)
# --------|------|---------------------|------------------------------
# D1 z3's `Le` printer orientation is UNRESOLVED and this port guessed wrong.
#    Two CPython measurements disagree with EACH OTHER: `0 <= i` printed
#    `i >= 0`, and `z3.IntVal(0, ctx) <= r0` printed `0 <= r0`. Same z3 build.
#    The port hoists iff the other side is a symbol, which gets the first right
#    and the second wrong.
#    | dv_var, dv_range_* | `And(v >= 0, v >= 15)` | `And(i >= 0, i <= 15)`
# D2 the same, on the RANGE's upper bound `ctx[1][src[0]] - 1`.
#    | dv_range_global | `And(r >= 0, 100 - 1 <= r)` | `And(r0 >= 0, r0 <= 100 - 1)`
# D3 `range_str` loses the axis id, so the symbol is `r` and not `r0`.
#    | dv_range_global, dv_range_loop, dv_range_m1 | `r` | `r0`, `rm1`
# D4 the `Sol` is written on a `Bool.pick` that also READS it, so entries and
#    assertions are duplicated.
#    | dv_var | `[, i]` | `[And(i >= 0, i <= 15), True]`
# D5 THE MASK IS NEVER ADDED. `uops_to_z3:95` does `solver.add(z3_mask)` and
#    nothing ported does, so no row can print the trailing `True` CPython always
#    prints. One line, and it is the first thing to fix.
#    | every row | `[]` / `[, i]` | `[..., True]`
# D6 `z3_and` takes the BIT-BLAST arm for `r & 15` AND for `r & -4`, so `pow2`
#    is not firing.
#    | dv_and15 | the `int_to_bv(...)` text | `(mod r0 16)`
#    | dv_and_neg4 | the `int_to_bv(...)` text | `r0 - r0%4`
# D7 `dv_unsup_two` and `dv_bad_dtype_bitcast` report ZERO violations. The
#    single-node `dv_unsup_stack` DOES report one, so the
#    `Ops.STACK is not supported by z3` TEXT is verified and the COUNT row and
#    the bitcast row are not.
# D8 `dv_rank_shr1` and `dv_unsup_stack` each report one violation and the
#    counts are right, but their MESSAGES are PORT-ADDED: CPython raises
#    `IndexError` on the first rather than returning a message. Marked as such.
#
# WHAT IS CONFIRMED AGAINST A CPython MEASUREMENT: `dv_const_ok` (`[] | 15 |
# | 0`), `dv_shr2`'s `If(0 > 2, invalid_shift, r/4)` shape,
# `dv_const_invalid`'s `Invalid`, and `n_z3_alu=11`. Those four, and nothing else.
#
# NEXT, in order, and none of it is a nice-to-have: D5 (one line -- the mask is
# the `CONST(True)` node and `uops_to_z3` must `Sol.add` it), D3 (one line --
# `rs_ids.go`'s separator test), D1/D2 (re-measure z3's `Le` printer in ONE
# process with ONE context and settle it; two measurements already disagree),
# D4 (find the `Bool.pick` that both reads and writes `Sol`), D6 (`pow2` on a
# literal held two's complement), D7 (the gate on `Ops.GROUP` and the BITCAST
# shape test).
# END BLOCK

# `Z` -- A z3 TERM. Not a value: nothing in this file is ever evaluated, and
# that is the point. `ZLit.v` is TWO'S COMPLEMENT (`-4` is 4294967292) because
# `z3.IntVal` takes a Python int and `u.arg` carries negatives:
# `buf.index(r & -4)` is in tinygrad's own test, test_validate_oob.py:97.
# `is_b` is the z3 SORT, which is what `isinstance(a, z3.BoolRef)` asks in
# `z3_and`/`z3_or`/`z3_xor`; it is a field rather than a `Z.is_b` recursion
# because every constructor here knows its own sort except `ZIf`.
# the gate has an oracle, and it is green on 80 of 90 shared rows.
#
# There was none until now, and that is the whole reason three rows were able to move in an
# unadjudicated direction: `dv_and15`/`dv_and21`/`dv_and_neg4` went from `- 1` to `- 256` in a
# region with no CPython oracle anywhere in `.agents/slop/`, so no reader existed that could have
# said the new value was wrong. The oracle is `.agents/slop/validate-oracle.py`; it calls
# `uops_to_z3` live. The reader is `.agents/slop/validate-gate.py`; it uses
# `rebase-gate.py`'s `rows()` and reports the DENOMINATOR.
#
#     port 155 rows, oracle 364 rows, SHARED 138, agree 123, disagree 15   (MEASURED)
#
# ⚠ THE PRIOR PREMISE WAS FALSE. This header used to record, as the reason `dv_and*` could not be
# adjudicated: "`z3` IS NOT INSTALLED IN THIS ENVIRONMENT". z3 IS installed --
# `z3.get_version()` is `(4, 16, 0, 0)`, `validate.py`'s own version gate at line 8 passes, and
# `import tinygrad.uop.validate` gives a live `z3_bv`. Rows `z3_ok`, `z3_d3` and
# `validate_import` in the oracle exist so a reader can check that in one command instead of
# taking it on trust. The rows were never un-adjudicable; they were un-oracled.
#
# reading, and every one is a mutation in `.agents/slop/validate-mutate.py` that moves rows AWAY
# from CPython when reverted:
#
#   the arena `dv2` builds the SINK in -- `Found.ar(g)`, not `Found.ar(t)`. The gate is interned
#     AFTER `t`, so `Found.ar(t)` is the store without it, and the walk read a node that is not
#     the gate. M3: 34 rows, disagree 10 -> 33.
#   `vz_cint` could not read a `CBool` CONST, so rule 7 MISSED on every gate and nothing was ever
#     added to the solver. This was the real cause of the missing `True`, not the missing
#     `solver.add`. M5: 68 rows, disagree 10 -> 60.
#   `solver.add(z3_mask)` -- validate.py:95 -- now happens (`vz_add_mask`).
#   `pow2`'s `m > 0` was written as a sign-bit test, which is False for every positive power of
#     two. `r & 15` and `r & -4` therefore took the bit-blast arm. `m != 0` is the same predicate
#     (`m & (m-1) == 0` forces m positive), and the theorem is checked as `pow2_fn_agree`.
#     M4: 6 rows, disagree 10 -> 16.
#   `create_bounded` built `Le(vmin, sym)`. With `vmin` a Python `int`, validate.py:51 REFLECTS
#     and z3 receives `Ge(sym, vmin)`. M6: 24 rows, disagree 10 -> 29.
#   `Ops.MAX` was reaching the `k`-tag ladder as `k = 0` and being silently MODded. `dv_max`
#     is the row that found it. M7: 3 rows, disagree 10 -> 13.
#   `range_str` and the violation join both DROPPED their first element (a `Bool` flag that took
#     the accumulator arm on the head), which is why `dv_const_ok` printed `[]` where CPython
#     prints `[True]` and why `dv_unsup_stack` reported one violation with no message.
#   `Sol.put` appended every node's TERM to the assertion list. M8: 34 rows, 10 -> 33.
#   `z3_lt` -- z3 canonicalises `a < n` to `n > a` when `n` is a z3 numeral and NOT when it is a
#     Python `int`, and `python_alu[CMPLT]` is `operator.lt`. M9: 5 rows, 15 -> 18.
#   `Ops.TRUNCDIV` was `k = 2`, i.e. `z3_floordiv`, and those are DIFFERENT FUNCTIONS. Two `z3_alu`
#     keys on one tag, and for a POSITIVE divisor they agree on shape and disagree on nothing
#     visible -- which is why nothing caught it. `dv_cdiv4` caught it.
#   NO PARENTHESES AT ALL: `dv_xor_m1` printed `-r0 + 1` where CPython prints `-(r0 + 1)`, and
#     THOSE ARE DIFFERENT FUNCTIONS. The rule is 60 measured cases and it is in `Z.par`.
#
# what the eight new `z3_alu` rows found on their first run, which is the argument for adding them
# rather than only naming the gap: before them 4 of the 11 keys had a fixture that REACHED them
# and SEVEN did not, `n_z3_alu=11` passed throughout, and the first gate run over the new rows
# reported FOUR defects -- `Ops.TRUNCDIV` floormodded, the missing parentheses, and `z3_xor's` `-(x+1)`
# printing as `-x + 1`. A membership count is not coverage; eight rows found three real bugs the
# day they were written.
#
# WHAT IS STILL RED, and each is a NAMED remaining difference rather than an unexplained one:
#
#   dv_shr2*, dv_shl2*      z3's `FreshInt` appends a per-CONTEXT counter: `invalid_shift!0`. The
#                           port prints the bare name. The `_term_nb` rows are the same rows with
#                           the counter suffix removed on BOTH sides and THEY AGREE, so everything
#                           else about both terms is CPython-exact. M11 (the shift factor doubled)
#                           moves 6 rows AWAY, so `dv_shr2_term_nb` is a real gate and not a
#                           normalised-away comparison.
#   dv_cmod4*, and ONLY that ONE SPACE   the port prints `*4` and `_term` prints `* 4`. EVIDENCE,
#                           not assertion: oracle row `#raw_cmod4` is the raw z3 string and it
#                           ENDS `r0/4)*\n4` -- z3 put a NEWLINE where it printed no space, and
#                           collapsing the wrap to a space invents one. THE PORT IS RIGHT AND
#                           the oracle's own normalisation is wrong here. a second encoding
#                           (`_term_ns`, wrap deleted with nothing) was built to fix it and is
#                           ALSO unsound in the opposite direction -- z3 wraps after a comma too,
#                           so it disagreed on 5 rows where the port is right -- and was removed.
#                           Neither whitespace normalisation of z3 output is sound; one primary
#                           encoding plus a named residual with the raw text is the honest form.
#   dv_where, dv_where_cs   FIXED. The port emitted `And(v >= 0, v <= 15)` TWICE because
#                           `ops.py:302`'s THIRD branch (`if node in cache: continue`) was
#                           missing: `seen` was CPython's `visited` flag AND the cache
#                           membership at once, so an already-visited node was re-pushed and,
#                           `cache` being a LIST, appended twice. Located by COUNTING both
#                           arenas -- `arena_nodes=6` on both sides, so the arena was EXCLUDED as
#                           the cause -- and by NAMING the duplicate rather than counting it:
#                           `walk_ops` read `Ops.PARAM ... Ops.PARAM ...`. `vz_step.seen` is the
#                           restored branch and `dv_where_walk` is the row; see `vz_step.keep`.
#   dv_unsup_stack          CPython RAISES `NotImplementedError`; the port answers with a
#   dv_unsup_two            violation LIST. Same for `AssertionError` and `TypeError` below. This
#   dv_rank_shr1            is the declared design difference, not a mystery: the port cannot
#   dv_bad_dtype_bitcast    raise. `_msg` rows carry the message TEXT, which both sides share.
#
# THE `dv_bad_dtype_bitcast` FIXTURE IS NOW ADJUDICABLE, and the stated requirement was FALSE.
# -- so the row could never be adjudicated as written. The constructible spelling is
# `O.ADt{S.boolean()}`, and `ADt` is ALREADY an exported `Arg` -- `ops.bend`'s own `s5.arena`
# builds `Ops.BITCAST` with `ADt{S.single()}` at slot 8 -- so NO `ops.bend` CHANGE IS NEEDED
# and the "dtype-carrying Arg" the brief asked for already existed. MEASURED: the port's
# `dv_bad_dtype_bitcast_msg` is now byte-identical to CPython's `NotImplementedError` message,
# and the row's remaining redness is ONLY the raise-vs-list shape shared with the three above.
#
# ALSO CORRECTED BY CALLING, because the refusal is NOT where anybody said it was:
# `UOp(Ops.BITCAST, (r, r))` CONSTRUCTS with `arg=None` and prints fine. The assert fires on
# the first `.dtype` READ -- `ops.py:122` is `dtype_from_uop(op, src, arg)` and `UOp.__init__`
# never calls it eagerly. Oracle rows `dv_bad_dtype_bitcast_argless_construct=ok` and
# `dv_bad_dtype_bitcast_argless_dtype=RAISED AssertionError: CAST/BITCAST arg must be DType,
# got None`. "The constructor refuses" and "the dtype read refuses" are different facts and a
# row that collapses them is a row about neither.
#   * `dv_rank_shr1`'s header used to claim CPython raises `IndexError: tuple index out of range`.
#     It does not: `z3_alu[Ops.SHL]` is called as `(x, *srcs)` with ONE src, so it raises
#     `TypeError: z3_shift() missing 1 required positional argument: 'b'`.
# the gate is red. this is the measured defect list and it is not fitted away.
#
# Both lanes are byte-identical and `ALL PROOFS CHECK`. The gate is red against
# CPython, and the rows name the defects. The renderer, the walk, the ten-rule
# tag ladder, the term IR, the violation list, and `O.Ops.name` as the
# `NotImplementedError` text all WORK; the PRINTER and two FIXTURES do not.
#
# defect | rows | what the port prints | what CPython prints (MEASURED)
# --------|------|---------------------|------------------------------
# D1 z3's `Le` printer orientation is UNRESOLVED and this port guessed wrong.
#    Two CPython measurements disagree with EACH OTHER: `0 <= i` printed
#    `i >= 0`, and `z3.IntVal(0, ctx) <= r0` printed `0 <= r0`. Same z3 build.
#    The port hoists iff the other side is a symbol, which gets the first right
#    and the second wrong.
#    | dv_var, dv_range_* | `And(v >= 0, v >= 15)` | `And(i >= 0, i <= 15)`
# D2 the same, on the RANGE's upper bound `ctx[1][src[0]] - 1`.
#    | dv_range_global | `And(r >= 0, 100 - 1 <= r)` | `And(r0 >= 0, r0 <= 100 - 1)`
# D3 `range_str` loses the axis id, so the symbol is `r` and not `r0`.
#    | dv_range_global, dv_range_loop, dv_range_m1 | `r` | `r0`, `rm1`
# D4 the `Sol` is written on a `Bool.pick` that also READS it, so entries and
#    assertions are duplicated.
#    | dv_var | `[, i]` | `[And(i >= 0, i <= 15), True]`
# D5 THE MASK IS NEVER ADDED. `uops_to_z3:95` does `solver.add(z3_mask)` and
#    nothing ported does, so no row can print the trailing `True` CPython always
#    prints. One line, and it is the first thing to fix.
#    | every row | `[]` / `[, i]` | `[..., True]`
# D6 `z3_and` takes the BIT-BLAST arm for `r & 15` AND for `r & -4`, so `pow2`
#    is not firing.
#    | dv_and15 | the `int_to_bv(...)` text | `(mod r0 16)`
#    | dv_and_neg4 | the `int_to_bv(...)` text | `r0 - r0%4`
# D7 `dv_unsup_two` and `dv_bad_dtype_bitcast` report ZERO violations. The
#    single-node `dv_unsup_stack` DOES report one, so the
#    `Ops.STACK is not supported by z3` TEXT is verified and the COUNT row and
#    the bitcast row are not.
# D8 `dv_rank_shr1` and `dv_unsup_stack` each report one violation and the
#    counts are right, but their MESSAGES are PORT-ADDED: CPython raises
#    `IndexError` on the first rather than returning a message. Marked as such.
#
# WHAT IS CONFIRMED AGAINST A CPython MEASUREMENT: `dv_const_ok` (`[] | 15 |
# | 0`), `dv_shr2`'s `If(0 > 2, invalid_shift, r/4)` shape,
# `dv_const_invalid`'s `Invalid`, and `n_z3_alu=11`. Those four, and nothing else.
#
# NEXT, in order, and none of it is a nice-to-have: D5 (one line -- the mask is
# the `CONST(True)` node and `uops_to_z3` must `Sol.add` it), D3 (one line --
# `rs_ids.go`'s separator test), D1/D2 (re-measure z3's `Le` printer in ONE
# process with ONE context and settle it; two measurements already disagree),
# D4 (find the `Bool.pick` that both reads and writes `Sol`), D6 (`pow2` on a
# literal held two's complement), D7 (the gate on `Ops.GROUP` and the BITCAST
# shape test).
