import ../../../../tinybendygrad/dtype.bend as D

def main() -> IO(Unit):
  do IO<Unit>:
    v : F32 <- D.fp8_to_float(60, D.dtypes.fp8e4m3)
    IO.print("F32ROW wrap_fp8to = " ++ F32.show(v))
