# THE MINIMAL PROOF THAT A LINEAR (Array-backed) STATE CANNOT BE THREADED THROUGH THE INTERPRETER'S
# LOOP. The loop must match the CURSOR (`match f un` in `run`) and, every iteration, DESTRUCTURE the
# state to rebuild it. Bend allows ONE match per body level and refuses mutual recursion, so the two
# matches have to live in two defs that call each other -- and whichever is written second is
# "an unfilled definition" at the point of use. Both orders are shown; both fail.
import Base

type S is Type:
  S{a: U32, n: U32}

def go.step(xs: List<U32>, +a: U32, +n: U32) -> S:
  match xs:
    case Nil{}: S{a, n}
    case h <> t: go(t, S{U32.add(a, h), U32.add(n, 1)})

def go(xs: List<U32>, s: S) -> S:
  match s:
    case S{a, n}: go.step(xs, a, n)

def main.x(r: S) -> U32:
  match r:
    case S{a, n}: a

def main() -> U32:
  +r = go([1, 2, 3], S{0, 0})
  main.x(r)
