import Base
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F

def val(m: Maybe<&2, O.Sint>) -> H.I64:
  match m:
    case Some{O.SI{i}}: i
    case _: H.i64_of_i32(0)

# `sized` walks its input with `List.append` and finishes with `List.reverse`, the
# SAME shape `srcs.go` has. `List.append` is order preserving, so if `sized` answers
# (3,2) for the input (2,3) it is reversed-on-arrival too, and every positional
# reader over it (`List.last` in is_image_shape, `drop_n` in reduce_dims,
# `bitcast_dims`' last) reads the wrong end.
def show(tag: String, +ds: List<&2, O.Sint>) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([tag,
      " len=", U32.show(U32.from_nat(List.length(&2, O.Sint, ds))),
      " head=", H.i64_text(val(List.head(&2, O.Sint, ds))),
      " last=", H.i64_text(val(List.last(&2, O.Sint, ds)))]))

def sized_line() -> IO(Unit):
  show("sized([2,3])    ", F.Sized.s(F.sized([F.sint_of(2), F.sint_of(3)])))

# and `marg` over g_resh23's STACK(2,3): the shape the reshape ARG carries, built by
# `marg.stack.go`, which appends in order and does NOT reverse
def marg_show(m: Maybe<&2, List<&2, O.Sint>>) -> IO(Unit):
  match m:
    case Some{ds}: show("marg(STACK2,3)", ds)
    case None{}: IO.print("marg = None")

def marg_line(x: F.Folded) -> IO(Unit):
  marg_show(F.marg(F.Folded.ar(x), 3))

def p23() -> F.Folded:
  F.folded(O.Found.ar(F.g_resh23()))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- sized_line()
    b : Unit <- marg_line(p23())
    c : Unit <- IO.print("")
    IO.print("")