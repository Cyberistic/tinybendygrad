#!/usr/bin/env python3
"""ew_graph_census-oracle.py -- CPython's OP SEQUENCE for every ported public `ew_*`.

    .venv/bin/python gates/ew_graph_census-oracle.py

THE SAME 43 ROWS `gates/ew_graph_census.bend` PRINTS, FROM CPYTHON. The bend lane prints the
port's toposort op sequence; this lane prints CPython's for the METHOD the port mirrors, so a
divergence is a SHAPE divergence and not a prose claim.

THE POPULATION IS DISCOVERED, NOT LISTED. `ew_<n>` is a row iff CPython's
`tinygrad/mixin/elementwise.py` defines a METHOD `<n>(self` or `__<n>__(self`:

    for n in $(grep -o '^def ew_[a-z_0-9]*' tinybendygrad/mixin/elementwise.bend \\
               | sed 's/^def ew_//' | sort -u); do
      grep -qE "^ *def (${n}|__${n}__)\\(self" tinygrad/mixin/elementwise.py && echo $n
    done | wc -l        # 43

`promote` and `remint` fall out because they are NOT methods (`def promote(t)`, `def remint(u, dt)`),
which is the right exclusion: their effect is only visible THROUGH a binop, and the port's own gate
covers the promotion matrix in `ew_promo_*` rows.

THE FIXTURE IS TWO DISTINCT CONSTS AND A BOOL, and DISTINCT is the point. `t4()` alone is what
`gates/tn_graph_census.bend` uses, and it is wrong HERE for a measured reason: the `ew_*` layer
merges two operand arenas by LENGTH (`ew_newer`), not by content (`O.Arena.merge`, which the `tn_*`
layer uses), so two operands from two `Arena.empty()`s collapse to whichever node the longer arena
holds at that index. `t4()` twice hides that because the two nodes are equal; `t4()` against `t7()`
does not. The bend lane therefore builds ONE arena holding CONST4, CONST7 and bool-True and hands
out all three, which is the port's own contract ("a pair that is a prefix pair by construction")
and the shape `ew-consts.bend` drives through `g_i32`. `UOp.const` hash-conses here, so the two
lanes see the same distinct nodes.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor


def seq(u, seen=None, out=None):
    if seen is None:
        seen, out = set(), []
    if id(u) in seen:
        return out
    seen.add(id(u))
    for s in u.src:
        seq(s, seen, out)
    out.append(u.op.name)
    return out


def sig(r) -> str:
    s = seq(r.uop)
    srcs = " ".join("Ops." + u.op.name for u in r.uop.src)
    return f"{len(s)} Ops.{r.uop.op.name}/{len(r.uop.src)} {srcs}"


def tc(v):
    return Tensor(UOp(Ops.CONST, src=(), arg=v), device="PYTHON")


def t4():
    return tc(4)


def t7():
    return tc(7)


def tb():
    return tc(True)


print(f"ew_add={sig(t4().add(t7()))}")
print(f"ew_bitwise_and={sig(t4().bitwise_and(t7()))}")
print(f"ew_bitwise_not={sig(t4().bitwise_not())}")
print(f"ew_bitwise_or={sig(t4().bitwise_or(t7()))}")
print(f"ew_bitwise_xor={sig(t4().bitwise_xor(t7()))}")
print(f"ew_contiguous_backward={sig(t4().contiguous_backward())}")
print(f"ew_detach={sig(t4().detach())}")
print(f"ew_div={sig(t4().div(t7()))}")
print(f"ew_eq={sig(t4().eq(t7()))}")
print(f"ew_exp={sig(t4().exp())}")
print(f"ew_exp2={sig(t4().exp2())}")
print(f"ew_floor={sig(t4().floor())}")
print(f"ew_fmod={sig(t4().fmod(t7()))}")
print(f"ew_ge={sig(t4() >= t7())}")
print(f"ew_gt={sig(t4() > t7())}")
print(f"ew_log={sig(t4().log())}")
print(f"ew_log10={sig(t4().log10())}")
print(f"ew_log2={sig(t4().log2())}")
print(f"ew_logical_not={sig(t4().logical_not())}")
print(f"ew_lshift={sig(t4().lshift(t7()))}")
print(f"ew_lt={sig(t4() < t7())}")
print(f"ew_masked_fill={sig(t4().masked_fill(tb(), t7()))}")
print(f"ew_maximum={sig(t4().maximum(t7()))}")
print(f"ew_mod={sig(t4().mod(t7()))}")
print(f"ew_mul={sig(t4().mul(t7()))}")
print(f"ew_ne={sig(t4().ne(t7()))}")
print(f"ew_neg={sig(t4().neg())}")
print(f"ew_pow={sig(t4().pow(t7()))}")
print(f"ew_quick_gelu={sig(t4().quick_gelu())}")
print(f"ew_reciprocal={sig(t4().reciprocal())}")
print(f"ew_rshift={sig(t4().rshift(t7()))}")
print(f"ew_sigmoid={sig(t4().sigmoid())}")
print(f"ew_silu={sig(t4().silu())}")
print(f"ew_sin={sig(t4().sin())}")
print(f"ew_sqrt={sig(t4().sqrt())}")
print(f"ew_square={sig(t4().square())}")
print(f"ew_sub={sig(t4().sub(t7()))}")
print(f"ew_swish={sig(t4().swish())}")
print(f"ew_tanh={sig(t4().tanh())}")
print(f"ew_threefry={sig(t4().threefry(t7()))}")
print(f"ew_trunc={sig(t4().trunc())}")
print(f"ew_ufix={sig(t4().ufix(7))}")
print(f"ew_where={sig(tb().where(t4(), t7()))}")

# THE MIXED-DTYPE ROWS, and they are the ones that see the `mod` dispatch. CPython promotes
# BEFORE testing the dtypes, so `int % float` takes the FLOAT arm. The same-dtype rows above
# cannot see this: with both operands int the two answers coincide.
def t7i():
    return Tensor(UOp(Ops.CONST, src=(), arg=7), device="PYTHON")


def tf25():
    return Tensor(UOp(Ops.CONST, src=(), arg=2.5), device="PYTHON")


print(f"ew_mod_mixed={sig(t7i() % tf25())}")
print(f"ew_fmod_mixed={sig(t7i().fmod(tf25()))}")

# THE SIBLING ROW. CPython has no arena to lose: `t4().add(t7())` keeps BOTH operands, so its
# node count is 3. The port is 3 only because `ew_join` now re-mints through `O.Arena.merge`;
# under the old length rule it was 2, with both srcs naming the SAME node.
print(f"ew_add_siblings={sig(t4().add(t7()))}")
