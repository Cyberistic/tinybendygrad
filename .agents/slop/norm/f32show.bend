# f32show.bend -- the compiler's OWN float spelling, one row per pattern, in bulk.

import Base
import ../../../tinybendygrad/base.bend as FB
import ../../../tinybendygrad/helpers.bend as H

# `F32.show` spliced in is `f32_show` (references/bend/bend2/bend.ts:1197).  The
# whole claim `canon.selftest.py` measures is about THAT string, so it is read out
# of the runtime rather than re-spelled here -- `JSL2-5` records the cost of
# assuming a re-spelling is one: `h * 2**32 + l` "moved 15 of 30 rows".
#
# ONE `String.concat` at the end, not an accumulator carried down the recursion:
# `frombits/gate_dtype.bend:41-52` measured that a linear accumulator is rebuilt
# at every step and that `String.concat` on a growing prefix is quadratic, and
# JavaScript's rope strings make both free -- so a JS-lane sweep this size would
# not have noticed either.
def rows(m: Nat, fuel: Word(m), +start: U32, +i: U32,
         acc: List<&2, String>) -> List<&2, String>:
  match m fuel:
    case 0n WNil{}:
      List.reverse(&2, String, acc)
    case 1n+p WCon{b, rest}:
      rows(p, rest, start, U32.add(i, 1),
           List.append(&2, String,
                       [String.concat([U32.show(U32.add(start, i)), " ",
                                       F32.show(FB.F32.from_bits(U32.add(start, i))),
                                       " "])],
                       acc))

def run(start: U32, step: U32, cn: U32) -> String:
  +count = U32.to_nat(cn)
  String.concat(rows(count, Word.zero(count), start, step, Nil{}))

def main() -> IO(Unit):
  do IO<Unit>:
    lo : U32 <- H.getenv_int("NS_LO", 0)
    st : U32 <- H.getenv_int("NS_STEP", 1)
    cn : U32 <- H.getenv_int("NS_COUNT", 0)
    u : Unit <- IO.print(run(lo, st, cn))
    return u