#!/usr/bin/env python3
"""shader-oracle.py -- the CPython side of `shader.bend`: the GRAPH and the VALUES.

    .venv/bin/python shaders/shader-oracle.py            # rows: the graph, node for node
    .venv/bin/python shaders/shader-oracle.py --values   # a circle, as numbers

TWO LANES AND TWO QUESTIONS, and they are not the same question:

  the graph lane   is the PORT's graph the CPython graph?  (`shader-gate.py` diffs the rows)
  the value lane   is the FORMULA a circle?                (this file executes it, because
                                                            CPython can and the port cannot)

WHY "THE SAME SPELLING" IS THE WHOLE ORACLE. A graph diff compares the two graphs that were
BUILT, so an oracle that builds a DIFFERENT graph agrees with nobody and an oracle that
builds a CLEVERER graph tests the oracle. Every line of `shader` below is the same primitive
as the corresponding line in `shader.bend`, in the same order, with no `.abs()`, no
`.clamp()` and no `.relu()`: those are tensor-API conveniences whose upstream spelling is a
WHERE ladder, so calling them here would measure tinygrad's conveniences and not the shader.

THE RULE THAT MAKES THIS AN ORACLE AND NOT A COPY: nothing here reads the port's output. The
graph is built from `Tensor.empty` upward and the rows are rendered from THIS build. A copy
of the port's rows would agree with the port by construction, which is the defect
`gates/tn_bitwise_not-oracle.py`'s post-mortem names.

THE ARG COLUMN renders four kinds -- a CONST's value, a BUFFER's ParamArg, a CAST's dtype,
and `ANone` -- and a `?` otherwise, which the gate treats as a REFUSAL rather than a value.

THE PLANT KNOB IS NOT READ HERE. `--plant` rewrites the PORT's `SH_R` in a copy, so if this
side also moved the two would agree and the gate would report a plant that did not fire.
MEASURED: that is exactly what the first version of `--plant` did."""
import sys

from tinygrad import Tensor, dtypes

N = 16
RADIUS = 0.5
EPS = 0.0001


def shader(x: Tensor, y: Tensor) -> Tensor:
  # d = length(p) - RADIUS
  dd = (x * x + y * y).sqrt() - RADIUS

  # THE NEIGHBOUR IS A MOVEMENT OP: pad one on the far side, shrink the near side away.
  # `pad`'s flat tuple is LAST AXIS FIRST -- `(0,1,0,0)` grows the WIDTH and `(0,0,0,1)`
  # grows the HEIGHT, MEASURED: `Tensor.empty(16,16).pad((0,0,0,1)).shape` is `(17, 16)`.
  # `shrink`'s is (start, end) per axis in (H, W) order.
  right = dd.pad((0, 1, 0, 0)).shrink(((0, N), (1, N + 1)))
  down = dd.pad((0, 0, 0, 1)).shrink(((1, N + 1), (0, N)))

  # fw = |d - right(d)| + |d - down(d)|, with abs written as maximum(x, -x) because
  # upstream's `abs` is a WHERE ladder and this fixture must not depend on which.
  dx = dd - right
  dy = dd - down
  fw = dx.maximum(-dx) + dy.maximum(-dy)

  # t = clamp((d + fw) / (2*fw + eps), 0, 1); there is NO Ops.MIN, so
  # min(a, 1) = a - max(a - 1, 0), which holds for every a >= 0.
  num = dd + fw
  den = (fw + fw) + EPS
  lo = (num / den).maximum(0.0)
  hi = (lo - 1.0).maximum(0.0)
  return 1.0 - (lo - hi)


def arg(u) -> str:
  a = u.arg
  if a is None:
    return "-"
  if type(a).__name__ == "ParamArg":
    return f"P{a.slot}"
  if type(a).__name__ == "DType":
    return f"dtypes.{a}"
  # `repr` and not `str`, because the port's `R.const_repr` renders `ConstFloat(1.0)` --
  # upstream's `ConstFloat.__repr__` -- and `str` would say `1.0` and hide the wrapper.
  if isinstance(a, (bool, int, float)) or type(a).__name__ in ("ConstFloat", "ConstInt"):
    return repr(a)
  return "?"


def rows(u, depth: int, out: list[str]) -> None:
  out.append(f"{depth} {u.op} {u.dtype} {arg(u)}")
  for s in u.src:
    rows(s, depth + 1, out)


def values() -> int:
  """A pixel grid in -1..1, and the three numbers that say the result is a CIRCLE.

  CENTRE AND CORNER ARE THE OBVIOUS TWO: alpha is 1 inside the disc and 0 outside it, so a
  formula with a sign error or a wrong radius disagrees on one of them. THE THIRD IS THE
  ONLY ONE THAT SEES `fwidth`: the count of pixels with an alpha STRICTLY BETWEEN 0 and 1 is
  the ANTI-ALIASING BAND, and it is EMPTY when the derivative is missing and the edge is
  hard. That is why `--values` exists -- a graph diff cannot tell a shader that computes
  `fwidth` from a shader that multiplies by zero."""
  g = ((Tensor.arange(N).float() + 0.5) / N) * 2 - 1
  a = shader(g.reshape(N, 1).expand(N, N), g.reshape(1, N).expand(N, N)).numpy()
  partial = int(((a > 0) & (a < 1)).sum())
  print(f"centre={a[N // 2, N // 2]:.4f}")
  print(f"corner={a[0, 0]:.4f}")
  print(f"partial={partial}")
  ok = abs(a[N // 2, N // 2] - 1.0) < 1e-6 and abs(a[0, 0]) < 1e-6 and 0 < partial < N * N // 2
  print("VALUES OK" if ok else "VALUES WRONG")
  return 0 if ok else 1


def main() -> int:
  if "--values" in sys.argv:
    return values()
  out: list[str] = []
  print("# shader=aa-circle")
  rows(shader(Tensor.empty(N, N), Tensor.empty(N, N)).uop, 0, out)
  print("\n".join(out))
  return 0


if __name__ == "__main__":
  sys.exit(main())
