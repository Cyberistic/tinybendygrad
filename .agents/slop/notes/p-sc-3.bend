import Base

type Split is Data:
  Split{ks: List<&2, U32>, ds: List<&2, U32>}

# Q: a Bool-parameter match nested inside a Data-record match arm, the ORIGINAL
# shape that was refused.
def pick(is_k: Bool, is_a: Bool, s: U32, sp: Split) -> Split:
  match sp:
    case Split{ks, ds}:
      match is_k:
        case True{} : Split{ks, ds}
        case False{}: pick2(is_a, s, ks, ds)

def pick2(is_a: Bool, s: U32, ks: List<&2, U32>, ds: List<&2, U32>) -> Split:
  match is_a:
    case True{} : Split{ks, [s] <> ds}
    case False{}: Split{[s] <> ks, ds}

# Q2: same, but the inner scrutinee is a Nat-arm match
def pick3(n: Nat, s: U32, sp: Split) -> Split:
  match sp:
    case Split{ks, ds}:
      match n:
        case 0n: Split{ks, ds}
        case _ : Split{[s] <> ks, ds}

# Q3: same, but the inner scrutinee is a LIST
def pick4(xs: List<&2, U32>, s: U32, sp: Split) -> Split:
  match sp:
    case Split{ks, ds}:
      match xs:
        case Nil{}    : Split{ks, ds}
        case _ <> rest: Split{[s] <> ks, ds}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print(String.concat(["ks=", U32.show(U32.from_nat(List.length(&2, U32, Split.ks(pick(True{}, False{}, 7, Split{Nil{}, Nil{}})))))]))
    b : Unit <- IO.print(String.concat(["p3=", U32.show(U32.from_nat(List.length(&2, U32, Split.ks(pick3(0n, 7, Split{Nil{}, Nil{}})))))]))
    c : Unit <- IO.print(String.concat(["p4=", U32.show(U32.from_nat(List.length(&2, U32, Split.ks(pick4([1], 7, Split{Nil{}, Nil{}})))))]))
    IO.print("alive")