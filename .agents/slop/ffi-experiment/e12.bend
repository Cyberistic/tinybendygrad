import Base
law fbits:
  Nat -> IO(U32)
def fbits(x):
  import "./shim12.c"
def main() -> IO(Unit):
  do IO<Unit>:
    r : U32 <- fbits(1065353216n)   # 0x3F800000 == 1.0f
    IO.print("F32_BITPATTERN " ++ U32.show(r))
