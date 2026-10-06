import ../../../../tinybendygrad/dtype.bend as D

def main() -> IO(Unit):
  do IO<Unit>:
    v : F32 = D.Dt.fp16(1.5)
    w : U32 = D.Dt.fp8_from(F32.bits(1.5), 0)
    IO.print("F32ROW pure_fp16 = " ++ F32.show(v))
    IO.print("F32ROW pure_fp8fr = " ++ U32.show(w))
