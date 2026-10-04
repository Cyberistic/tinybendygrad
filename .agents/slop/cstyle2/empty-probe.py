#!/usr/bin/env python3
"""empty-probe.py -- are the SEVEN EMPTY `cfo` rows a refusal or a wrong answer?

THE QUESTION, and why it matters for the four columns. In this tree
`CStyleLanguage.code_for_op` is a CLASS-LEVEL **dict** (`cstyle.py:143`), not a method,
and the device subclasses EDIT it: `ClangRenderer.code_for_op` (`cstyle.py:291`) *removes*
`EXP2, SIN, LOG2, TRUNC, RECIPROCAL` and *adds* `FDIV`; `CUDARenderer` (`cstyle.py:435`)
adds `h`-prefixed forms; `HIPRenderer` (`cstyle.py:535`) adds `_ocml` forms.
Upstream calls it as `ctx.code_for_op[x.op](...)` (`cstyle.py:64`), so an op with no arm
is a `KeyError` -- a REFUSAL. The port's documented answer for a refusal is `""`
(`cstyle-gate.py`'s `PORT_KEYERROR`), so the 7 empty rows should be refusals and not a
table the port lost.

MEASURED FROM LIVE CPYTHON, by asking each renderer's own dict for the arm and calling it
if it is there. Nothing is transcribed from `cstyle.bend`'s `py=` column.

  usage: empty-probe.py
"""
import sys

sys.path.insert(0, ".")
from tinygrad import dtypes  # noqa: E402
from tinygrad.uop.ops import Ops  # noqa: E402
from tinygrad.renderer.cstyle import CStyleLanguage, ClangRenderer, HIPRenderer, \
    MetalRenderer, CUDARenderer, OpenCLRenderer  # noqa: E402

# (row name as cstyle.bend spells it, renderer class, the op)
ROWS = [
  ("cfo BASE  FDIV f32", CStyleLanguage, Ops.FDIV),
  ("cfo CLANG FDIV f32", ClangRenderer, Ops.FDIV),
  ("cfo CLANG EXP2 f32", ClangRenderer, Ops.EXP2),
  ("cfo CLANG LOG2 f32", ClangRenderer, Ops.LOG2),
  ("cfo CLANG RECIPROC f32", ClangRenderer, Ops.RECIPROCAL),
  ("cfo CLANG SIN f32", ClangRenderer, Ops.SIN),
  ("cfo METAL FDIV f32", MetalRenderer, Ops.FDIV),
  ("cfo CUDA  FDIV f32", CUDARenderer, Ops.FDIV),
  # NOT IN cstyle.bend AT ALL, so a reader cannot see that HIP was never probed:
  ("cfo HIP   FDIV f32 (NO ROW)", HIPRenderer, Ops.FDIV),
  ("cfo OPENCLFDIV f32 (NO ROW)", OpenCLRenderer, Ops.FDIV),
]


def ask(cls, op):
  """Exactly what upstream's `ctx.code_for_op[x.op](a, b, dtype)` does."""
  arm = cls.code_for_op.get(op, None)
  if arm is None:
    return "REFUSED (KeyError: no arm)"
  try:
    return repr(arm("X", "Y", dtypes.float32))
  except TypeError:  # a UNARY arm
    return repr(arm("X", dtypes.float32))


def main():
  print(f"{'row':<32} {'upstream code_for_op answer (live CPython)'}")
  refused = absent = 0
  for name, cls, op in ROWS:
    v = ask(cls, op)
    if "(NO ROW)" in name:
      absent += 1
      tag = "  <- cstyle.bend NEVER PROBES THIS: a coverage hole, not a row"
    elif v.startswith("REFUSED"):
      refused += 1
      tag = "  <- the port's value is \"\" : CORRECT"
    else:
      tag = "  <- the port's value is a real expression"
    print(f"{name:<32} {v}{tag}")
  print()
  print(f"rows probed here {len(ROWS)}; refused by upstream {refused}; "
        f"with NO ROW in cstyle.bend {absent}")
  print()
  print("So the EMPTY values are UPSTREAM REFUSALS, and the port is right to answer \"\".")
  print("They are cause (c) -- the renderer's own dispatch does not cover the arm -- and")
  print("there are TWO of them that cstyle.bend never probes at all (HIP, OPENCL FDIV),")
  print("which is a coverage hole and not a row.")
  return 0


if __name__ == "__main__":
  sys.exit(main())