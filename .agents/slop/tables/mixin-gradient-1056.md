<!-- FROM: tinybendygrad/mixin/gradient.bend:1056 -->
# BLOCK:
# THE DRIVER -- `reduce_gradient` (gradient.py:8-18) and `call_gradient` (:20-50) are
# STILL WALLS, and `_deepwalk` / `compute_gradient` are NOT (they landed above this
# block). The three notes are kept separate because the reasons are different, and the
# two that closed are kept with their reasons CLOSED so the next reader does not
# rediscover them.
#
# `_deepwalk` -- gradient.py:109 -- LANDED. `root.topovisit(lambda u: any(in_target_path[x]
# or x in targets for x in u.src), in_target_path)` was called a wall because "the VISITOR
# is a PYTHON CALLABLE closing over a dict, which is the P4 concern every rewrite rule in
# tinygrad shares". That was TRUE OF THE SPELLING AND FALSE OF THE PROBLEM: the visitor
# reads only each node's SRCS, and a src is always EARLIER in a toposort, so ONE forward
# pass carrying a `Data` pair of parallel lists computes the same lattice. That is
# `fold.bend`'s own Kahn argument, and the pass is `dw_flags` above. The `Bool` lattice
# ("a node is on the target path iff ANY src is, with DETACH excluded", gradient.py:114)
# is `dw_any` and `dw_keep_test`. `topovisit`'s Callable is still not ported -- nothing in
# `ops.py` calls it -- and `O.UOp.topovisit` (uop/ops.bend:2943 symbol=UOp.mstack.go) still answers the plain
# toposort, which is the order this file drives.
#
# `compute_gradient` -- gradient.py:116-145 -- LANDED, with THREE named omissions.
#   (a) and (b) below were recorded as "PORTABLE, and not the wall", and they were:
#       `grads` is a `Data` pair of parallel lists with an IN-PLACE update (`gput.at`),
#       which is what makes it dict-shaped, and every update is an O(n) copy -- the same
#       trade `fold.bend` pays and calls "slow and checkable beats fast and unprovable".
#   (c) THE WALL THAT IS STILL A WALL: gradient.py:132-133, the shaped-edge reduce
#           v = v.cast(sum_acc_dtype(v.dtype))._rop(Ops.ADD, broadcast_axes(k.shape, v.shape)).reshape(k.shape).cast(v.dtype)
#       needs `broadcast_axes` (ops.py:89), which reads `resolve(s == 1)` and
#       `resolve(out_shape[nleft+i] != 1)` on a `Sint` -- SYMBOLIC comparisons, and
#       `symbolic.py`'s `resolve` is not ported. It also needs `sum_acc_dtype` (dtype.py:220),
#       which is `least_upper_dtype` against `getenv("SUM_DTYPE")`, and `Config` is a P6
#       concern (`uop/symbolic.py` is also P3).
#       and it is worse than a wall: it is a place cpthon itself raises. The committed
#       oracle's second fixture drives `compute_gradient` into
#       `RuntimeError: cannot broadcast (UOp(Ops.ADD, ...)) into ()` at gradient.py:133,
#       so that line has no CPython answer to gate against on a shaped edge at all.
# TODO(p3) mixin/gradient.py:132  compute_gradient -- the shaped-edge reduce needs
#   `broadcast_axes` (ops.py:89) and `sum_acc_dtype` (dtype.py:220), both of which read
#   `resolve` on a `Sint` or `Config`. Phase P3 owns `symbolic`; P6 owns `Config`.
#   The walk, the `grads` table and the accumulation AROUND it are LANDED above and are
#   gated by sixteen rows against CPython (see the gate's WALK block).
#   (d) gradient.py:140-144, the BACKWARD-METADATA pass, reads `all_metadata` (ops.py's
#   module-level dict). It has no effect on `grads`, so no row in this gate can see it;
#   it is a NAMED OMISSION rather than a silent one.
#   (e) `call_gradient` (:20-50) is NOT reachable from here -- a CALL in the walk is the
#   one node shape whose gradient this port cannot produce, and `cg_fire.pick` reaches
#   gradient.py:127's refusal instead. STATED so nobody reads a short `walk_grads_n` as
#   "the walk ran on a graph with a CALL".
#
# THE UPSTREAM WHY ON THAT BRANCH, kept because the CALL path is the one place the
# walk asks for information rather than computing it:
#   gradient.py:119 -- "CALL: pass needed param set so backward only computes required
#   gradients". The `needed` SET is the set of argument INDICES whose value is a
#   target or reaches one, and it is passed DOWN into `call_gradient` so that the
#   backward body computes ONLY those gradients. The consequence is a WORKED
#   EXAMPLE rather than a style: a CALL whose body computes ten gradients and
#   whose caller asks for one pays for one. It is also why `call_gradient` reads
#   `needed - outputs.keys()` (gradient.py:34) -- the outputs' own gradients are
#   already in `ctx.src` and must not be recomputed (gradient.py:34-35).
#
# `call_gradient` -- gradient.py:20-50, and this is the BIGGEST of what is left. It reads
# `k.arg.grad_fxn` (a CALLBACK on a `CallArg`), `fxn.src[0].unsharded_base.arg.slot`
# (an axis-normalised slot), `st.src[1].param_like(len(args)+i)`, `params` from
# `fxn.toposort(enter_calls=False)`, `view_as` + `shard_shape` + `sharding` +
# `grads[p].view_as(...)`, `renumber_invalid_outputs` (function.py), and two
# `substitute(walk=True)` passes. Every one of those is a different subsystem:
# `CallArg`/`CallInfo` is `ops.bend`'s, `renumber_invalid_outputs` is `function.py`'s,
# `view_as`/`shard_shape` are `mixin/op.py`'s, and the `substitute` walks are a graph
# rewrite over a PATH SET.
#
# THE TWO UPSTREAM WHY-S ON THIS FUNCTION, kept because they are the only two
# statements about what the backward body IS rather than what it computes:
#   gradient.py:37 -- "Reuse the output PARAMs for saved forward values instead of
#   recomputing them." The forward pass SAVED the values it needed as PARAMs of
#   the CALL's body; the backward pass SUBSTITUTES those saved values back in
#   (`bwd_body.substitute({st.src[1]:st.src[0] for st in outputs.values()},
#   walk=True)`) instead of recomputing them. So a precompiled CALL's backward
#   does not re-run the forward -- it reads the forward's own PARAMs. The
#   `walk=True` is what makes the substitution reach EVERY occurrence, not just
#   the top one.
#   gradient.py:43 -- "Compact this scope's PARAMs, capturing free Variables as
#   inputs." After the substitution the body holds PARAMs it no longer needs
#   (`used` is the SORTED list of the PARAMs actually reachable), and the body is
#   RENUMBERED so that the PARAMs it keeps are consecutive from 0. A PARAM with
#   a negative slot is a FREE VARIABLE, and those are captured as the function's
#   inputs rather than dropped -- that is the "capturing free Variables as
#   inputs" half. The SORT is by slot and it is what makes the renumbering
#   deterministic.
# TODO(p3) mixin/gradient.py:20  call_gradient -- needs `CallArg.grad_fxn` (a callback
#   in a dataclass field, `ops.py`), `renumber_invalid_outputs` (`function.py`),
#   `view_as`/`shard_shape`/`sharding` (`mixin/op.py`, ops.py:707/461/1248) and two
#   `substitute(walk=True)` passes. Five subsystems, none of them this file's.
#
# `partial_store_gradient` -- gradient.py:52-62, the helper tag 30 calls. Its WALL is
# MUTUAL RECURSION and it is the one wall in this file that is a Bend LAW rather than a
# missing dependency, so it is stated under `gr_29` and repeated here:
# TODO(p3) mixin/gradient.py:52  partial_store_gradient -- the body calls
#   `pm_gradient.rewrite` (gradient.py:124, reached through `compute_gradient` at
#   gradient.py:61), so `gr_29` and `gr_rewrite` would be mutually
#   recursive and Bend refuses mutual recursion outright.
#
# WHAT NEXT, in the order the walls fall.
#   1. `symbolic.py`'s `resolve` unblocks `compute_gradient`'s shaped-edge reduce AND
#      `reduce_gradient`'s three arms, because both are `resolve` on a `Sint`.
#   2. `mixin/op.py` unblocks tag 23 (`ctx[i]`), which is the only movement rule whose
#      answer is not a movement op.
#   3. `uop/weak.bend`'s `_min_max` unblocks tag 25 (`UNSHARD`), tag 15
#      (`has_buffer_identity`) and `mixin/dtype.bend`'s `commit_dtype`.
#   4. `call_gradient` needs the five subsystems above and is the largest single item.
# THE TABLE. 33 entries, `pm_gradient.pdict` order, and the `ops`/`rej` columns are
# Python's OWN -- dumped from `upat_compile` and the `pdict` reject sets, not inferred.
# The interesting column is `rej`, and it is non-empty at exactly FOUR tags: 27 rejects
# `CALL` and 28/29/30 reject `STORE`. Those are `early_reject` (ops.py:1478), which is a
# NECESSARY CONDITION and not a veto despite the name (`ops.py:1609` is
# `if not early_reject.issubset(ler): continue`, so the rule FIRES when the op set IS a
# subset). For a pattern whose first src is a bare name the set is `None` -> empty, and
# an empty set is a subset of everything, which is why the other 29 are `Nil{}`.
#
# `rej` still decides SOMETHING here, unlike in `spec.bend` where the measured result was
# that it decides nothing: tags 28 and 29 have the SAME op set (`AFTER`) and the SAME
# reject set (`STORE`), so `rej` cannot separate them and the IDENTITY CHECK is the only
# thing that can. `t_rej27` and `t_rej29` are the rows for the spelling.
# END BLOCK

# THE DRIVER -- `reduce_gradient` (gradient.py:8-18) and `call_gradient` (:20-50) are
# STILL WALLS, and `_deepwalk` / `compute_gradient` are NOT (they landed above this
# block). The three notes are kept separate because the reasons are different, and the
# two that closed are kept with their reasons CLOSED so the next reader does not
# rediscover them.
#
# `_deepwalk` -- gradient.py:109 -- LANDED. `root.topovisit(lambda u: any(in_target_path[x]
# or x in targets for x in u.src), in_target_path)` was called a wall because "the VISITOR
# is a PYTHON CALLABLE closing over a dict, which is the P4 concern every rewrite rule in
# tinygrad shares". That was TRUE OF THE SPELLING AND FALSE OF THE PROBLEM: the visitor
# reads only each node's SRCS, and a src is always EARLIER in a toposort, so ONE forward
# pass carrying a `Data` pair of parallel lists computes the same lattice. That is
# `fold.bend`'s own Kahn argument, and the pass is `dw_flags` above. The `Bool` lattice
# ("a node is on the target path iff ANY src is, with DETACH excluded", gradient.py:114)
# is `dw_any` and `dw_keep_test`. `topovisit`'s Callable is still not ported -- nothing in
# `ops.py` calls it -- and `O.UOp.topovisit` (uop/ops.bend:2943 symbol=UOp.mstack.go) still answers the plain
# toposort, which is the order this file drives.
#
# `compute_gradient` -- gradient.py:116-145 -- LANDED, with THREE named omissions.
#   (a) and (b) below were recorded as "PORTABLE, and not the wall", and they were:
#       `grads` is a `Data` pair of parallel lists with an IN-PLACE update (`gput.at`),
#       which is what makes it dict-shaped, and every update is an O(n) copy -- the same
#       trade `fold.bend` pays and calls "slow and checkable beats fast and unprovable".
#   (c) THE WALL THAT IS STILL A WALL: gradient.py:132-133, the shaped-edge reduce
#           v = v.cast(sum_acc_dtype(v.dtype))._rop(Ops.ADD, broadcast_axes(k.shape, v.shape)).reshape(k.shape).cast(v.dtype)
#       needs `broadcast_axes` (ops.py:89), which reads `resolve(s == 1)` and
#       `resolve(out_shape[nleft+i] != 1)` on a `Sint` -- SYMBOLIC comparisons, and
#       `symbolic.py`'s `resolve` is not ported. It also needs `sum_acc_dtype` (dtype.py:220),
#       which is `least_upper_dtype` against `getenv("SUM_DTYPE")`, and `Config` is a P6
#       concern (`uop/symbolic.py` is also P3).
#       and it is worse than a wall: it is a place cpthon itself raises. The committed
#       oracle's second fixture drives `compute_gradient` into
#       `RuntimeError: cannot broadcast (UOp(Ops.ADD, ...)) into ()` at gradient.py:133,
#       so that line has no CPython answer to gate against on a shaped edge at all.
# TODO(p3) mixin/gradient.py:132  compute_gradient -- the shaped-edge reduce needs
#   `broadcast_axes` (ops.py:89) and `sum_acc_dtype` (dtype.py:220), both of which read
#   `resolve` on a `Sint` or `Config`. Phase P3 owns `symbolic`; P6 owns `Config`.
#   The walk, the `grads` table and the accumulation AROUND it are LANDED above and are
#   gated by sixteen rows against CPython (see the gate's WALK block).
#   (d) gradient.py:140-144, the BACKWARD-METADATA pass, reads `all_metadata` (ops.py's
#   module-level dict). It has no effect on `grads`, so no row in this gate can see it;
#   it is a NAMED OMISSION rather than a silent one.
#   (e) `call_gradient` (:20-50) is NOT reachable from here -- a CALL in the walk is the
#   one node shape whose gradient this port cannot produce, and `cg_fire.pick` reaches
#   gradient.py:127's refusal instead. STATED so nobody reads a short `walk_grads_n` as
#   "the walk ran on a graph with a CALL".
#
# THE UPSTREAM WHY ON THAT BRANCH, kept because the CALL path is the one place the
# walk asks for information rather than computing it:
#   gradient.py:119 -- "CALL: pass needed param set so backward only computes required
#   gradients". The `needed` SET is the set of argument INDICES whose value is a
#   target or reaches one, and it is passed DOWN into `call_gradient` so that the
#   backward body computes ONLY those gradients. The consequence is a WORKED
#   EXAMPLE rather than a style: a CALL whose body computes ten gradients and
#   whose caller asks for one pays for one. It is also why `call_gradient` reads
#   `needed - outputs.keys()` (gradient.py:34) -- the outputs' own gradients are
#   already in `ctx.src` and must not be recomputed (gradient.py:34-35).
#
# `call_gradient` -- gradient.py:20-50, and this is the BIGGEST of what is left. It reads
# `k.arg.grad_fxn` (a CALLBACK on a `CallArg`), `fxn.src[0].unsharded_base.arg.slot`
# (an axis-normalised slot), `st.src[1].param_like(len(args)+i)`, `params` from
# `fxn.toposort(enter_calls=False)`, `view_as` + `shard_shape` + `sharding` +
# `grads[p].view_as(...)`, `renumber_invalid_outputs` (function.py), and two
# `substitute(walk=True)` passes. Every one of those is a different subsystem:
# `CallArg`/`CallInfo` is `ops.bend`'s, `renumber_invalid_outputs` is `function.py`'s,
# `view_as`/`shard_shape` are `mixin/op.py`'s, and the `substitute` walks are a graph
# rewrite over a PATH SET.
#
# THE TWO UPSTREAM WHY-S ON THIS FUNCTION, kept because they are the only two
# statements about what the backward body IS rather than what it computes:
#   gradient.py:37 -- "Reuse the output PARAMs for saved forward values instead of
#   recomputing them." The forward pass SAVED the values it needed as PARAMs of
#   the CALL's body; the backward pass SUBSTITUTES those saved values back in
#   (`bwd_body.substitute({st.src[1]:st.src[0] for st in outputs.values()},
#   walk=True)`) instead of recomputing them. So a precompiled CALL's backward
#   does not re-run the forward -- it reads the forward's own PARAMs. The
#   `walk=True` is what makes the substitution reach EVERY occurrence, not just
#   the top one.
#   gradient.py:43 -- "Compact this scope's PARAMs, capturing free Variables as
#   inputs." After the substitution the body holds PARAMs it no longer needs
#   (`used` is the SORTED list of the PARAMs actually reachable), and the body is
#   RENUMBERED so that the PARAMs it keeps are consecutive from 0. A PARAM with
#   a negative slot is a FREE VARIABLE, and those are captured as the function's
#   inputs rather than dropped -- that is the "capturing free Variables as
#   inputs" half. The SORT is by slot and it is what makes the renumbering
#   deterministic.
# TODO(p3) mixin/gradient.py:20  call_gradient -- needs `CallArg.grad_fxn` (a callback
#   in a dataclass field, `ops.py`), `renumber_invalid_outputs` (`function.py`),
#   `view_as`/`shard_shape`/`sharding` (`mixin/op.py`, ops.py:707/461/1248) and two
#   `substitute(walk=True)` passes. Five subsystems, none of them this file's.
#
# `partial_store_gradient` -- gradient.py:52-62, the helper tag 30 calls. Its WALL is
# MUTUAL RECURSION and it is the one wall in this file that is a Bend LAW rather than a
# missing dependency, so it is stated under `gr_29` and repeated here:
# TODO(p3) mixin/gradient.py:52  partial_store_gradient -- the body calls
#   `pm_gradient.rewrite` (gradient.py:124, reached through `compute_gradient` at
#   gradient.py:61), so `gr_29` and `gr_rewrite` would be mutually
#   recursive and Bend refuses mutual recursion outright.
#
# WHAT NEXT, in the order the walls fall.
#   1. `symbolic.py`'s `resolve` unblocks `compute_gradient`'s shaped-edge reduce AND
#      `reduce_gradient`'s three arms, because both are `resolve` on a `Sint`.
#   2. `mixin/op.py` unblocks tag 23 (`ctx[i]`), which is the only movement rule whose
#      answer is not a movement op.
#   3. `uop/weak.bend`'s `_min_max` unblocks tag 25 (`UNSHARD`), tag 15
#      (`has_buffer_identity`) and `mixin/dtype.bend`'s `commit_dtype`.
#   4. `call_gradient` needs the five subsystems above and is the largest single item.
# THE TABLE. 33 entries, `pm_gradient.pdict` order, and the `ops`/`rej` columns are
# Python's OWN -- dumped from `upat_compile` and the `pdict` reject sets, not inferred.
# The interesting column is `rej`, and it is non-empty at exactly FOUR tags: 27 rejects
# `CALL` and 28/29/30 reject `STORE`. Those are `early_reject` (ops.py:1478), which is a
# NECESSARY CONDITION and not a veto despite the name (`ops.py:1609` is
# `if not early_reject.issubset(ler): continue`, so the rule FIRES when the op set IS a
# subset). For a pattern whose first src is a bare name the set is `None` -> empty, and
# an empty set is a subset of everything, which is why the other 29 are `Nil{}`.
#
# `rej` still decides SOMETHING here, unlike in `spec.bend` where the measured result was
# that it decides nothing: tags 28 and 29 have the SAME op set (`AFTER`) and the SAME
# reject set (`STORE`), so `rej` cannot separate them and the IDENTITY CHECK is the only
# thing that can. `t_rej27` and `t_rej29` are the rows for the spelling.
