import Base

def spin(n: Nat, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p: spin(p, U32.add(acc, 1))

def put(xs: List<&2, U32>, i: Nat, v: U32) -> List<&2, U32>:
  List.set(&2, U32, xs, i, v)

def fill(n: Nat, +acc: U32) -> List<&2, U32>:
  match n:
    case 0n: Nil{}
    case 1n+p: U32.add(acc, 1) <> fill(p, U32.add(acc, 1))

def rd(+xs: List<&2, U32>, i: Nat) -> Maybe<&2, U32>: List.get(&2, U32, xs, i)

def walk.go(+xs: List<&2, U32>, m: Maybe<&2, U32>, +i: Nat, k: U32) -> List<&2, U32>:
  match m:
    case Some{v}: put(xs, i, U32.add(v, k))
    case None{}: xs

def walk(+xs: List<&2, U32>, +i: Nat, k: U32) -> List<&2, U32>:
  walk.go(xs, rd(xs, i), i, k)

def deep(n: Nat, xs: List<&2, U32>, +k: U32) -> List<&2, U32>:
  match n:
    case 0n: xs
    case 1n+p: deep(p, walk(xs, U32.to_nat(k), k), k)

def showm(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{v}: U32.show(v)
    case None{}: "none"

def bench() -> String:
  +xs = deep(200000n, put(fill(200n, 0), 5n, 42), 7)
  String.concat(["at5=", showm(rd(xs, 5n)), " at199=", showm(rd(xs, 199n))])

def main() -> IO(Unit):
  do IO<Unit>:
    s : Unit <- IO.print(String.concat(["spin 1000000 = ", U32.show(spin(1000000n, 0))]))
    t : Unit <- IO.print(bench())
    return Unit{}