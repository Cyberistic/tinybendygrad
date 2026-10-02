import Base

def ushow(+xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}   : ""
    case h <> +t : String.concat([U32.show(h), ",", ushow(t)])

# A: no read of the fuel `k` in the arm
def urA(k: Nat) -> List<&2, U32>:
  match k:
    case 0n : Nil{}
    case 1n+m: List.append(&2, U32, urA(m), [0])

# D: the index is a second parameter that GROWS
def urD(k: Nat, +i: U32) -> List<&2, U32>:
  match k:
    case 0n : Nil{}
    case 1n+m:
      xs = urD(m, U32.add(i, 1))
      List.append(&2, U32, [i], xs)

# E: two Nat patterns in one arm, one for the fuel and one for the index
def urE(k: Nat, +i: Nat) -> List<&2, U32>:
  match k:
    case 0n : Nil{}
    case 1n+m: List.append(&2, U32, urE(m, i), [U32.from_nat(i)])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([ushow(urA(3n)), "|", ushow(urD(3n, 0)), "|", ushow(urE(3n, 0n))]))
