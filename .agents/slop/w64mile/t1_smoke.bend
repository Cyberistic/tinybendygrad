# smoke: does the 6 `Dt.i64_*` FFI seam execute at all?
# One row, one use per U32 -- U32 is linear (LC-3), so every operand is built
# inline and nothing is shared.
import ../../../tinybendygrad/dtype.bend as D
import ../../../tinybendygrad/helpers.bend as H
import ../../../tinybendygrad/LAWS/spec.bend as S

def main() -> IO(Nat):
  do IO<Nat>:
    q : H.I64 <- S.Dt.i64_floor_div(H.i64_of_hi_lo(0, 7), H.i64_of_hi_lo(0, 2))
    IO.print("floor_div 7//2 = " ++ H.i64_text(q))
    return 0n