# THE FLOAT-TO-INT CONVERSION PROBE. WHAT DOES `F32.to_u32` ACTUALLY DO?

#     ./bin/bend .agents/slop/vslane/f32int.bend
#
# `symbolic.bend`'s FLOAT LANE NEEDS THE INTEGER VALUE OF A FLOAT (`int(x)`, WHICH
# TRUNCATES TOWARD ZERO) FOR THE CAST, AND `Base`'s `F32.to_u32` IS THE ONLY
# FLOAT-TO-INTEGER PRIMITIVE THE PORT HAS. WHAT IT DOES IS NOT DOCUMENTED IN
# `references/bend/bend2/base.bend` -- IT IS A `law` -- SO IT IS MEASURED HERE.

import ../../../tinybendygrad/helpers.bend as H
import ../../../tinybendygrad/uop/ops.bend as O

def pu(nm: String, +v: U32) -> IO(Unit):
  IO.print(String.concat([nm, " = ", U32.show(v)]))

def pf(nm: String, +v: F32) -> IO(Unit):
  IO.print(String.concat([nm, " = ", U32.show(F32.bits(v)), " (", F32.show(v), ")"]))

def main() -> IO(Unit):
  do IO<Unit>:
    pu("to_u32(1.5)", F32.to_u32(1.5))
    pu("to_u32(2.5)", F32.to_u32(2.5))
    pu("to_u32(abs(2.5))", F32.to_u32(F32.abs(F32.neg(2.5))))
    pu("to_u32(abs(3.5))", F32.to_u32(F32.abs(F32.neg(3.5))))
    pu("to_u32(-1.0)", F32.to_u32(F32.neg(1.0)))
    pu("to_u32(-2.0)", F32.to_u32(F32.neg(2.0)))
    pu("to_u32(-0.5)", F32.to_u32(F32.neg(0.5)))
    pu("to_u32(0.0)", F32.to_u32(0.0))
    pu("to_u32(4294967295.0)", F32.to_u32(4294967295.0))
    pu("to_u32(4294967297.0)", F32.to_u32(4294967297.0))
    pf("abs(-2.5)", F32.abs(F32.neg(2.5)))
    pu("to_u32(abs(-2.5))", F32.to_u32(F32.abs(F32.neg(2.5))))
