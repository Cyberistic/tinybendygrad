# cr_graph_census.bend -- A GRAPH CENSUS over every ported PUBLIC `cr_*` in
# `tinybendygrad/mixin/creation.bend`: each driven once, with its toposort OP SEQUENCE
# printed.
#
#   .venv/bin/python gates/cr_graph_census-gate.py
#
# THE POPULATION IS DISCOVERED. `cr_<n>` is a row iff CPython's
# `tinygrad/mixin/creation.py` defines a METHOD `<n>(self` / `<n>(cls`. `creation.bend`
# has 39 distinct `cr_*` def prefixes; TEN of them mirror a creation.py method -- the
# other 29 are the plumbing (`cr_cast`, `cr_from_py`, `cr_bounds`, `cr_mop`, `cr_after`,
# `cr_alloc`, ...) and the gate's own printers/fixtures, exactly the way
# `ew_graph_census` drops `ew_join`/`ew_binop`/`ew_promote`. `const` is a
# `raise NotImplementedError` in creation.py and has NO def here; `_multi_like` is W2
# (the multi-device arm) and has NO def here either, so neither is a row.
#
# THE TEN BASE ROWS ARE ONE PER METHOD. THE EIGHTEEN `_v` ROWS ARE VARIANTS -- the fixtures
# that reach the arms the default call does not: the identity reshape (`empty(4)`), the
# 0-dim shape (`empty()`), the one-element shape arg that is a BARE CONST and not a STACK
# (`full((4,),7)`), `buffer=False` (the EXPAND root), the weak-dtype CAST (`dtype=half`,
# `dtype=int32`), the bool and float CONSTs, and the `*_like` methods on an INT32 and a BOOL
# receiver. The sibling `ew_graph_census` adds two such variants beyond its 43 methods; these
# are named `_v` so the count is auditable.
#
# THE FIXTURE. Every `cr_*` here takes the ARENA as a parameter rather than calling
# `O.Arena.empty()` itself (the port's own header: the arena IS Python's process-wide
# `UOpMetaClass.ucache`). The `full` family threads `T.Tensor.ar(val)` into the ALLOC, so
# ONE arena per row holds the CONST, the STACK, the EXPAND and the ALLOC. The `*_like`
# rows hand in `T.Tensor.ar(C.cr_fx2d())` -- the port's own `Tensor([[1.,2.],[3.,4.]])` --
# and `T.Tensor.ar(MO.mo_i1d())` for the int32 receiver, so the CONST is interned into the
# same arena CPython's global ucache interns it into.
#
# WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `NOOP` IS THE BOTTOM (`Arena.bottom()`), so a
# `NOOP` anywhere in a graph is an index read out of range and always a defect. The Python
# gate reads the LANE'S OWN output for it, so a `NOOP` in any row fails the gate.
#
# THE OP SEQUENCE IS PRINTED, NOT JUST THE VERDICT, because a graph can be wrong WITHOUT
# a NOOP: `cr_full`'s `dt in dtypes.weaks` test, the CONST's cast fold (`cr_cast`) and the
# arena `cr_alloc` is built in are all invisible to a bottom check, and each of them is a
# row in the file's own mutation table. The sequences are the evidence a reader compares
# against CPython; the `NOOP` row is the assertion.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/mixin/op.bend as MO
import ./../tinybendygrad/mixin/creation.bend as C

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# THE PRINTER IS THE PORT'S OWN `O.Rng.sig` -- node count, root op, root nsrc and the src
# op sequence in the format every sibling census uses. `+t` because the arena and the
# index are two reads of one tensor.
def crow(nm: String, +t: T.Tensor) -> IO(Unit):
  srow(nm, O.Rng.sig(T.Tensor.ar(t), T.Tensor.u(t)))

# ===========================================================================
# THE TEN BASE ROWS -- one per creation.py method.
# ===========================================================================

# creation.py:14 `const_like`. `b` is 0 (an int) on a float32 receiver, so the CONST is
# weakint and the CAST to f32 is real; `nz=True` (self is 2-D) so the EXPAND is the body.
def c_const_like() -> IO(Unit):
  +f = C.cr_fx2d()
  crow("const_like", C.cr_const_like(True{}, T.Tensor.ar(f), O.CInt{H.i64_of_i32(0)}, S.single(), [2, 2]))

# creation.py:23 `empty`.
def c_empty() -> IO(Unit):
  crow("empty", C.cr_empty(O.Arena.empty(), Some{S.single()}, [2, 3], S.D1{0}))

# creation.py:45 `empty_like`. `given=False` and a float32 `self_dt`, so `commit_dtype`
# answers f32 with no bounds (`dt`/`half` is ignored, exactly as CPython's `dtype=None`).
def c_empty_like() -> IO(Unit):
  +f = C.cr_fx2d()
  crow("empty_like", C.cr_empty_like(T.Tensor.ar(f), False{}, S.half(), S.single(), None{}, None{}, [2, 2], S.D1{0}))

# creation.py:53 `invalids` -- `full(argfix(*shape), Invalid, ...)`.
def c_invalids() -> IO(Unit):
  crow("invalids", C.cr_invalids(O.Arena.empty(), [2, 3], S.D1{0}))

# creation.py:64 `full`. `42` is a weakint CONST, `dtypes.from_py(42)` is weakint, so
# `cr_cast` folds and the CONST is BARE (9 nodes, one fewer than `full(.., dtype=half)`).
def c_full() -> IO(Unit):
  crow("full", C.cr_full(True{}, O.Arena.empty(), O.CInt{H.i64_of_i32(42)}, S.weakint(), [2, 3], S.D1{0}))

# creation.py:89 `full_like`. `dtype or self.dtype` with `dtype` unset is the receiver's
# f32, so the int 9 is CONST'd weakint and CAST to f32.
def c_full_like() -> IO(Unit):
  +f = C.cr_fx2d()
  crow("full_like", C.cr_full_like(T.Tensor.ar(f), O.CInt{H.i64_of_i32(9)}, S.single(), True{}, [2, 2], S.D1{0}))

# creation.py:108 `zeros` -- `full(argfix(*shape), 0.0, ...)`, a weakfloat CONST.
def c_zeros() -> IO(Unit):
  crow("zeros", C.cr_zeros(O.Arena.empty(), O.CFloat{0.0}, S.weakfloat(), [2, 3], S.D1{0}))

# creation.py:124 `zeros_like` -- `self.full_like(0, ...)`, so `self.dtype` wins and the
# int 0 is CAST to f32 (the sibling `zeros` row has a FLOAT CONST and no CAST).
def c_zeros_like() -> IO(Unit):
  +f = C.cr_fx2d()
  crow("zeros_like", C.cr_zeros_like(T.Tensor.ar(f), S.single(), [2, 2], S.D1{0}))

# creation.py:138 `ones` -- `full(argfix(*shape), 1.0, ...)`, a weakfloat CONST.
def c_ones() -> IO(Unit):
  crow("ones", C.cr_ones(O.Arena.empty(), O.CFloat{1.0}, S.weakfloat(), [2, 3], S.D1{0}))

# creation.py:154 `ones_like` -- `self.full_like(1, ...)`, the int 1 CAST to f32.
def c_ones_like() -> IO(Unit):
  +f = C.cr_fx2d()
  crow("ones_like", C.cr_ones_like(T.Tensor.ar(f), S.single(), [2, 2], S.D1{0}))

# ===========================================================================
# THE SIXTEEN VARIANTS.
# ===========================================================================

# `empty(4)`: `cr_resh.same([4], 4)` is TRUE, so the reshape is a no-op and the root is the
# bare ALLOC -- the ONE arm where `empty` builds no RESHAPE at all (fact 4 of the header).
def c_empty_v4() -> IO(Unit):
  crow("empty_v4", C.cr_empty(O.Arena.empty(), Some{S.single()}, [4], S.D1{0}))

# `empty()`: the 0-dim shape gives `prod([]) == 1` and a ZERO-src STACK, so the reshape is
# NOT a no-op and the graph is ALLOC, STACK/0, RESHAPE.
def c_empty_v0() -> IO(Unit):
  crow("empty_v0", C.cr_empty(O.Arena.empty(), Some{S.single()}, [], S.D1{0}))

# `full((4,), 7)`: a ONE-element shape arg is `src[0]` and not a `STACK` (`shape_to_shape_arg`
# ops.py:108), so the EXPAND has a bare CONST src and the identity reshape leaves the root's
# src[0] as the ALLOC.
def c_full_v4() -> IO(Unit):
  crow("full_v4", C.cr_full(True{}, O.Arena.empty(), O.CInt{H.i64_of_i32(7)}, S.weakint(), [4], S.D1{0}))

# `full((2,3), 42, buffer=False)`: the root is the EXPAND, no ALLOC/STORE/AFTER at all.
def c_full_vnobuf() -> IO(Unit):
  crow("full_vnobuf", C.cr_full(False{}, O.Arena.empty(), O.CInt{H.i64_of_i32(42)}, S.weakint(), [2, 3], S.D1{0}))

# `full((), 42, buffer=False)`: a 0-dim EXPAND is the early NOOP (`ops.py:820`), so the
# whole call is the bare CONST.
def c_full_v0nobuf() -> IO(Unit):
  crow("full_v0nobuf", C.cr_full(False{}, O.Arena.empty(), O.CInt{H.i64_of_i32(42)}, S.weakint(), [], S.D1{0}))

# `full((2,3), 42, dtype=half)`: `from_py(42) == weakint != half`, so the CAST is REAL and
# the CONST is the 10th node.
def c_full_vhalf() -> IO(Unit):
  crow("full_vhalf", C.cr_full(True{}, O.Arena.empty(), O.CInt{H.i64_of_i32(42)}, S.half(), [2, 3], S.D1{0}))

# `full((2,3), True)`: a bool CONST at `boolean`, and `cr_cast` folds it -- 9 nodes.
def c_full_vbool() -> IO(Unit):
  crow("full_vbool", C.cr_full(True{}, O.Arena.empty(), O.CBool{True{}}, S.boolean(), [2, 3], S.D1{0}))

# `full((2,3), 42.0)`: a weakfloat CONST, `cr_cast` folds it -- 9 nodes.
def c_full_vfloat() -> IO(Unit):
  crow("full_vfloat", C.cr_full(True{}, O.Arena.empty(), O.CFloat{42.0}, S.weakfloat(), [2, 3], S.D1{0}))

# `zeros((2,3), dtype=int32)`: `int32.const(0.0)` truncates to the int 0 (fact 3), so the
# CONST is weakint and the CAST to int32 is REAL -- 10 nodes.
def c_zeros_vi32() -> IO(Unit):
  crow("zeros_vi32", C.cr_zeros(O.Arena.empty(), O.CInt{H.i64_of_i32(0)}, S.int32(), [2, 3], S.D1{0}))

# `ones((2,3), dtype=int32)`: the same truncation-and-CAST.
def c_ones_vi32() -> IO(Unit):
  crow("ones_vi32", C.cr_ones(O.Arena.empty(), O.CInt{H.i64_of_i32(1)}, S.int32(), [2, 3], S.D1{0}))

# `full_like(9, dtype=half)`: `dtype or self.dtype` is half, so the int 9 is CAST to half;
# shape (2,2) has ONE distinct shape CONST, so 9 nodes and not 10.
def c_full_like_vhalf() -> IO(Unit):
  +f = C.cr_fx2d()
  crow("full_like_vhalf", C.cr_full_like(T.Tensor.ar(f), O.CInt{H.i64_of_i32(9)}, S.half(), True{}, [2, 2], S.D1{0}))

# `full_like(9, buffer=False)`: the EXPAND root, src[0] the CAST.
def c_full_like_vnobuf() -> IO(Unit):
  +f = C.cr_fx2d()
  crow("full_like_vnobuf", C.cr_full_like(T.Tensor.ar(f), O.CInt{H.i64_of_i32(9)}, S.single(), False{}, [2, 2], S.D1{0}))

# `empty_like(dtype=half)`: `given=True`, so the ALLOC's dtype is half and `commit_dtype`
# is not reached. The shape is the receiver's (2,2), so 4 nodes.
def c_empty_like_vhalf() -> IO(Unit):
  +f = C.cr_fx2d()
  crow("empty_like_vhalf", C.cr_empty_like(T.Tensor.ar(f), True{}, S.half(), S.single(), None{}, None{}, [2, 2], S.D1{0}))

# `Tensor([1,2,3,4]).zeros_like()`: `self.dtype` is int32, so `full((4,), 0, dtype=int32)`
# -- the int 0 CAST to int32, a bare shape CONST, and an IDENTITY reshape (7 nodes).
def c_zeros_like_vi() -> IO(Unit):
  +i = MO.mo_i1d()
  crow("zeros_like_vi", C.cr_zeros_like(T.Tensor.ar(i), S.int32(), [4], S.D1{0}))

# `Tensor([1,2,3,4]).empty_like()`: `commit_dtype` on an int32 receiver answers int32, and
# the (4,) reshape is the identity -- the bare ALLOC.
def c_empty_like_vi() -> IO(Unit):
  +i = MO.mo_i1d()
  crow("empty_like_vi", C.cr_empty_like(T.Tensor.ar(i), False{}, S.int32(), S.int32(), None{}, None{}, [4], S.D1{0}))

# `Tensor(7).const_like(0)`: a 0-dim receiver has `self._shape == ()`, so the `_mop(EXPAND)`
# is skipped and the whole call is the bare CONST -- the `nz=False` arm.
def c_const_like_v0d() -> IO(Unit):
  crow("const_like_v0d", C.cr_const_like(False{}, O.Arena.empty(), O.CInt{H.i64_of_i32(0)}, S.weakint(), []))

# `Tensor([True,False,True,True]).zeros_like()`: `self.dtype` is bool, so CPython's
# `bool.const(0)` is the BOOL `False` and `.cast(bool)` FOLDS -- a bare CONST. The port's
# `cr_zeros_like` (creation.bend:427) hardcodes `MO.mo_ki(0)`, an INT const, so
# `cr_const_of` reads `from_py(0) == weakint != bool` and builds a REAL CAST. One extra node.
def c_zeros_like_vbool() -> IO(Unit):
  crow("zeros_like_vbool", C.cr_zeros_like(O.Arena.empty(), S.boolean(), [4], S.D1{0}))

# `Tensor([True,False,True,True]).ones_like()`: the same hardcoded-int defect, `mo_ki(1)`.
def c_ones_like_vbool() -> IO(Unit):
  crow("ones_like_vbool", C.cr_ones_like(O.Arena.empty(), S.boolean(), [4], S.D1{0}))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- c_const_like()
    b : Unit <- c_empty()
    c : Unit <- c_empty_like()
    d : Unit <- c_invalids()
    e : Unit <- c_full()
    f : Unit <- c_full_like()
    g : Unit <- c_zeros()
    h : Unit <- c_zeros_like()
    i : Unit <- c_ones()
    j : Unit <- c_ones_like()
    k : Unit <- c_empty_v4()
    l : Unit <- c_empty_v0()
    m : Unit <- c_full_v4()
    n : Unit <- c_full_vnobuf()
    o : Unit <- c_full_v0nobuf()
    p : Unit <- c_full_vhalf()
    q : Unit <- c_full_vbool()
    r : Unit <- c_full_vfloat()
    s : Unit <- c_zeros_vi32()
    t : Unit <- c_ones_vi32()
    u : Unit <- c_full_like_vhalf()
    v : Unit <- c_full_like_vnobuf()
    w : Unit <- c_empty_like_vhalf()
    x : Unit <- c_zeros_like_vi()
    y : Unit <- c_empty_like_vi()
    z : Unit <- c_const_like_v0d()
    aa : Unit <- c_zeros_like_vbool()
    ab : Unit <- c_ones_like_vbool()
    return Unit{}
