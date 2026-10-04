# TARGET 1 smoke. The `Dt.i64_*` seam is reachable as `D.Dt.<name>` where `D` is
# dtype.bend's module alias -- `Dt` itself is declared in LAWS/spec.bend, so the
# qualified path binds the DEF's module, not the TYPE's. Measured: the spellings
# `Dt.i64_floor_div` and `S.Dt.i64_floor_div` are both "not a defined name".
#
# U32 is linear (LC-3), so every operand is built inline and shared by nothing.
import ../../../tinybendygrad/dtype.bend as D
import ../../../tinybendygrad/helpers.bend as H

def main() -> IO(Nat):
  do IO<Nat>:
    q : H.I64 <- D.Dt.i64_floor_div(H.i64_of_hi_lo(0, 7), H.i64_of_hi_lo(0, 2))
    IO.print("floor_div 7//2 = " ++ H.i64_text(q))
    return 0n