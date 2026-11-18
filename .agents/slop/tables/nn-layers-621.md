<!-- FROM: tinybendygrad/nn/layers.bend:621 -->
# BLOCK:
# --- `_pool` -- movement.py:614-632, IN UPSTREAM'S ORDER --------------------
#
# NO ARITHMETIC IS SPELLED HERE. Every number is `mixin/movement.bend`'s.
#
# the chain is upstream's, line by line, and the order is LOAD-bearing:
#   movement.py:624  x = self.repeat(noop ++ [ceildiv(k*(i*f+d), i)])
#   movement.py:626  x = x.shrink_to(noop ++ [k*(i*f+d)])
#   movement.py:627  x = x.reshape(noop ++ flatten((k, i*f+d)))
#   movement.py:629  x = x.shrink_to(noop ++ flatten((k, o*s))).reshape(noop ++ flatten((k, o, s)))
#   movement.py:630  x = x.shrink_to(noop ++ flatten((k, o, 1))).reshape(noop ++ flatten((k, o)))
#   movement.py:632  return x.permute(range(nn), *[nn+2i+1], *[nn+2i])
#
# `noop` IS `[None] * (self.ndim - len(k_))` (movement.py:618) AND `None` MEANS
# "this axis is not shrunk", so the shrink's target keeps the source's own SIZE
# on those axes. THE PORT'S TARGETS ARE SIZES, so the noop axes carry the
# SOURCE'S OWN DIMS -- which is `nn/pool.bend:142`'s `W4.lead` and NOT a list of
# ones. MEASURED: with ones there, the channel axis was shrunk from 3 to 1 and
#
# and the two shrink targets are not the same list. `movement.py:626` shrinks to
# `k*(i*f+d)` and `movement.py:627` reshapes to `(k, i*f+d)` -- THE DILATED SIZE
# WITHOUT THE `k *`. `mx_pool_kid` (movement.bend:316) IS `k*(i*f+d)`, so the
# reshape's target needs a SECOND number, and a reshape that is not
# size-preserving is a ValueError (movement.py:181).
# END BLOCK

# --- `_pool` -- movement.py:614-632, IN UPSTREAM'S ORDER --------------------
#
# NO ARITHMETIC IS SPELLED HERE. Every number is `mixin/movement.bend`'s.
#
# the chain is upstream's, line by line, and the order is LOAD-bearing:
#   movement.py:624  x = self.repeat(noop ++ [ceildiv(k*(i*f+d), i)])
#   movement.py:626  x = x.shrink_to(noop ++ [k*(i*f+d)])
#   movement.py:627  x = x.reshape(noop ++ flatten((k, i*f+d)))
#   movement.py:629  x = x.shrink_to(noop ++ flatten((k, o*s))).reshape(noop ++ flatten((k, o, s)))
#   movement.py:630  x = x.shrink_to(noop ++ flatten((k, o, 1))).reshape(noop ++ flatten((k, o)))
#   movement.py:632  return x.permute(range(nn), *[nn+2i+1], *[nn+2i])
#
# `noop` IS `[None] * (self.ndim - len(k_))` (movement.py:618) AND `None` MEANS
# "this axis is not shrunk", so the shrink's target keeps the source's own SIZE
# on those axes. THE PORT'S TARGETS ARE SIZES, so the noop axes carry the
# SOURCE'S OWN DIMS -- which is `nn/pool.bend:142`'s `W4.lead` and NOT a list of
# ones. MEASURED: with ones there, the channel axis was shrunk from 3 to 1 and
#
# and the two shrink targets are not the same list. `movement.py:626` shrinks to
# `k*(i*f+d)` and `movement.py:627` reshapes to `(k, i*f+d)` -- THE DILATED SIZE
# WITHOUT THE `k *`. `mx_pool_kid` (movement.bend:316) IS `k*(i*f+d)`, so the
# reshape's target needs a SECOND number, and a reshape that is not
# size-preserving is a ValueError (movement.py:181).
