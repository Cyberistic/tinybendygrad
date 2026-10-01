import Base
import ./../../tinybendygrad/helpers.bend as H
import ./../../tinybendygrad/tensor.bend as T
import ./../../tinybendygrad/LAWS/spec.bend as S
import ./../../tinybendygrad/uop/ops.bend as O

def ushow(xs: List<&2, U32>) -> String:
  List.show(&2, U32, U32.show, xs)

def itext(x: H.I64) -> String: H.i64_text(x)

def ishow(xs: List<&2, H.I64>) -> String:
  List.show(&2, H.I64, itext, xs)

def go() -> IO(Unit):
  do IO<Unit>:
    rev : List<&2, U32> = List.reverse(&2, U32, [1, 2, 3])
    IO.print(String.concat(["rev=", ushow(rev)]))
    i64 : List<&2, H.I64> = [H.i64_of_i32(4294967295), H.i64_of_i32(4294967294)]
    IO.print(String.concat(["i64=", ishow(i64)]))
    IO.print(String.concat(["f32sqrt=", F32.show(F32.sqrt(80.0))]))
    IO.print(String.concat(["f32pow=", F32.show(F32.pow(80.0, 0.5))]))
    IO.print(String.concat(["f32div=", F32.show(F32.div(1.0, F32.sqrt(80.0)))]))
    IO.print(String.concat(["f32div4=", F32.show(F32.div(1.0, F32.sqrt(4.0)))]))
    IO.print(String.concat(["m=skip"]))
    ar : O.Arena = O.Arena.empty()
    IO.print(String.concat(["ar_next=", U32.show(O.Arena.next(ar))]))
    IO.print(String.concat(["i64neg=", H.i64_text(H.i64_of_i32(4294967294))]))
    IO.print(String.concat(["i64add=", H.i64_text(H.i64_add(H.i64_of_i32(4294967294), H.i64_of_i32(2)))]))

def main() -> IO(Unit):
  go()
