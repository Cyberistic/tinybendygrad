# ===========================================================================
# ns-patir.bend -- THE PATTERN-COMPILER IR ALONE, so the two-sided verdict compares
# ONE graph against ONE graph. Unit `NONSHAPE`. Imports `graphcmp.bend` for the RENDERER,
# so every row is the differ's own text.
#
# The graph is upstream's own construction, `_get_clause(UPat(Ops.ADD), UOp(Ops.CUSTOMI,
# arg=("uop", dtypes.void)))` at `tinygrad/uop/upat.py:66` -- 4 nodes in toposort order
# CUSTOMI PYLITERAL CUSTOM AND. Never hand-written.
#
# The last node is EXPECTED TO DISAGREE and the reason is upstream's, not the port's:
# `_shape` on an `AND` over shapeless srcs hits `assert len(self.src) > 0 and all(x is
# not None for x in input_shapes)` at ops.py:444 and the differ's widening prints `R`,
# while the port's `all_shapes` REFUSES for exactly the same reason and prints `?`. `R`
# would be a claim upstream does not make -- upstream says "this graph is invalid" -- so
# this unit does not widen it away and the refusal is the result.
#
# WHAT THIS FILE IS ON TRIAL FOR is the first three nodes' dtype and shape columns, which
# are the thing `fold.bend`'s CUSTOM/CUSTOMI arm was fixed for. The `arg` column is a
# DIFFER normal-form question and is not settled by anything in fold.bend.
import ./../graphcmp.bend as GC
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/LAWS/spec.bend as S

def g_patir() -> O.Found:
  +ci = O.UOp.new(O.Arena.empty(), O.OpsCUSTOMI{}, Nil{},
    # `arg=('uop', dtypes.void)` upstream. `AInk` IS the `(str, DType)` pair
    # (uop/spec.bend:1043-1047).
    O.AInk{"uop", S.void()}, O.TNone{})
  +pl = O.UOp.new(O.Found.ar(ci), O.OpsPYLITERAL{}, Nil{},
    # `arg=Ops.ADD` upstream -- a BARE `Ops`. `Arg` has no unpaired-`Op` variant, so the
    # closest constructor is taken and `argstr` prints it under REDUCE's prefix. THIS IS
    # NOT A PORT ANSWER; see .agents/slop/NONSHAPE.md sec 3.
    O.AReduce{O.OpsADD{}, 0}, O.TNone{})
  +cu = O.UOp.new(O.Found.ar(pl), O.OpsCUSTOM{}, [O.Found.i(ci), O.Found.i(pl)],
    O.AInk{"{0}.op is {1}", S.void()}, O.TNone{})
  O.UOp.new(O.Found.ar(cu), O.OpsAND{}, [O.Found.i(cu)], O.ANone{}, O.TNone{})

def main() -> IO(Unit):
  do IO<Unit>:
    +f : O.Found <- IO.pure(O.Found, g_patir())
    +x : F.Folded <- IO.pure(F.Folded, F.folded(O.Found.ar(f)))
    h : Unit <- IO.print(String.concat(["# root=", U32.show(O.Found.i(f)), " nodes=",
      U32.show(O.Arena.next(O.Found.ar(f))), " settled=",
      Bool.show(F.Kahn.settled(F.Folded.ar(x), F.Folded.t(x)))]))
    GC.rows.of(F.Folded.ar(x), F.Folded.t(x), f)