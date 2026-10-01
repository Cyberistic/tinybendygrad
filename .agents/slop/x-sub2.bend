import Base
import ../../tinybendygrad/uop/ops.bend as O

type Uop is Data:
  Uop{op: O.Op, a: U32, b: U32}

# 1. a shared list used four times in four statements, with and without +
def w(ws: List<&2, String>, i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, ws, i), "-")

def four2(+ws: List<&2, String>) -> String:
  String.concat([w(ws, 0n), w(ws, 1n), w(ws, 2n), w(ws, 3n)])

# 2. match on a FIELD of a parameter
def kind.go(op: O.Op) -> String:
  match op:
    case O.OpsADD{}: "add"
    case O.OpsMUL{}: "mul"
    case _: "other"

# 3. Maybe<&2, String> as a Data field, and a String field
type Boxed is Data:
  Boxed{m: Maybe<&2, String>, s: String, n: U32}

# 4. String.lines and a shared String
def heads(s: String) -> String:
  String.concat([w(String.lines(s), 0n), "|", w(String.lines(s), 1n)])

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print(four2(["0: ADD", "int", "-", "1 2"]))
    b : Unit <- IO.print(kind.go(O.OpsMUL{}))
    c : Unit <- IO.print(heads("one\ntwo\nthree"))
    return Unit{}