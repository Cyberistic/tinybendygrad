<!-- FROM: tinybendygrad/uop/ops.bend:1294 -->
# BLOCK:
# `CallInfo.__repr__` (ops.py:1401) is at the end of the equality block, because it
# compares against `S.void()` and `eq_dt` is what does the comparing.
# THE ARENA.
#
# `Node` is `UOp`'s four fields and adds nothing: `op`, `src`, `arg`, `tag`. The
# arena IS the ucache and the node table at once, because in Bend they are the
# same thing -- a UOp is an index into a list of nodes, and a hash-cons hit is
# "a node with this key is already in the list".
#
# INDEX 0 IS RESERVED. `Arena.empty` starts with one node in it, the bottom, so
# every U32 is a valid index and 0 is this port's spelling of both Python's
# `None` UOp and the IndexError that `self.src[0]` on an empty src raises.
# `UOp.is_none` is the test, and it is the only place a UOp index is compared
# against a constant.
#
# The `Metadata` side table (`all_metadata`, ops.py:215) is NOT a second store.
# Python keeps it in a `WeakKeyDictionary` beside the arena so that replacing a
# UOp drops its metadata; the arena is monotone and has no weakrefs, so metadata
# is a field of the node and `UOp.replace` does not carry it over, which is the
# behaviour Python gets from the weakref dying.
# END BLOCK

# `CallInfo.__repr__` (ops.py:1401) is at the end of the equality block, because it
# compares against `S.void()` and `eq_dt` is what does the comparing.
# THE ARENA.
#
# `Node` is `UOp`'s four fields and adds nothing: `op`, `src`, `arg`, `tag`. The
# arena IS the ucache and the node table at once, because in Bend they are the
# same thing -- a UOp is an index into a list of nodes, and a hash-cons hit is
# "a node with this key is already in the list".
#
# INDEX 0 IS RESERVED. `Arena.empty` starts with one node in it, the bottom, so
# every U32 is a valid index and 0 is this port's spelling of both Python's
# `None` UOp and the IndexError that `self.src[0]` on an empty src raises.
# `UOp.is_none` is the test, and it is the only place a UOp index is compared
# against a constant.
#
# The `Metadata` side table (`all_metadata`, ops.py:215) is NOT a second store.
# Python keeps it in a `WeakKeyDictionary` beside the arena so that replacing a
# UOp drops its metadata; the arena is monotone and has no weakrefs, so metadata
# is a field of the node and `UOp.replace` does not carry it over, which is the
# behaviour Python gets from the weakref dying.
