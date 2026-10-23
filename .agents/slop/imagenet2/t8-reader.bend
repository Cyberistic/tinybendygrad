# T8 -- what state does the reader END in, and how many entries?
import Base
import ../../../tinybendygrad/extra/datasets/imagenet.bend as I

def stname(s: I.St) -> String:
  match s:
    case I.Want{tok, next}: "Want"
    case I.SOpen{}: "SOpen"
    case I.SNameQ{index}: "SNameQ"
    case I.SScalar{index, name}: "SScalar"
    case I.SSep{}: "SSep"
    case I.SKStr{acc}: "SKStr"
    case I.SNStr{acc, index}: "SNStr"
    case I.SSStr{acc, index, name}: "SSStr"
    case I.SNum{acc, index, name}: "SNum"
    case I.SNumEnd{acc, index, name}: "SNumEnd"
    case I.SClose{index, name}: "SClose"
    case I.SDone{}: "SDone"
    case I.SFail{why}: "SFail"

def why(s: I.St) -> String:
  match s:
    case I.SFail{why}: why
    case _: ""

def show.go(+s: I.St, es: List<&2, I.Entry>) -> String:
  String.concat([stname(s), " n=", Nat.show(List.length(&2, I.Entry, es)), " why=", why(s)])

def show(m: (I.St & List<&2, I.Entry>)) -> String:
  (s, es) = m
  show.go(s, es)

def main() -> IO(Unit):
  do IO<Unit>:
    a : (I.St & List<&2, I.Entry>) <- IO.pure((I.St & List<&2, I.Entry>), I.ci.read("{\"0\": [\"tench\", 0]}"))
    IO.print(show(a))
    b : (I.St & List<&2, I.Entry>) <- IO.pure((I.St & List<&2, I.Entry>), I.ci.read("{\"0\": [\"tench\", 0], \"1\": [\"goldfish\", 1]}"))
    IO.print(show(b))
    IO.print("")
