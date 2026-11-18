<!-- FROM: tinybendygrad/mixin/gradient.bend:3119 -->
# BLOCK:
# the 3-d fixture.  `a` is the target, `per` is the root, `ctx` is the root grad.
#
# * why it is 3-d and not 2-d, and it is not a taste: a 2-element permutation is an
# INVOLUTION, SO ITS ARGSORT IS ITSELF. *  `argsort((1,0))` is `(1,0)` (MEASURED, §1.4),
# so on a 2-D fixture the rule's ORDER row would read the same whether the rule ARGSORTED
# or merely copied the order -- A ROW THAT CANNOT GO RED IS A LABEL.  With the order
# `(1, 2, 0)` the argsort is `(2, 0, 1)`, so the row distinguishes them.
#
# AND WHY EVERY DIMENSION IS 2: the shape of `per` is the shape of `a` PERMUTED, and the
# shape of `ctx` must EQUAL it or the shaped-edge reduce at gradient.py:131 fires and
# upstream raises (it needs `broadcast_axes`, which is symbolic).  With every dimension
# equal, the permuted shape IS the shape.
# END BLOCK

# the 3-d fixture.  `a` is the target, `per` is the root, `ctx` is the root grad.
#
# * why it is 3-d and not 2-d, and it is not a taste: a 2-element permutation is an
# INVOLUTION, SO ITS ARGSORT IS ITSELF. *  `argsort((1,0))` is `(1,0)` (MEASURED, §1.4),
# so on a 2-D fixture the rule's ORDER row would read the same whether the rule ARGSORTED
# or merely copied the order -- A ROW THAT CANNOT GO RED IS A LABEL.  With the order
# `(1, 2, 0)` the argsort is `(2, 0, 1)`, so the row distinguishes them.
#
# AND WHY EVERY DIMENSION IS 2: the shape of `per` is the shape of `a` PERMUTED, and the
# shape of `ctx` must EQUAL it or the shaped-edge reduce at gradient.py:131 fires and
# upstream raises (it needs `broadcast_axes`, which is symbolic).  With every dimension
# equal, the permuted shape IS the shape.
