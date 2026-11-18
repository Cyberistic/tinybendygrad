<!-- FROM: tinybendygrad/mixin/movement.bend:1447 -->
# BLOCK:
# SECTION I1 -- THE SIX CORE WRAPPERS. Python's order is `_broadcast_to`, `expand`,
# `reshape`, `pad`, `shrink`, `permute`, `flip` (movement.py:128-254) and this file
# follows it.
#
# the shape of every one is the same four steps, and that is worth saying once:
#   1. build the arg as a `List<&2, U32>` of python ints (the `List` algebra);
#   2. intern it as a STACK of CONSTs (`mxw_stk`), in the arena it grows;
#   3. build the movement node in THAT arena (never the caller's);
#   4. the identity test against the SOURCE's shape (`mxw_same`).
# Steps 2 and 3 are the arena rule and step 4 is the merge point with Section A-H.
#
# `+made = ...` IS A SHARED `let` AND IT IS LOAD-BEARING. The node is needed by the
# identity test AND by the `pick`, and a `let` is affine, so an unshared one is a
# compile error and a re-CALL is a second node with a second arena. The rule is
# `+x = ...` for a shared local, which is the notes' `+q = p` shape.
# THE PICK, and `Bool.pick` is not used here because both arms are Tensors and the
# `+` on two of them is noisier than a `match`. movement.py:185 is
# `return self if ret.shape == self.shape else ret`, so `True` answers `t`.
# END BLOCK

# SECTION I1 -- THE SIX CORE WRAPPERS. Python's order is `_broadcast_to`, `expand`,
# `reshape`, `pad`, `shrink`, `permute`, `flip` (movement.py:128-254) and this file
# follows it.
#
# the shape of every one is the same four steps, and that is worth saying once:
#   1. build the arg as a `List<&2, U32>` of python ints (the `List` algebra);
#   2. intern it as a STACK of CONSTs (`mxw_stk`), in the arena it grows;
#   3. build the movement node in THAT arena (never the caller's);
#   4. the identity test against the SOURCE's shape (`mxw_same`).
# Steps 2 and 3 are the arena rule and step 4 is the merge point with Section A-H.
#
# `+made = ...` IS A SHARED `let` AND IT IS LOAD-BEARING. The node is needed by the
# identity test AND by the `pick`, and a `let` is affine, so an unshared one is a
# compile error and a re-CALL is a second node with a second arena. The rule is
# `+x = ...` for a shared local, which is the notes' `+q = p` shape.
# THE PICK, and `Bool.pick` is not used here because both arms are Tensors and the
# `+` on two of them is noisier than a `match`. movement.py:185 is
# `return self if ret.shape == self.shape else ret`, so `True` answers `t`.
