<!-- FROM: tinybendygrad/mixin/creation.bend:320 -->
# BLOCK:
# `expand` -- movement.py:149 -- for `full`'s 0-dim source; see the header's W4 for the
# whole reduction. `T.tn_mop` supplies ops.py:823's early NOOP (`if op is Ops.EXPAND
# and len(arg) == 0: return self`), so `full((), 42, buffer=False)` is the bare CONST,
# which is CPython's own answer.
#
# `expand` IS `_broadcast_to` (movement.py:149-162 -> movement.py:128-146), so THIS IS
# `_broadcast_to` AND NOT A BARE EXPAND. `mxw_bcast` is CPython's rule: the marg is
# the LEFT-ADDED dims and THEN the dims of the source axes that were 1 and became
# bigger, and the squeeze and the permute are what make the result's shape the
# target's. for a 0-dim source every dim is left-added, so the marg is the whole
# target and `mxw_bcast` BUILDS EXACTLY WHAT `cr_mop` BUILT -- the squeeze is a
# no-op reshape and the permute is the identity, and both wrappers drop their node.
# FOR A SOURCE WITH A 1 IN IT -- `nn/pool.bend:185 symbol=pool_rep.rp`'s `_pool` repeat -- the marg is
# the REPEAT COUNTS, and the bare EXPAND this def used to build was the shape
# `tuple(self.marg) + ps` (ops.py:397) reads as: THE WHOLE TARGET CONCATENATED WITH
# THE SOURCE.
# END BLOCK

# `expand` -- movement.py:149 -- for `full`'s 0-dim source; see the header's W4 for the
# whole reduction. `T.tn_mop` supplies ops.py:823's early NOOP (`if op is Ops.EXPAND
# and len(arg) == 0: return self`), so `full((), 42, buffer=False)` is the bare CONST,
# which is CPython's own answer.
#
# `expand` IS `_broadcast_to` (movement.py:149-162 -> movement.py:128-146), so THIS IS
# `_broadcast_to` AND NOT A BARE EXPAND. `mxw_bcast` is CPython's rule: the marg is
# the LEFT-ADDED dims and THEN the dims of the source axes that were 1 and became
# bigger, and the squeeze and the permute are what make the result's shape the
# target's. for a 0-dim source every dim is left-added, so the marg is the whole
# target and `mxw_bcast` BUILDS EXACTLY WHAT `cr_mop` BUILT -- the squeeze is a
# no-op reshape and the permute is the identity, and both wrappers drop their node.
# FOR A SOURCE WITH A 1 IN IT -- `nn/pool.bend:185 symbol=pool_rep.rp`'s `_pool` repeat -- the marg is
# the REPEAT COUNTS, and the bare EXPAND this def used to build was the shape
# `tuple(self.marg) + ps` (ops.py:397) reads as: THE WHOLE TARGET CONCATENATED WITH
# THE SOURCE.
