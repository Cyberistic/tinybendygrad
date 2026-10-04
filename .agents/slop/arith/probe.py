#!/usr/bin/env python3
"""probe.py -- ARITH-2. Which of the six ops can the corpus REACH, and by WHOSE code.

Nothing here is transcribed. Every candidate is emitted through the SAME `row_of` loop the
differ uses (`rows_of`, checked byte-equal against `emit_py` below), so a candidate that
dies in `row_of` (e.g. `dtype_from_uop`'s WHERE arm, ops.py:158) is a WALL, not a count.
And every op census is read off the emitted rows, not off `UOp.op.name` on a hand-walked
tree: that mistake is recorded in `g_where`'s docstring and it produced a census of a graph
that cannot be emitted at all.

The six, and where upstream CONSTRUCTS each one (grep for the site, then CALL it here):

  CDIV    elementwise.py:251  a.div(b, rounding_mode="trunc") on int/int -- EAGER
  CMOD    elementwise.py:226  a.fmod(b) on int/int -- EAGER
  CMPEQ   elementwise.py:337  a.eq(b) == a.ne(b).logical_not() -- EAGER, and it is the exact
          LHS of upstream's OWN late rewrite at codegen/decomp/op.py:117
  NEG     codegen/decomp/op.py:105  `x * -1 -> NEG x` -- a REWRITE
  SUB     codegen/decomp/op.py:106  `x + (-y) -> SUB x y` -- a REWRITE, and eager `sub` is
          elementwise.py:123 `a.alu(Ops.ADD, -b)`, i.e. exactly its LHS
  FDIV    codegen/decomp/op.py:124  `reciprocal x -> CONST 1.0 FDIV x` -- a REWRITE, and
          eager float `div` is elementwise.py:255 `a.alu(Ops.MUL, b.reciprocal())`

ARITH-4. TWO TRAPS THIS PROBE FELL INTO, both of which would have read as "no wall":
  * `G.unchunks(r[1:])` instead of `G.unchunks(r)`. `reach/census.py:24` builds a dict
    keyed on `r[1:]` (drop the first CHARACTER, which is the first chunk's `N:LEN:` header)
    but DECODES `r`. Passing the truncated string to `unchunks` gives
    `ValueError: invalid literal for int() with base 10: ''` on EVERY candidate, which
    reads as six walls and is really one wrong argument.
  * `from tinygrad import ...` at module scope runs BEFORE `os.environ["DEV"]="CPU"`, so
    every ALLOC carries `sMETAL`. graphcmp.py's own `load_tinygrad()` exists to make the
    import order load-bearing; a probe that imports first opts out of it silently.
"""
import sys, pathlib, os, collections

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parents[2]))
os.environ["DEV"] = "CPU"
import graphcmp as G

WANT = {"CDIV", "CMOD", "CMPEQ", "FDIV", "NEG", "SUB"}


def rows_of(ast):
  """`emit_py`'s own row loop (graphcmp.py:1703-1705) applied to an AST the probe built,
  because `emit_py` takes a graph NAME (graphcmp.py:1686) and the candidates are not yet
  in `GRAPHS`. Asserted byte-equal against `emit_py` on `matmul` in `main`."""
  lst = list(ast.toposort())
  ix = {id(n): i + 1 for i, n in enumerate(lst)}
  return [G.row_of(n, i + 1, ix) for i, n in enumerate(lst)]


def census(ast):
  rows = rows_of(ast)
  return len(rows), dict(sorted(collections.Counter(G.unchunks(r)[1] for r in rows).items()))


def build(kind: str):
  """`kind` names the CANDIDATE. Every branch is an upstream PUBLIC construction; none of
  them writes `UOp(Ops.X, ...)` by hand, which is the rule `g_alu` states."""
  from tinygrad import Tensor, dtypes
  from tinygrad.uop.ops import UOp
  if kind == "fmod-int":                                  # CMOD, eager
    a, b = Tensor.empty(4, 3, dtype=dtypes.int), Tensor.empty(4, 3, dtype=dtypes.int)
    return UOp.group(a.fmod(b).uop)
  if kind == "cdiv-int":                                  # CDIV, eager
    a, b = Tensor.empty(4, 3, dtype=dtypes.int), Tensor.empty(4, 3, dtype=dtypes.int)
    return UOp.group(a.div(b, rounding_mode="trunc").uop)
  if kind == "eq-bool":                                   # CMPEQ, eager
    a, b = Tensor.empty(4, 3, dtype=dtypes.float), Tensor.empty(4, 3, dtype=dtypes.float)
    return UOp.group(a.eq(b).uop)
  if kind == "ne-not-eq":                                 # CMPEQ's LHS, on its own
    a, b = Tensor.empty(4, 3, dtype=dtypes.float), Tensor.empty(4, 3, dtype=dtypes.float)
    return UOp.group(a.ne(b).logical_not().uop)
  if kind == "neg-int":                                   # NEG, eager?
    return UOp.group(Tensor.empty(4, 3, dtype=dtypes.int).neg().uop)
  if kind == "neg-float":                                 # NEG, eager?
    return UOp.group(Tensor.empty(4, 3, dtype=dtypes.float).neg().uop)
  if kind == "sub-eager":                                 # SUB, eager? (elementwise.py:123)
    a, b = Tensor.empty(4, 3, dtype=dtypes.float), Tensor.empty(4, 3, dtype=dtypes.float)
    return UOp.group((a - b).uop)
  if kind == "recip-float":                               # FDIV's LHS: RECIPROCAL, eager
    return UOp.group(Tensor.empty(4, 3, dtype=dtypes.float).reciprocal().uop)
  if kind == "mulm1-int":                                 # NEG's LHS: `x * -1`
    a = Tensor.empty(4, 3, dtype=dtypes.int)
    return UOp.group((a * -1).uop)
  raise KeyError(kind)


CANDS = ["fmod-int", "cdiv-int", "eq-bool", "ne-not-eq", "neg-int", "neg-float",
         "sub-eager", "recip-float", "mulm1-int"]


def main() -> int:
  G.load_tinygrad()
  G.COMM = G.commutative()
  seen: set[str] = set()
  with G.Context(NO_COLOR=1):
    same = rows_of(G.base("matmul")) == G.emit_py("matmul", None)
    print(f"# rows_of == emit_py on `matmul`: {same}   (the two-line copy, asserted)")
    for k in CANDS:
      try:
        ast = build(k)
      except Exception as e:
        print(f"# {k:<12} BUILD-WALL {type(e).__name__}: {' '.join(str(e).split())[:120]}")
        continue
      try:
        n, ops = census(ast)
      except Exception as e:
        print(f"# {k:<12} EMIT-WALL  {type(e).__name__}: {' '.join(str(e).split())[:120]}")
        continue
      hit = sorted(WANT & set(ops))
      seen |= set(hit)
      print(f"# {k:<12} rows={n:<4} WANTED={hit}  census={ops}")
  print(f"#")
  print(f"# reached by an EAGER construction alone: {sorted(seen)}")
  print(f"# still missing: {sorted(WANT - seen)}")
  return 0


if __name__ == "__main__":
  sys.exit(main())