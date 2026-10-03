import Base
import ./../../tinybendygrad/codegen/decomp/dtype.bend as D
import ./../../tinybendygrad/LAWS/spec.bend as S

# Probe: `f2f_clamp_max` (dtype.py:128-131) for each of dd-oracle.py's CLAMP_DTS,
# printed as `F(<f32 bits>)` -- the SAME shape as `dd_lab.node`'s float-CONST arm
# at dtype.bend:1734 and as the oracle's `c{i}` rows. Does not edit dtype.bend.

def show.mx(m: Maybe<&2, F32>) -> String:
  match m:
    case None{}: "refused:unported"
    case Some{+f}: String.concat(["F(", U32.show(F32.bits(f)), ")"])

def show.dt(nm: String, +dt: S.Dt) -> String:
  String.concat([nm, "=", show.mx(D.f2f_clamp_max(dt)), "\n"])

def main() -> IO(Unit):
  IO.print(String.concat([
    show.dt("c0", S.fp8e4m3()), show.dt("c1", S.fp8e4m3fnuz()),
    show.dt("c2", S.fp8e5m2()), show.dt("c3", S.fp8e5m2fnuz()),
    show.dt("c4", S.half()), show.dt("c5", S.bfloat16()),
    show.dt("c6", S.single()), show.dt("c7", S.double())]))