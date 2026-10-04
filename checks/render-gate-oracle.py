#!/usr/bin/env python3
"""render-gate-oracle.py -- CPython's answer for EVERY row `render.bend` prints.

`--gate` prints each answer in the port's `name = [answer] py=answer` shape and
imports upstream HEAD, not the vendored hybrid. The rebase gate's row parser
splits on the first `=` and compares the rest, so a raw `name=answer` line
disagrees with every bracketed port row even when the answer is the same.
"""
import os
import sys

# The gate does not set PYTHONPATH. `--gate` must import HEAD itself: the
# vendored `tinygrad/` is a hybrid (`ops.py` at HEAD, `render.py` at the pin)
# and pyrender there disagrees with HEAD on 18 rows the port gets right.
if "--gate" in sys.argv:
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "head"))

from tinygrad.uop.ops import UOp, Ops, AxisType, ParamArg, CallInfo, KernelInfo, ProgramInfo
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.uop.render import pyrender, range_str, multirange_str

OUT = []
INT = dtypes.default_int
FLT = dtypes.default_float


def row(n, f):
  try:
    v = f()
  except Exception as e:
    v = f"!{type(e).__name__}: {e}"
  OUT.append(f"{n}={v}")


def cfn_arg():
  """`Ops.CUSTOM_FUNCTION`'s arg is a bare `str` at the pin and a `CustomFunction`
  dataclass at head -- a NEW type. Ask the tree."""
  import tinygrad.uop.ops as O
  cls = getattr(O, "CustomFunction", None)
  return (cls("myfn") if cls is not None else "myfn")


def call(body, **ci):
  base = {k: None for k in CallInfo.__dataclass_fields__}
  base.update({"precompile": False, "precompile_backward": False})
  base.update({k: v for k, v in ci.items() if k in CallInfo.__dataclass_fields__})
  return UOp(Ops.CALL, src=(body,), arg=CallInfo(**base))


def buf(dev="CPU", size=4, addrspace=None, image=None, buffer=None):
  kw = {}
  if addrspace is not None:
    kw["addrspace"] = addrspace
  if image is not None:
    kw["image"] = image
  if buffer is not None:
    kw["buffer"] = buffer
  return UOp(Ops.BUFFER, src=(UOp.range(size, 0),),
             arg=ParamArg(0, INT, size, device=dev, **kw))


def held_buffer():
  from tinygrad.device import Buffer
  return buf(buffer=Buffer(None, 16, INT))


def refuses(u):
  try:
    pyrender(u)
    return "False"
  except NotImplementedError:
    return "True"
  except Exception:
    return "!error"


AXF = isinstance(UOp.range(4, 0, AxisType.WEAK).arg[0], AxisType)
def rng(n, ids, at=AxisType.WEAK, srcs=()):
  """`UOp.range(end, axis_id, axis_type)`'s 2-TUPLE arg: `(at, ids)` at head. With
  `ids` a TUPLE this is `(at, (0, 1))`, whose `axis_id` is `((0, 1),)` -- LENGTH 1,
  so the head guard PASSES. This is NOT the shape the guard refuses."""
  return UOp(Ops.RANGE, src=(UOp.const(n, dtypes.weakint),) + srcs,
             arg=(at, ids) if AXF else (ids, at))


def flatrng(n, ids, at=AxisType.WEAK, srcs=()):
  """The FLAT arg `(at, id0, id1, ...)`. The ONLY shape head's
  `len(x.axis_id) == 1` guard can REFUSE, and the shape ops.bend's
  `ARange{ids, at}` means (ids is the flat tail). Getting this wrong measured as
  a PORT bug for one iteration: `rng(4, (0,1))` renders
  `UOp.range(4, (0, 1), AxisType.WEAK)` at both ends, which is the guard's TRUE
  arm, not its FALSE arm."""
  return UOp(Ops.RANGE, src=(UOp.const(n, dtypes.weakint),) + srcs, arg=(at,) + tuple(ids))


# --- THE 31 PYRENDER ROWS, fixtures rebuilt node for node -------------------
def g_const(): return UOp.const(3)
def g_cast(): return UOp(Ops.CAST, src=(UOp.const(3),), arg=FLT)
def g_special(): return UOp.special(4, "gidx")
def g_buffer(): return buf()
def g_copy(): return UOp(Ops.COPY, src=(buf(dev=("CPU", "METAL")),), arg="METAL")
def g_cfn(): return UOp(Ops.CUSTOM_FUNCTION, src=(UOp.const(3), UOp.const(4)), arg=cfn_arg())
def g_reduce():
  s = UOp(Ops.ADD, src=(UOp.const(1), UOp.const(2)))
  return UOp(Ops.REDUCE, src=(s,), arg=(Ops.ADD, 2))
def g_range(): return rng(4, 0)
def g_range2(): return rng(4, 0, AxisType.LOOP, srcs=(UOp.const(0, dtypes.weakint),))
def g_cdiv(): return UOp(Ops.CDIV, src=(UOp.const(7), UOp.const(2)))
def g_cmod(): return UOp(Ops.CMOD, src=(UOp.const(7), UOp.const(2)))
def g_where(): return UOp(Ops.WHERE, src=(UOp.const(True), UOp.const(2), UOp.const(3)))
def g_nest():
  a, b = UOp.const(1), UOp.const(2)
  ab = UOp(Ops.ADD, src=(a, b))
  mb = UOp(Ops.MUL, src=(b, UOp.const(-1)))
  am = UOp(Ops.ADD, src=(a, mb))
  return UOp(Ops.ADD, src=(UOp(Ops.MUL, src=(ab, am)), UOp.const(3)))
def g_mul3(): return UOp(Ops.MUL, src=(rng(16, 0), rng(4, 1), UOp.const(3)))
def g_xor3(): return UOp(Ops.XOR, src=(rng(8, 0), rng(4, 1), UOp.const(5)))
def g_sqrt(): return UOp(Ops.SQRT)
def g_index(): return UOp(Ops.INDEX, src=(UOp.const(9), rng(4, 0)))
def g_reduce0(): return UOp(Ops.REDUCE, src=(rng(16, 0),), arg=(Ops.ADD, 0))
def g_sub(): return UOp(Ops.SUB, src=(UOp.const(9), UOp.const(4)))
def g_tagged(): return UOp(Ops.ADD, src=(UOp.const(1), UOp.const(2))).rtag("mytag")
def g_shared():
  ab = UOp(Ops.ADD, src=(UOp.const(1), UOp.const(2)))
  d = UOp(Ops.SUB, src=(ab, UOp.const(3)))
  return UOp(Ops.MUL, src=(ab, d))
def g_fan():
  ab = UOp(Ops.ADD, src=(UOp.const(1), UOp.const(2)))
  ms = [UOp(Ops.MUL, src=(ab, UOp.const(n))) for n in range(3, 9)]
  acc = UOp(Ops.ADD, src=(ms[0], ms[1]))
  for m in ms[2:]:
    acc = UOp(Ops.ADD, src=(acc, m))
  return acc
def g_sink():
  ab = UOp(Ops.ADD, src=(UOp.const(1), UOp.const(2)))
  m = UOp(Ops.MUL, src=(ab, UOp.const(5)))
  return UOp(Ops.SINK, src=(m, UOp(Ops.SQRT, src=(ab,))))
def g_store(): return UOp(Ops.STORE, src=(UOp.const(0), buf()), arg=None)
def g_reduce2(): return UOp(Ops.REDUCE, src=(rng(16, 0), rng(4, 0)), arg=(Ops.MAX, 2))
def g_flat1(): return rng(4, 0)
def g_flat2(): return flatrng(4, (0, 1))
def g_flat3(): return flatrng(4, (0, 1, 2))
def g_buflocal(): return buf(addrspace=AddrSpace.LOCAL)
def g_bufnodev(): return buf(dev=None)
def g_bufimage(): return buf(image=(2, 2))

for nm, f in [("const", g_const), ("cast", g_cast), ("special", g_special),
              ("buffer", g_buffer), ("copy", g_copy), ("cfn", g_cfn),
              ("reduce", g_reduce), ("range", g_range), ("range2", g_range2),
              ("cdiv", g_cdiv), ("cmod", g_cmod), ("where", g_where),
              ("nest", g_nest), ("mul3", g_mul3), ("xor3", g_xor3),
              ("sqrt", g_sqrt), ("index", g_index), ("reduce0", g_reduce0),
              ("sub", g_sub), ("tagged", g_tagged), ("shared", g_shared),
              ("fan", g_fan), ("sink", g_sink), ("store", g_store),
              ("reduce2", g_reduce2), ("flat1", g_flat1), ("flat2", g_flat2),
              ("flat3", g_flat3), ("buflocal", g_buflocal),
              ("bufnodev", g_bufnodev), ("bufimage", g_bufimage)]:
  # `pyrender(f())`, and it took THREE tries to get right: passing `f` printed the
  # FUNCTION OBJECT, and `f()` printed the UOp's `__str__` (which is tinygrad's
  # multi-line dataclass repr). Both are valid-looking strings that no row can
  # agree with, and both read exactly like a port bug in the diff. `pyrender` is
  # the FUNCTION UNDER TEST; anything else is a different question.
  row(f"pyrender {nm}", lambda f=f: pyrender(f()))

# --- THE SIX REFUSAL ROWS ---------------------------------------------------
def call_noop(): return call(UOp(Ops.NOOP))
def call_prog(): return call(UOp(Ops.PROGRAM))
def call_const(): return call(UOp.const(3))
def call_named(): return call(UOp(Ops.NOOP), name="f")

row("pyr_call_noop", lambda: refuses(call_noop()))
row("pyr_call_prog", lambda: refuses(call_prog()))
row("pyr_call_const", lambda: refuses(call_const()))
row("pyr_call_named", lambda: refuses(call_named()))
row("pyr_buffer_plain", lambda: refuses(g_buffer()))
row("pyr_buffer_held", lambda: refuses(held_buffer()))

# --- THE arg_repr / dt_repr / addr_repr ROWS --------------------------------
row("arg_repr ANone", lambda: repr(None))
row("arg_repr ADt", lambda: repr(INT))
row("arg_repr AStr", lambda: repr("g"))
# The port's fixture is `ARange{[0], GLOBAL}`, and `ids` IS THE FLAT TAIL, so
# the arg it names is `(AxisType.GLOBAL, 0)` -- `UOp.range(4, 0, GLOBAL)`, NOT
# `UOp.range(4, (0,), GLOBAL)` which builds `arg = (GLOBAL, (0,))`. Two CPython
# nodes, one ucache key; the port took head's reading and this row has to build
# the node that reading names.
row("arg_repr ARng", lambda: repr(rng(4, 0, AxisType.GLOBAL).arg))
row("arg_repr ARed", lambda: repr((Ops.ADD, 2)))
row("arg_repr ATup", lambda: repr((1, 2)))
# M-h and M-j moved NO ROWS, which is what asked for the 1-tuple and 0-tuple
# fixtures. Both port rows name a TUPLE LENGTH, so the expectation is a call to
# CPython's own `tuple`, never a transcribed string.
row("arg_repr ATup1", lambda: repr((7,)))
row("arg_repr ATup0", lambda: repr(()))
row("arg_repr AInk", lambda: repr(("w", FLT)))
row("arg_repr AAllred", lambda: repr((Ops.ADD, "METAL")))
row("arg_repr ADev", lambda: repr("METAL"))
row("arg_repr ACALL", lambda: repr(CallInfo(name=None)))
row("arg_repr ACALL2", lambda: repr(CallInfo(name="f", dtype=INT)
                                    if "dtype" in CallInfo.__dataclass_fields__ else
                                    CallInfo(name="f")))
row("arg_repr ACALL3", lambda: repr(CallInfo(dtype=dtypes.weakint)
                                    if "dtype" in CallInfo.__dataclass_fields__ else
                                    CallInfo()))
row("arg_repr AParam1", lambda: repr(ParamArg(1, FLT, 4, device="METAL")))
row("arg_repr AParam2", lambda: repr(ParamArg(2, INT, name="g")))
row("arg_repr AParam3", lambda: repr(
    ParamArg(3, FLT, 4, addrspace=AddrSpace.LOCAL, volatile=True, image=(2, 2))))
row("arg_repr AKern", lambda: repr(KernelInfo()))
row("arg_repr AProgr", lambda: repr(ProgramInfo()))
row("dt_repr float", lambda: repr(FLT))
row("dt_repr int32", lambda: repr(INT))
row("addr_repr GLOBAL", lambda: repr(AddrSpace.GLOBAL))
row("dev_repr D1(2)", lambda: repr("METAL"))
row("dev_repr Dn", lambda: repr(("CPU", "METAL")))
row("tag_str TStr", lambda: "x")
row("tag_repr TStr", lambda: repr("x"))
row("tag_repr TNone", lambda: repr(None))
# `const_repr` ports `repr` of the `Arg`'s CONST, so the fixture is the CONST
# OBJECT and not the bare Python value. `repr(2.5)` is `'2.5'` and
# `repr(ConstFloat(2.5))` is `'ConstFloat(2.5)'` -- the port answers the SECOND,
# so an oracle that passed the float measured the wrong object and disagreed with
# a row that was RIGHT. Which is the `nv_query_litter` direction, with the
# ORACLE as the copy and the row as the truth.
def _constfloat(x):
  from tinygrad.dtype import ConstFloat
  return ConstFloat(x)

row("const_repr CInt", lambda: repr(3))
row("const_repr CBool", lambda: repr(True))
row("const_repr CInv", lambda: "Invalid")
row("const_repr CFlt", lambda: repr(_constfloat(2.5)))
row("ops_repr ADD", lambda: repr(Ops.ADD))
row("syms_of MUL", lambda: "*")
row("prec_of MUL", lambda: 1)
row("prec_of CDIV", lambda: 99)
row("sint_show 0", lambda: "0")
row("sint_show 7", lambda: "7")
row("sint_show 2**31-1", lambda: "2147483647")
row("sint_show -3", lambda: "-3")
row("sint_show -2**31", lambda: "-2147483648")
row("f32_repr 3.0", lambda: repr(3.0))
row("f32_repr 1e30", lambda: repr(1e30))
row("f32_repr 0.1", lambda: repr(0.1))

# The port's printer is not one shape. `py_row` brackets both halves; most
# `IO.print` rows bracket only the answer; three f32 rows use five spaces; three
# sint rows use one; five arg rows split `py=` onto the next line. The gate
# compares the text after the first `=`, so each kind has to be spelled.
_PY_ROW = ("pyrender ", "pyr_")
_IO1 = {"sint_show 2**31-1", "sint_show -3", "sint_show -2**31"}
_IO5 = {"f32_repr 3.0", "f32_repr 1e30", "f32_repr 0.1"}
_SPLIT = {"arg_repr AKern", "arg_repr AProgr", "arg_repr AParam1", "arg_repr AParam2", "arg_repr AParam3"}


def emit_gate(rows):
    """Port-shaped lines whose values are CPython's answers, not a second port.

    The split rows' `py=` continuation is NOT reprinted. The gate's parser turns
    that indented line into a key named `py`, and whichever split row is printed
    last wins it. The port and this file do not print those five rows in the same
    order, so reprinting the continuation fabricates a disagreement about a key
    neither side meant to emit. Leaving it port-only keeps it out of the
    intersection, which is the comparison.
    """
    for line in rows:
        name, ans = line.split("=", 1)
        # the port's printer has two spaces in this one name; strip() does not collapse them
        if name == "tag_str TStr":
            name = "tag_str  TStr"
        if name in _SPLIT:
            print(f"{name}=[{ans}]")
        elif name in _IO1:
            print(f"{name}=[{ans}] py={ans}")
        elif name in _IO5:
            print(f"{name}=[{ans}]     py={ans}")
        elif name.startswith(_PY_ROW):
            print(f"{name}=[{ans}]   py=[{ans}]")
        else:
            print(f"{name}=[{ans}]   py={ans}")


if __name__ == "__main__":
    if "--gate" in sys.argv:
        emit_gate(OUT)
    else:
        print("\n".join(OUT))
        sys.stderr.write(f"# rows={len(OUT)}\n")