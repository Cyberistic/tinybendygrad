# ===========================================================================
# ns-oparg.bend -- DOES `Arg` HAVE A CONSTRUCTOR FOR A BARE `Op`?  THIS FILE DOES NOT
# COMPILE, AND THAT IS ITS OUTPUT.  Unit `NONSHAPE`.
#
# Upstream's PYLITERAL literal is `self.op[0]` -- a single `Ops` member
# (`tinygrad/uop/upat.py:26`). `graphcmp.py` renders it as its own atom,
# `ATOMS["ops"] + name`, measured `OADD` (`.agents/slop/noneshape/pyarg-run0.txt` sec B).
#
# The port's `O.Arg` (uop/ops.bend:1054) has NINETEEN constructors and exactly TWO of them
# hold an `Op` -- `AReduce{rop, num_axes}` and `AAllred{rop, dev}` -- and BOTH pair it
# with something. So `UOp(Ops.PYLITERAL, arg=<a bare Ops>)` cannot be spelled, and the
# cshape probe spelled it `AReduce{OpsADD, 0}`, which `argstr` prints as `rd(OADD,i0)`:
# the differ's own text admitting a graph it could not build.
#
# THE COMPILER NAMED IT.  Recorded rather than paraphrased, because "a hole in the type"
# is a claim and this is the claim failing to typecheck:
#
#   SOME PROOFS FAIL
#   Error:
#   - expected : a declared constructor of Arg
#   - observed : O.OpsADD{}
#
# `ops.bend`'s own `Arg` block lists `tuple[int, ...]  ATuple  ... PYLITERAL arg`, and
# THAT TRANSCRIPTION IS WRONG: `tinygrad/uop/__init__.py:101` says "PYLITERAL carries a
# Python literal as an arg for CUSTOM predicates", and the four values `upat.py` builds
# are an `Ops` (:26), a `DType` (:39), a `str` (:44) and `self.arg` (:29) -- never a
# `tuple[int, ...]`. So the fix is a TYPE CHANGE, one variant, and it is in a file this
# unit does not own. See .agents/slop/NONSHAPE.md sec 3.
import ./../../../tinybendygrad/uop/ops.bend as O

def main() -> IO(Unit):
  do IO<Unit>:
    u : O.Found <- IO.pure(O.Found, O.UOp.new(O.Arena.empty(), O.OpsPYLITERAL{}, Nil{},
      # `arg=Ops.ADD` upstream. There is no `Arg` constructor that takes one `Op` alone.
      O.OpsADD{}, O.TNone{}))
    IO.pure(Unit, Unit{})