import ../../../../probe_min.bend as M

def main() -> IO(Unit):
  do IO<Unit>:
    v : F32 <- M.two(1.5)
    IO.print("F32ROW min_M = " ++ F32.show(v))
