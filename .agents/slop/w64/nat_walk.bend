# W-1  Nat runtime ceiling, by DOUBLING from the literal ceiling 4294967295n.
#
# PRE-REGISTERED EXPECTATION (written before this file was first run):
#   I expect doubling to survive well past 2^32 and to FAIL somewhere between
#   2^51 and 2^53, because the inherited claim is
#     "works to 2^51-1 and aborts at 2^52-1, while its own error message says 2^48-1"
#   I EXPECT THE INHERITED CLAIM NOT TO REPRODUCE. Two measured facts contradict
#   it or leave it unsupported: (a) the FFI experiment observed a runtime Nat of
#   4378857668, which is only ~2^32 and so does NOT corroborate 2^51; (b)
#   `bend base Nat` shows Nat.mul/divmod/cmp are defined by PEANO structural
#   recursion, so there is no reason to expect a 2^48 machine limit at all --
#   the arithmetic semantics are unary. Either Nat is machine-backed at runtime
#   (then doubling should WRAP SILENTLY and never fail) or it is Peano (then
#   Nat.double on a 2^32 value should be a 2^32-step recursion and hang/OOM).
#   Both of those are findings that beat a confirmation of 2^51.
#
# SHAPE NOTES (each of these cost a compile round; recorded so it is not re-paid):
#   * Bend has NO `if`. Use `match` on `True{}`/`False{}` or on a Nat literal.
#   * A `match` HEADS a def body; it is not a term. So the match cannot sit
#     inside the `do` block -- the arms carry their own `do` blocks.
#   * A `match` may only inspect a PARAMETER, never a computed value, which is
#     why the counter is a real parameter. It goes FIRST because the
#     termination checker reads arguments left to right and needs the shrinking
#     argument first; `n` after it is free to change.
#   * NO `value.field` SUGAR -- `n.show` is a parse error ("expected a defined
#     name"); every projection is an explicit call, `Nat.show(n)`.
#   * `Nat` is AFFINE and Nat.show SPENDS it, so walk returns IO(Unit): the
#     printed line is the record, and returning the value would need a copy
#     that `Nat` does not permit.
#
# OUTPUT IS PAIRS (fuel, val), and THE ORDER IS WHAT I AM READING, so it is
# structural -- no list, no append, no fold, no reverse. The fuel column is a
# SELF-CHECK on that order: it must descend by exactly 1 per line, and the val
# column must double. If fuel does not descend, the order is wrong and every
# val reading is void. Print precedes each doubling, so the last surviving value
# is on record even if the process dies on the next one.

import Base

def walk(fuel: Nat, +n: Nat) -> IO(Unit):
  match fuel:
    case 0n:
      do IO<Unit>:
        IO.print("W-1 fuel=0 val=" ++ Nat.show(n))
    case 1n+ +p:
      do IO<Unit>:
        IO.print("W-1 fuel=" ++ Nat.show(p) ++ " val=" ++ Nat.show(n))
        walk(p, Nat.double(n))

def main() -> IO(Unit):
  do IO<Unit>:
    walk(40n, 4294967295n)