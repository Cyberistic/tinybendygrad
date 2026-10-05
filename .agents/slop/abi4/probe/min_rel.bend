import ../../../../probe_min.bend

def main() -> IO(Unit):
  do IO<Unit>:
    v : F32 <- two(1.5)
    IO.print("F32ROW min_rel = " ++ F32.show(v))
