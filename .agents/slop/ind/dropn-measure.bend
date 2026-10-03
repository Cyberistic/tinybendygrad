# Which of drop_n and the reduce law is wrong. Imports the LIVE spec.
# List.drop is Base's contract, not a call to the helper under test.
#
#   ./bin/bend .agents/slop/ind/dropn-measure.bend
import Base
import ../../../tinybendygrad/LAWS/spec.bend as S

def shp(ds: List<&2, S.Sdim>) -> S.Sp:
  S.SpReshape{S.SpInvalid{}, S.SpInvalid{}, ds}

def dims456() -> List<&2, S.Sdim>:
  [S.SN{4n}, S.SN{5n}, S.SN{6n}]

def dims4() -> List<&2, S.Sdim>:
  [S.SN{4n}]

def q_numel(s: S.Sp) -> Nat:
  S.dims_prod(S.Sp.shape(s))

def q_reduced(t: S.Sp, n: Nat) -> Nat:
  q_numel(S.SpReduce{t, Nil{}, S.SpInvalid{}, n})

def q_dims.go(m: Maybe<&2, S.Shape>) -> List<&2, S.Sdim>:
  match m:
    case Some{sh}: S.Shape.to_dims(sh)
    case None{}: Nil{}

def q_dims(s: S.Sp) -> List<&2, S.Sdim>:
  q_dims.go(S.Sp.shape(s))

def base_drop(ds: List<&2, S.Sdim>, n: Nat) -> List<&2, S.Sdim>:
  List.drop(&2, S.Sdim, ds, n)

def base_take(ds: List<&2, S.Sdim>, n: Nat) -> List<&2, S.Sdim>:
  List.take(&2, S.Sdim, ds, n)

def dim_show(d: S.Sdim) -> String:
  match d:
    case S.SN{v}: Nat.show(v)
    case S.SS{_}: "SS"

def dims_show(ds: List<&2, S.Sdim>) -> String:
  match ds:
    case Nil{}: ""
    case d <> r:
      match r:
        case Nil{}: dim_show(d)
        case _ <> _: dim_show(d) ++ "," ++ dims_show(r)

def row(label: String, +lhs: Nat, +rhs: Nat) -> String:
  label ++ " LHS=" ++ Nat.show(lhs) ++ " RHS=" ++ Nat.show(rhs) ++ " eq=" ++ Bool.show(Nat.is_eq(lhs, rhs))

def law_now(+t: S.Sp, +n: Nat) -> Nat:
  Nat.mul(q_reduced(t, n), S.prod(S.drop_n(q_dims(t), n)))

def law_take_np1(+t: S.Sp, +n: Nat) -> Nat:
  Nat.mul(q_reduced(t, n), S.prod(base_take(q_dims(t), Nat.add(n, 1n))))

def law_fixed_as_written(+ds: List<&2, S.Sdim>, +n: Nat) -> Nat:
  Nat.mul(S.prod(base_drop(ds, n)), S.prod(base_drop(ds, n)))

def law_fixed_take_n(+ds: List<&2, S.Sdim>, +n: Nat) -> Nat:
  Nat.mul(S.prod(base_drop(ds, n)), S.prod(base_take(ds, n)))

def law_fixed_take_np1(+ds: List<&2, S.Sdim>, +n: Nat) -> Nat:
  Nat.mul(S.prod(base_drop(ds, n)), S.prod(base_take(ds, Nat.add(n, 1n))))

def rhs_of(ds: List<&2, S.Sdim>) -> Nat:
  S.prod(ds)

def unwrap(m: Maybe<&2, S.Shape>) -> S.Shape:
  match m:
    case Some{sh}: sh
    case None{}: S.Shape.empty()

def idx1() -> S.Sp:
  S.SpIdx1{shp(dims456()), S.SpRange{S.SpInvalid{}}}

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("drop_n_456_0=" ++ dims_show(S.drop_n(dims456(), 0n)))
    IO.print("drop_n_456_1=" ++ dims_show(S.drop_n(dims456(), 1n)))
    IO.print("drop_n_456_2=" ++ dims_show(S.drop_n(dims456(), 2n)))
    IO.print("list_drop_456_0=" ++ dims_show(base_drop(dims456(), 0n)))
    IO.print("list_drop_456_1=" ++ dims_show(base_drop(dims456(), 1n)))
    IO.print("list_drop_456_2=" ++ dims_show(base_drop(dims456(), 2n)))
    IO.print("idx1_rank=" ++ Nat.show(S.Shape.ndim(unwrap(S.Sp.shape(idx1())))))
    IO.print("idx1_dims=" ++ dims_show(S.Shape.to_dims(unwrap(S.Sp.shape(idx1())))))
    IO.print(row("law_now_4_0", law_now(shp(dims4()), 0n), q_numel(shp(dims4()))))
    IO.print(row("law_now_456_1", law_now(shp(dims456()), 1n), q_numel(shp(dims456()))))
    IO.print(row("law_take_np1_4_0", law_take_np1(shp(dims4()), 0n), q_numel(shp(dims4()))))
    IO.print(row("law_take_np1_456_1", law_take_np1(shp(dims456()), 1n), q_numel(shp(dims456()))))
    IO.print(row("if_exact_as_written_4_0", law_fixed_as_written(dims4(), 0n), rhs_of(dims4())))
    IO.print(row("if_exact_as_written_456_1", law_fixed_as_written(dims456(), 1n), rhs_of(dims456())))
    IO.print(row("if_exact_take_n_4_0", law_fixed_take_n(dims4(), 0n), rhs_of(dims4())))
    IO.print(row("if_exact_take_n_456_1", law_fixed_take_n(dims456(), 1n), rhs_of(dims456())))
    IO.print(row("if_exact_take_np1_4_0", law_fixed_take_np1(dims4(), 0n), rhs_of(dims4())))
    IO.print(row("if_exact_take_np1_456_1", law_fixed_take_np1(dims456(), 1n), rhs_of(dims456())))
