import Base
import ./substrate.bend as Sub

def t_const_bool_int_splits() -> Bool:
  +u = UOp.new(Arena.empty(), OpsCONST{}, Nil{}, CBool{True{}}, TNone{})
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["port=", Bool.show(Sub.answer())]))
