import Base

# Does a 64-bit word exist as a user-declared type? This is the whole question:
# Base ships F32{data: Word(32n)} and NO F64/I64/U64, so if a user can declare
# F64{data: Word(64n)} the representation question is settled.
type F64 is Data:
  F64{data: Word(64n)}

def bch(b: Bool) -> Char:
  match b:
    case False{}:
      Chr{U32.from_nat(48n)}
    case True{}:
      Chr{U32.from_nat(49n)}
# Readback. `k` is the peel fuel (a parameter, because a match may only inspect
# a parameter) and it goes FIRST so the termination checker sees the shrinking
# argument before the free one. Prints LSB-first, so bit i of the answer is the
# i-th character -- which is the convention the CPython diff assumes.
def bits(k: Nat, w: Word(k)) -> String:
  match k:
    case 0n:
      ""
    case 1n+kk:
      match w:
        case WCon{b, t}:
          Char.show(bch(b)) ++ bits(kk, t)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("W-3 control w1   =" ++ bits(64n, WCon{True{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WCon{False{}, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}))
