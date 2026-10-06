import ../../../../probe_min.bend as D

def main() -> IO(Unit):
  do IO<Unit>:
    v : F32 <- D.two(1.5)
    IO.print("F32ROW min_D = " ++ F32.show(v))
