#!/usr/bin/env python3
"""ew_activation-oracle.py -- THE CPYTHON LANE of the activation comparison.

    .venv/bin/python gates/ew_activation-oracle.py <port-rows> > cpython.rows

IT READS THE PORT'S ROWS AND ANSWER THE SAME QUESTIONS.  The port's row is

    M <name> <alpha|-> <gamma|-> <fixture f32 bits>

and the fixture's f32 BITS are the only thing the oracle needs to build CPython's
tensor -- so THE FIXTURE LIST LIVES IN THE PORT'S DRIVER (`gates/ew_activation.bend`)
and there is no second list to keep in step.  A fixture the two lanes disagree about
shows up as a CONSTANT-BIT difference in the diff, which is a loud failure and not a
quiet one.

WHAT IT PRINTS, per row:

    M <name> <alpha|-> <gamma|-> <fixture f32 bits>       CPython's graph header
    R <root id>                                            the root's toposort position
    <id> <op> <dtype> <arg> <src ids...>                   CPython's nodes
    V <name> <alpha|-> <gamma|-> <fixture f32 bits> <f32 bits> <repr>   CPython's value

THE NODE SPELLING IS THE PORT'S: the OP, the DTYPE (`spec.bend`'s names -- CPython's
`float32` is mapped onto `f32`), the ARGUMENT (`cf:<f32 bits>` for a float constant,
`ci:<hi>:<lo>` for an integer one, `cb:True` for a boolean one, `dt:<dtype>` for a
CAST's target, `-` for a node with no argument) and the srcs IN SLOT ORDER.  THE IDS
ARE THE TOPOSORT POSITIONS and the port's are ARENA INDICES, which is why the
comparison is CANONICAL and not positional.

THE CONSTANTS ARE COMPARED AS f32 BITS AND NOT AS DECIMALS, because the port has no
F64: CPython's `math.pi / 2` is a DOUBLE and the port's is an f32, and the two are
the same NUMBER only after the rounding.  Comparing the decimals would say they
differ; comparing the bits says what the graph actually computes.

THE VALUE IS MEASURED, NOT ASSERTED: it is `Tensor(...).<method>(...).numpy()` on the
PYTHON device, so it is tinygrad's own arithmetic on tinygrad's own graph.

THIS IS CPYTHON'S OWN `tinygrad/mixin/elementwise.py` AT THE PIN IN THIS TREE, and
not a re-implementation of it: the method is CALLED, and the graph is read back out
of the UOp the call built.  `gates/ew_activation-compare.py` rebuilds the port's own
dump as tinygrad UOps for the same reason -- an oracle that re-implements
`Tensor.asin` agrees with a port that is ITSELF wrong.
"""
import struct
import sys

from tinygrad.dtype import dtypes
from tinygrad.tensor import Tensor
from tinygrad.uop.ops import Ops, UOp

DTNAME = {"float32": "f32", "float16": "f16", "float64": "f64", "int32": "i32",
          "int8": "i8", "uint8": "u8", "int64": "i64", "uint32": "u32", "bool": "bool",
          "weakint": "weakint", "weakfloat": "weakfloat"}


def f32bits(x) -> int:
  return struct.unpack("I", struct.pack("f", float(x)))[0]


def frombits(b: int) -> float:
  return struct.unpack("f", struct.pack("I", b))[0]


def i64words(v: int) -> str:
  return f"{(v >> 32) & 0xFFFFFFFF}:{v & 0xFFFFFFFF}"


def dtname(dt) -> str:
  return DTNAME.get(dt.name, dt.name)


def argstr(u: UOp) -> str:
  if u.op is Ops.CONST:
    v = u.arg
    if isinstance(v, bool):
      return "cb:" + ("True" if v else "False")
    if isinstance(v, int):
      return "ci:" + i64words(v)
    return "cf:" + str(f32bits(float(v)))
  if u.op is Ops.CAST:
    return "dt:" + dtname(u.arg)
  return "-"


def dump(u: UOp):
  ts = list(u.toposort())
  idx = {id(x): i for i, x in enumerate(ts)}
  return [(i, x.op.name, dtname(x.dtype), argstr(x), [idx[id(s)] for s in x.src]) for i, x in enumerate(ts)]


def method(t: Tensor, name: str, alpha, gamma):
  """THE CPython METHOD, CALLED WITH THE PORT'S PARAMETERS.

  `alpha` and `gamma` arrive as f32 BITS, and the value handed to CPython is the
  DOUBLE nearest those bits -- so CPython's constant has the same f32 as the port's,
  and the two graphs carry the same CONST.
  """
  a = frombits(int(alpha)) if alpha != "-" else None
  g = frombits(int(gamma)) if gamma != "-" else None
  if name == "asin":
    return t.asin()
  if name == "acos":
    return t.acos()
  if name == "atan":
    return t.atan()
  if name in ("elu", "elu_alpha"):
    return t.elu(a)
  if name in ("celu", "celu_alpha"):
    return t.celu(a)
  if name in ("selu", "selu_alpha"):
    return t.selu(a, g)
  if name == "relu":
    return t.relu()
  if name == "sigmoid":
    return t.sigmoid()
  if name == "tanh":
    return t.tanh()
  if name == "quick_gelu":
    return t.quick_gelu()
  if name == "swish":
    return t.swish()
  if name == "silu":
    return t.silu()
  raise KeyError(name)


def main(argv):
  if len(argv) != 2:
    print("usage: ew_activation-oracle.py <port-rows>", file=sys.stderr)
    return 2
  rows = [l for l in open(argv[1]).read().splitlines() if l.startswith("M ")]
  for r in rows:
    _, nm, alpha, gamma, fx = r.split(" ")
    t = Tensor(UOp.const(frombits(int(fx)), dtypes.weakfloat), device="PYTHON")
    out = method(t, nm, alpha, gamma)
    nodes = dump(out._uop)
    print(f"M {nm} {alpha} {gamma} {fx}")
    print(f"R {len(nodes) - 1}")
    for i, op, dt, arg, srcs in nodes:
      print(f"{i} {op} {dt} {arg} " + " ".join(str(s) for s in srcs))
    v = float(out.numpy().reshape(-1)[0])
    print(f"V {nm} {alpha} {gamma} {fx} {f32bits(v)} {v!r}")
  return 0


if __name__ == "__main__":
  sys.exit(main(sys.argv))
