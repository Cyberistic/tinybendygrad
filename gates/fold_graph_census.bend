# fold_graph_census.bend -- A VALUE CENSUS of the FOLD PROPERTIES of
# `tinybendygrad/uop/fold.bend`.
#
#   .venv/bin/python gates/fold_graph_census-gate.py
#
# WHAT THIS IS. The seven censuses beside it print OP SEQUENCES (a graph). A fold
# property answers a VALUE -- a dtype, a shape, a pair of bounds, a bool, a node --
# and an op sequence cannot see a value. This driver prints the VALUE of every fold
# property the port answers, for the SAME fixture graph, and the oracle reads the
# SAME property off a real `UOp`. `gatekit`'s two-lane shape is unchanged; only the
# printed thing differs.
#
# THE POPULATION IS THE SEVEN CPYTHON PROPERTIES (`tinygrad/uop/ops.py`):
#   :247  UOp.dtype      :267  UOp.is_invalid  :454  UOp.shape
#   :600  UOp.const_like :782  UOp.base        :1102 UOp.vmin   :1104 UOp.vmax
# SIX are answered by this port. `const_like` (ops.py:600) is NOT: it is a named WALL
# in `schedule/rangeify.bend` ("needs `DType.const` and `_mop(EXPAND)`"), and there is
# no `fold.bend` def for it -- `grep '^def .*const_like' uop/fold.bend` is EMPTY. So a
# census of the port's fold can print six of the seven, and the seventh is the
# FINDING, not a missing row.
#
# THE TEXTUAL FORM. One line per fixture, and every field is the port's OWN printer:
#
#   <tag> <sig4> dtype=<nm|ABSENT> shape=<(..)|none|raise|ABSENT> base=<op|ABSENT>
#         self=<0|1|-> invalid=<0|1> vmin=<bnd|ABSENT> vmax=<bnd|ABSENT>
#
#   * `sig4` is `F.sig4` (fold.bend:5553): `n=<toposort len> op=<Ops.X> nsrc=<k>
#     srcops=<A|B>`. It is the same four facts the sibling censuses print, so a
#     fixture built with the wrong op or src count is caught BEFORE its value is read.
#   * `dtype` is `F.dt_nm` (fold.bend:5891), which reads `S.Dt`'s fourth field -- the
#     port's spelling of tinygrad's `DType.name`. `spec.bend` has no reader for it.
#   * `shape` is `F.dims_str` (fold.bend:5867). `none` is Python's `_shape is None`,
#     `raise` is a Python raise, and `ABSENT` is the PORT's own refusal (the fold
#     produced no `Derived` for the node). The port's `F.shape_str` conflates `none`
#     with `raise`; this driver keeps them apart because they are different claims.
#   * `base` is the base NODE's op name (`Ops.name`), and `self` is 1 when the base
#     IS the node (`u.base is u`). Both fields are needed: `ADD(ADD(x,y), z)` has
#     `base.op == ADD` and `base is not self`.
#   * `invalid` is `F.is_invalid` (fold.bend:2405) -- a reader over the node's own
#     arg, so it is total where a table read is not.
#   * `vmin`/`vmax` are `F.bnd_show` (fold.bend:3494): `+hi:lo`/`-hi:lo` for an
#     integer (a sign plus an UNSIGNED 64-bit magnitude), `NInf`/`PInf` for an
#     infinity, `F<float>` for a finite float. The oracle renders CPython's real
#     `u.vmin` into the SAME three shapes, so the diff is a value diff.
#
# THE FIXTURE IS THE WHOLE GAME. `gates/ew_graph_census.bend`'s `world()` puts every
# node in ONE arena and hands them out, which is the safe shape; this driver is a set
# of independent fixtures (each builds its own arena) because a fold property is read
# per NODE, so the fixture must VARY the op, the dtype and the src shapes:
#   * every dtype class a CONST can hold: weakint, weakfloat, bool, Invalid;
#   * the two 64-bit BUFFER limits (sign + unsigned magnitude);
#   * the elementwise/binary arms (ADD, SUB, MUL) over CONSTs;
#   * the movement arms whose SHAPE is answered (RESHAPE, EXPAND, PAD) and whose BASE
#     walks a chain (DETACH over RESHAPE, RESHAPE over RESHAPE);
#   * RANGE and SPECIAL, whose bound is `0, src[0].vmax - 1`;
#   * STACK, whose bound is a fold over its srcs;
#   * the arg-only trap: `c_int3` and `c_int4` differ ONLY in the CONST's arg, so
#     dtype/shape/base/self/invalid are IDENTICAL and only `vmin`/`vmax` move -- the
#     `Rng.sig`-does-not-print-an-arg failure, made visible.
#
# THE ARENA MERGE RULE. This driver has no merge at all: every fixture is built by
# `O.UOp.new`/`O.UOp.const`, which APPEND to the arena the fold was built on, never
# `O.Arena.merge` and never `ew_newer`'s length rule. So trap (b) is structurally
# absent here; the fixtures differ because the OPS differ.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F

# ===========================================================================
# THE PRINTERS. Each is a `Maybe` out of a reader and the file's own word for
# "this fold cannot answer": `ABSENT`.
# ===========================================================================

def b01(b: Bool) -> String:
  Bool.pick(String, b, "1", "0")

def dtv(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: F.dt_nm(d)
    case None{}: "ABSENT"

def shape_inner(+ar: O.Arena, g: Maybe<&2, List<&2, O.Sint>>) -> String:
  match g:
    case None{}: "none"
    case Some{ds}: F.dims_str(ar, ds)

def shapev(+ar: O.Arena, m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  match m:
    case None{}: "ABSENT"
    case Some{g}: shape_inner(ar, g)

def basev(+ar: O.Arena, m: Maybe<&1, U32>) -> String:
  match m:
    case Some{b}: O.Ops.name(O.Arena.op(ar, b))
    case None{}: "ABSENT"

def selfv(i: U32, m: Maybe<&1, U32>) -> String:
  match m:
    case Some{b}: b01(U32.is_eq(b, i))
    case None{}: "-"

def bndv(m: Maybe<&2, F.Bnd>) -> String:
  match m:
    case Some{b}: F.bnd_show(b)
    case None{}: "ABSENT"

# ===========================================================================
# THE ROW. ONE fold per fixture, and the `_min_max` SWEEP over the FINISHED table,
# because `UOp.vmin` reads a `BTable` and `UOp.dtype` reads the main `Table`. The
# readers are the port's public `F.UOp.*` and nothing here reimplements one.
#
# The `+` bindings pay for reading the arena, the table, the index and the bound
# table more than once in the one line; `mm.sweep` consumes nothing at the call site
# because the bindings are already duplicable.
# ===========================================================================
def row(nm: String, +f: O.Found) -> IO(Unit):
  +x = F.folded(O.Found.ar(f))
  +ar = F.Folded.ar(x)
  +tb = F.Folded.t(x)
  +i = O.Found.i(f)
  +sg = F.sig4(ar, i)
  +dt = dtv(F.UOp.dtype(ar, tb, i))
  +sh = shapev(ar, F.UOp.shape(ar, tb, i))
  +bs = basev(ar, F.UOp.base(ar, tb, i))
  +sl = selfv(i, F.UOp.base(ar, tb, i))
  +iv = b01(F.is_invalid(ar, i))
  +bt = F.mm.sweep(ar, tb)
  +vm = bndv(F.UOp.vmin(ar, bt, i))
  +vx = bndv(F.UOp.vmax(ar, bt, i))
  IO.print(String.concat([nm, "=", sg, " dtype=", dt, " shape=", sh, " base=", bs,
    " self=", sl, " invalid=", iv, " vmin=", vm, " vmax=", vx]))

# ===========================================================================
# THE FIXTURE BUILDERS. `O.UOp.new`/`O.UOp.const` append to the arena and answer a
# `Found`; `O.Found.ar`/`O.Found.i` are the grown arena and the new index.
# ===========================================================================

def pa(dt: S.Dt, size: Maybe<&2, U32>, vmm: Maybe<&2, O.PyRange>) -> O.ParamArg:
  O.ParamArg{0, dt, size, vmm, None{}, None{}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}

def cst(ar: O.Arena, n: U32) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(n)})

def buf(ar: O.Arena, dt: S.Dt, size: U32) -> O.Found:
  O.UOp.new(ar, O.OpsBUFFER{}, Nil{}, O.AParam{pa(dt, Some{size}, None{})}, O.TNone{})

def param(ar: O.Arena, dt: S.Dt, size: Maybe<&2, U32>, vmm: Maybe<&2, O.PyRange>) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{}, O.AParam{pa(dt, size, vmm)}, O.TNone{})

def bin2(ar: O.Arena, op: O.Op, a: O.Found, b: O.Found) -> O.Found:
  O.UOp.new(ar, op, [O.Found.i(a), O.Found.i(b)], O.ANone{}, O.TNone{})

def un1(ar: O.Arena, op: O.Op, a: O.Found, arg: O.Arg) -> O.Found:
  O.UOp.new(ar, op, [O.Found.i(a)], arg, O.TNone{})

def stk2(ar: O.Arena, a: O.Found, b: O.Found) -> O.Found:
  O.UOp.new(ar, O.OpsSTACK{}, [O.Found.i(a), O.Found.i(b)], O.ANone{}, O.TNone{})

def resh(ar: O.Arena, s: O.Found, m: O.Found) -> O.Found:
  O.UOp.new(ar, O.OpsRESHAPE{}, [O.Found.i(s), O.Found.i(m)], O.ANone{}, O.TNone{})

# `shape_to_shape_arg((2, 2))`: STACK(CONST(2), CONST(2)), and the two CONSTs are ONE
# node after interning -- the same collapse CPython's ucache makes.
def marg22(ar: O.Arena) -> O.Found:
  +c0 = cst(ar, 2)
  +c1 = cst(O.Found.ar(c0), 2)
  stk2(O.Found.ar(c1), c0, c1)

def f_c_int3() -> O.Found: O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(3)})

def f_c_int4() -> O.Found: O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})

def f_c_float() -> O.Found: O.UOp.const(O.Arena.empty(), O.CFloat{1.0})

def f_c_bool_t() -> O.Found: O.UOp.const(O.Arena.empty(), O.CBool{True{}})

def f_c_bool_f() -> O.Found: O.UOp.const(O.Arena.empty(), O.CBool{False{}})

def f_c_invalid() -> O.Found: O.UOp.const(O.Arena.empty(), O.CInvalid{})

def f_buf_i32() -> O.Found: buf(O.Arena.empty(), S.int32(), 4)

def f_buf_i64() -> O.Found: buf(O.Arena.empty(), S.int64(), 2)

def f_add_ii() -> O.Found:
  +a = cst(O.Arena.empty(), 3)
  +b = cst(O.Found.ar(a), 4)
  bin2(O.Found.ar(b), O.OpsADD{}, a, b)

def f_sub_ii() -> O.Found:
  +a = cst(O.Arena.empty(), 3)
  +b = cst(O.Found.ar(a), 4)
  bin2(O.Found.ar(b), O.OpsSUB{}, a, b)

def f_mul_ii() -> O.Found:
  +a = cst(O.Arena.empty(), 3)
  +b = cst(O.Found.ar(a), 4)
  bin2(O.Found.ar(b), O.OpsMUL{}, a, b)

def f_cast_i32() -> O.Found:
  +a = cst(O.Arena.empty(), 3)
  un1(O.Found.ar(a), O.OpsCAST{}, a, O.ADt{S.int32()})

def f_stack2() -> O.Found:
  +a = cst(O.Arena.empty(), 2)
  +b = cst(O.Found.ar(a), 3)
  stk2(O.Found.ar(b), a, b)

def f_reshape22() -> O.Found:
  +b = buf(O.Arena.empty(), S.int32(), 4)
  +m = marg22(O.Found.ar(b))
  resh(O.Found.ar(m), b, m)

def f_resh_resh() -> O.Found:
  +b = buf(O.Arena.empty(), S.int32(), 4)
  +m = marg22(O.Found.ar(b))
  +r = resh(O.Found.ar(m), b, m)
  +c = cst(O.Found.ar(r), 4)
  resh(O.Found.ar(c), r, c)

def f_expand() -> O.Found:
  +b = buf(O.Arena.empty(), S.int32(), 4)
  +c = cst(O.Found.ar(b), 2)
  bin2(O.Found.ar(c), O.OpsEXPAND{}, b, c)

def f_detach_resh() -> O.Found:
  +b = buf(O.Arena.empty(), S.int32(), 4)
  +m = marg22(O.Found.ar(b))
  +r = resh(O.Found.ar(m), b, m)
  un1(O.Found.ar(r), O.OpsDETACH{}, r, O.ANone{})

def f_range5() -> O.Found:
  +c = cst(O.Arena.empty(), 5)
  O.UOp.range_end(O.Found.ar(c), O.Found.i(c), [0], O.AXIS_LOOP{})

def f_special4() -> O.Found:
  +c = cst(O.Arena.empty(), 4)
  O.UOp.special(O.Found.ar(c), O.Found.i(c), "N")

def f_threefry() -> O.Found:
  +a = cst(O.Arena.empty(), 0)
  +b = cst(O.Found.ar(a), 0)
  +c = cst(O.Found.ar(b), 0)
  O.UOp.new(O.Found.ar(c), O.OpsTHREEFRY{}, [O.Found.i(a), O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

def f_noop_buf() -> O.Found:
  +b = buf(O.Arena.empty(), S.int32(), 4)
  un1(O.Found.ar(b), O.OpsNOOP{}, b, O.ANone{})

def f_store_buf() -> O.Found:
  +b = buf(O.Arena.empty(), S.int32(), 4)
  +c = cst(O.Found.ar(b), 0)
  bin2(O.Found.ar(c), O.OpsSTORE{}, b, c)

def f_pad_param() -> O.Found:
  +p = param(O.Arena.empty(), S.int32(), Some{4}, Some{O.PyRange{H.i64_of_i32(5), H.i64_of_i32(9)}})
  +o = cst(O.Found.ar(p), 0)
  +z = cst(O.Found.ar(o), 11)
  O.UOp.new(O.Found.ar(z), O.OpsPAD{}, [O.Found.i(p), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

def f_param_neg() -> O.Found:
  param(O.Arena.empty(), S.int32(), None{}, Some{O.PyRange{H.i64_of_i32(4294967293), H.i64_of_i32(7)}})

# A PARAM `variable`, the port's `g_mv_var`: `vmin_vmax` present, so `sym_dim` answers
# it. `nm` is the dim's own name, which is what `dim_str` prints.
def var(ar: O.Arena, lo: U32, hi: U32, nm: String) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{},
    O.AParam{O.ParamArg{0, S.weakint(), None{}, Some{O.PyRange{H.i64_of_i32(lo), H.i64_of_i32(hi)}},
      Some{1}, Some{nm}, S.Aalu{}, None{}, False{}, None{}, None{}, False{}, None{}}}, O.TNone{})

# EXPAND over a symbolic marg with a REAL end: the SPECIAL's interval is `[0, 98]`, so
# `sym_dim` answers the `SU` and BOTH lanes print `(2,U(Ops.SPECIAL:N),4)`. This is the
# row that says a symbolic dim is ANSWERED (as an `SU`) and not merely refused.
def f_expand_sym_pos() -> O.Found:
  +b = buf(O.Arena.empty(), S.int32(), 4)
  +e = cst(O.Found.ar(b), 99)
  +n = O.UOp.special(O.Found.ar(e), O.Found.i(e), "N")
  +c = cst(O.Found.ar(n), 2)
  +k = stk2(O.Found.ar(c), c, n)
  bin2(O.Found.ar(k), O.OpsEXPAND{}, b, k)

# THE SAME OP WITH AN END OF ZERO: the SPECIAL's interval is `[0, -1]`, EMPTY, which
# `sym_dim` refuses because ops.py:408's `all(x >= 0)` is then decidable. CPython does
# NOT refuse (its `ssimplify` is the identity here), so this is a DECLARED divergence --
# the `mv_expsym` class, pinned in the gate.
def f_expand_sym() -> O.Found:
  +b = buf(O.Arena.empty(), S.int32(), 4)
  +e = cst(O.Found.ar(b), 0)
  +n = O.UOp.special(O.Found.ar(e), O.Found.i(e), "N")
  +c = cst(O.Found.ar(n), 2)
  +k = stk2(O.Found.ar(c), c, n)
  bin2(O.Found.ar(k), O.OpsEXPAND{}, b, k)

# RESHAPE over a bare PARAM `n` in `[0, 0xFFFFFF]`: unresolvable, so no raise, and both
# lanes answer `(U(Ops.PARAM:n))`.
def f_reshbare_n() -> O.Found:
  +b = buf(O.Arena.empty(), S.int32(), 4)
  +n = var(O.Found.ar(b), 0, 16777215, "n")
  resh(O.Found.ar(n), b, n)

# THE RESIDUAL, AND IT IS A DECLARED DIVERGENCE. `w` over `[0, 3]` and `prod(ps) = 4`
# are DISJOINT, so `resolve(..., False)` is decidable and TRUE and CPython raises
# `bad reshape`; this fold answers `(U(Ops.PARAM:w))` because it cannot multiply
# intervals. The `mv_reshbare_dis` class, pinned in the gate.
def f_reshbare_w() -> O.Found:
  +b = buf(O.Arena.empty(), S.int32(), 4)
  +w = var(O.Found.ar(b), 0, 3, "w")
  resh(O.Found.ar(w), b, w)

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("fold_c_int3", f_c_int3())
    b : Unit <- row("fold_c_int4", f_c_int4())
    c : Unit <- row("fold_c_float", f_c_float())
    d : Unit <- row("fold_c_bool_t", f_c_bool_t())
    e : Unit <- row("fold_c_bool_f", f_c_bool_f())
    f : Unit <- row("fold_c_invalid", f_c_invalid())
    g : Unit <- row("fold_buf_i32", f_buf_i32())
    h : Unit <- row("fold_buf_i64", f_buf_i64())
    i : Unit <- row("fold_add_ii", f_add_ii())
    j : Unit <- row("fold_sub_ii", f_sub_ii())
    k : Unit <- row("fold_mul_ii", f_mul_ii())
    l : Unit <- row("fold_cast_i32", f_cast_i32())
    m : Unit <- row("fold_stack2", f_stack2())
    n : Unit <- row("fold_reshape22", f_reshape22())
    o : Unit <- row("fold_resh_resh", f_resh_resh())
    p : Unit <- row("fold_expand", f_expand())
    q : Unit <- row("fold_detach_resh", f_detach_resh())
    r : Unit <- row("fold_range5", f_range5())
    s : Unit <- row("fold_special4", f_special4())
    t : Unit <- row("fold_threefry", f_threefry())
    u : Unit <- row("fold_noop_buf", f_noop_buf())
    v : Unit <- row("fold_store_buf", f_store_buf())
    w : Unit <- row("fold_pad_param", f_pad_param())
    x : Unit <- row("fold_param_neg", f_param_neg())
    y : Unit <- row("fold_expand_sym_pos", f_expand_sym_pos())
    z : Unit <- row("fold_expand_sym", f_expand_sym())
    aa : Unit <- row("fold_reshbare_n", f_reshbare_n())
    ab : Unit <- row("fold_reshbare_w", f_reshbare_w())
    return Unit{}
