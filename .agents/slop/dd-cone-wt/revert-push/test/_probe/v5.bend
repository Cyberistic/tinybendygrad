import Base
import ../../LAWS/spec.bend as S
import ../../dtype.bend as D

def lut_row(+a: S.Dt, +b: S.Dt) -> String:
  String.concat([D.dt_name(a), "\t", D.dt_name(b), "\t", D.dt_name(D.least_upper.of(a, b)), "\t"])

def lut_rows.go(+a: S.Dt, ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case +h <> t:
      +r = lut_row(a, h)
      lut_rows.go(a, t, String.append(acc, r))

def lut_rows.all(ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case +h <> +t:
      +r = lut_rows.go(h, t, "")
      lut_rows.all(t, String.append(acc, r))

def lut_rows(ds: List<&2, S.Dt>) -> String: lut_rows.all(ds, "")

def main() -> IO(Unit):
  do IO<Unit>: IO.print(lut_rows(D.dtypes.all()))
