# mx_graph_census.bend -- A GRAPH CENSUS over the ported PUBLIC movement WRAPPERS in
# `tinybendygrad/mixin/movement.bend`: each driven once per fixture, with its toposort OP
# SEQUENCE printed in the format CPython prints for the method it mirrors.
#
#   .venv/bin/python gates/mx_graph_census-gate.py
#
# THE POPULATION IS DISCOVERED, AND THE DISCOVERY IS TWO FILTERS, NOT A LIST.
#
#   .venv/bin/python -c "..."   # see the gate's docstring for the exact command
#
#   (1) the `mx*` names: `grep -o '^def mx[a-z_0-9]*' tinybendygrad/mixin/movement.bend
#       | sort -u` -> 85, which is the whole public surface (`mx_`, `mxm_`, `mxw_`).
#   (2) A name is a METHOD PORT iff, after stripping one of the three prefixes `mxw_`,
#       `mxm_`, `mx_`, the remainder names a method of CPython's
#       `tinygrad/mixin/movement.py`. That is 7: `mxm_expand`->expand, `mxm_shape`->shape,
#       `mxw_flip`->flip, `mxw_pad`->pad, `mxw_permute`->permute, `mxw_reshape`->reshape,
#       `mxw_shrink`->shrink.
#   (3) A METHOD PORT is a ROW iff it BUILDS A UOp GRAPH -- i.e. its body calls
#       `O.UOp.new`, so it returns a `T.Tensor` and there is a toposort to print. That
#       drops `mxm_shape` (`-> List<&2, U32>`, the `_shape` arms of ops.py, not a
#       movement.py method body) and `mxm_expand` (`-> Bool`, a one-bit op test), which
#       are READERS of a graph and not builders of one. What remains is the WRITE HALF:
#
#           mxw_reshape  mxw_permute  mxw_pad  mxw_shrink  mxw_flip        (5)
#
#       and it is exactly the five methods `mixin/movement.py` gives an IDENTITY TEST
#       (`return self if ret.shape == self.shape else ret`, :185/:190/:194/:231/:254).
#       The rest of `movement.py` is NOT PORTED (see the file header's NOT PORTED list),
#       so 5 is the whole graph-building surface and not a sample of it.
#
# THE FIXTURE IS THE PORT'S OWN, AND IT IS `MX.mxw_base()`. The write half's identity
# test reads the SOURCE's shape, so the source cannot be a bare node -- it is
# `RESHAPE(BUFFER, STACK(1,4,8,8))`, the port's own base (:1571-1575). The CPython lane
# builds the SAME graph from a raw `UOp.new_buffer` and not from `Tensor.empty`, and the
# reason is MEASURED: `Tensor.empty(1,4,8,8, device='PYTHON')` is
# `6 Ops.RESHAPE/2 Ops.ALLOC Ops.STACK`, an ALLOC where the port has a BUFFER, and the
# ALLOC/BUFFER split would move every no-op row (`reshape_noop`, `permute_noop`,
# `pad_noop`, `shrink_noop`, `flip_noop`) because those rows return the BASE, whose root
# srcs ARE the storage node. `UOp.new_buffer("PYTHON", 256, float)` makes the CPython base
# byte-identical to the port's: `6 Ops.RESHAPE/2 Ops.BUFFER Ops.STACK`.
#
# THE PRINTER IS `O.Rng.sig` (ops.bend:5897) AND NOT `mxw_sig`. `mxw_sig` is the file's
# own `n=/op=/nsrc=/srcops=` string; the census format is the one the other three censuses
# use (`<toposort length> Ops.<TOP>/<nsrc> <src op sequence>`), so the CPython oracle can
# reproduce it with a `seq()`/`sig()` pair and the two lanes are comparable line-for-line.
#
# EVERY ROW IS DRIVEN THROUGH THE TENSOR-LEVEL METHOD (`MX.mxw_reshape`, `MX.mxw_pad`,
# ...) and not through the internal `.go`/`.of` helpers, for the reason the brief records:
# an oracle that calls a path the wrapper does not take agrees with a port that mirrors
# the wrong thing. The identity-test arm is a TENSOR-LEVEL branch (`mxw_pick`), so only
# the wrapper reaches it -- the `*_noop` rows are the ones that see it.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/mixin/movement.bend as MX

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# `O.Rng.sig` reads the arena and the node index. `+t` because both accessors read it.
def sg(+t: T.Tensor) -> String:
  O.Rng.sig(T.Tensor.ar(t), T.Tensor.u(t))

# --- the base, and the five wrappers, each with a real fixture and a no-op ----------
def sig_base() -> String:
  +t = MX.mxw_base()
  sg(t)

def sig_reshape_1_2_8_16() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_reshape(t, [1, 2, 8, 16]))

def sig_reshape_1_4_64() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_reshape(t, [1, 4, 64]))

def sig_reshape_noop() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_reshape(t, [1, 4, 8, 8]))

# THE ONE-ELEMENT SHAPE ARG, AND IT IS A LIVE PATH. `shape_to_shape_arg` (ops.py:106-110) is
# `src[0] if len(src) == 1 else UOp(Ops.STACK, src=src)`, so CPython builds a BARE CONST for a
# one-element shape; `mxw_stk` (:1254) is `G.mstack` UNCONDITIONALLY, so the port builds a
# `STACK`. `mixin/rand.bend` calls `MX.mxw_reshape(t, [])` and `MX.mxw_reshape(t, [1, ...])`
# on the `_pool` path and its own R3 records the same fact ("fixed for PAD and SHRINK, NOT for
# RESHAPE"). `256` is `prod((1,4,8,8))`, so the reshape is legal on both sides.
def sig_reshape_256() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_reshape(t, [256]))

def sig_permute_1_0_2_3() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_permute(t, [1, 0, 2, 3]))

def sig_permute_3_1_2_0() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_permute(t, [3, 1, 2, 0]))

def sig_permute_noop() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_permute(t, [0, 1, 2, 3]))

# `pad`'s second list is the ABSOLUTE END (`(x[0], s+x[0]+x[1])`, movement.py:189), which
# is what `mxw_pad`'s `his` already is: `pad(((0,0),(0,0),(1,1),(1,1)))` over (1,4,8,8)
# has marg `((0,1),(0,4),(1,10),(1,10))`, so `his = [1,4,10,10]`.
def sig_pad_1_1() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_pad(t, [0, 0, 1, 1], [1, 4, 10, 10]))

def sig_pad_asy() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_pad(t, [0, 0, 2, 1], [2, 6, 13, 9]))

def sig_pad_noop() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_pad(t, [0, 0, 0, 0], [1, 4, 8, 8]))

# `shrink`'s second list is the SIZE (`(x[0], x[1]-x[0])`, movement.py:211), so
# `shrink(((0,0),(0,0),(1,5),(1,5)))` is `offs=[0,0,1,1] sizes=[1,4,4,4]`.
def sig_shrink_1_1() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_shrink(t, [0, 0, 1, 1], [1, 4, 4, 4]))

def sig_shrink_asy() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_shrink(t, [0, 1, 2, 0], [1, 3, 5, 8]))

def sig_shrink_noop() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_shrink(t, [0, 0, 0, 0], [1, 4, 8, 8]))

def sig_flip_0() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, [1, 0, 0, 0]))

def sig_flip_01() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, [1, 1, 0, 0]))

def sig_flip_noop() -> String:
  +t = MX.mxw_base()
  sg(MX.mxw_flip(t, [0, 0, 0, 0]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("base", sig_base())
    b : Unit <- srow("reshape_1_2_8_16", sig_reshape_1_2_8_16())
    c : Unit <- srow("reshape_1_4_64", sig_reshape_1_4_64())
    d : Unit <- srow("reshape_noop", sig_reshape_noop())
    d2 : Unit <- srow("reshape_256", sig_reshape_256())
    e : Unit <- srow("permute_1_0_2_3", sig_permute_1_0_2_3())
    f : Unit <- srow("permute_3_1_2_0", sig_permute_3_1_2_0())
    g : Unit <- srow("permute_noop", sig_permute_noop())
    h : Unit <- srow("pad_1_1", sig_pad_1_1())
    i : Unit <- srow("pad_asy", sig_pad_asy())
    j : Unit <- srow("pad_noop", sig_pad_noop())
    k : Unit <- srow("shrink_1_1", sig_shrink_1_1())
    l : Unit <- srow("shrink_asy", sig_shrink_asy())
    m : Unit <- srow("shrink_noop", sig_shrink_noop())
    n : Unit <- srow("flip_0", sig_flip_0())
    o : Unit <- srow("flip_01", sig_flip_01())
    p : Unit <- srow("flip_noop", sig_flip_noop())
    return Unit{}
