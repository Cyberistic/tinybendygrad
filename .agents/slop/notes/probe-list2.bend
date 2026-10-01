import Base

type T is Data:
  T{n: U32}

def T.n(x: T) -> U32:
  match x:
    case T{n}: n

def at(xs: List<&2, T>, n: Nat) -> U32:
  T.n(Maybe.default(&2, T, List.get(&2, T, xs, n), T{9}))

def d(+xs: List<&2, T>) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["len=", Nat.show(List.length(&2, T, xs)),
                           " [", U32.show(at(xs, 0n)), ",", U32.show(at(xs, 1n)),
                           ",", U32.show(at(xs, 2n)), "]"]))

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- d([T{1}, T{2}, T{3}])
    _ : Unit <- d(List.reverse(&2, T, [T{1}, T{2}, T{3}]))
    _ : Unit <- d(List.append(&2, T, List.append(&2, T, [T{1}], [T{2}]), [T{3}]))
    _ : Unit <- d(List.reverse(&2, T, List.append(&2, T, List.append(&2, T, [T{1}], [T{2}]), [T{3}])))
    IO.print("")
