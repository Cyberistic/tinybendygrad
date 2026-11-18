<!-- FROM: tinybendygrad/nn/optim.bend:882 -->
# BLOCK:
# THE GATE.
#
# Nothing is EXECUTED. Every row is either a STRING or the SIGNATURE of a lazily
# built graph -- `n=<count> OP/<nsrc> ...` in toposort, with the bare `Enum.name` --
# so the oracle needs no device, which is the whole reason this is a graph gate and
# not an execution gate. `optim.py`'s `_step` is PURE graph construction: it touches
# no Buffer and calls no realize, so the same graphs are available on both sides.
#
# the fixtures are handles, and that is wall 1 applied to the oracle as well as to
# the port: Python's `self.b[i]` is a `Tensor.zeros` whose graph is
# `ALLOC/CAST/CONST/EXPAND/STORE/AFTER`, six nodes that are `empty_like` -- device
# state the port does not build. So the oracle REPLACES the momentum buffer with a
# plain `Tensor([0.0, 0.0], device='PYTHON')` and the port receives a BUFFER index.
# Both sides then see one BUFFER and the six-node prefix is gone from BOTH, which is
# the only way the row can mean anything. It is stated here because a reader who
# compares against an unreplaced oracle will see six extra nodes and wonder.
#
# the `n=` count is in every signature row on purpose, for tensor.bend's reason: a
# boolean row that says "the ADD is there" cannot see a missing CONST, and two CONSTs
# print the same signature whichever way round they are swapped. The rows that pin
# ORDER specifically are `op_lars0` (two CONSTs, so order-free by construction) and
# `op_prewd`/`op_trust`, which have a BUFFER and a CONST in the same multiply.
# END BLOCK

# THE GATE.
#
# Nothing is EXECUTED. Every row is either a STRING or the SIGNATURE of a lazily
# built graph -- `n=<count> OP/<nsrc> ...` in toposort, with the bare `Enum.name` --
# so the oracle needs no device, which is the whole reason this is a graph gate and
# not an execution gate. `optim.py`'s `_step` is PURE graph construction: it touches
# no Buffer and calls no realize, so the same graphs are available on both sides.
#
# the fixtures are handles, and that is wall 1 applied to the oracle as well as to
# the port: Python's `self.b[i]` is a `Tensor.zeros` whose graph is
# `ALLOC/CAST/CONST/EXPAND/STORE/AFTER`, six nodes that are `empty_like` -- device
# state the port does not build. So the oracle REPLACES the momentum buffer with a
# plain `Tensor([0.0, 0.0], device='PYTHON')` and the port receives a BUFFER index.
# Both sides then see one BUFFER and the six-node prefix is gone from BOTH, which is
# the only way the row can mean anything. It is stated here because a reader who
# compares against an unreplaced oracle will see six extra nodes and wonder.
#
# the `n=` count is in every signature row on purpose, for tensor.bend's reason: a
# boolean row that says "the ADD is there" cannot see a missing CONST, and two CONSTs
# print the same signature whichever way round they are swapped. The rows that pin
# ORDER specifically are `op_lars0` (two CONSTs, so order-free by construction) and
# `op_prewd`/`op_trust`, which have a BUFFER and a CONST in the same multiply.
