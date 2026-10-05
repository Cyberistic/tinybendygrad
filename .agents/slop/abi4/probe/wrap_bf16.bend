import ../../../../tinybendygrad/dtype.bend as D

def main() -> IO(Unit):
  do IO<Unit>:
    v : F32 <- D.float_to_bf16(1.5)
    IO.print("F32ROW wrap_bf16 = " ++ F32.show(v))
