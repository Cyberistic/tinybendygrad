import Base
import ../../tinybendygrad/runtime/executor.bend as X
import ../../tinybendygrad/LAWS/spec.bend as S
import ../../tinybendygrad/uop/ops.bend as O

def say(s: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(s), _ => IO.pure(Unit, Unit{}))

def text(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{+t}: t
    case Fail{_}: ""

def blank() -> X.Args: X.Args{"", 1, 1, 1, Nil{}, True{}}

def nm(+e: X.Elem) -> String:
  String.concat([X.elemname(e), " dt=", U32.show(S.Dt.itemsize(X.Elem.dt(e)))])

def trace(+k: Nat, +p: X.Prog) -> IO(Unit):
  match k:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+j:
      +u = X.Uop.at(X.Prog.us(p), X.Prog.pc(p))
      s = String.concat([U32.show(X.Prog.pc(p)), " ", X.opname.of(u),
        " slot=", U32.show(X.Uop.slot(u)), " nsrc=", U32.show(X.Uop.nsrc(u)),
        " s0=", nm(X.Prog.src(p, u, 0n)),
        " s1=", nm(X.Prog.src(p, u, 1n))])
      IO.bind(Unit, Unit, say(s), _ => trace(j, X.Prog.step(p)))

def go(ld: Maybe<&2, X.Load>) -> IO(Unit):
  match ld:
    case Some{+l}: trace(40n, X.Prog.of(blank(), l))
    case None{}: say("REFUSED")

def path(m: Maybe<&2, X.Args>) -> String:
  match m:
    case Some{+a}: X.Args.path(a)
    case None{}: ""

def after(pr: (File & Result<&1, &1, U32 & String, String>)) -> IO(Unit):
  (f, r) = pr
  IO.bind(Unit, Unit, File.close(f), _ => go(X.Prog.parse(text(r))))

def main() -> IO(Unit):
  do IO<Unit>:
    av : List<String> <- IO.args()
    IO.bind(File, Unit, IO.try(File, File.open(path(X.Args.of(av)), "r")),
      f => IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(f, 1073741824),
        pr => after(pr)))
