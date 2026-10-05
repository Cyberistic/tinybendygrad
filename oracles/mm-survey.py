#!/usr/bin/env python
# mm-survey.py -- MEASUREMENT ONLY. What does `UOp._min_max` actually answer, by
# op class, on device-free live UOps? Prints the root op, the dtype, the type NAME
# of each bound beside its value.
#
# This is the survey that decides the Bend representation: if every bound that
# appears is inside int32/float32, a U32/I64-pair port is honest; if int64 limits
# appear they are a named wall.
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, ParamArg           # noqa: E402
from tinygrad.uop import GroupOp                          # noqa: E402
from tinygrad import dtypes                               # noqa: E402
from tinygrad.uop.ops import shape_to_shape_arg, Invalid  # noqa: E402

i32 = dtypes.i32
u32 = dtypes.u32
f32 = dtypes.f32


def c(v, dt=i32):
  return UOp.const(v, dt)


def binop(op, a, b):
  return UOp(op, (a, b))


def show(tag, u):
  try:
    mm = u._min_max
  except Exception as e:
    print(f"{tag:16s} op={u.op.name:10s} RAISE {type(e).__name__}: {e}")
    return None
  ts = type(mm[0]).__name__ + "/" + type(mm[1]).__name__
  print(f"{tag:16s} op={u.op.name:10s} dt={u.dtype.name:8s} ty={ts:11s} ({mm[0]!r}, {mm[1]!r})")
  return mm


print("== GroupOp.Binary on two consts, int32 ==")
B = [Ops.ADD, Ops.SUB, Ops.MUL, Ops.AND, Ops.OR, Ops.XOR, Ops.SHL, Ops.SHR,
     Ops.CDIV, Ops.CMOD, Ops.FLOORDIV, Ops.FLOORMOD, Ops.MAX, Ops.CMPLT,
     Ops.CMPNE, Ops.CMPEQ]
for op in B:
  show(f"{op.name.lower()}_p", binop(op, c(12, i32), c(10, i32)))
print("-- negative second operand --")
for op in B:
  show(f"{op.name.lower()}_n", binop(op, c(12, i32), c(-10, i32)))
print("-- negative FIRST operand --")
for op in B:
  show(f"n_{op.name.lower()}", binop(op, c(-12, i32), c(10, i32)))
print("-- three sign quadrants on MUL/MAX/CMOD only --")
for op in [Ops.MUL, Ops.MAX, Ops.CMOD, Ops.FLOORDIV, Ops.FLOORMOD, Ops.CDIV]:
  show(f"nn_{op.name.lower()}", binop(op, c(-12, i32), c(-10, i32)))

print("== non-const (unbounded) srcs ==")
buf = UOp(Ops.BUFFER, (), ParamArg(0, i32, size=4))
bu = UOp(Ops.BUFFER, (), ParamArg(0, u32, size=4))
for op in B:
  show(f"buf_{op.name.lower()}", binop(op, buf, c(10, i32)))
print("-- with an unsigned buffer --")
for op in [Ops.MUL, Ops.ADD, Ops.CDIV, Ops.FLOORDIV, Ops.FLOORMOD, Ops.CMOD, Ops.MAX, Ops.CMPLT]:
  show(f"bu_{op.name.lower()}", binop(op, bu, c(10, u32)))

print("== range / special / stack / where / pad / movement ==")
show("range10", UOp.range(10, 0))
show("range0", UOp.range(0, 0))
show("special4", UOp(Ops.SPECIAL, (), ("4", 1)))
show("stack23", shape_to_shape_arg((2, 3)))
show("stack_sib", shape_to_shape_arg((2, 2)))
show("where", UOp(Ops.WHERE, (c(True, dtypes.bool), c(3, i32), c(-9, i32))))
show("pad", UOp(Ops.PAD, (c(3, i32), shape_to_shape_arg((2,)), c(0, i32), c(0, i32))))
show("pad_neg", UOp(Ops.PAD, (c(-3, i32), shape_to_shape_arg((2,)), c(0, i32), c(0, i32))))
show("reshape", UOp(Ops.RESHAPE, (buf, shape_to_shape_arg((2, 2))), ()))
show("permute", UOp(Ops.PERMUTE, (buf,), (1, 0)))
show("expand", UOp(Ops.EXPAND, (buf, shape_to_shape_arg((4, 4))), ()))
show("shrink", UOp(Ops.SHRINK, (buf, shape_to_shape_arg((2, 2))), ()))
show("flip", UOp(Ops.FLIP, (buf,), (0,)))
show("index", UOp(Ops.INDEX, (buf, c(2, i32), c(1, i32)), ()))
show("contig_back", UOp(Ops.CONTIGUOUS_BACKWARD, (buf, c(2, i32), c(1, i32), c(1, i32)), ()))

print("== cast ==")
show("i32_to_f32", c(3, i32).cast(f32))
show("i32_to_u32", c(-3, i32).cast(u32))
show("i32_to_i8", c(300, i32).cast(dtypes.i8))
show("i32_to_bool", c(3, i32).cast(dtypes.bool))
show("f32_to_i32", UOp(Ops.BUFFER, (), ParamArg(0, f32, size=4)).cast(i32))
show("u32_to_i32", UOp(Ops.BUFFER, (), ParamArg(0, u32, size=4)).cast(i32))
show("f32_cast_f32", buf.cast(f32))

print("== defines / param ==")
show("param_plain", UOp(Ops.PARAM, (), ParamArg(0, i32)))
show("param_vminmax", UOp(Ops.PARAM, (), ParamArg(0, i32, vmin=0, vmax=255)))

print("== floats ==")
for op in [Ops.ADD, Ops.MUL, Ops.MAX, Ops.FLOORDIV, Ops.FLOORMOD, Ops.CDIV, Ops.CMOD]:
  show(f"f32_{op.name.lower()}", binop(op, c(1.5, f32), c(2.5, f32)))
show("f32_const", c(1.5, f32))
show("f32_nan", UOp.const(float('nan'), f32))
show("f32_mulneg", binop(Ops.MUL, c(1.5, f32), c(-2.5, f32)))

print("== invalid ==")
show("invalid", UOp(Ops.CONST, (), (dtypes.bool, Invalid)))

print("== 64-bit: does the DEFAULT branch ever reach an i64 limit ==")
b64 = UOp(Ops.BUFFER, (), ParamArg(0, dtypes.i64, size=4))
bu64 = UOp(Ops.BUFFER, (), ParamArg(0, dtypes.u64, size=4))
show("buf64", b64)
show("buf64_add", binop(Ops.ADD, b64, c(3, dtypes.i64)))
show("buf64_mul", binop(Ops.MUL, b64, c(3, dtypes.i64)))
show("buf64_fdiv", binop(Ops.FLOORDIV, b64, c(3, dtypes.i64)))
show("buf64_cast32", b64.cast(i32))
show("buf32_cast64", buf.cast(dtypes.i64))
show("bu64", bu64)
show("bu64_cast32", bu64.cast(i32))
show("buf64_castf32", b64.cast(f32))

print("== mixed / chained ==")
show("mixed_add", binop(Ops.ADD, buf, bu))
show("mixed_mul", binop(Ops.MUL, buf, bu))
show("mixed_cmplt", binop(Ops.CMPLT, buf, bu))
show("chain", binop(Ops.MUL, binop(Ops.ADD, buf, c(1, i32)), binop(Ops.ADD, bu, c(2, u32))))

print("== what happens with a symbolic RANGE on the right ==")
r = UOp.range(10, 0)
for op in [Ops.MUL, Ops.CDIV, Ops.FLOORDIV, Ops.FLOORMOD, Ops.CMOD, Ops.MAX, Ops.ADD, Ops.SHL]:
  show(f"rng_{op.name.lower()}", binop(op, buf, r))

print("== widest bounds actually reached by the DEFAULT branch ==")
worst_lo, worst_hi = 0, 0
cases = []
for dt in [dtypes.i8, dtypes.i16, i32, dtypes.i64, u32, dtypes.u64, f32, dtypes.f16]:
  for v in [0, 1, -1, 7]:
    cases.append((dt, v))
for dt in [dtypes.i8, dtypes.i16, i32, dtypes.i64, u32, dtypes.u64, f32, dtypes.f16]:
  bb = UOp(Ops.BUFFER, (), ParamArg(0, dt, size=4))
  print(f"buffer({dt.name:8s}) = {bb._min_max!r}   min={dt.min!r} max={dt.max!r}")