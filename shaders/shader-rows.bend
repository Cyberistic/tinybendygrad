# shaders/shader-rows.bend -- THE GRAPH AS ROWS, one line per node.
#
# THE PRESENTATION HALF, and it lives here so that `shader.bend` stays PURE: a compile
# failure in the runner or in the C toolchain must not be able to break the gate that
# compares graphs. `shader.bend` builds, this file prints, `shader-run.bend` executes.
#
# THE ROW FORMAT is a preorder unfolding:
#
#   <depth> <op> <dtype> <arg>
#
# DEPTH AND NOT AN INDEX, because the port's ids are ARENA INDICES and CPython's are
# creation-order ids: the same graph is two different numberings, so a diff over ids would
# be a diff of conventions. A DAG is printed as its UNFOLDING -- a shared node appears once
# per path -- which is deterministic on both sides and needs no visited set.
#
# A `?` IN THE ARG COLUMN IS A REFUSAL AND NOT A VALUE: it means an `Arg` variant this
# fixture has no rendering for. `shader-gate.py` fails on it rather than letting two unknowns
# agree, because two unknowns agreeing is the "0 disagreements over 0 comparisons" defect.

import ../tinybendygrad/uop/ops.bend as O
import ../tinybendygrad/uop/fold.bend as F
import ../tinybendygrad/uop/render.bend as R
import ../tinybendygrad/LAWS/spec.bend as S
import ./shader.bend as SH

def sh_dt(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: R.dt_repr(d)
    case None{}: "?"

def sh_arg(a: O.Arg) -> String:
  match a:
    case O.ANone{}: "-"
    case O.APy{v}: R.const_repr(v)
    case O.ADt{d}: R.dt_repr(d)
    case O.AParam{p}: String.concat(["P", U32.show(O.ParamArg.slot(p))])
    case _: "?"

def sh_row(+ar: O.Arena, +tb: F.Table, +k: U32, +d: U32) -> String:
  String.concat([U32.show(d), " ", O.Ops.name(O.Arena.op(ar, k)), " ",
    sh_dt(F.UOp.dtype(ar, tb, k)), " ", sh_arg(O.Arena.arg(ar, k))])

# THE WALK. `fuel` is the arena's node count, which bounds the unfolding because every
# printed node consumes one; the `case 0n` arm is unreachable on a well-formed graph and is
# what makes the walk total, not a limit on it.
#
# IT RECURSES ON THE SOURCE LIST and not on a node, because bend checks defs in FILE ORDER
# and so a mutually recursive pair (`walk` calls `srcs`, `srcs` calls `walk`) does not
# compile. One def over a list, with the node's own children pressed in front of its
# siblings, IS the preorder walk: children, then siblings, at the same depth.
def sh_walk(fuel: Nat, +ar: O.Arena, +tb: F.Table, ss: List<&2, U32>, +d: U32) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+ +p:
      match ss:
        case Nil{}: IO.pure(Unit, Unit{})
        case +s <> rest:
          do IO<Unit>:
            h : Unit <- IO.print(sh_row(ar, tb, s, d))
            c : Unit <- sh_walk(p, ar, tb, O.Arena.srcs(ar, s), U32.add(d, 1))
            r : Unit <- sh_walk(p, ar, tb, rest, d)
            IO.pure(Unit, r)

def main() -> IO(Unit):
  do IO<Unit>:
    +f : O.Found <- IO.pure(O.Found, SH.sh_graph())
    +x : F.Folded <- IO.pure(F.Folded, F.folded(O.Found.ar(f)))
    h : Unit <- IO.print("# shader=aa-circle")
    r : Unit <- sh_walk(U32.to_nat(O.Arena.next(O.Found.ar(f))), F.Folded.ar(x),
      F.Folded.t(x), [O.Found.i(f)], 0)
    IO.pure(Unit, r)
