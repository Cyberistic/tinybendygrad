import Base
import ../../../tinybendygrad/LAWS/spec.bend as S
import ./p10-lemmas.bend as N

def split(ds: List<&2, S.Sdim>, n: Nat) -> {Nat.mul(S.prod(List.drop(&2, S.Sdim, ds, n)), S.prod(List.take(&2, S.Sdim, ds, n))) == S.prod(ds) : Nat}:
  match ds:
    case Nil{}:
      {==}
    case d <> r:
      match n:
        case 0n:
          N.nat_mul_one_r(S.prod(d <> r))
        case 1n+p:
          +q = p
          +dd = d
          +rr = r
          ih = split(rr, q)
          dim = S.dim_of(dd)
          dropp = S.prod(List.drop(&2, S.Sdim, rr, q))
          takep = S.prod(List.take(&2, S.Sdim, rr, q))
          swapped = N.nat_mul_swap(dropp, dim, takep)
          sswap = Equal.sym(Nat, Nat.mul(dropp, Nat.mul(dim, takep)), Nat.mul(dim, Nat.mul(dropp, takep)), swapped)
          %sswap : {_ == Nat.mul(dim, S.prod(rr)) : Nat}
          sih = Equal.sym(Nat, Nat.mul(dropp, takep), S.prod(rr), ih)
          %sih : {Nat.mul(dim, _) == Nat.mul(dim, S.prod(rr)) : Nat}
          {==}

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("split")
