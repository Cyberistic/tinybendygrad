import Base
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F

def val(m: Maybe<&2, O.Sint>) -> H.I64:
  match m:
    case Some{O.SI{i}}: i
    case _: H.i64_of_i32(0)

def hx.go(+ds: List<&2, O.Sint>) -> String:
  match ds:
    case Nil{}: String.concat([""])
    case h <> t: String.concat([H.i64_text(val(Some{h})), " ", hx.go(t)])

def hx(m: Maybe<&2, List<&2, O.Sint>>) -> String:
  match m:
    case Some{+ds}: hx.go(ds)
    case None{}: String.concat(["NONE"])

# helpers.py:37 `is_image_shape`. CPython: (32,32,4) True, (4,32,32) False
def img_line() -> IO(Unit):
  do IO<Unit>:
    +ds: List<&2, O.Sint> = List.append(&2, O.Sint,
      List.append(&2, O.Sint, [F.sint_of(32)], [F.sint_of(32)]), [F.sint_of(4)])
    +dx: List<&2, O.Sint> = List.append(&2, O.Sint,
      List.append(&2, O.Sint, [F.sint_of(4)], [F.sint_of(32)]), [F.sint_of(32)])
    IO.print(String.concat(["is_image_shape (32,32,4)=",
      Bool.show(F.is_image_shape(Some{ds})), " want True    ",
      Bool.show(F.is_image_shape(Some{dx})), " want False   (python: True False)"]))

# ops.py BITCAST `_shape` arm: `ps[:-1]+((ps[-1]*input_sz)//output_sz,)`, or the
# RuntimeError when it does not divide. CPython: ([2,6],8,4) -> (2,3); ([3],8,4) raises
def bc_line() -> IO(Unit):
  do IO<Unit>:
    +ds: List<&2, O.Sint> = [F.sint_of(2), F.sint_of(6)]
    +o: List<&2, O.Sint> = [F.sint_of(3)]
    IO.print(String.concat(["bitcast_dims([2,6],8,4)=", String.concat([hx(F.bitcast_dims(Some{ds}, 8, 4)), "  want 2 3      "]),
      "bitcast_dims([3],8,4)=", String.concat([hx(F.bitcast_dims(Some{o}, 8, 4)), "  want NONE"])]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- img_line()
    b : Unit <- bc_line()
    IO.print("")
