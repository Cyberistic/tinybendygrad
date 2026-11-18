<!-- FROM: tinybendygrad/mixin/rand.bend:182 -->
# BLOCK:
# THE BORROWED BLOCK -- `mixin/op.py:166 arange` and `mixin/op.py:731 cat`, plus the
# two specialisations of `movement.py:128` and `op.py:74` they need. NONE OF THESE IS
# MINE. Every def is `op_`-prefixed, every def's comment names the file and line it belongs
# to, and the whole block deletes itself the moment `mixin/op.bend` grows
# `mo_arange`/`mo_cat` and `mixin/movement.bend` grows `mxw_bcast`. It is here because a
# file with no buildable callee has no gate, and the gate is the only evidence this port
# has. IT IS GATED (`arange3`, `arange5`), so it is a MEASURED implementation and not a
# restatement of the code that calls it.
# `self.shape[-len(k_):]`, which is the WHOLE shape for the 1-D `k_ = (k,)` that
# `_cumalu` passes, and `mxw_dims_of` is `movement.bend`'s own merge point (the arg for a
# movement node, the fold for anything else) so the dim read here is the fold's answer and
# not a re-derivation. it is a parameter and not a call at every call site, because
# `mxw_dims_of` runs a whole Kahn fold and `op_pool1` needs the source's `i` eleven times.
# END BLOCK

# THE BORROWED BLOCK -- `mixin/op.py:166 arange` and `mixin/op.py:731 cat`, plus the
# two specialisations of `movement.py:128` and `op.py:74` they need. NONE OF THESE IS
# MINE. Every def is `op_`-prefixed, every def's comment names the file and line it belongs
# to, and the whole block deletes itself the moment `mixin/op.bend` grows
# `mo_arange`/`mo_cat` and `mixin/movement.bend` grows `mxw_bcast`. It is here because a
# file with no buildable callee has no gate, and the gate is the only evidence this port
# has. IT IS GATED (`arange3`, `arange5`), so it is a MEASURED implementation and not a
# restatement of the code that calls it.
# `self.shape[-len(k_):]`, which is the WHOLE shape for the 1-D `k_ = (k,)` that
# `_cumalu` passes, and `mxw_dims_of` is `movement.bend`'s own merge point (the arg for a
# movement node, the fold for anything else) so the dim read here is the fold's answer and
# not a re-derivation. it is a parameter and not a call at every call site, because
# `mxw_dims_of` runs a whole Kahn fold and `op_pool1` needs the source's `i` eleven times.
