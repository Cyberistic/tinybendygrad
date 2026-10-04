# ===========================================================================
# ns-fix.bend -- EIGHT SEPARATE QUESTIONS ABOUT `uop/fold.bend`'s CUSTOM/CUSTOMI arm,
# one graph each, so that "the port has no rule" cannot be confused with "the port
# refuses the same assert upstream refuses". Unit `NONSHAPE`. Imports `graphcmp.bend`
# for the RENDERER, so every row below is the differ's own text and not mine.
#
# The upstream fact being tested is `tinygrad/uop/ops.py:370-372`:
#
#   case Ops.CUSTOM | Ops.CUSTOMI:
#     if self.dtype is dtypes.void: return None
#     input_shapes = [x._shape for x in self.src if x._shape is not None]
#     return _broadcast_shape(*input_shapes) if input_shapes else None
#
# MEASURED on CPython (`.agents/slop/noneshape/pyarg-run0.txt` §E), because the two
# `None`s on those three lines are DIFFERENT PROOFS of the same conclusion and the port
# has to reproduce both:
#
#   dtype void,        0 srcs   -> _shape = None     shape RAISES at ops.py:455
#   dtype uint32,      0 srcs   -> _shape = None     shape RAISES at ops.py:455
#   dtype uint32, 1 shaped src  -> _shape = (2,)     the broadcast
#   dtype void,   1 shaped src  -> _shape = None     the `if void` line WINS
#   dtype uint32, shapeless+shaped src -> (2,)       the FILTER, not the assert
#
# So `None` here always means "NO SHAPE", never "no answer", and the differ's faithful
# spelling of it is `R` (`graphcmp.bend`'s `shape_str`: `Some{None{}}` -> `R`, outer
# `None` -> `?`). `fold.bend:2296-2297` answered the OUTER `None` -- the port-only state
# "the fold produced no `Derived`" -- which is the conflation.
#
# Q1  AND over two SHAPED CONSTs. The control: if this settles, the port HAS an `AND`
#     rule and the pattern IR's `?` is the port correctly refusing upstream's assert at
#     ops.py:444. (fold.bend:2265)
# Q2  CUSTOMI, void, no srcs        -- ops.py:371 `if void: return None`. Expect 4:void 1:R
# Q3  CUSTOM,  void, no srcs        -- the same line.             Expect 4:void 1:R
# Q4  PYLITERAL, no srcs            -- ops.py:375 `return None`, already `late()`.
# Q5  CUSTOM, u32, NO srcs         -- ops.py:372 `if input_shapes else None`. Expect 5:uint32 1:R
# Q6  CUSTOM, u32, one SHAPED src   -- ops.py:372 `_broadcast_shape`.     Expect 5:uint32 2:(...)
# Q7  CUSTOM, u32, a SHAPELESS src first, then a shaped one
#     -- ops.py:372's FILTER. `all_shapes` would REFUSE this; upstream drops the
#     shapeless one and broadcasts the rest. Expect 5:uint32 2:(...)
# Q8  CUSTOM, VOID, one shaped src -- ops.py:371's `if void` runs FIRST, so the srcs
#     are never read. Expect 4:void 1:R, NOT a broadcast. This is the row that
#     separates "void is checked first" from "void is checked last".
import ./../graphcmp.bend as GC
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/helpers.bend as H

# a src with the shape `(2,)`. Upstream's `UOp.const((4,3))` is a STACK of two CONSTs,
# so `_shape` is `(2,)`; the port has no `UOp.stack`, and `param_ds.shape` answers a
# PARAM's `arg.size` as `(size,)` (fold.bend's `param_shape.size`), so the same `(2,)` is
# reachable with the port's own constructor. Q6/Q7/Q8 need a src `all_shapes` ACCEPTS,
# and Q7 needs one it REFUSES.
def two() -> O.Found:
  pa : O.ParamArg = O.ParamArg{1, S.single(), Some{2}, None{}, None{}, None{}, S.AGlobal{},
    None{}, False{}, None{}, None{}, False{}, None{}}
  O.UOp.new(O.Arena.empty(), O.OpsPARAM{}, Nil{}, O.AParam{pa}, O.TNone{})

# Q1: AND over two SHAPED CONSTs.
def q1_and() -> O.Found:
  +ar = O.Arena.empty()
  +c1 = O.UOp.const(ar, O.CInt{H.i64_of_i32(1)})
  +c2 = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(2)})
  O.UOp.new(O.Found.ar(c2), O.OpsAND{}, [O.Found.i(c1), O.Found.i(c2)], O.ANone{}, O.TNone{})

def q2_customi() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsCUSTOMI{}, Nil{}, O.AInk{"uop", S.void()}, O.TNone{})

def q3_custom() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsCUSTOM{}, Nil{}, O.AInk{"{0}.op is {1}", S.void()}, O.TNone{})

def q4_pylit() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsPYLITERAL{}, Nil{},
    # A bare `Ops` is what `upat.py:26` builds (`arg=self.op[0]`). `Arg` has no
    # unpaired-`Op` variant, so the closest arm is taken here and `argstr` prints it
    # under REDUCE's prefix -- see ns-arg.md, this is NOT a port answer.
    O.AReduce{O.OpsADD{}, 0}, O.TNone{})

def q5_u32_nosrc() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsCUSTOM{}, Nil{}, O.AInk{"tu0", S.uint32()}, O.TNone{})

def q6_u32_shaped() -> O.Found:
  +st = two()
  O.UOp.new(O.Found.ar(st), O.OpsCUSTOM{}, [O.Found.i(st)], O.AInk{"tu0", S.uint32()}, O.TNone{})

def q7_u32_mixed() -> O.Found:
  +st = two()
  +ci = O.UOp.new(O.Found.ar(st), O.OpsCUSTOMI{}, Nil{}, O.AInk{"y", S.void()}, O.TNone{})
  O.UOp.new(O.Found.ar(ci), O.OpsCUSTOM{}, [O.Found.i(ci), O.Found.i(st)],
    O.AInk{"tu0", S.uint32()}, O.TNone{})

def q8_void_shaped() -> O.Found:
  +st = two()
  O.UOp.new(O.Found.ar(st), O.OpsCUSTOM{}, [O.Found.i(st)], O.AInk{"tu0", S.void()}, O.TNone{})

def show(name: String, +f: O.Found) -> IO(Unit):
  do IO<Unit>:
    +x : F.Folded <- IO.pure(F.Folded, F.folded(O.Found.ar(f)))
    h : Unit <- IO.print(String.concat(["# ", name, " nodes=",
      U32.show(O.Arena.next(O.Found.ar(f))), " settled=",
      Bool.show(F.Kahn.settled(F.Folded.ar(x), F.Folded.t(x)))]))
    GC.rows.of(F.Folded.ar(x), F.Folded.t(x), f)

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- show("Q1 AND over two SHAPED srcs   (the control)", q1_and())
    b : Unit <- show("Q2 CUSTOMI void 0src  ops.py:371", q2_customi())
    c : Unit <- show("Q3 CUSTOM  void 0src  ops.py:371", q3_custom())
    d : Unit <- show("Q4 PYLITERAL 0src      ops.py:375", q4_pylit())
    e : Unit <- show("Q5 CUSTOM  u32  0src  ops.py:372 else-None", q5_u32_nosrc())
    f : Unit <- show("Q6 CUSTOM  u32  1 shaped src ops.py:372 broadcast", q6_u32_shaped())
    g : Unit <- show("Q7 CUSTOM  u32  shapeless+shaped src -- the FILTER", q7_u32_mixed())
    h : Unit <- show("Q8 CUSTOM  VOID 1 shaped src -- void is checked FIRST", q8_void_shaped())
    IO.pure(Unit, Unit{})