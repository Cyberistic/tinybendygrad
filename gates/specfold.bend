# specfold.bend -- the PORT half of the spec-fold lane: the node shapes whose verdict
# commit d4160980e decides, read in the port's own fold.
#
#   checks/bendlock.sh -- .venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend gates/specfold.bend
#
# WHAT THIS IS. `d4160980e` moved eight tests out of the port's rule BODIES and into
# the port's rule CONDITIONS, so that the port's conditions say exactly what upstream's
# PATTERNS say. The class it fixed is one: a rule whose port condition is STRICTER than
# upstream's pattern reaches nodes upstream's scan cannot reach, and the two sides then
# disagree -- not about the node, but about WHICH RULE SPEAKS. Upstream's fold is
# first-wins and a pattern that does not match means "move on"; the port's `O.pm_when`
# returns `VSkip{}` when its condition is false, which is the same "move on".
#
# THE FIVE FIXTURES, and each one is a shape the commit's diff decides:
#
#   reshape_f32  RESHAPE whose SECOND src -- the SHAPE -- is a float. Upstream's
#                `spec.py:166` puts the shape's dtype in the PATTERN
#                (`UPat(dtype=dtypes.ints+(dtypes.weakint, dtypes.void))`), so a float
#                shape cannot match it, the scan continues, and upstream answers `None`.
#                The port's `te_5` had no dtype clause at all, so it matched and the port
#                answered `True`. That is the commit's headline divergence.
#   range2       RANGE with TWO srcs. Upstream's `spec.py:81` is `src=(UPat(),)` -- a
#                ONE-tuple, so EXACTLY one src -- and the port's `sh_12` used to accept
#                any number of srcs (`nsrc_ge(1)`).
#   backedge_int BACKEDGE whose THIRD src -- the CONDITION -- is not boolean-dtyped.
#                Upstream's `spec.py:88` puts the condition's dtype in the PATTERN
#                (`UPat(dtype=dtypes.bool)`); the port's `sh_15` did not test it.
#   buffer0      BUFFER with ZERO srcs. Upstream's `spec.py:150` is
#                `src=(p_size,), allow_any_len=True`, and `allow_any_len` relaxes the
#                length ABOVE the tuple's length, never below it, so a 0-src BUFFER
#                cannot match it. The port's `te_1` had no length test at all.
#   alloc0       ALLOC with ZERO srcs -- `spec.py:153`, `te_2`, and the same shape.
#
# THE THREE CONTROLS, and each one is a shape the commit's diff does NOT decide, so its
# rows must NOT move when the commit is reversed:
#   reshape_i32  RESHAPE whose shape src is an int -- `te_5` matches it either way.
#   range1       RANGE with ONE src -- `sh_12` matches it either way.
#   backedge_bool BACKEDGE whose condition IS boolean-dtyped -- `sh_15` matches it.
#
# `1` is VTrue, `0` is VFalse, `9` is VSkip -- the port's `Sp.show_v` spelling, and
# `gates/specfold-oracle.py` prints the same numbers from CPython's own matchers.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/uop/spec.bend as Sp

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# ONE FIXTURE, ALL SIX VERDICTS. `fu_rewrite`/`kg_rewrite` take their `PMEntrys` by
# `+`, and a table is affine: it is spent on use, so the tables are RE-BUILT per use.
def probe(+nm: String, +i: U32, +fx: F.Folded) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row(String.concat([nm, "_sh"]), Sp.show_v(Sp.shared_rewrite(fx, i)))
    b : Unit <- row(String.concat([nm, "_te"]), Sp.show_v(Sp.tensor_rewrite(fx, i)))
    c : Unit <- row(String.concat([nm, "_sp"]), Sp.show_v(Sp.program_rewrite(fx, i)))
    d : Unit <- row(String.concat([nm, "_hq"]), Sp.show_v(Sp.hcq_rewrite(fx, i)))
    e : Unit <- row(String.concat([nm, "_sk"]), Sp.show_v(Sp.kg_rewrite(Sp.kernel_graph_table(), fx, i)))
    f : Unit <- row(String.concat([nm, "_sf"]), Sp.show_v(Sp.fu_rewrite(Sp.full_table(), fx, i)))
    return Unit{}

# FIXTURE ONE. A RESHAPE whose SHAPE src is a float. The float is spelled as a CAST to
# f32 over a weakfloat CONST, because that is how upstream spells `UOp.const(1.0,
# dtypes.float32)` -- a CONST cannot carry a float dtype in either tree, so the dtype
# lives in the CAST and the SHAPE src's dtype is f32 on BOTH sides.
def reshape_f32() -> O.Found:
  +src = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +fc = O.UOp.const(O.Found.ar(src), O.CFloat{1.0})
  +shp = O.UOp.new(O.Found.ar(fc), O.OpsCAST{}, [O.Found.i(fc)], O.ADt{S.single()}, O.TNone{})
  O.UOp.new(O.Found.ar(shp), O.OpsRESHAPE{}, [O.Found.i(src), O.Found.i(shp)], O.ANone{}, O.TNone{})

# THE CONTROL: the same RESHAPE with an INT shape. `te_5`'s dtype clause admits it, so
# the row must not move when the commit is reversed.
def reshape_i32() -> O.Found:
  +src = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +c = O.UOp.const(O.Found.ar(src), O.CInt{H.i64_of_i32(2)})
  +shp = O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{S.int32()}, O.TNone{})
  O.UOp.new(O.Found.ar(shp), O.OpsRESHAPE{}, [O.Found.i(src), O.Found.i(shp)], O.ANone{}, O.TNone{})

# FIXTURE TWO. A RANGE with TWO srcs. Upstream's `spec.py:81` is `src=(UPat(),)` -- a
# ONE-tuple -- so exactly one src, and the port's `sh_12` used to be `nsrc_ge(1)`.
def range2() -> O.Found:
  +c1 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +c2 = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(2)})
  O.UOp.new(O.Found.ar(c2), O.OpsRANGE{}, [O.Found.i(c1), O.Found.i(c2)],
            O.ARange{[O.Found.i(c1)], O.AXIS_WEAK{}}, O.TNone{})

# THE CONTROL: the same RANGE with ONE src, which `sh_12` matches either way.
def range1() -> O.Found:
  +c1 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  O.UOp.new(O.Found.ar(c1), O.OpsRANGE{}, [O.Found.i(c1)],
            O.ARange{[O.Found.i(c1)], O.AXIS_WEAK{}}, O.TNone{})

# FIXTURE THREE. A BACKEDGE whose CONDITION is an int CONST. Upstream's `spec.py:88`
# puts the condition's dtype in the PATTERN (`UPat(dtype=dtypes.bool)`), so an int
# condition cannot match it.
def backedge_int() -> O.Found:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +loop = O.UOp.loop(O.Found.ar(c), 0)
  O.UOp.backedge(O.Found.ar(loop), O.Found.i(c), O.Found.i(loop), O.Found.i(c))

# THE CONTROL: the same BACKEDGE with a BOOL-typed condition, which `sh_15` matches
# either way. The bool is a CAST over the CONST, because a CONST carries weakint.
def backedge_bool() -> O.Found:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +b = O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{S.boolean()}, O.TNone{})
  +loop = O.UOp.loop(O.Found.ar(b), 0)
  O.UOp.backedge(O.Found.ar(loop), O.Found.i(c), O.Found.i(loop), O.Found.i(b))

# FIXTURE FOUR. A GLOBAL BUFFER with ZERO srcs. Upstream's `spec.py:150` is
# `src=(p_size,), allow_any_len=True` -- `allow_any_len` relaxes the length ABOVE the
# tuple's, so a 0-src BUFFER cannot match it and upstream's scan continues.
#
# THE PARAMARG. `buf_param()` is the port's GLOBAL int32 buffer with a device and a
# realized buffer; it carries NO size, and the size in this tree is `src[0]` -- so a
# 0-src BUFFER has no size, and `te_1`'s `Pa.size` conjunct is false. That is the
# port's reading of a node upstream never reaches, and it is why the port's pre-commit
# answer is `False` where upstream's is `None`: the rule SPOKE, and upstream's did not.
def buffer0() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{Sp.buf_param()}, O.TNone{})

# FIXTURE FIVE. A GLOBAL ALLOC with ZERO srcs -- `spec.py:153` and the port's `te_2`.
# An ALLOC has no realized buffer, and `te_2`'s size conjunct is a tautology, so the
# port's pre-commit answer is `True`: the port ACCEPTED a node upstream's scan never
# reaches.
# THE ALLOC's PARAMARG, minted HERE rather than borrowed, because `tinybendygrad/**` is
# not this lane's to edit. It is `Sp.buf_param()` with the realized buffer REMOVED --
# an ALLOC declares storage without a runtime buffer -- and it is GLOBAL with a device,
# so `te_2`'s addrspace conjunct and `kg_6`'s are both satisfied.
def alloc_param() -> O.ParamArg:
  O.ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
             False{}, None{}, None{}, False{}, None{}}

def alloc0() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsALLOC{}, Nil{}, O.AParam{alloc_param()}, O.TNone{})

def shape_rows(+nm: String, +n: O.Found) -> IO(Unit):
  probe(nm, O.Found.i(n), F.folded(O.Found.ar(n)))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- shape_rows("reshape_f32", reshape_f32())
    b : Unit <- shape_rows("reshape_i32", reshape_i32())
    c : Unit <- shape_rows("range2", range2())
    d : Unit <- shape_rows("range1", range1())
    e : Unit <- shape_rows("backedge_int", backedge_int())
    f : Unit <- shape_rows("backedge_bool", backedge_bool())
    g : Unit <- shape_rows("buffer0", buffer0())
    h : Unit <- shape_rows("alloc0", alloc0())
    return Unit{}
