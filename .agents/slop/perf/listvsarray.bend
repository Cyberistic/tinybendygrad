# .agents/slop/perf/listvsarray.bend -- THE INTERPRETER's HOT ACCESS, List vs Array.
#
# **⇒ THE QUESTION IS NARROW AND IT IS THE WHOLE OF STAGE 3.** The Bend
# interpreter's 15.4 s for a 16x16 matmul is 100% INSIDE `ops_python.bend` --
# measured, the CPython-side encode+decode is 1.3 ms -- and its hot path indexes
# three structures that are all `List`:
#
#   ops_python.bend:789  `Uop.at`     -- `List.get`, once per STEP, O(pc)
#   ops_python.bend:896  `Val.put`    -- `List.set`, once per ALU op, O(#vals)
#   ops_python.bend:900  `Mem.byte`   -- `List.get`, FOUR times per LOAD, O(#bytes)
#   ops_python.bend:902  `Mem.put`    -- `List.set`, FOUR times per STORE
#
# **⇒ AND `Mem` IS THE ONE THAT MATTERS**: a 16x16 matmul's memory arena is
# `3 x 1024` bytes, and every element of the matmul touches several of them.
#
# `Array<T>` is `Type`, so `a[i] <- v` REWRITES THE SLOT AND HANDS THE SAME ARRAY
# BACK -- "no copy", the guide says. **⇒ SO THIS FILE ASKS WHETHER THAT IS TRUE
# HERE, ON THIS COMPILER, BY COUNTING.**
import Base

def N() -> U32: 65535

# THE LIST LANE: `n` reads and `n` writes at a rotating index, which is the shape
# `Mem.byte`/`Mem.put` have.
def list_run.go(fuel: Nat, +xs: List<&2, U32>, +i: U32) -> List<&2, U32>:
  match fuel:
    case 0n: xs
    case 1n+p:
      +r = Maybe.default(&2, U32, List.get(&2, U32, xs, U32.to_nat(i)), 0)
      +w = List.set(&2, U32, xs, U32.to_nat(i), U32.add(r, 1))
      list_run.go(p, w, U32.mod(U32.add(i, 7), N()))

def list_run() -> List<&2, U32>:
  list_run.go(2000n, List.replicate(&2, U32, U32.to_nat(N()), 0), 0)

# THE ARRAY LANE: the same two operations on `Array<U32>`.
def arr_run.go(fuel: Nat, +xs: Array<U32>, +i: U32) -> Array<U32>:
  match fuel:
    case 0n: xs
    case 1n+p:
      +r = xs[U32.to_nat(i)]
      +w = Array.set(xs, U32.to_nat(i), U32.add(r, 1))
      arr_run.go(p, w, U32.mod(U32.add(i, 7), N()))

def arr_run() -> Array<U32>:
  arr_run.go(2000n, [0 : U32*65536n], 0)

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print("listvsarray: see .agents/slop/perf/run.sh for the timing")
    IO.pure(Unit, Unit{})
