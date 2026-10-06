import ../../../../tinybendygrad/dtype.bend as D

def main() -> IO(Unit):
  do IO<Unit>:
    v : F32 <- D.Dt.bf16(1073741824)
    IO.print("F32ROW bf16 = " ++ F32.show(v))
