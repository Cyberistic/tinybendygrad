import Base

type P is Data:
  P{a: U32, b: U32}

# A: two-scrutinee match on (fuel, other) in a self-recursive def
def f1(xs: List<&2, U32>, ys: List<&2, U32>, acc: List<&2, P>) -> List<&2, P>:
  match xs ys:
    case Nil{} _       : acc
    case _ <> _ Nil{}  : acc
    case x <> xt y <> yt: f1(xt, yt, List.append(&2, P, acc, [P{x, y}]))

def g1(xs: List<&2, U32>, ys: List<&2, U32>) -> List<&2, P>:
  f1(xs, ys, Nil{})

# B: swap the scrutinee order
def f2(ys: List<&2, U32>, xs: List<&2, U32>, acc: List<&2, P>) -> List<&2, P>:
  match ys xs:
    case Nil{} _       : acc
    case _ <> _ Nil{}  : acc
    case y <> yt x <> xt: f2(yt, xt, List.append(&2, P, acc, [P{y, x}]))

def g2(ys: List<&2, U32>, xs: List<&2, U32>) -> List<&2, P>:
  f2(ys, xs, Nil{})

# C: match only the NON-fuel list, and drop from the fuel
def head(xs: List<&2, U32>) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, 0n), 0)

def tail(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}   : Nil{}
    case _ <> t  : t

def f3(ys: List<&2, U32>, xs: List<&2, U32>, acc: List<&2, P>, more: Bool) -> List<&2, P>:
  match ys more:
    case Nil{} _        : acc
    case _ <> _ False{} : acc
    case y <> yt True{} : f3(yt, tail(xs), List.append(&2, P, acc, [P{head(xs), y}]), more_next(xs))

def more_next(xs: List<&2, U32>) -> Bool:
  match xs:
    case _ <> _: True{}
    case _: False{}

def g3(ys: List<&2, U32>, xs: List<&2, U32>) -> List<&2, P>:
  f3(ys, xs, Nil{}, more_next(xs))

def n(xs: List<&2, P>) -> U32:
  U32.from_nat(List.length(&2, P, xs))

def t_a() -> U32: n(g1([1, 2], [3, 4]))
def t_b() -> U32: n(g2([1, 2], [3, 4]))
def t_c() -> U32: n(g3([1, 2], [3, 4]))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["a=", U32.show(t_a())]))
    IO.print(String.concat(["b=", U32.show(t_b())]))
    IO.print(String.concat(["c=", U32.show(t_c())]))
