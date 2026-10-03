import Base
import ./uop/ops.bend as O
import ./uop/render.bend as R

# P1: is `+` spellable on a TUPLE destructuring binder?
def p1(u: U32, p: (O.Arena & Map<&2, U32>)) -> (O.Arena & U32 & Map<&2, U32>):
  (ar, +m) = p
  (ar, R.cu32(m, u), m)

def main() -> IO(Unit):
  a0 = O.Arena.empty()
  +p0 = O.UOp.new(a0, O.OpsPARAM{}, Nil{}, O.ABad{}, O.TNone{})
  m0 = Map.new(&2, U32)
  IO.print(U32.show(O.Found.i(p1(4, (O.Found.ar(p0), m0)))))