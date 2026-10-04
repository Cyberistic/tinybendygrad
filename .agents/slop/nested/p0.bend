import Base
# .agents/slop/nested/p0.bend -- the reference for what "nested" must MEAN, written
# in Bend rather than asserted.  THREE lexically distinct `List.range` walks, one
# inside the next, so a reader can see the depth in the source.  A match may not
# scrutinise a computed value, so every walk arrives as a PARAMETER; a binder used
# twice needs the `+` that makes it affine; a bare `+` on Nat is refused.
#
# ROW ENCODING.  Each visit appends `100*depth + 10*d + i`, where d is the top-level
# index, i the middle index and depth is 1 innermost, 2 middle, 3 outer, 0 the end of
# a walk.  So every element is DISTINCT (an all-equal row cannot hide an ordering bug)
# and every row NAMES ITS OWN LOOP DEPTH -- what the brief demands of a fixture.
#
# `IO.print` DOES NOT INTERPOLATE: "{x}" prints the eight characters `{x}`.
# MEASURED here; rows are built with String.concat + U32.show, which is what the port
# does at `row`/`urow` (ops_python.bend:2570-2572).  An uninterpolated brace in a
# transcript reads as agreement and is not one.

def hundred() -> U32: U32.from_nat(100n)
def ten() -> U32: U32.from_nat(10n)

def at(+d: Nat, +i: Nat, depth: Nat) -> U32:
  U32.add(U32.mul(hundred(), U32.from_nat(depth)), U32.add(U32.mul(ten(), U32.from_nat(d)), U32.from_nat(i)))

def inner(+d: Nat, +i: Nat) -> List<&2, U32>: [at(d, i, 1n)]

def outer(+d: Nat, xs: List<&2, Nat>) -> List<&2, U32>:
  match xs:
    case Nil{}: [at(d, 0n, 0n)]
    case +i <> is_: List.append(&2, U32, inner(d, i),
      List.append(&2, U32, [at(d, i, 2n)], outer(d, is_)))

def mid(+d: Nat, xs: List<&2, Nat>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case +j <> js_: List.append(&2, U32, outer(j, List.range(4n)),
      List.append(&2, U32, [at(d, j, 3n)], mid(d, js_)))

def row(+x: U32) -> String:
  String.concat(["row depth=", U32.show(U32.div(x, hundred())), " top=",
    U32.show(U32.mod(U32.div(x, ten()), ten)), " mid=", U32.show(U32.mod(x, ten()))])

def show(xs: List<&2, U32>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case x <> ts_: IO.bind(Unit, Unit, IO.print(row(x)), _ => show(ts_))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("DEPTH-2 REFERENCE NEST: 3 outer x 4 middle x 1 inner; every row names its depth")
    show(mid(0n, List.range(3n)))
    IO.print(String.concat(["visits=", U32.show(U32.from_nat(List.length(&2, U32, mid(0n, List.range(3n)))))]))
    IO.print("DONE")
