<!-- FROM: tinybendygrad/mixin/movement.bend:510 -->
# BLOCK:
# SECTION D -- `marg` (ops.py:814-819) and `_shape`'s movement arms (ops.py:409-431).
# THIS IS W1/W2 ANSWERED.
#
# `marg` in full:
#     case Ops.RESHAPE | Ops.EXPAND: return self.src[1].as_shape
#     case Ops.PAD | Ops.SHRINK:    return tuple(zip(self.src[1].as_shape, self.src[2].as_shape))
#     case Ops.PERMUTE | Ops.FLIP:  return self.arg
#
# So `marg` is a THREE-WAY dispatch on the op and each arm is a reader over the
# arena -- and every reader is `as_shape` over a STACK of CONSTs except the
# PERMUTE/FLIP arm, which is the node's own `arg` (`ATuple{ys}`), already a list of
# U32s. That is the whole reason the wall is closable, and it is why this section is
# short: there is no arithmetic here at all, only three reads.
# IS A MOVEMENT OP WHOSE `marg` IS AN `ATuple` -- PERMUTE and FLIP. `op_in` is
# `ops.bend`'s membership test and an empty set is a subset of everything, so the
# set is written out rather than left empty.
# END BLOCK

# SECTION D -- `marg` (ops.py:814-819) and `_shape`'s movement arms (ops.py:409-431).
# THIS IS W1/W2 ANSWERED.
#
# `marg` in full:
#     case Ops.RESHAPE | Ops.EXPAND: return self.src[1].as_shape
#     case Ops.PAD | Ops.SHRINK:    return tuple(zip(self.src[1].as_shape, self.src[2].as_shape))
#     case Ops.PERMUTE | Ops.FLIP:  return self.arg
#
# So `marg` is a THREE-WAY dispatch on the op and each arm is a reader over the
# arena -- and every reader is `as_shape` over a STACK of CONSTs except the
# PERMUTE/FLIP arm, which is the node's own `arg` (`ATuple{ys}`), already a list of
# U32s. That is the whole reason the wall is closable, and it is why this section is
# short: there is no arithmetic here at all, only three reads.
# IS A MOVEMENT OP WHOSE `marg` IS AN `ATuple` -- PERMUTE and FLIP. `op_in` is
# `ops.bend`'s membership test and an empty set is a subset of everything, so the
# set is written out rather than left empty.
