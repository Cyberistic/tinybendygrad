# CAN A SHAPE DIM BE AN `O.SU` IN THIS ARENA? Every reader that could mint one is
# probed here. If none can, `count_of`'s `SU` arm is unreachable-by-construction and
# the M9 mutation is measuring an unreachable state, not a gap in the gate.
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/LAWS/spec.bend as S

def pa_sym() -> O.ParamArg:
  # `size` is `Maybe<&2, U32>` (ops.bend:699) with the comment "always a concrete int
  # (never symbolic)" -- so this is the ONLY spelling available and it is a count.
  O.ParamArg{0, S.int32(), Some{5}, None{}, None{}, None{}, S.AGlobal{}, None{},
    False{}, None{}, None{}, False{}, None{}}

def pa_plain() -> O.ParamArg:
  O.ParamArg{0, S.int32(), Some{4}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

# A `do IO<Unit>` BLOCK CANNOT BIND A TUPLE EITHER -- `(a, b) = probe()` is "expected
# a pattern" -- so the two `O.Found` values are read back INSIDE the printing def from
# the SAME pure call. `O.UOp.new` is pure given an arena (the arena carries the intern
# table), so the second call finds the node the first one added: the "call the pure
# function twice" form the notes record.
def sym_node() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{pa_sym()}, O.TNone{})

def plain_node() -> O.Found:
  O.UOp.new(O.Found.ar(sym_node()), O.OpsBUFFER{}, Nil{}, O.AParam{pa_plain()}, O.TNone{})

def show_sym() -> IO(Unit):
  IO.print(String.concat(["size=5, no vmin_vmax: n=", U32.show(O.Arena.next(O.Found.ar(sym_node())))]))

def show_plain() -> IO(Unit):
  IO.print(String.concat(["size=4, vmin_vmax Some:  n=", U32.show(O.Arena.next(O.Found.ar(plain_node())))]))

def main() -> IO(Unit):
  do IO<Unit>:
    show_sym()
    show_plain()
