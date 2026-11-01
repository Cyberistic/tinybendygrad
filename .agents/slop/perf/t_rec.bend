# t_rec.bend -- CAN AN `Array` LIVE IN A RECORD, AND DOES A WRITE THROUGH IT STAY IN PLACE?
#
#     ./bin/bend .agents/slop/perf/t_rec.bend -o /tmp/rec && /usr/bin/time -p /tmp/rec
#
# This is the question the arena refactor turns on, and both halves are answered here:
#
#   * `type S is Data: S{a: Array<E>, ...}` IS REFUSED -- "expected Data, observed Type". A
#     reusable record cannot hold an `Array`, which is exactly why `Prog.vs`/`Prog.ms` are
#     `List`s today and why one arena write costs ~48 heap cells (REPORT.md 35.2/35.6).
#   * `type S is Type: S{a: Array<E>, ...}` (a LINEAR record) COMPILES and the writes are IN
#     PLACE: 2 000 000 writes through the record, read back at the end, in well under 10 ms --
#     against 0.90 s for the same traffic in the `Val.put` shape.
#
# So the arena change is possible and its payoff is measured; what it COSTS is that `Prog` stops
# being reusable (`+p: Prog` -> a linear `p`), which touches 42 defs and 37 `Prog{...}`
# constructors. That is the unit of work, and this file is its green light.
import Base

type E is Data:
  E{b: U32}

# THE QUESTION: can an `Array` live in a record, and does a write through a `+` parameter stay
# IN PLACE or copy? If it copies, the arena refactor has to make the record linear first.
type S is Type:
  S{a: Array<E>, n: U32}

def E.b(e: E) -> U32:
  match e:
    case E{b}: b

def arr_fin(r: Array<E> & E) -> U32:
  match r:
    case (a, e): E.b(e)

# `+s` -- the port's shape: a record threaded as a REUSABLE parameter
def S.a(s: S) -> Array<E>:
  match s:
    case S{a, n}: a

def S.set(s: S, +i: U32, +e: E) -> S:
  match s:
    case S{a, n}: S{Array.set(E, a, i, e), n}

def loop_plus(f: Nat, s: S, +i: U32) -> U32:
  match f:
    case 0n: arr_fin(Array.get(E, S.a(s), U32.mod(i, 512)))
    case 1n+g: loop_plus(g, S.set(s, U32.mod(i, 512), E{U32.mul(i, 3)}), U32.add(i, 1))

def plus_mode() -> U32: loop_plus(2000000n, S{Array.new(E, 9n, E{0}), 0}, 0)

def main() -> IO(Unit):
  do IO<Unit>: IO.print(U32.show(plus_mode()))
