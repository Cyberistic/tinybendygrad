import ./../../../tinybendygrad/helpers.bend as H
def main() -> IO(Unit):
  do IO<Unit>:
    x : Unit <- IO.print(U32.show(H.i64_of_i32(1)))
