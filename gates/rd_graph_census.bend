# rd_graph_census.bend -- THE GRAPH CENSUS over `mixin/rand.bend`'s `_threefry_random_bits`
# path. Every def driven once, its toposort OP SEQUENCE printed in the same format CPython
# prints for the same graph.
#
#   .venv/bin/python gates/rd_graph_census-gate.py
#
# WHY A CENSUS. `tinygrad/mixin/rand.py:12-15` is ONE method whose graph the port splits into
# four defs, and each split is a place the arena can be threaded wrong:
#
#   rand.py:13  `(counts1.cast(uint64) << 32) | counts0.cast(uint64)`            `rd_p64`
#   rand.py:14  `x.threefry((key[1].cast(uint64) << 32) | key[0].cast(uint64))` `rd_tfb.three`
#   rand.py:15  `x.cast(uint32).cat((x >> 32).cast(uint32))`                     `rd_tfb.cat`
#   rand.py:12  `_threefry_random_bits(key, counts0, counts1)`  = the four above `rd_tfb`
#
# THE PRINTER IS THE PORT'S OWN. `M.mo_sig_t` (op.bend:1146) is the census printer the
# `mo_graph_census` gate already uses -- the deep toposort, bare op names, so a wrong node
# ANYWHERE in the graph moves a row and not only the root.
#
# THE FIXTURES ARE `Tensor.empty`, NOT `arange`, AND THAT IS THE WHOLE POINT. `rand.py:26`
# builds the counts from `arange`, and the port's `R.op_arange` has its OWN known divergence
# from CPython (`rand.bend`'s header R2: the port's `arange(3, uint32)` is 28 nodes against
# CPython's 31, a separate defect in the trailing `.cast` and `_pool`). A gate over the OR
# ARENA RULE must not also be a gate over `arange`, or every row is red for a reason that has
# nothing to do with the arena. `Tensor.empty(3, uint32)` is ONE `ALLOC` in BOTH lanes, so the
# counts here are a chain the port threads correctly and the OR is the only thing under test.
#
# NOTHING IS EXECUTED. Every row is the signature of the LAZY graph, so no device is needed
# and the CPython lane is a `toposort()`.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/mixin/op.bend as M
import ./../tinybendygrad/mixin/creation.bend as CR
import ./../tinybendygrad/mixin/rand.bend as R

# THE COUNTS PAIR. `c1` is built AFTER `c0`, so `c1` is the NEWER node -- which is exactly the
# `rd_p64(c1, c0)` order `rd_tfb.x` uses and the order that exposed the defect: `rd_p64` puts
# the NEWER operand FIRST (it is `src[0]`, the shifted term), and the old `mo_bin` folded the
# SECOND operand's arena and answered the NOOP bottom.
def rd_c0(+ar: O.Arena) -> T.Tensor: CR.cr_empty(ar, Some{S.uint32()}, [3], S.D1{0})
def rd_c1(+t: T.Tensor) -> T.Tensor: M.mo_bin_c(t, O.OpsADD{}, M.mo_ki(1))

# `p64` -- rand.py:13 as `rd_p64(hi, lo)` spells it, driven with the call's own `(c1, c0)`
# order so the SHIFTED term is `src[0]` exactly as `_threefry_random_bits` writes it.
def c_p64() -> IO(Unit):
  +ar = O.Arena.empty()
  +c0: T.Tensor = rd_c0(ar)
  +c1: T.Tensor = rd_c1(c0)
  M.mo_sig_t("p64", R.rd_p64(c1, c0))

# `x` -- rand.py:13 as `rd_tfb.x(c0, c1)` spells it. A CONTROL for `p64`: `rd_tfb.x` IS
# `rd_p64(c1, c0)`, so the two rows must be byte-identical.
def c_x() -> IO(Unit):
  +ar = O.Arena.empty()
  +c0: T.Tensor = rd_c0(ar)
  +c1: T.Tensor = rd_c1(c0)
  M.mo_sig_t("x", R.rd_tfb.x(c0, c1))

# `three` -- rand.py:14, the key half. It reaches a SECOND `rd_p64` over `key[1]` and `key[0]`,
# so the row exercises the same arena rule through the key path.
def c_three() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = R.rd_key(ar)
  +c0: T.Tensor = rd_c0(T.Tensor.ar(k))
  +c1: T.Tensor = rd_c1(c0)
  M.mo_sig_t("three", R.rd_tfb.three(R.rd_tfb.x(c0, c1), k))

# `tfb` -- the WHOLE method, which is the row CPython's own `_threefry_random_bits` anchors.
def c_tfb() -> IO(Unit):
  +ar = O.Arena.empty()
  +k = R.rd_key(ar)
  +c0: T.Tensor = rd_c0(T.Tensor.ar(k))
  +c1: T.Tensor = rd_c1(c0)
  M.mo_sig_t("tfb", R.rd_tfb(T.Tensor.ar(c1), k, c0, c1))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- c_p64()
    b : Unit <- c_x()
    c : Unit <- c_three()
    d : Unit <- c_tfb()
    return Unit{}
