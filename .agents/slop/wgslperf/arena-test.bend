# THE ARENA's CHUNKED LOOKUP, CHECKED AGAINST THE NODES: THE CHUNKED INDEX AND THE NODE LIST
# MUST AGREE, AND THE NODE OF INDEX `i` IS IN CHUNK `i / 32`.
#
# THE ARENA's INDEX 0 IS THE BOTTOM NODE (`Arena.empty()`), SO THE NODE BUILT WITH THE SRC
# `[i]` IS AT INDEX `i + 1`.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O

def src_is(ss: List<&2, U32>, i: U32) -> Bool:
  match ss:
    case h <> t: U32.is_eq(h, i)
    case Nil{}: False{}

def check.src(ok: Bool, bad: Nat) -> Nat:
  match ok:
    case True{}: bad
    case False{}: Nat.add(bad, 1n)

def check.of(hit: Maybe<&1, O.Node>, i: U32, bad: Nat) -> Nat:
  match hit:
    case Some{nd}: check.src(src_is(O.Node.src(nd), U32.sub(i, 1)), bad)
    case None{}: Nat.add(bad, 1n)

def check.all(n: Nat, +ar: O.Arena, +i: U32, bad: Nat) -> Nat:
  match n:
    case 0n: bad
    case 1n+p:
      bad2 = check.of(O.Arena.at(ar, i), i, bad)
      check.all(p, ar, U32.add(i, 1), bad2)

def build.go(n: Nat, +ar: O.Arena, +i: U32) -> O.Arena:
  match n:
    case 0n: ar
    case 1n+p: build.go(p, O.Arena.put(ar, O.Node{O.OpsADD{}, [i], O.ANone{}, O.TNone{}, 0}), U32.add(i, 1))

def report(+ar: O.Arena) -> IO(Unit):
  do IO<Unit>:
    bad : Nat = check.all(40n, ar, 1, 0n)
    IO.print(String.concat(["THE BAD LOOKUPS: ", Nat.show(bad)]))
    IO.print(String.concat(["THE ARENA's COUNT: ", U32.show(O.Arena.next(ar))]))
    IO.print(String.concat(["THE NODES: ", U32.show(U32.from_nat(List.length(&2, O.Node, O.Arena.nodes(ar))))]))
    IO.print(String.concat(["THE CHUNKS: ", U32.show(U32.from_nat(List.length(&2, List<&2, O.Node>, O.Arena.cs(ar))))]))

def main() -> IO(Unit):
  do IO<Unit>:
    report(build.go(40n, O.Arena.empty(), 0))
