import Base

# A microbenchmark of the ONE structural choice the executor's hot paths make:
# INDEX a List by a counter (List.get walks from the head, O(i)) versus WALK it as a cons
# (pattern match, O(1) per step).  `Prog.hex.go` and `Prog.line.go` in ops_python.bend both
# index; this measures what that costs, on the real bend compiler.
#
# usage: walkbench <n> idx|walk

def sum.idx(+n: Nat, +xs: List<&2, U32>, +i: U32, +acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p: sum.idx(p, xs, U32.add(i, 1),
      U32.add(acc, Maybe.default(&2, U32, List.get(&2, U32, xs, U32.to_nat(i)), 0)))

def sum.walk(xs: List<&2, U32>, +acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case h <> t: sum.walk(t, U32.add(acc, h))

def run.walk(+n: U32) -> IO(Unit):
  do IO<Unit>:
    xs : List<&2, U32> <- IO.pure(List<&2, U32>, List.replicate(U32, U32.to_nat(n), 1))
    IO.print(U32.show(sum.walk(xs, 0)))

def run.idx(+n: U32) -> IO(Unit):
  do IO<Unit>:
    xs : List<&2, U32> <- IO.pure(List<&2, U32>, List.replicate(U32, U32.to_nat(n), 1))
    IO.print(U32.show(sum.idx(U32.to_nat(n), xs, 0, 0)))

def run(+n: U32, walk: Bool) -> IO(Unit):
  match walk:
    case True{}: run.walk(n)
    case False{}: run.idx(n)

def go(n: String, m: String) -> IO(Unit):
  run(U32.from_nat(Maybe.default(&2, Nat, Nat.read(n), 0n)), String.eq(m, "walk"))

def dispatch(as: List<String>) -> IO(Unit):
  match as:
    case _p <> (n <> (m <> _t)): go(n, m)
    case _: IO.print("usage: walkbench <n> idx|walk")

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    dispatch(as)
