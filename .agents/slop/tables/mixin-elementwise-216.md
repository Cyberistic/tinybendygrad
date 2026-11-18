<!-- FROM: tinybendygrad/mixin/elementwise.bend:216 -->
# BLOCK:
# two arenas, and the longer one contains the other. `ufix` can hand back a Tensor
# built in a DIFFERENT store from `self`'s -- the `ETen` case, where the operand was
# made elsewhere -- and then `_broadcasted` folds one arena and promotes against
# another. `Arena.node` answers the BOTTOM for an index past the end, which is a
# `void` dtype and therefore a `cast`, and the whole failure is SILENT: the cast is
# a real node, every arity is right, and the graph is wrong. That is why the two
# operands are REBASED onto one arena here rather than at each call site.
#
# "longer" is `Arena.next`, the store's node COUNT, and it is the right test because
# the store is APPEND-ONLY: every index valid in the shorter arena is still valid in
# the longer one, and no index is renumbered. This is the same argument
# `uop/divandmod.bend`'s rule 4 makes about a `+` not enforcing arena identity, and
# here it is the FIX rather than the hazard.
# END BLOCK

# two arenas, and the longer one contains the other. `ufix` can hand back a Tensor
# built in a DIFFERENT store from `self`'s -- the `ETen` case, where the operand was
# made elsewhere -- and then `_broadcasted` folds one arena and promotes against
# another. `Arena.node` answers the BOTTOM for an index past the end, which is a
# `void` dtype and therefore a `cast`, and the whole failure is SILENT: the cast is
# a real node, every arity is right, and the graph is wrong. That is why the two
# operands are REBASED onto one arena here rather than at each call site.
#
# "longer" is `Arena.next`, the store's node COUNT, and it is the right test because
# the store is APPEND-ONLY: every index valid in the shorter arena is still valid in
# the longer one, and no index is renumbered. This is the same argument
# `uop/divandmod.bend`'s rule 4 makes about a `+` not enforcing arena identity, and
# here it is the FIX rather than the hazard.
