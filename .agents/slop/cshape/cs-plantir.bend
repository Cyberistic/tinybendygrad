# ===========================================================================
# cs-plantir.bend -- FOUR SEPARATE QUESTIONS ABOUT THE PORT SIDE OF THE PATTERN-COMPILER
# IR, EACH ITS OWN GRAPH, so that ONE unsettled node cannot be mistaken for "the port has
# no rule" and vice versa. Unit `CSHAPE`. Imports `graphcmp.bend` for the RENDERER, so
# every row below is the differ's own text.
#
# The py side's measurement that these four answer (`.agents/slop/cshape/rows-run0.txt`):
#   `_get_clause(UPat(Ops.ADD), CUSTOMI('uop'))` renders, once `cshape` catches
#   AssertionError, as
#     CUSTOMI 4:void 1:R ... n(suop,Dvoid)
#     PYLITERAL 4:void 1:R ... OADD
#     CUSTOM 4:void 1:R ... n(s{0}.op is {1},Dvoid)
#     AND 4:void 1:R ... N
#   and the port renders those four nodes as `1:? 1:?` on all but PYLITERAL.
#
# Q1  AND over two SHAPED srcs. If this settles, the port HAS an AND rule and the `?` on
#     the pattern-IR AND is the port correctly refusing upstream's assert. If it does not,
#     the port has no AND rule at all and the two are one defect.
# Q2  CUSTOMI with NO srcs -- upstream ops.py:370-371 `if self.dtype is dtypes.void:
#     return None`, a REAL `_shape` of None. Does the port answer `(void, None)` (which
#     renders `4:void 1:R`, the same letters PYLITERAL gets from `late()`) or `None{}`
#     (which renders `1:? 1:?`)? THIS IS THE WHOLE QUESTION, and it has nothing to do
#     with the src shape: `all_shapes` is not reached.
# Q3  CUSTOM with NO srcs, same question against ops.py:370-371.
# Q4  PYLITERAL with no srcs -- `late()` is `Some{DtShape{S.void(), None{}}}` and it is
#     the ONE matcher-IR op that settles. The control for Q2/Q3: three ops, one upstream
#     rule (`return None`), two port answers.
import ./../graphcmp.bend as GC
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/helpers.bend as H

# Q1: AND over two SHAPED CONSTs. `O.UOp.const` gives a real weakint CONST with shape `()`,
# so the Broadcastable arm's `all_shapes` is satisfied and nothing else varies.
def q1_and() -> O.Found:
  +ar = O.Arena.empty()
  +c1 = O.UOp.const(ar, O.CInt{H.i64_of_i32(1)})
  +c2 = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(2)})
  O.UOp.new(O.Found.ar(c2), O.OpsAND{}, [O.Found.i(c1), O.Found.i(c2)], O.ANone{}, O.TNone{})

# Q2: a CUSTOMI with no srcs at all. Upstream ops.py:370-371 answers `_shape = None`
# because its dtype is void, so `.shape` raises at ops.py:455 and the differ's faithful
# spelling is `R`. The port's ladder arm is `None{}` (fold.bend:2297).
def q2_customi() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsCUSTOMI{}, Nil{}, O.AInk{"uop", S.void()}, O.TNone{})

# Q3: a CUSTOM with no srcs. Same upstream arm (ops.py:370-372 covers both), same
# question, and fold.bend:2296 is the arm.
def q3_custom() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsCUSTOM{}, Nil{}, O.AInk{"{0}.op is {1}", S.void()}, O.TNone{})

# Q4: PYLITERAL, no srcs. The control. Same upstream fact as Q2 and Q3 (`return None`),
# and the port's arm is `late()`.
def q4_pylit() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsPYLITERAL{}, Nil{}, O.ATuple{[0]}, O.TNone{})

def show(name: String, +f: O.Found) -> IO(Unit):
  do IO<Unit>:
    +x : F.Folded <- IO.pure(F.Folded, F.folded(O.Found.ar(f)))
    h : Unit <- IO.print(String.concat(["# ", name, " nodes=",
      U32.show(O.Arena.next(O.Found.ar(f))), " settled=",
      Bool.show(F.Kahn.settled(F.Folded.ar(x), F.Folded.t(x)))]))
    GC.rows.of(F.Folded.ar(x), F.Folded.t(x), f)

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- show("Q1 AND over two SHAPED srcs", q1_and())
    b : Unit <- show("Q2 CUSTOMI, no srcs (upstream ops.py:371 `return None`)", q2_customi())
    c : Unit <- show("Q3 CUSTOM, no srcs  (upstream ops.py:371 `return None`)", q3_custom())
    d : Unit <- show("Q4 PYLITERAL, no srcs (upstream ops.py:375 `return None`)", q4_pylit())
    IO.pure(Unit, Unit{})
