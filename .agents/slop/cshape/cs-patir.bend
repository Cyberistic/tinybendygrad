# ===========================================================================
# cs-patir.bend -- THE PORT SIDE OF THE PATTERN-COMPILER IR, BUILT WITH THE PORT'S OWN
# CONSTRUCTORS. Unit `CSHAPE`. Read-only with respect to `graphcmp.bend`: it IMPORTS the
# differ's own renderer, so the rows below are the DIFFER's rows and not mine, and any
# disagreement is a disagreement between the port and CPython rather than between the port
# and a hand-built fixture. (`g_flip` re-implemented `UOp.group` wrongly while ops.bend:2486
# had it right, and the port got blamed.)
#
# The graph is upstream's: `_get_clause(UPat(Ops.ADD), UOp(Ops.CUSTOMI, arg=("uop",
# dtypes.void)))` at tinygrad/uop/upat.py:66, measured on the py side to be 4 nodes in
# toposort order CUSTOMI PYLITERAL CUSTOM AND with
#   CUSTOMI    nsrc=0 arg=('uop', dtypes.void)          dtype=void
#   PYLITERAL  nsrc=0 arg=Ops.ADD                      dtype=void
#   CUSTOM     nsrc=2 arg=('{0}.op is {1}', dtypes.void) dtype=void
#   AND        nsrc=1 arg=None                         dtype=void
#
# WHAT IS ASKED, and it is one question per column:
#   * does the port's `Arg` taxonomy have a home for `(String, Dt)` and for a bare `Op`?
#     The four nodes are built with the CLOSEST arm each has, and `argstr`'s own answer is
#     printed, so the answer is the port's and not mine.
#   * what does `shape_str` say for the AND, whose two upstream readings disagree:
#     `_shape` ASSERTS (ops.py:444, "None input shape not supported for Ops.AND") rather
#     than answering None, so the port's `all_shapes` (fold.bend:875) refuses and the node
#     has no `Derived` at all -> `?`, which is a PORT-ONLY state.
import ./../graphcmp.bend as GC
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/LAWS/spec.bend as S

# ONE arena, four nodes, LAZY, exactly the toposort order the py side printed. Every node
# is `O.UOp.new` -- the port's own node constructor, the same one `g_special`/`g_cast` use.
def g_patir() -> O.Found:
  +ci = O.UOp.new(O.Arena.empty(), O.OpsCUSTOMI{}, Nil{},
    # `arg=('uop', dtypes.void)` upstream. `Arg`'s taxonomy (ops.bend:1050-1070) has NO
    # `(String, Dt)` pair: `AStr` is a String ALONE and `AInk{ins, dt}` is the pair but
    # under INS's spelling. `AInk` is the pair, so it is what carries the two fields --
    # the question is whether `argstr` can RENDER it as a plain tuple.
    O.AInk{"uop", S.void()}, O.TNone{})
  +pl = O.UOp.new(O.Found.ar(ci), O.OpsPYLITERAL{}, Nil{},
    # `arg=Ops.ADD` upstream -- a BARE `Ops`. `Arg` has no bare-`Op` variant: `AReduce` is
    # the only one holding an `Op` and it holds it PAIRED with a count.
    O.AReduce{O.OpsADD{}, 0}, O.TNone{})
  +cu = O.UOp.new(O.Found.ar(pl), O.OpsCUSTOM{}, [O.Found.i(ci), O.Found.i(pl)],
    # `arg=('{0}.op is {1}', dtypes.void)` -- the same pair again.
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
