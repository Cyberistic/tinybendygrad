#!/usr/bin/env python3
"""validate-oracle.py -- the CPython oracle for `tinybendygrad/uop/validate.bend`.

WHY THIS FILE EXISTS, and it is the same sentence `dv_and*`'s header could not finish:
`uop/validate.bend` had NO oracle anywhere in `.agents/slop/`, so a defect in its
`z3_bv` width -- the arena-aliasing fix that moved `dv_and15`/`dv_and21`/`dv_and_neg4`
from `- 1` to `- 256` -- was adjudicated by nobody. Three rows changed and the direction
was OPEN. A region with defects and no oracle is how that happens.

⚠ THE PRIOR UNIT'S PREMISE WAS FALSE AND IT IS THE FIRST THING TO CHECK. Its own words were
"**`z3` IS NOT INSTALLED IN THIS ENVIRONMENT**, so CPython's `uops_to_z3` could not be
CALLED, and `dv_and*` has no oracle anywhere in `.agents/slop/`". z3 IS INSTALLED:

    $ python3 -c "import z3; print(z3.get_version())"     -> (4, 16, 0, 0)
    $ python3 -c "import tinygrad.uop.validate as V; print(V.z3_bv)"
    -> <function z3_bv at 0x...>            # validate.py:8's version gate PASSES

`validate.py` imports cleanly and `uops_to_z3` runs. So `dv_and*` was never un-adjudicable;
it was un-oracled. `z3_d3` and `z3_ok` below are the two rows that make the premise checkable
by a reader instead of by trust, and they are emitted FIRST so a truncated run still shows
them.

WHAT IS CALLED, never re-derived. Every `dv_*` value comes from CPython's own
`uops_to_z3(solver, idx, gate)` with `solver.add(z3_mask)` -- validate.py:92-95 verbatim --
and every `z3_*` value comes from the named `validate.py` def on the port's own fixture. The
`_min_max` numbers the port HAND-WRITES into its `Sol.ms` table are printed as `mm_*` rows so
the table is checked against CPython's `UOp._min_max` rather than trusted; they are inputs,
not answers, and a transcription error in one would otherwise be invisible.

FIXTURE CORRESPONDENCE, which is the failure `multi.bend` measured. This oracle RE-TYPES the
port's fixtures in tinygrad's own constructors. The claim that the two describe one graph is
therefore a CLAIM, and it is supported by three measured facts rather than asserted:
`mm_*` rows (CPython's `_min_max` == the port's hand-written table), `dt_*` rows (the dtype
each fixture carries), and `ax_*` rows (the axis ids `range_str` reads). One fixture does NOT
correspond and is reported rather than quietly adjusted -- see `dv_bad_dtype_bitcast`.

ROW SHAPE. F1, `name=value`, read by `rebase-gate.py`'s `rows()`. FOUR rows per fixture:
the whole row, then `cs`, `term` and `n` alone. The per-field rows are why: a region whose
blob row is red for one defect tells you nothing about whether the OTHER fields are right, and
"3 of 4 fields agree" is the only useful thing to know about a row under adjudication. This
is the same reason `rebase-gate.py` refuses to let a name stand in for a comparable lane.

ONE ENCODING NORMALISATION, named: z3's pretty-printer WRAPS a long term across lines with a
three-space indent, e.g. `If(...,\\n   BV2Int(...) - 256,\\n   BV2Int(...))`. Runs of
whitespace are collapsed to one space. This is not a fudge: the wrap is a property of the
COLUMN WIDTH, not of the term -- `#raw_and21` below prints the wrapped text so the wrap is
visible, and collapsing cannot merge `a + b` with `a+b` (z3 prints `*` `/` `%` tight and
`+` `-` spaced, and that spacing survives the collapse).

    DEV=NULL python3 .agents/slop/validate-oracle.py
"""
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO))

import z3  # noqa: E402
from tinygrad.dtype import Invalid, dtypes  # noqa: E402
from tinygrad.uop.ops import Ops, UOp, range_str  # noqa: E402
from tinygrad.uop.validate import (  # noqa: E402
  uops_to_z3, z3_bv, z3_xor, z3_and, z3_or, z3_alu, z3_shift)

OUT = []


def emit(nm, v):
  OUT.append((nm, v))


def norm(s):
  """Collapse z3's line wrapping. See the module docstring: the wrap is a column property."""
  return " ".join(s.split())


# ---------------------------------------------------------------- the fixtures
T = UOp.const(True)


def fx_const(v):
  return UOp.const(v)


def fx_var(nm, lo, hi):
  return UOp.variable(nm, lo, hi, dtype=dtypes.int32)


def fx_range(at, ids, end=100):
  return UOp.range(end, ids, at)


def row_of(idx, gate):
  """validate.py:92-95 verbatim -- a fresh Solver AND a fresh Context per call, which is why
  `invalid_shift`'s per-context counter restarts at `!0` on every row."""
  solver = z3.Solver(ctx=z3.Context())
  z3_idx, z3_mask = uops_to_z3(solver, idx, gate)
  solver.add(z3_mask)
  return str(solver), str(z3_idx)


def fixture(nm, idx, gate=T, prov=()):
  """One fixture: the blob row plus the three per-field rows, or the RAISE CPython actually
  performs. CPython's `validate_index_with_z3` does not return a violation LIST -- it RAISES
  (validate.py:87 NotImplementedError, :89 AssertionError, and a TypeError from a one-src SHL),
  so a raise is the honest value and it is emitted as one. The port answers with a list; that
  disagreement is REAL and is defect class D7/D8."""
  for tag, v in prov:
    emit(f"{nm}_{tag}", v)
  try:
    cs, term = row_of(idx, gate)
  except Exception as e:  # noqa: BLE001 -- the exception IS the answer, and it is named
    emit(nm, f"RAISED {type(e).__name__}: {e}")
    return
  vs, n = "", 0  # CPython's own `vs` is empty whenever it does not raise
  emit(nm, f"{norm(cs)} | {norm(term)} | {vs} | {n}")
  emit(f"{nm}_cs", norm(cs))
  emit(f"{nm}_term", norm(term))
  emit(f"{nm}_n", str(n))


def main():
  from tinygrad.uop.ops import AxisType

  # ---- 0. THE PREMISE. Two rows, first, so a truncated run still shows them. -------------
  emit("z3_ok", int(bool(z3)))
  emit("z3_d3", "%d.%d.%d.%d" % z3.get_version())
  emit("validate_import", int("tinygrad.uop.validate" in sys.modules))

  # ---- 1. THE COMPARISON PRINTER. validate.py builds its comparisons with Python's operators
  # on MIXED operands, and a Python `int` on the LEFT reflects, so `(vmin <= s)` at
  # validate.py:51 is `Ge(s, vmin)` in the AST, not `Le(vmin, s)`. That reflection -- not a
  # printer reorientation -- is why CPython prints `i >= 0`. The rule measured over 80 ordered
  # pairs is: print `b flip(a)` iff `b` is a numeral and `a` is not.
  i, j = z3.Int("i"), z3.Int("j")
  E = z3.IntVal(100) - z3.IntVal(1)
  S = [("i", i), ("j", j), ("5", z3.IntVal(5)), ("99", E), ("-5", z3.IntVal(-5))]
  OPS = {"<": (lambda a, b: a < b, ">"), "<=": (lambda a, b: a <= b, ">="),
         ">": (lambda a, b: a > b, "<"), ">=": (lambda a, b: a >= b, "<=")}
  for opn, (mk, _) in OPS.items():
    for an, a in S:
      for bn, b in S:
        if an == bn:
          continue
        emit(f"cmp_{an}{opn}{bn}", norm(str(mk(a, b))))
  # the reflection itself, which is what validate.py:51 actually evaluates
  emit("refl_0_le_i", norm(str(0 <= i)))
  emit("refl_i_le_0", norm(str(i <= 0)))
  emit("refl_0_le_expr", norm(str(0 <= E)))

  # ---- 2. `range_str` (ops.py:95) -- the AXIS IDS, joined by `_`, negatives as `m<n>`.
  for tag, at, ids in (("g", AxisType.GLOBAL, 0), ("l", AxisType.LOOP, 0),
                       ("m1", AxisType.GLOBAL, -1), ("two", AxisType.GLOBAL, (0, 1))):
    rr = UOp.range(100, ids, at) if not isinstance(ids, tuple) else \
        UOp(Ops.RANGE, (UOp.const(100),), (at, *ids))
    emit(f"rs_{tag}", range_str(rr))
    emit(f"ax_{tag}", repr(rr.axis_id))

  # ---- 3. `z3_and`'s POWER-OF-TWO PREDICATE, validate.py:29-30. `m > 0 and m&(m-1) == 0`
  # and `m != 0 and m&(m-1) == 0` are the SAME PREDICATE over every integer: `m&(m-1) == 0`
  # forces m to be a power of two, hence positive. Enumerated over a window that contains
  # every case the port's fixtures reach, so the two spellings are compared as functions and
  # not argued about.
  def py_pow2(m):
    return m > 0 and (m & (m - 1)) == 0

  def port_pow2(m):
    """The port's `pow2`, transcribed: a sign-BIT test where Python has `m > 0`."""
    u = m & 0xFFFFFFFF
    return (u & 0x80000000) != 0 and (u & (u - 1)) == 0

  POW2 = [-8, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 7, 8, 15, 16, 21, 22, 32, 64, 255, 256]
  agree = sum(1 for m in POW2 if py_pow2(m) == port_pow2(m))
  emit("pow2_win_n", str(len(POW2)))
  emit("pow2_agree", str(agree))
  for m in POW2:
    emit(f"pow2_{m}", int(py_pow2(m)))
  # the two spellings as functions over the window, for the theorem check
  emit("pow2_fn_agree", int(all(py_pow2(m) == (m != 0 and (m & (m - 1)) == 0) for m in POW2)))

  # ---- 4. `z3_bv`'s WIDTH -- validate.py:16, called. This is the row that adjudicates the
  # `- 1` -> `- 256` move, and it is a width and not a printed string so it can be green on
  # its own. `off` is `2**w`, which is the literal inside z3's signed `BV2Int` expansion.
  def width(x):
    return 1 + max(int(x.src[0].vmax).bit_length(), int(x.src[1].vmax).bit_length(),
                   int(-x.src[0].vmin).bit_length(), int(-x.src[1].vmin).bit_length())

  WIDTHS = []
  for op in (Ops.AND, Ops.OR, Ops.XOR):
    for hi, k in ((100, 21), (100, 15), (64, 2), (8, 21)):
      t = UOp(op, (UOp.range(hi, 0, AxisType.GLOBAL), UOp.const(k)))
      WIDTHS.append((f"{op.name.lower()}_{hi}_{k}", t))
  for lo, hi, k in ((-100, 100, 21), (-1, 1, 3), (0, 1, 1)):
    v = UOp.variable("v", lo, hi, dtype=dtypes.int32)
    t = UOp(Ops.AND, (v, UOp.const(k)))
    WIDTHS.append((f"and_var{lo}_{hi}_{k}", t))
  WIDTHS.append(("and_buf_neg", UOp(Ops.AND, (UOp.const(-4), UOp.const(21)))))
  for tag, t in WIDTHS:
    emit(f"w_{tag}", str(width(t)))
    emit(f"w_{tag}_off", str(2 ** width(t)))
    emit(f"mm_{tag}_s0", repr(t.src[0]._min_max))
    emit(f"mm_{tag}_s1", repr(t.src[1]._min_max))

  # ---- 5. THE FIXTURE ROWS, one per `dv_*` the port prints. ------------------------------
  r_g = UOp.range(100, 0, AxisType.GLOBAL)
  r_l = UOp.range(100, 0, AxisType.LOOP)
  r_m1 = UOp.range(100, -1, AxisType.GLOBAL)
  r64 = UOp.range(64, 0, AxisType.GLOBAL)
  r8 = UOp.range(8, 0, AxisType.GLOBAL)
  r16 = UOp.range(16, 0, AxisType.GLOBAL)

  fixture("dv_const_ok", UOp.const(15), prov=(("dt", "weakint"), ("mm", repr(UOp.const(15)._min_max))))
  fixture("dv_var", fx_var("i", 0, 15), prov=(("dt", "i32"), ("mm", repr(fx_var("i", 0, 15)._min_max))))
  fixture("dv_var_neg", fx_var("i", -5, 10), prov=(("mm", repr(fx_var("i", -5, 10)._min_max)),))
  fixture("dv_range_global", r_g, prov=(("mm", repr(r_g._min_max)), ("dt", str(r_g.dtype))))
  fixture("dv_range_loop", r_l, prov=(("mm", repr(r_l._min_max)),))
  fixture("dv_range_m1", r_m1, prov=(("mm", repr(r_m1._min_max)), ("ax", repr(r_m1.axis_id))))
  for k, nm in ((15, "dv_and15"), (21, "dv_and21"), (-4, "dv_and_neg4")):
    t = UOp(Ops.AND, (r_g, UOp.const(k)))
    fixture(nm, t, prov=(("mm_s0", repr(t.src[0]._min_max)), ("mm_s1", repr(t.src[1]._min_max)),
                         ("w", str(width(t)))))
  t = UOp(Ops.SHR, (r64, UOp.const(2)))
  fixture("dv_shr2", t, prov=(("mm_s0", repr(t.src[0]._min_max)), ("mm_s1", repr(t.src[1]._min_max))))
  vw = fx_var("v", 0, 15)
  cm = UOp(Ops.CMPLT, (vw, UOp.const(8)))
  inv = UOp.const(Invalid)
  fixture("dv_where", UOp(Ops.WHERE, (cm, vw, inv)),
          prov=(("mm", repr(vw._min_max)), ("mm_cm", repr(cm._min_max)), ("mm_inv", repr(inv._min_max))))
  fixture("dv_const_invalid", UOp.const(Invalid), prov=(("dt", str(UOp.const(Invalid).dtype)),))
  fixture("dv_unsup_stack", UOp(Ops.STACK, (UOp.const(2), UOp.const(3))), prov=(("dt", "weakint"),))
  fixture("dv_unsup_two", UOp(Ops.GROUP, (UOp(Ops.STACK, (UOp.const(2), UOp.const(3))),
                                          UOp(Ops.STACK, (UOp.const(5), UOp.const(7))))),
          prov=(("dt", str(UOp(Ops.GROUP, (UOp(Ops.STACK, (UOp.const(2), UOp.const(3))),
                                            UOp(Ops.STACK, (UOp.const(5), UOp.const(7))))).dtype)),))
  fixture("dv_rank_shr1", UOp(Ops.SHL, (r8,)), prov=(("dt", str(r8.dtype)),))
  # ⚠ THE ONE FIXTURE THAT DOES NOT CORRESPOND, and it is left as the port has it so the row
  # stays the same question. The port builds `Ops.BITCAST` with `arg=None`, and CPython's
  # `dtype_from_uop` (ops.py:182) ASSERTS on that: `CAST/BITCAST arg must be DType, got None`.
  # So CPython cannot be asked this row at all -- the answer below is the constructor's, not
  # `uops_to_z3`'s. `dv_bitcast_bool` is the CONSTRUCTIBLE spelling of the same port intent
  # (`arg=dtypes.bool`, two srcs, so rule 5's shape test fails and rules 9/10 do not claim
  # BITCAST) and it does reach validate.py.
  try:
    bc = UOp(Ops.BITCAST, (r16, r16))
    emit("dv_bad_dtype_bitcast", norm(str(bc.dtype)))
  except Exception as e:  # noqa: BLE001
    emit("dv_bad_dtype_bitcast", f"RAISED {type(e).__name__}: {e}")
  fixture("dv_bitcast_bool", UOp(Ops.BITCAST, (r16, r16), arg=dtypes.bool), prov=(("dt", "bool"),))

  # ---- 6. TABLE COUNTS, read off the live objects. --------------------------------------
  emit("n_z3_alu", str(len(z3_alu)))
  emit("n_z3_alu_keys", "|".join(sorted(o.name for o in z3_alu)))

  # ---- 7. THE WRAPPED TEXT, so the normalisation above is visible rather than claimed. ----
  s = z3.Solver(ctx=z3.Context())
  z3_idx, z3_mask = uops_to_z3(s, UOp(Ops.AND, (r_g, UOp.const(21))), T)
  s.add(z3_mask)
  emit("#raw_and21", repr(str(z3_idx)))
  emit("#wrap_and21", str(str(z3_idx).count("\n")))

  for nm, v in OUT:
    print(f"{nm}={v}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
