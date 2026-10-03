# Re-measure the two open laws against the LIVE tree.
# drop_n is List.drop. The reduce law multiplies by prod(take(dims, n)).
#
#   ./bin/bend .agents/slop/ind/p9-measure.bend
import Base
import ../../../tinybendygrad/LAWS/spec.bend as S

def shp(ds: List<&2, S.Sdim>) -> S.Sp:
  S.SpReshape{S.SpInvalid{}, S.SpInvalid{}, ds}

def sn(n: Nat) -> S.Sdim:
  S.SN{n}

def ss() -> S.Sdim:
  S.SS{S.SpInvalid{}}

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

def law_take_n(+t: S.Sp, +n: Nat) -> Nat:
  Nat.mul(q_reduced(t, n), S.prod(List.take(&2, S.Sdim, q_dims(t), n)))

def law_take_np1(+t: S.Sp, +n: Nat) -> Nat:
  Nat.mul(q_reduced(t, n), S.prod(List.take(&2, S.Sdim, q_dims(t), Nat.add(n, 1n))))

def law_drop_kept(+t: S.Sp, +n: Nat) -> Nat:
  Nat.mul(q_reduced(t, n), S.prod(S.drop_n(q_dims(t), n)))

def bcast(+a: S.Sp, +b: S.Sp) -> Nat:
  Nat.max(q_numel(S.SpAdd{a, b}), q_numel(b))

def row(label: String, +lhs: Nat, +rhs: Nat) -> String:
  label ++ " LHS=" ++ Nat.show(lhs) ++ " RHS=" ++ Nat.show(rhs) ++ " eq=" ++ Bool.show(Nat.is_eq(lhs, rhs))

def brow(label: String, +a: S.Sp, +b: S.Sp) -> String:
  row(label, bcast(a, b), q_numel(S.SpAdd{a, b}))

def d456() -> List<&2, S.Sdim>:
  [sn(4n), sn(5n), sn(6n)]

def d4() -> List<&2, S.Sdim>:
  [sn(4n)]

def d23() -> List<&2, S.Sdim>:
  [sn(2n), sn(3n)]

def d33() -> List<&2, S.Sdim>:
  [sn(3n), sn(3n)]

def dss() -> List<&2, S.Sdim>:
  [ss(), sn(5n)]

def d37() -> List<&2, S.Sdim>:
  [sn(3n), sn(7n)]

def d50() -> List<&2, S.Sdim>:
  [sn(5n), sn(0n)]

def d3() -> List<&2, S.Sdim>:
  [sn(3n)]

def d20() -> List<&2, S.Sdim>:
  [sn(2n), sn(0n)]

def d11() -> List<&2, S.Sdim>:
  [sn(1n), sn(1n)]

def d41() -> List<&2, S.Sdim>:
  [sn(4n), sn(1n)]

def d13() -> List<&2, S.Sdim>:
  [sn(1n), sn(3n)]

def d2() -> List<&2, S.Sdim>:
  [sn(2n)]

def d22() -> List<&2, S.Sdim>:
  [sn(2n), sn(2n)]

def dzero_suffix() -> List<&2, S.Sdim>:
  [sn(5n), sn(1n), sn(0n)]

def dpos() -> List<&2, S.Sdim>:
  [sn(3n), sn(4n)]

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("drop_n_456_0=" ++ Nat.show(List.length(&2, S.Sdim, S.drop_n(d456(), 0n))))
    IO.print("drop_n_456_1=" ++ Nat.show(List.length(&2, S.Sdim, S.drop_n(d456(), 1n))))
    IO.print("drop_n_456_2=" ++ Nat.show(List.length(&2, S.Sdim, S.drop_n(d456(), 2n))))
    IO.print(row("take_n_4_0", law_take_n(shp(d4()), 0n), q_numel(shp(d4()))))
    IO.print(row("take_n_456_1", law_take_n(shp(d456()), 1n), q_numel(shp(d456()))))
    IO.print(row("take_n_456_0", law_take_n(shp(d456()), 0n), q_numel(shp(d456()))))
    IO.print(row("take_n_456_3", law_take_n(shp(d456()), 3n), q_numel(shp(d456()))))
    IO.print(row("take_n_456_5", law_take_n(shp(d456()), 5n), q_numel(shp(d456()))))
    IO.print(row("take_n_ss_1", law_take_n(shp(dss()), 1n), q_numel(shp(dss()))))
    IO.print(row("take_n_none_0", law_take_n(S.SpInvalid{}, 0n), q_numel(S.SpInvalid{})))
    IO.print(row("take_n_zero_1", law_take_n(shp(d50()), 1n), q_numel(shp(d50()))))
    IO.print(row("take_np1_4_0", law_take_np1(shp(d4()), 0n), q_numel(shp(d4()))))
    IO.print(row("take_np1_456_1", law_take_np1(shp(d456()), 1n), q_numel(shp(d456()))))
    IO.print(row("kept_4_0", law_drop_kept(shp(d4()), 0n), q_numel(shp(d4()))))
    IO.print(row("kept_456_1", law_drop_kept(shp(d456()), 1n), q_numel(shp(d456()))))
    IO.print(brow("bc_23_33", shp(d23()), shp(d33())))
    IO.print(brow("bc_ss_37", shp(dss()), shp(d37())))
    IO.print(brow("bc_50_3", shp(d50()), shp(d3())))
    IO.print(brow("bc_20_11", shp(d20()), shp(d11())))
    IO.print(brow("bc_23_41", shp(d23()), shp(d41())))
    IO.print(brow("bc_13_23", shp(d13()), shp(d23())))
    IO.print(brow("bc_2_22", shp(d2()), shp(d22())))
    IO.print(brow("bc_3_23", shp(d3()), shp(d23())))
    IO.print(brow("bc_50_pos", shp(d50()), shp(dpos())))
    IO.print(brow("bc_zsuf_pos", shp(dzero_suffix()), shp(dpos())))
    IO.print(brow("bc_pos_zsuf", shp(dpos()), shp(dzero_suffix())))
    IO.print(brow("bc_none_33", S.SpStore{S.SpInvalid{}, S.SpInvalid{}, None{}}, shp(d33())))
    IO.print(brow("bc_33_none", shp(d33()), S.SpStore{S.SpInvalid{}, S.SpInvalid{}, None{}}))
    IO.print(brow("bc_eq_ss", shp(dss()), shp(dss())))
