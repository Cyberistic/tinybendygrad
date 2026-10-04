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
import re
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


def norm_ns(s):
  """Remove z3's line wrap with NOTHING in its place -- the encoding the port already uses, so a
  `_term_ns` row asks only whether the two TOKEN STREAMS agree."""
  return re.sub(r"\n\s*", "", s)


def norm(s):
  """Collapse z3's line wrapping. See the module docstring: the wrap is a column property.

  \u26a0 AND THIS IS AN ARTEFACT-PRODUCING NORMALISATION, WHICH `_term_ns` EXISTS TO PROVE. z3 breaks
  a long term at a position of ITS CHOOSING, not by replacing a space, so a wrap sometimes lands
  where there was no space: the raw text of `dv_cmod4`'s term ends `... r0/4)*\n4`, and collapsing
  gives `... r0/4)* 4` -- a space z3 never printed. MEASURED, and it is why `dv_cmod4` first
  disagreed with the port on `* 4` against `*4` when the two were otherwise IDENTICAL.

  `norm_ns` is emitted alongside as `_term_ns` so the artefact is a NAMED ROW rather than a red
  that looks like a defect. NEITHER normalisation is SOUND -- `i < 0,\n   If(` really did have a
  space there and `*\n4` really did not -- so the pair brackets the truth and neither states it.
  That is the honest shape for a normalisation that cannot be undone."""
  return " ".join(s.split())


def nofresh(s):
  """Strip z3's per-Context `FreshInt` counter suffix (`invalid_shift!0` -> `invalid_shift`).

  The port has no counter -- `ZFresh` prints the bare name -- so the port's `_term_nb` IS its
  `_term`. Declaring the normalisation on BOTH sides is what makes the `_term_nb` rows
  comparable, and it is what confines the counter divergence to the `_term` rows instead of
  letting one token make `dv_shr2`'s whole term unreadable."""
  return re.sub(r"!\d+", "", s)


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


def walk_of(idx, gate):
  """`validate.py:83-84` verbatim -- `UOp.sink(*uops).toposort(gate=...)[:-1]`.

  WHY A WALK ROW AT ALL, and it is the row the `dv_where` defect needed. `dv_where`'s blob row
  said `And(v >= 0, v <= 15)` TWICE, which names a repeated TERM and not a repeated NODE: three
  units saw that blob and none localised it, because a repeated term looks exactly like a
  legitimately repeated one. A COUNT cannot localise it either -- a count says `6` and not
  `where`. The walk is the op SEQUENCE, so it says `Ops.PARAM` twice and names the node.
  `[:-1]` drops the SINK and NOT the gate's CONST, which is why the sequence ends `Ops.CONST`.
  """
  gate_fn = lambda x: x.op not in {Ops.AFTER, Ops.SHRINK, Ops.ALLOC, Ops.BUFFER} and \
      (x.dtype in dtypes.ints + (dtypes.bool, dtypes.weakint) or x.op is Ops.SINK)
  return list(UOp.sink(idx, gate).toposort(gate=gate_fn))[:-1]


def fixture(nm, idx, gate=T, prov=()):
  """One fixture: the blob row plus the three per-field rows, or the RAISE CPython actually
  performs. CPython's `validate_index_with_z3` does not return a violation LIST -- it RAISES
  (validate.py:87 NotImplementedError, :89 AssertionError, and a TypeError from a one-src SHL),
  so a raise is the honest value and it is emitted as one. The port answers with a list; that
  disagreement is REAL and is defect class D7/D8.

  `_msg` is emitted for a raise as the EXCEPTION MESSAGE, because the message text is the part
  the port CAN reproduce: `NotImplementedError: Ops.STACK is not supported by z3` and the port's
  violation list carry the same string. So `_msg` is green for `dv_unsup_stack` while the blob
  row is red for the raise-versus-list shape -- proven and unproven, separated by row name."""
  for tag, v in prov:
    emit(f"{nm}_{tag}", v)
  # THE WALK ROW, emitted for EVERY fixture rather than only `dv_where`: a walk is a graph
  # property and one fixture cannot say the walk is right, only that it was right once.
  try:
    emit(f"{nm}_walk", " ".join(str(u.op) for u in walk_of(idx, gate)) + " ")
  except Exception as e:  # noqa: BLE001
    emit(f"{nm}_walk", f"RAISED {type(e).__name__}: {e}")
  try:
    cs, term = row_of(idx, gate)
  except Exception as e:  # noqa: BLE001 -- the exception IS the answer, and it is named
    emit(nm, f"RAISED {type(e).__name__}: {e}")
    emit(f"{nm}_msg", str(e))
    return
  vs, n = "", 0  # CPython's own `vs` is empty whenever it does not raise
  emit(nm, f"{norm(cs)} | {norm(term)} | {vs} | {n}")
  emit(f"{nm}_cs", norm(cs))
  emit(f"{nm}_term", norm(term))
  # `_term_ns` IS EMITTED, so the claim `norm`'s own docstring makes -- "that encoding invents
  # the OPPOSITE error on five rows where the port is right" -- is COUNTED BY THE GATE instead
  # of asserted in prose. Neither normalisation is sound; the pair brackets the truth and the
  # bracket's width is a measured disagreement count rather than a sentence.
  emit(f"{nm}_term_ns", nofresh(norm_ns(term)))
  emit(f"{nm}_term_nb", nofresh(norm(term)))
  emit(f"{nm}_n", str(n))
  emit(f"{nm}_msg", vs)


def main():
  from tinygrad.uop.ops import AxisType

  # ---- 0. THE PREMISE. Two rows, first, so a truncated run still shows them. -------------
  emit("z3_ok", int(bool(z3)))
  emit("z3_d3", "%d.%d.%d.%d" % z3.get_version())
  emit("validate_import", int("tinygrad.uop.validate" in sys.modules))

  # ---- 1. THE COMPARISON PRINTER. validate.py builds its comparisons with Python's operators
  # on MIXED operands, and a Python `int` on the LEFT reflects, so `(vmin <= s)` at
  # validate.py:51 is `Ge(s, vmin)` in the AST, not `Le(vmin, s)`. That reflection -- not a
  # printer reorientation -- is why CPython prints `i >= 0`.
  #
  # ⚠ THE OPERATOR SPELLING IN THE ROW NAME IS `lt`/`le`/`gt`/`ge`, NOT `<`/`<=`, AND THAT IS NOT
  # COSMETIC. `rows()` splits F1 on the FIRST `=`, so a name containing `<=` splits INSIDE ITSELF:
  # `cmp_i<=5=5 >= i` parsed to the name `cmp_i<` with the value `5=5 >= i`. MEASURED on this
  # oracle before the fix: 310 printed lines, 280 parsed rows, **30 collapsed onto 10 names**, and
  # each of those 10 names then held FOUR different measurements. A table whose operator names
  # collide is a table that silently answers a different question for 30 of its rows, and the
  # count of printed lines hides it. **A ROW NAME MUST NOT CONTAIN `=`** -- that is the same rule
  # as "row names contain SPACES, use `rows()`", stated from the other side.
  i, j = z3.Int("i"), z3.Int("j")
  E = z3.IntVal(100) - z3.IntVal(1)
  S = [("i", i), ("j", j), ("5", z3.IntVal(5)), ("99", E), ("-5", z3.IntVal(-5))]
  OPS = {"lt": lambda a, b: a < b, "le": lambda a, b: a <= b,
         "gt": lambda a, b: a > b, "ge": lambda a, b: a >= b}
  for opn, mk in OPS.items():
    for an, a in S:
      for bn, b in S:
        if an == bn:
          continue
        emit(f"cmp_{an}{opn}{bn}", norm(str(mk(a, b))))
  # the reflection itself, which is what validate.py:51 actually evaluates
  emit("refl_0_le_i", norm(str(0 <= i)))
  emit("refl_i_le_0", norm(str(i <= 0)))
  emit("refl_0_le_expr", norm(str(0 <= E)))
  emit("refl_z_le_i", norm(str(z3.IntVal(0) <= i)))
  emit("refl_z_le_i_2", norm(str(i <= z3.IntVal(0))))
  emit("refl_i_le_z", norm(str(i <= z3.IntVal(0))))
  emit("refl_z_le_expr", norm(str(z3.IntVal(0) <= E)))

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
  # `Ops.MAX`. `validate.py:47` is `lambda _,a,b: z3.If(a<b, b, a)`; the port routed MAX into a
  # `k`-tag ladder where an unknown tag silently took the FLOORMOD arm, and no row covered it.
  fixture("dv_max", UOp(Ops.MAX, (r_g, UOp.const(21))), prov=(("dt", "weakint"),))
  # ---- 5b. THE OTHER SEVEN `z3_alu` BUILDERS. Before these rows only 4 of the 11 keys had a
  # fixture that REACHED them, and `n_z3_alu=11` could not see that -- which is how `Ops.MAX` came
  # to be floormodded. Seven builders, seven rows, all called live.
  fixture("dv_or21", UOp(Ops.OR, (r_g, UOp.const(21))))
  fixture("dv_xor21", UOp(Ops.XOR, (r_g, UOp.const(21))))
  # `z3_xor`'s CONSTANT arm, validate.py:21: `x ^ -1 = -(x+1)`. No width, and no row until now.
  fixture("dv_xor_m1", UOp(Ops.XOR, (r_g, UOp.const(-1))))
  fixture("dv_cdiv4", UOp(Ops.CDIV, (r_g, UOp.const(4))))
  fixture("dv_cmod4", UOp(Ops.CMOD, (r_g, UOp.const(4))))
  fixture("dv_floordiv4", UOp(Ops.FLOORDIV, (r_g, UOp.const(4))))
  fixture("dv_floormod4", UOp(Ops.FLOORMOD, (r_g, UOp.const(4))))
  fixture("dv_shl2", UOp(Ops.SHL, (r_g, UOp.const(2))))
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
  # ⚠ THE FIXTURE THAT DID NOT CORRESPOND, and IT NOW DOES. The port used to build
  # `Ops.BITCAST` with `arg=ANone{}`, and CPython's `dtype_from_uop` (ops.py:182) ASSERTS on
  # that: `CAST/BITCAST arg must be DType, got None`. So `dv_bad_dtype_bitcast` had NO CPython
  # answer and was unadjudicable -- the row was a port statement with no referee.
  #
  # THE CONSTRUCTIBLE SPELLING IS ONE `Arg` FIELD AND IT IS NOT AN `ops.bend` CHANGE:
  # `O.ADt{S.boolean()}` is already exported by `ops.bend` (its own `s5.arena` builds
  # `Ops.BITCAST` with `ADt{S.single()}` at slot 8), so `validate.bend` reaches it directly.
  # MEASURED: with `ADt{S.boolean()}` the port prints
  #   dv_bad_dtype_bitcast_msg = Ops.BITCAST is not supported by z3
  # which is byte-identical to the `NotImplementedError` message CPython raises here. The brief
  # this answers asked for a dtype-carrying `Arg` in `ops.bend`; the arg type is ALREADY THERE
  # and the premise was false.
  #
  # THE REFUSED SPELLING KEEPS ITS OWN ROWS, so the refusal is reported rather than lost -- a
  # dropped refusal and a passing row are indistinguishable in a gate that only counts.
  #
  # ⚠ AND THE REFUSAL IS NOT WHERE ANYBODY SAID IT WAS. The port's header, and this oracle's
  # own header until now, said CPython's `dtype_from_uop` ASSERTS on `arg=None` "at the
  # constructor". It does not: `UOp(Ops.BITCAST, (r16, r16))` CONSTRUCTS FINE and prints
  # `arg=None`. The assert fires on the first `.dtype` READ, and `ops.py:122` is
  # `dtype_from_uop(op, src, arg)` -- a function `UOp.__init__` never calls eagerly. So the
  # refusal is a LAZY one, and a port row that walks dtype-carrying nodes never reaches it. Both
  # halves are separate rows because collapsing them would repeat the error.
  try:
    bc = UOp(Ops.BITCAST, (r16, r16))
    emit("dv_bad_dtype_bitcast_argless_construct", "ok")
    try:
      emit("dv_bad_dtype_bitcast_argless_dtype", norm(str(bc.dtype)))
    except Exception as e:  # noqa: BLE001
      emit("dv_bad_dtype_bitcast_argless_dtype", f"RAISED {type(e).__name__}: {e}")
  except Exception as e:  # noqa: BLE001
    emit("dv_bad_dtype_bitcast_argless_construct", f"RAISED {type(e).__name__}: {e}")
  fixture("dv_bad_dtype_bitcast", UOp(Ops.BITCAST, (r16, r16), arg=dtypes.bool), prov=(("dt", "bool"),))

  # ---- 6. TABLE COUNTS, read off the live objects. --------------------------------------
  emit("n_z3_alu", str(len(z3_alu)))
  emit("n_z3_alu_keys", "|".join(sorted(o.name for o in z3_alu)))

  # ---- 6b. THE WIDTH ROWS, under the NAMES THE PORT PRINTS. `bv_w_*` in
  # `validate.bend`'s `main` reads `bv_w` off a fixture-shaped arena, so these four rows are
  # the same four numbers under the names the two lanes can intersect on. They are the rows
  # that adjudicate the `- 1` -> `- 256` move ON ITS OWN, with no printer text in them.
  for tag, k in (("and21", 21), ("and15", 15), ("and_neg4", -4)):
    emit(f"bv_w_{tag}", str(width(UOp(Ops.AND, (r_g, UOp.const(k))))))
    emit(f"bv_w_off_{tag}", str(2 ** width(UOp(Ops.AND, (r_g, UOp.const(k))))))

  # ---- 8. THE `c2d` LANE -- `copy_to_device`'s FOUR REFUSALS. ----------------------------
  # Sourced from `.agents/slop/c2d-refusal-rows.py`, which is the file that OWNS these rows
  # and says why each fixture is the one `validate.bend` builds. It is loaded and run rather
  # than copied, because a second copy of a fixture list is a second list to keep in step --
  # and `agent-core.md` records a row set that was written twice and adjudicated once.
  #
  # WHY THEY LIVE HERE AT ALL, and it is a COVERAGE claim rather than tidiness: `validate.bend`
  # is the only `.bend` this unit owns, `ops.bend` has another owner, and `s5_copy_sel` was a
  # GREEN row asserting agreement on a node CPython refuses. A refusal needs a fixture with a
  # positive control one step away, and the fixture set has to live somewhere both lanes can
  # be run against. This is that somewhere.
  import importlib.util  # noqa: E402

  c2d_spec = importlib.util.spec_from_file_location("c2d_rows", HERE / "c2d-refusal-rows.py")
  c2d = importlib.util.module_from_spec(c2d_spec)
  c2d_spec.loader.exec_module(c2d)
  _c2d_out = []
  c2d.out = lambda nm, v: _c2d_out.append(f"{nm}={v}")
  c2d.main()
  OUT.extend(_c2d_out)
  emit("c2d_lane_loaded", int(len(_c2d_out)))

  # ---- 7. THE WRAPPED TEXT, so the normalisation above is visible rather than claimed. ----
  s = z3.Solver(ctx=z3.Context())
  z3_idx, z3_mask = uops_to_z3(s, UOp(Ops.AND, (r_g, UOp.const(21))), T)
  s.add(z3_mask)
  emit("#raw_and21", repr(str(z3_idx)))
  emit("#wrap_and21", str(str(z3_idx).count("\n")))
  # THE ONE NAMED RESIDUAL, WITH ITS EVIDENCE. `dv_cmod4_term` is the only row where the port and
  # `_term` differ, and it differs by ONE SPACE: the raw text below ends `r0/4)*\n4`, so z3 put a
  # newline where it printed no space and collapsing the wrap to a space invents one. MEASURED --
  # and it is why `norm_ns` is not emitted either: z3 also wraps after a comma, so that encoding
  # invents the OPPOSITE error on five rows where the port is right.
  cs2, term2 = row_of(UOp(Ops.CMOD, (UOp.range(100, 0, AxisType.GLOBAL), UOp.const(4))), T)
  emit("#raw_cmod4", repr(term2))
  emit("#wrap_cmod4", str(term2.count("\n")))

  for nm, v in OUT:
    print(f"{nm}={v}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
