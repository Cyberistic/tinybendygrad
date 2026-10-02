import Base

def nt(n: Nat) -> String:
  match n:
    case 0n: "0"
    case 1n+p: String.concat(["S", nt(p)])

def ur(k: Nat, +i: U32) -> List<&2, U32>:
  match k:
    case 0n : Nil{}
    case 1n+m:
      xs = ur(m, U32.add(i, 1))
      List.append(&2, U32, [i], xs)

def show(+xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}   : ""
    case h <> +t : String.concat([U32.show(h), ",", show(t)])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["log2(16)=", nt(U32.log2(16)), " log2(32)=", nt(U32.log2(32)),
      " log2(128)=", nt(U32.log2(128)), " log2(1)=", nt(U32.log2(1)),
      " log2(4)=", nt(U32.log2(4)), " log2(16/1)=", nt(U32.log2(U32.div(4, 2))),
      " ur(4)=", show(ur(4n, 0)), " min(16,64)=", U32.show(U32.min(16, 64))]))
