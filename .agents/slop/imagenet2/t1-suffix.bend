# T1 -- does Bend's termination checker accept a self-call whose argument is a
# runtime-computed SUFFIX of the parameter's list?  The JSON parser's shape needs
# exactly this: parse a value, return the rest.
import Base

def drop1(cs: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}: Nil{}
    case h <> t: t

def go(cs: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}: Nil{}
    case h <> t:
      r = drop1(cs)
      go(r)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(U32.to_nat(List.length(&1, U32, go([1, 2, 3])))))
    IO.print("")
