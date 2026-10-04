import ./../../../tinybendygrad/LAWS/spec.bend as S
def main() -> IO(Unit):
  do IO<Unit>:
    x : Unit <- IO.print(S.Dt.pri(S.int32()).show)
