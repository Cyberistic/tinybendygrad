import Base

# WHAT THIS PROBES: `List.append(&2, A, r, [x])` -- is `x` at the END of `r`, or in
# FRONT of it? The project notes claim both, in different places, and `marg.go` in
# `movement.bend` depends on the answer. So: build [1,2,3] by folding with
# `List.append(acc, [x])` and read the head. head == 1 means APPEND, head == 3 means
# PREPEND. MEASURED: head == 1, so `append(r, [x])` appends at the END and a fold that
# appends on the way UP reverses its list.

def go(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}  : acc
    case x <> t : go(t, List.append(&2, U32, acc, [x]))

def empty() -> List<&2, U32>:
  Nil{}

def three() -> List<&2, U32>:
  [1, 2, 3]

def head(xs: List<&2, U32>) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, 0n), 99)

def answer() -> U32:
  head(go(three(), empty()))

def row(v: U32) -> IO(Unit):
  IO.print(String.concat([U32.show(v)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row(0)
    row(answer())