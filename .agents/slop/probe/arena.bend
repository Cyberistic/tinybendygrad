# probe/arena.bend -- print the `grad` fixture's arena, node by node.
#
# Scratch, not a gate: it exists to answer ONE question the corpus artifacts cannot --
# whether the port's MUL rule reads its operands, or their children.  Delete it once
# the row is green.
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/mixin/gradient.bend as G
import ./../../../tinybendygrad/LAWS/spec.bend as S

def leaf(+ar: O.Arena, slot: U32) -> O.Found:
  +sh = G.gnew(ar, O.OpsSTACK{}, Nil{}, O.ANone{})
  G.gnew(O.Found.ar(sh), O.OpsBUFFER{}, [O.Found.i(sh)], O.AParam{O.ParamArg.of(slot, S.single())})

def build() -> G.CState:
  +n0 = leaf(O.Arena.empty(), 0)
  +n1 = leaf(O.Found.ar(n0), 1)
  +n2 = leaf(O.Found.ar(n1), 2)
  +m = G.gnew(O.Found.ar(n2), O.OpsMUL{}, [O.Found.i(n0), O.Found.i(n1)], O.ANone{})
  +s = G.gnew(O.Found.ar(m), O.OpsADD{}, [O.Found.i(n0), O.Found.i(n2)], O.ANone{})
  +t = G.gnew(O.Found.ar(s), O.OpsADD{}, [O.Found.i(m), O.Found.i(s)], O.ANone{})
  +sd = G.gconst(O.Found.ar(t), G.k_fone())
  G.compute_gradient(O.Found.i(t), O.Found.i(sd),
                     [O.Found.i(n0), O.Found.i(n1), O.Found.i(n2)], O.Found.ar(sd))

def row(+ar: O.Arena, +i: U32) -> String:
  String.concat([U32.show(i), " ", O.Ops.name.of(O.Arena.op(ar, i)),
                 " n=", U32.show(O.Arena.nsrc(ar, i)),
                 " s0=", U32.show(O.Arena.src(ar, i, 0)),
                 " s1=", U32.show(O.Arena.src(ar, i, 1))])

def go(+ar: O.Arena, k: Nat, +i: U32) -> IO(Unit):
  match k:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        q : Unit <- IO.print(row(ar, i))
        go(ar, p, U32.sub(i, 1))

def main() -> IO(Unit):
  +cs = build()
  +ar = G.CState.ar_of(cs)
  +n = O.Arena.next(ar)
  go(ar, U32.to_nat(n), U32.sub(n, 1))
