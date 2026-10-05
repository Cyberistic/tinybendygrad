import ../../../../tinybendygrad/dtype.bend as D

def main() -> IO(Unit):
  do IO<Unit>:
    v : U32 <- D.float_to_fp8(1.5, D.dtypes.fp8e4m3)
    IO.print("F32ROW wrap_fp8fr = " ++ U32.show(v))
