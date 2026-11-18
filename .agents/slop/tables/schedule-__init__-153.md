<!-- FROM: tinybendygrad/schedule/__init__.bend:153 -->
# BLOCK:
# NOT PORTED, ONE LINE EACH, WITH THE WALL BEHIND IT.
#
# TODO(p3) __init__.py:18 symbol=_states  `_states`' assert -- a raise, as above.
# WALL(p3) __init__.py:28  the AssertionError in _split_after (see above) -- BLOCKED: needs Python's `raise AssertionError`; the port DROPS the invalid src instead (`Split` carries only Python's two fields) and `split_bad_ks` pins the drop.
# WALL(p3) __init__.py:62  `t not in k.backward_slice` is read as a nocalls
#   toposort; that is EXACT, and the header explains why -- NOT A GAP: `sc_in_bs` reads `O.UOp.toposort_nocalls` and `wt_keep` applies `t is not k` FIRST (:885-886), so the two predicates are the SAME.
# TODO(p3) __init__.py:78  `raise RuntimeError("cycle detected in assign graph")`
#   -- a raise, as above. `COUNT_fx*_cyc` in the gate is the observable it guards, and it is 1
#   for fx2 and fx5 and 0 for fx1, so a cycle is visible as a non-empty answer even though the
#   raise is not.
# wall(p3) ops.py:107     `buf_uop`'s mselect and mstack arms (see above) -- blocked: needs the arena threaded through a walk that constructs (interns) a UOp: mselect is `src[0].buf_uop.mselect(self.arg)` (tinygrad/uop/ops.py:911 symbol=buf_uop) and mstack rebuilds `UOp(MSTACK, ...)` (:925). Both arms are multi-device (`schedule/multi.py`) and read only by `create_schedule`'s `buf_uops` line; the port's walk is a fuel fold that stops at mstack.
# TODO(p3) __init__.py:66-80  the `while queue` loop is a fuel fold, not a while.
#   The queue is a `List` in Python's DEQUE ORDER -- `popleft` is a head pop and `append` is
#   `List.append`, which is `qs ++ [x]` and O(n) -- so the loop's own list is re-wrapped by the
#   BUILTIN and not by a constructor in this file. `z_pick` and `lk.put` say which end each
#   operation is on, because getting either wrong still typechecks and still terminates.
#
# AND THE THIRTEEN NAMES IN __init__.py:82-301 THAT THE PORT DOES NOT HAVE:
#
#   create_new_buffer resolve_linear_call pm_resolve_linear_call
#   pm_schedule pm_copy_from_store contiguous_mops_to_view
#   pm_callify_ctx_collect canonicalize_call_body pm_canonicalize_alloc
#   replace_input_buffer pm_replace_buf transform_to_call
#   create_linear_with_vars
#
