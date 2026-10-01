import Base
import ../../tinybendygrad/runtime/executor.bend as X
import ../../tinybendygrad/uop/ops.bend as O
import ../../tinybendygrad/LAWS/spec.bend as S

def say(s: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(s), _ => IO.pure(Unit, Unit{}))

def text(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{+t}: t
    case Fail{_}: ""

def blank() -> X.Args: X.Args{"", 1, 1, 1, Nil{}, True{}}

def report(+p: X.Prog) -> IO(Unit):
  +u = X.Uop.at(X.Prog.us(p), X.Prog.pc(p))
  ptr = X.Prog.src(p, u, 0n)
  +f = X.Prog.buf(p, u)
  msg = String.concat([
    "pc=", U32.show(X.Prog.pc(p)),
    " op=", X.opname.of(u),
    " cur=", U32.show(X.Prog.cur(p, u)), " trip=", U32.show(X.Prog.trip(p, u)),
    " loop=", U32.show(X.Prog.loop(p, X.Prog.pc(p))),
    " slot=", U32.show(X.Uop.slot(u)),
    " run=", U32.show(X.Uop.run(u)),
    " nvs=", U32.show(U32.from_nat(List.length(&2, X.Elem, X.Prog.vs(p)))),
    " a0=", U32.show(X.Elem.bits(X.Val.at(X.Prog.vs(p), 0))),
    " a12=", U32.show(X.Elem.bits(X.Val.at(X.Prog.vs(p), 12))),
    " a13=", U32.show(X.Elem.bits(X.Val.at(X.Prog.vs(p), 13))),
    " a14=", U32.show(X.Elem.bits(X.Val.at(X.Prog.vs(p), 14))),
    " a15=", U32.show(X.Elem.bits(X.Val.at(X.Prog.vs(p), 15))),
    " src1=", U32.show(X.Uop.src1(u)),
    " ptr=", X.elemname(ptr),
    " bufb=", U32.show(X.Buf.base(f)), " w=", U32.show(X.Buf.w(f)), " e=", U32.show(X.Buf.e(f)),
    " store.i=", U32.show(X.Prog.store.i(p, u, 0)),
    " addr=", U32.show(X.Prog.store.addr(p, u, 0)),
    " open=", X.bs(X.Prog.store.open(p, u, 0)),
    " lane0=", U32.show(X.Prog.store.v(p, u, 0))])
  IO.bind(Unit, Unit, say(msg), _ => IO.pure(Unit, Unit{}))

# ONE fold: step until the countdown runs out. `Prog.step` is rebuilt, so the
# countdown comes first in the self-call (MEASURED).
# report every pc, so the walk can be read
def seek(+steps: Nat, +p: X.Prog) -> IO(Unit):
  match steps:
    case 0n: report(p)
    case 1n+j: IO.bind(Unit, Unit, say(String.concat([U32.show(X.Prog.pc(p)), ":",
      X.opname.of(X.Uop.at(X.Prog.us(p), X.Prog.pc(p)))])),
      _ => seek(j, X.Prog.step(p)))

def show_nat(k: Nat) -> String:
  X.U32.show(X.Prog.pc(X.Prog.of(X.Args{"", 1, 1, 1, Nil{}, True{}}, X.Prog.dummy())))  -- noop

def one(+k: Nat, p: X.Prog) -> IO(Unit):
  +r = X.run(k, p)
  IO.bind(Unit, Unit, say(String.concat(["fuel=", X.show_nat(k), " bad=", X.bs(X.Prog.bad(r)),
    " dead=", X.bs(X.Prog.dead(r)), " pc=", U32.show(X.Prog.pc(r))])),
    _ => IO.pure(Unit, Unit{}))

def go(ld: Maybe<&2, X.Load>) -> IO(Unit):
  match ld:
    case Some{+l}:
      +pr = X.Prog.of(blank(), l)
      one(1n, pr)
    case None{}: say("REFUSED")

def after(pr: (File & Result<&1, &1, U32 & String, String>)) -> IO(Unit):
  (f, r) = pr
  IO.bind(Unit, Unit, File.close(f), _ => go(X.Prog.parse(text(r))))

def path(m: Maybe<&2, X.Args>) -> String:
  match m:
    case Some{+a}: X.Args.path(a)
    case None{}: ""

def main() -> IO(Unit):
  do IO<Unit>:
    av : List<String> <- IO.args()
    IO.bind(File, Unit, IO.try(File, File.open(path(X.Args.of(av)), "r")),
      f => IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(f, 1073741824), after))