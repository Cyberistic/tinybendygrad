# THE SEMANTICS OF `List.drop` AND `List.take`, MEASURED ON THE STDLIB
# `references/bend/bend2/base.bend` THAT `import Base` RESOLVES TO.
#
# NOTHING PORT-SPECIFIC HERE. THIS FILE EXISTED TO ANSWER ONE QUESTION:
# IS `List.drop(xs, n)` A HEAD DROP OR A TAIL DROP?
#
# `List.take(xs, n)` KEEPS THE FIRST `n`; `List.drop(xs, n)` IS ITS COMPLEMENT
# (base.bend:984 and base.bend:993). SO IF `take` IS A PREFIX, `drop` IS A
# HEAD DROP, AND `xs[:-1]` IS NOT SPELLABLE WITH IT.

import Base

def show(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: ""
    case h <> t: String.concat([U32.show(h), ",", show(t)])

def main() -> IO(Unit):
  +xs: List<&2, U32> = [2, 4, 3]
  do IO<Unit>:
    IO.print(String.concat(["xs            = ", show(xs)]))
    IO.print(String.concat(["take(xs,0)    = ", show(List.take(&2, U32, xs, 0n))]))
    IO.print(String.concat(["take(xs,1)    = ", show(List.take(&2, U32, xs, 1n))]))
    IO.print(String.concat(["take(xs,2)    = ", show(List.take(&2, U32, xs, 2n))]))
    IO.print(String.concat(["take(xs,3)    = ", show(List.take(&2, U32, xs, 3n))]))
    IO.print(String.concat(["take(xs,99)   = ", show(List.take(&2, U32, xs, 99n))]))
    IO.print(String.concat(["drop(xs,0)    = ", show(List.drop(&2, U32, xs, 0n))]))
    IO.print(String.concat(["drop(xs,1)    = ", show(List.drop(&2, U32, xs, 1n))]))
    IO.print(String.concat(["drop(xs,2)    = ", show(List.drop(&2, U32, xs, 2n))]))
    IO.print(String.concat(["drop(xs,3)    = ", show(List.drop(&2, U32, xs, 3n))]))
    IO.print(String.concat(["drop(xs,99)   = ", show(List.drop(&2, U32, xs, 99n))]))
    IO.print(String.concat(["length(xs)    = ", Nat.show(List.length(&2, U32, xs))]))
    IO.print(String.concat(["Nat.sub(0,1)  = ", Nat.show(Nat.sub(0n, 1n))]))
    IO.print(String.concat(["Nat.sub(3,1)  = ", Nat.show(Nat.sub(3n, 1n))]))
