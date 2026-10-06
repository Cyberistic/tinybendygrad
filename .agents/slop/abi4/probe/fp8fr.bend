import ../../../../tinybendygrad/dtype.bend as D

def main() -> IO(Unit):
  do IO<Unit>:
    v : U32 <- D.Dt.fp8_from(1069547520, 0)
    IO.print("F32ROW fp8fr = " ++ U32.show(v))
