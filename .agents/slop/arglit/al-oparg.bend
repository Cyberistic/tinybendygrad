# ===========================================================================
# al-oparg.bend -- `ns-oparg.bend` AGAIN, NOW THAT `Arg` HAS A CONSTRUCTOR FOR A
# BARE `Op`.  Unit `ARGLIT`.  THE COMPILE IS THE OUTPUT, BOTH TIMES.
#
# Upstream's PYLITERAL literal is `self.op[0]` -- a single `Ops` member
# (`tinygrad/uop/upat.py:26`). `graphcmp.py` renders it as its own atom,
# `ATOMS["ops"] + name`, MEASURED `OADD` on CPython at `al-oparg-run0.txt` sec A.
#
# `noneshape/ns-oparg.bend` passed `O.OpsADD{}` where an `O.Arg` was wanted and
# `bend` named the hole (`expected : O.Arg / observed : O.Op`, sec A of that run).
# That file is a DIFFERENT unit's and is LEFT ALONE: it still fails, and it should,
# because its text says a constructor does not exist and one now does. This file is
# the same probe with the constructor spelled, so the two runs are a PAIR and a
# reader can see the type went from a hole to a value.
#
# WHAT MAKES `AOpLit` THE RIGHT SHAPE RATHER THAN A STRING: the port's `AReduce` and
# `AAllred` both hold an `Op` and BOTH PAIR it, so the only two candidates were
# `AReduce{op, 0}` -- which `argstr` prints as `rd(OADD,i0)`, a REDUCE's text on a node
# that is not a REDUCE -- and `AAllred`, which needs a `dev` this node has none of.
# A paired constructor is a LYING answer, so the fix is a THIRD constructor and not a
# choice between the existing two. `frozenset` literals (`upat.py:25,36,43`) are
# deliberately NOT covered: three element types under one Python type, see NONSHAPE.md.
import ./../../../tinybendygrad/uop/ops.bend as O

def main() -> IO(Unit):
  do IO<Unit>:
    u : O.Found <- IO.pure(O.Found, O.UOp.new(O.Arena.empty(), O.OpsPYLITERAL{}, Nil{},
      # `arg=Ops.ADD` upstream (`upat.py:26`). `AOpLit` is the unpaired `Op`.
      O.AOpLit{O.OpsADD{}}, O.TNone{}))
    IO.pure(Unit, Unit{})
