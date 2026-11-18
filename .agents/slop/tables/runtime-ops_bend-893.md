<!-- FROM: tinybendygrad/runtime/ops_bend.bend:893 -->
# BLOCK:
# THE CHAIN WALK AT :208 IS NOT A LOOP HERE, and the reason is measured: Bend
# descends only on a structurally MATCHED column
# (references/bend/tests/halt/threaded_state_after.bend writes
# `case 1n+p: go(p, acc+1)`), so `ls_src0(ls, p)` -- a call -- shrinks no column
# and cannot be the fuel. Re-deriving the walk upward answers the same question
# without a descent:
#
#   base[j] = the largest k <= j whose op is NOT in the chain set
#
# which is what `while uops[b].op in {…}: b = uops[b].srcs[0]-1` converges to,
# because the chain only ever moves DOWN the post-order list. `bases.go` is a
# fold over the list tail, so it needs no descent at all.
#
# The one difference is a list whose EVERY prefix is a chain op. Python's `b`
# would go to -1 and read `uops[-1]`, i.e. the LAST line; `base[j]` is 0 there,
# and `ls_at` answers the bottom line, whose arg is "-" and which `is_buf`
# rejects. So a packet whose first line is a chain op gets no write-back instead
# of a wrong one. `bend_prog_base_zero` is the row that records it.
# END BLOCK

# THE CHAIN WALK AT :208 IS NOT A LOOP HERE, and the reason is measured: Bend
# descends only on a structurally MATCHED column
# (references/bend/tests/halt/threaded_state_after.bend writes
# `case 1n+p: go(p, acc+1)`), so `ls_src0(ls, p)` -- a call -- shrinks no column
# and cannot be the fuel. Re-deriving the walk upward answers the same question
# without a descent:
#
#   base[j] = the largest k <= j whose op is NOT in the chain set
#
# which is what `while uops[b].op in {…}: b = uops[b].srcs[0]-1` converges to,
# because the chain only ever moves DOWN the post-order list. `bases.go` is a
# fold over the list tail, so it needs no descent at all.
#
# The one difference is a list whose EVERY prefix is a chain op. Python's `b`
# would go to -1 and read `uops[-1]`, i.e. the LAST line; `base[j]` is 0 there,
# and `ls_at` answers the bottom line, whose arg is "-" and which `is_buf`
# rejects. So a packet whose first line is a chain op gets no write-back instead
# of a wrong one. `bend_prog_base_zero` is the row that records it.
