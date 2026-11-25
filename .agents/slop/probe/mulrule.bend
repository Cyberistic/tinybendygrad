# probe/mulrule.bend -- ask `gmul`, `gmul_bc` and `gr_12` each in isolation.
#
# The `grad` corpus row shows the port multiplying by a BUFFER's SHAPE child (`STACK`) where
# CPython multiplies by the BUFFER.  Each def below gets its OWN fixture arena, so a rule
# that grows the arena cannot be blamed on the one before it.
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/mixin/gradient.bend as G
import ./../../../tinybendygrad/mixin/bcast.bend as BC
import ./../../../tinybendygrad/LAWS/spec.bend as S

type Fwd is Data:
  Fwd{ar: O.Arena, m: U32, sd: U32}

def Fwd.ar(f: Fwd) -> O.Arena:
  match f:
    case Fwd{ar, m, sd}: ar

def Fwd.m(f: Fwd) -> U32:
  match f:
    case Fwd{ar, m, sd}: m

def Fwd.sd(f: Fwd) -> U32:
  match f:
    case Fwd{ar, m, sd}: sd

def leaf(+ar: O.Arena, slot: U32) -> O.Found:
  +sh = G.gnew(ar, O.OpsSTACK{}, Nil{}, O.ANone{})
  G.gnew(O.Found.ar(sh), O.OpsBUFFER{}, [O.Found.i(sh)], O.AParam{O.ParamArg.of(slot, S.single())})

def fwd() -> Fwd:
  +n0 = leaf(O.Arena.empty(), 0)
  +n1 = leaf(O.Found.ar(n0), 1)
  +n2 = leaf(O.Found.ar(n1), 2)
  +m = G.gnew(O.Found.ar(n2), O.OpsMUL{}, [O.Found.i(n0), O.Found.i(n1)], O.ANone{})
  +s = G.gnew(O.Found.ar(m), O.OpsADD{}, [O.Found.i(n0), O.Found.i(n2)], O.ANone{})
  +t = G.gnew(O.Found.ar(s), O.OpsADD{}, [O.Found.i(m), O.Found.i(s)], O.ANone{})
  +sd = G.gconst(O.Found.ar(t), G.k_fone())
  Fwd{O.Found.ar(sd), O.Found.i(m), O.Found.i(sd)}

def last(+ar: O.Arena) -> String:
  +i = U32.sub(O.Arena.next(ar), 1)
  String.concat(["node ", U32.show(i), " = ", O.Ops.name.of(O.Arena.op(ar, i)),
                 "(", U32.show(O.Arena.src(ar, i, 0)), ", ",
                 U32.show(O.Arena.src(ar, i, 1)), ")  next=", U32.show(O.Arena.next(ar))])

def t_gmul() -> IO(Unit):
  do IO<Unit>:
    +f : Fwd = fwd()
    +ar : O.Arena = Fwd.ar(f)
    a : Unit <- IO.print("the fixture: m=5 src(m,1)=3")
    +r : O.Found = G.gmul(ar, 3, 9)
    IO.print(String.concat(["gmul(3,9) -> ", last(O.Found.ar(r))]))

def t_gmul_bc() -> IO(Unit):
  do IO<Unit>:
    +f : Fwd = fwd()
    +ar : O.Arena = Fwd.ar(f)
    +r : O.Found = G.gmul_bc(ar, 3, 9)
    IO.print(String.concat(["gmul_bc(3,9) -> ", last(O.Found.ar(r)),
                            " node=", U32.show(O.Found.i(r))]))

def t_gr12() -> IO(Unit):
  do IO<Unit>:
    +f : Fwd = fwd()
    +ar : O.Arena = Fwd.ar(f)
    +m : U32 = Fwd.m(f)
    +sd : U32 = Fwd.sd(f)
    +r : G.GRes = G.gr_12(ar, sd, m)
    IO.print(String.concat(["gr_12(m=", U32.show(m), ", ctx=", U32.show(sd),
                            ") -> ", last(G.gs_ar(r)),
                            " solid=", U32.show(G.gs_solid(r))]))

def t_bcast() -> IO(Unit):
  do IO<Unit>:
    +f : Fwd = fwd()
    +ar : O.Arena = Fwd.ar(f)
    +ds : List<&2, U32> = G.gdims(ar, 9)
    a : Unit <- IO.print(String.concat(["gdims(cast 9) len=",
      U32.show(U32.from_nat(List.length(&2, U32, ds))),
      " bc_dims(buffer 3) len=",
      U32.show(U32.from_nat(List.length(&2, U32, BC.bc_dims(ar, 3))))]))
    +y : O.Found = BC.bcast(ar, 3, ds)
    IO.print(String.concat(["BC.bcast(3, ds) node=", U32.show(O.Found.i(y)),
                            " last=", last(O.Found.ar(y))]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_gmul()
    b : Unit <- t_gmul_bc()
    c : Unit <- t_gr12()
    t_bcast()
