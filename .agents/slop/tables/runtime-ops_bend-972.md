<!-- FROM: tinybendygrad/runtime/ops_bend.bend:972 -->
# BLOCK:
# :208, answered from the table: the walk from a STORE's `u.srcs[0]` lands on
# `base[u.srcs[0]]`.
# THE real :208 WALK, AND the `bases` TABLE is a FALSE EQUIVALENCE. The file's own
# header claims "which is what `while uops[b].op in {...}: b = uops[b].srcs[0]-1`
# converges to, because the chain only ever moves DOWN the post-order list" and
# tabulates `base[j]` as the largest k <= j that is not a chain op. THAT IS FALSE.
# MEASURED on `packet-tiny.txt`: the STORE is line 11 (0-based) with srcs (10, 11),
# so `b = 9`; line 9 is `INDEX f32 - 1 5`, and following its POINTER gives
# `b = 1 - 1 = 0` -- line 0, a PARAM. The table's rule gives `base[9] = 8` (the
# LOAD above it), which is a different line entirely. CPython's own answer is
# `out_bufs = [0]`, and only the pointer chase produces it.
#
# SO THE CHASE IS THE CHASE: `chase.at` is `u.srcs[0]-1` and `chase.go` is the
# `while`. It is ONE self-recursive def -- Bend refuses mutual recursion -- with the
# flag carried, exactly the shape `ops_python.bend` `bytes.go` uses.
# `ls` LEADS THE CALL, and that is forced: arguments are read left to right and the
# call must be DECREASING on a structurally matched column. `ls` is the same list
# every step, so the `Nat` fuel is what shrinks -- and it must not sit behind `ls`
# in the signature of the def that recurses.
# THE step is taken while the op is a chain op -- :208's
# `while self.uops[b].op in {...}: b = self.uops[b].srcs[0]-1`. The first version
# had the test INVERTED (`Bool.not(is_chain(...))` for the stop), so the chase never
# moved. MEASURED: `store_base.of` answered 11 where CPython answers 0.
# THE step is taken while the op is a chain op -- :208's
# `while self.uops[b].op in {...}: b = self.uops[b].srcs[0]-1` keeps MOVING while the
# test holds and STOPS when it fails. So the pick is "not a chain op -> STOP at b",
# and `chase.go` recurses with `go_` UNCHANGED, re-testing at the new b.
# END BLOCK

# :208, answered from the table: the walk from a STORE's `u.srcs[0]` lands on
# `base[u.srcs[0]]`.
# THE real :208 WALK, AND the `bases` TABLE is a FALSE EQUIVALENCE. The file's own
# header claims "which is what `while uops[b].op in {...}: b = uops[b].srcs[0]-1`
# converges to, because the chain only ever moves DOWN the post-order list" and
# tabulates `base[j]` as the largest k <= j that is not a chain op. THAT IS FALSE.
# MEASURED on `packet-tiny.txt`: the STORE is line 11 (0-based) with srcs (10, 11),
# so `b = 9`; line 9 is `INDEX f32 - 1 5`, and following its POINTER gives
# `b = 1 - 1 = 0` -- line 0, a PARAM. The table's rule gives `base[9] = 8` (the
# LOAD above it), which is a different line entirely. CPython's own answer is
# `out_bufs = [0]`, and only the pointer chase produces it.
#
# SO THE CHASE IS THE CHASE: `chase.at` is `u.srcs[0]-1` and `chase.go` is the
# `while`. It is ONE self-recursive def -- Bend refuses mutual recursion -- with the
# flag carried, exactly the shape `ops_python.bend` `bytes.go` uses.
# `ls` LEADS THE CALL, and that is forced: arguments are read left to right and the
# call must be DECREASING on a structurally matched column. `ls` is the same list
# every step, so the `Nat` fuel is what shrinks -- and it must not sit behind `ls`
# in the signature of the def that recurses.
# THE step is taken while the op is a chain op -- :208's
# `while self.uops[b].op in {...}: b = self.uops[b].srcs[0]-1`. The first version
# had the test INVERTED (`Bool.not(is_chain(...))` for the stop), so the chase never
# moved. MEASURED: `store_base.of` answered 11 where CPython answers 0.
# THE step is taken while the op is a chain op -- :208's
# `while self.uops[b].op in {...}: b = self.uops[b].srcs[0]-1` keeps MOVING while the
# test holds and STOPS when it fails. So the pick is "not a chain op -> STOP at b",
# and `chase.go` recurses with `go_` UNCHANGED, re-testing at the new b.
