# WORK FILE -- generated from `.agents/slop/blob-before-work.bend`. DELETE ME.
#
# `ops_blobbefore.bend` measures the ORIGINAL defect in `eq_arg.ABlob` on the PRISTINE
# tree (hash d662cccb800c287df24c8d91a8a6b2ba64d7c2b15133829f2457a6ec16174a7a): two
# BINARY nodes whose args have the SAME LENGTH land on the SAME arena index. It sits
# beside `ops.bend` because a scratch copy in another directory cannot resolve
# `import ./ops.bend`. It is deleted at the end of the unit.
import Base
import ./ops.bend as O

def blobbefore_len(a: O.Arg) -> U32:
  match a:
    case O.ABlob{n}: n
    case _: 0

# two BINARY nodes, arg lengths 4 and 4 -- the same length, and the pristine port has no
# way to tell them apart because `ABlob` carries only the length.
def blobbefore_same_len_idx() -> String:
  +a = O.UOp.new(O.Arena.empty(), O.OpsBINARY{}, Nil{}, O.ABlob{4}, O.TNone{})
  +b = O.UOp.new(O.Found.ar(a), O.OpsBINARY{}, Nil{}, O.ABlob{4}, O.TNone{})
  String.concat([U32.show(O.Found.i(a)), ",", U32.show(O.Found.i(b))])

# CONTROL: DIFFERENT lengths, which is the only pair the length key separates.
def blobbefore_diff_len_count() -> U32:
  +a = O.UOp.new(O.Arena.empty(), O.OpsBINARY{}, Nil{}, O.ABlob{4}, O.TNone{})
  +c = O.UOp.new(O.Found.ar(a), O.OpsBINARY{}, Nil{}, O.ABlob{2}, O.TNone{})
  U32.sub(O.Arena.next(O.Found.ar(c)), 1)

def blobbefore_same_len_count() -> U32:
  +a = O.UOp.new(O.Arena.empty(), O.OpsBINARY{}, Nil{}, O.ABlob{4}, O.TNone{})
  +b = O.UOp.new(O.Found.ar(a), O.OpsBINARY{}, Nil{}, O.ABlob{4}, O.TNone{})
  U32.sub(O.Arena.next(O.Found.ar(b)), 1)

# the arg round-trips as a LENGTH, which is all it ever was.
def blobbefore_arg_len() -> U32:
  +a = O.UOp.new(O.Arena.empty(), O.OpsBINARY{}, Nil{}, O.ABlob{4}, O.TNone{})
  blobbefore_len(O.Arena.arg(O.Found.ar(a), O.Found.i(a)))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["blobbefore_same_len_idx=", blobbefore_same_len_idx()]))
    IO.print(String.concat(["blobbefore_same_len_count=", U32.show(blobbefore_same_len_count())]))
    IO.print(String.concat(["blobbefore_diff_len_count=", U32.show(blobbefore_diff_len_count())]))
    IO.print(String.concat(["blobbefore_arg_len=", U32.show(blobbefore_arg_len())]))
    IO.print(String.concat(["blobbefore_eq_arg_4_4=", Bool.show(O.eq_arg(O.ABlob{4}, O.ABlob{4}))]))
    IO.print(String.concat(["blobbefore_eq_arg_4_2=", Bool.show(O.eq_arg(O.ABlob{4}, O.ABlob{2}))]))