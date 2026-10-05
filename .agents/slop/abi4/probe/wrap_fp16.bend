import ../../../../tinybendygrad/dtype.bend as D

def main() -> IO(Unit):
  do IO<Unit>:
    v : F32 <- D.float_to_fp16(1.5)
    IO.print("F32ROW wrap_fp16 = " ++ F32.show(v))
