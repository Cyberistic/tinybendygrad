import ../../../../tinybendygrad/dtype.bend as D

def main() -> IO(Unit):
  do IO<Unit>:
    v : F32 <- D.Dt.fp16(1.5)
    IO.print("F32ROW fp16 = " ++ F32.show(v))
