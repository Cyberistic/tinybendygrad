# P1..P4 -- the constructs the five movement arms need, probed before fold.bend is
# edited. Every one of these is a guess until the checker has agreed.
import Base

# P1: A THREE-SCRUTINEE match on three Maybes, with `case _ _ _` as the cover.
type P1s is Data:
  P1s{x: U32, y: U32, z: U32}

def P1s.v(r: P1s) -> Bool:
  match r:
    case P1s{+x, +y, +z}: Bool.and(U32.is_lt(x, U32.add(y, z)), U32.is_lt(y, z))

def p1(a: Maybe<&1, U32>, b: Maybe<&1, U32>, c: Maybe<&1, U32>) -> Bool:
  match a b c:
    case Some{x} Some{y} Some{z}: P1s.v(P1s{x, y, z})
    case _ _ _: False{}

# P2: a GENERIC two-Maybe join that appends, so EXPAND's `marg + ps` is one call.
def p2(m: Maybe<&2, List<&2, U32>>, n: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match m n:
    case Some{g} Some{h}: Some{List.append(&2, U32, g, h)}
    case _ _: None{}

# P3: a self-call passing TWO LIST TAILS first, so `zip`'s truncation is one walk.
type P3 is Data:
  P3{a: List<&2, U32>, b: List<&2, U32>}

def P3.a(x: P3) -> List<&2, U32>:
  match x:
    case P3{a, b}: a

def P3.b(x: P3) -> List<&2, U32>:
  match x:
    case P3{a, b}: b

def p3.go(xs: List<&2, U32>, ys: List<&2, U32>, acc: List<&2, U32>, brd: List<&2, U32>) -> P3:
  match xs ys:
    case Nil{} Nil{}      : P3{acc, brd}
    case x <> xt, y <> yt  : p3.go(xt, yt, List.append(&2, U32, acc, [x]), List.append(&2, U32, brd, [y]))
    case _ _              : P3{acc, brd}

def p3(xs: List<&2, U32>, ys: List<&2, U32>) -> P3:
  p3.go(xs, ys, Nil{}, Nil{})

# P4: a `+` list parameter read by `List.get` AND handed to the self-call.
def p4.put(d: Maybe<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match d:
    case Some{v}: List.append(&2, U32, acc, [v])
    case None{}  : acc

def p4.go(ys: List<&2, U32>, +ps: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ys:
    case Nil{}  : acc
    case y <> t : p4.go(t, ps, p4.put(List.get(&2, U32, ps, U32.to_nat(y)), acc))

# P5: `Nat` length equality, for `len(ps) == len(marg)` on PERMUTE and FLIP.
def p5(xs: List<&2, U32>, ys: List<&2, U32>) -> Bool:
  Nat.is_eq(List.length(&2, U32, xs), List.length(&2, U32, ys))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["p1=", Bool.show(p1(Some{1}, Some{2}, Some{3}))]))
    IO.print(String.concat(["p1n=", Bool.show(p1(Some{1}, Some{2}, None{}))]))
    IO.print(String.concat(["p2=", Bool.show(Maybe.is_some(&2, List<&2, U32>, p2(Some{[1]}, Some{[2]})))]))
    IO.print(String.concat(["p3=", Bool.show(Bool.and(Nat.is_eq(List.length(&2, U32, P3.a(p3([1, 2], [3, 4, 5]))), 2n), Nat.is_eq(List.length(&2, U32, P3.b(p3([1, 2], [3, 4, 5]))), 2n)))]))
    IO.print(String.concat(["p4=", Bool.show(Nat.is_eq(List.length(&2, U32, p4.go([0, 1], [9, 8], Nil{})), 2n))]))
    IO.print(String.concat(["p5=", Bool.show(p5([1], [1]))]))
    IO.print(String.concat(["p5n=", Bool.show(p5([1], [1, 2]))]))
