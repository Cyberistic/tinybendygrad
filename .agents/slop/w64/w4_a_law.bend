import Base

type F64 is Data:
  F64{data: Word(64n)}

def bch(b: Bool) -> Char:
  match b:
    case False{}:
      Chr{U32.from_nat(48n)}
    case True{}:
      Chr{U32.from_nat(49n)}

def bits(k: Nat, w: Word(k)) -> String:
  match k:
    case 0n:
      ""
    case 1n+kk:
      match w:
        case WCon{b, t}:
          Char.show(bch(b)) ++ bits(kk, t)

law f4add:
  for a: F64
  for b: F64
  F64
  import "./f4_a.c"

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("W-4 A unreachable")
