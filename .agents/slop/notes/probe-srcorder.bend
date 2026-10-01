import Base
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F

# `src_dt(k, ss)` is the fold's own positional reader: `pri` is the lattice rank, so
# int32 is 5 and weakint is 1. Which one comes back for k=0 says the order.
def row(tag: String, +ss: List<&2, F.Derived>) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([tag,
      " len=", Nat.show(List.length(&2, F.Derived, ss)),
      " dt0.pri=", U32.show(S.Dt.pri(F.src_dt(0, ss))),
      " dt1.pri=", U32.show(S.Dt.pri(F.src_dt(1, ss)))]))

def gathered(tag: String, m: Maybe<&2, List<&2, F.Derived>>) -> IO(Unit):
  match m:
    case Some{ss}: row(tag, ss)
    case None{}: IO.print(String.concat([tag, " = None"]))

def srcs_of(m: Maybe<&2, List<&2, F.Derived>>) -> IO(Unit):
  match m:
    case Some{ss}: row("after srcs  ", F.Srcs.ss(F.srcs(ss)))
    case None{}: IO.print("after srcs   = None")

def arena_line(+x: F.Folded) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["next=", U32.show(O.Arena.next(F.Folded.ar(x))), " arena src0=", U32.show(O.Arena.src(F.Folded.ar(x), 4, 0)),
                            " src1=", U32.show(O.Arena.src(F.Folded.ar(x), 4, 1))]))

def gather_line(+x: F.Folded) -> IO(Unit):
  gathered("Kahn.gather ", F.Kahn.gather(F.Folded.ar(x), 4, F.Folded.t(x)))

def after_line(+x: F.Folded) -> IO(Unit):
  srcs_of(F.Kahn.gather(F.Folded.ar(x), 4, F.Folded.t(x)))

def p22() -> F.Folded:
  F.folded(O.Found.ar(F.g_resh22()))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- arena_line(p22())
    b : Unit <- gather_line(p22())
    c : Unit <- after_line(p22())
    d : Unit <- IO.print("")
    IO.print("")