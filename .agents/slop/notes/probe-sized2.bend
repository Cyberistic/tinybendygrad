import Base
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F

def val(m: Maybe<&2, O.Sint>) -> H.I64:
  match m:
    case Some{O.SI{i}}: i
    case _: H.i64_of_i32(0)

def show(tag: String, +ds: List<&2, O.Sint>) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([tag,
      " head=", H.i64_text(val(List.head(&2, O.Sint, ds))),
      " last=", H.i64_text(val(List.last(&2, O.Sint, ds)))]))

def show_sized(tag: String, +ds: List<&2, O.Sint>) -> IO(Unit):
  show(tag, F.Sized.s(F.sized(ds)))

def show_pad(tag: String, +ds: List<&2, O.Sint>) -> IO(Unit):
  show(tag, F.Sized.s(F.pad_to(F.sized(ds), 3n)))

# Python: `(1,)*(max_dim-len(s))+s` -- pad_to(2,3) is [1,2,3]. Reversed is [3,2,1].
def pad_line() -> IO(Unit):
  show_pad("pad_to([2,3],3)", [F.sint_of(2), F.sint_of(3)])

# Python helpers.py:37 `is_image_shape`: `len(shape)==3 and shape[-1]==4`.
# The image shape is (4,32,32): LAST is 32, so Python says False. A reversed
# list answers the FIRST dim, 4, so the port says True.
def img_line() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["is_image_shape((4,32,32))=",
      Bool.show(F.is_image_shape(Some{List.append(&2, O.Sint, List.append(&2, O.Sint, [F.sint_of(4)], [F.sint_of(32)]), [F.sint_of(32)])})),
      " (python: False)"]))

def sized_line() -> IO(Unit):
  show_sized("sized([2,3])      ", [F.sint_of(2), F.sint_of(3)])

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- sized_line()
    b : Unit <- pad_line()
    c : Unit <- img_line()
    d : Unit <- IO.print("")
    IO.print("")