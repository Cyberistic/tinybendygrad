#!/usr/bin/env python3
# mm-lift-gate.py -- the CPython oracle for `_min_max`'s OP TABLE, ops.py:1105-1163.
#
# THE SAME ZERO-TRANSCRIPTION RULE as the rest of this unit's gates, and here it is a
# TABLE rather than a formula: the fixture list below is written ONCE and both the Bend
# gate lines and the CPython expectations are generated from it. A row cannot be right on
# one lane and wrong on the other, because there is only one copy of the inputs.
#
# WHY THE FIXTURES ARE ALL CONST-SRCS. Every src in a fixture is a `CONST`, so its
# `_min_max` is `(v, v)` -- KNOWN, not computed -- which means the oracle can hand the
# Bend table a `List<&2, Bnd2>` it built from the same two integers without needing a walk.
# That is what makes the TABLE gateable before the WALK exists, and it is the reason this
# gate and the walk are separate work.
#
#     .venv/bin/python .agents/slop/mm-lift-gate.py                 > $OUT/lift-py.txt
#     .venv/bin/python .agents/slop/mm-lift-gate.py --emit-bend     > $OUT/lift-rows.bend
#     ./bin/bend tinybendygrad/uop/fold.bend | grep '^lf'            > $OUT/lift-bend.txt
#     diff $OUT/lift-py.txt $OUT/lift-bend.txt
#
# THE SATURATION ROWS ARE A SECOND CLASS AND THEY ARE NOT GATED FOR EQUALITY. Python's
# ints are unbounded, so `2**63 + 2**63` is `2**64` there and `PInf` here. Those rows are
# emitted `lfx_` and the expectation is the PORT's saturating answer plus CPython's real
# number in brackets, so the divergence is IN the row rather than smoothed into an
# agreeing one. This is the same treatment `mv_expsym` gets.
#
# ---------------------------------------------------------------------------
# WHY `main` PINS THE INTERPRETER AND WHY A DEATH IS NOT A ZERO.  Both were measured, and
# the second one is the defect that made this file unreadable for a day:
#
#     python3 .agents/slop/mm-lift-gate.py            ->  rc=1, STDOUT 0 lines
#     .venv/bin/python .agents/slop/mm-lift-gate.py    ->  rc=0, STDOUT 131 lines
#
# `python3` on PATH is 3.14 with no `.pth`; the EDITABLE tinygrad install exists only in
# `.venv` (3.12), so `from tinygrad import dtypes` raises ModuleNotFoundError. A harness
# that reads STDOUT and counts lines saw **0** -- and the project read that 0 as "no CPython
# answer exists for the `_min_max` table", which is a claim about the PORT and is really a
# claim about the LAUNCHER. So:
#
#   * THE PIN. `oracle_py.resolve()` decides which interpreter may answer, and this file
#     RE-EXECS under it, so both commands above now print the same 131 rows. The mechanism
#     is the project's own and not a second one invented here; `resolve()` also REFUSES an
#     interpreter whose tinygrad resolves outside this tree, which is the L-11 trap: a `.venv`
#     copied out of the repo still has `MAPPING = {'tinygrad': '/abs/path/to/the/original/
#     tinygrad'}` in `__editable___tinygrad_0_14_0_finder.py`, and every row it produced
#     would be measured against a tree the port is not ported from.
#   * THE DEATH. A gate that could not run says `DIED` and exits **2**, on STDOUT so a
#     line-counting harness cannot mistake it for an answer, and 2 rather than 1 because
#     `oracle_py.refuse()` already reserves 1 for "the run happened and found a broken
#     port". Three instruments died today and reported something else instead --
#     `nv_nvdev_gate.py` hid 15 disagreements behind a 3-value unpack traceback,
#     `rebase-oracle-ops.py` exits 1 on a missing `importlib` and prints nothing.
#
# `--selfcheck` PROVES the death path rather than asserting it, and it drives BOTH refusals by
# moving the gate into a THROWAWAY TREE in $TMPDIR -- never the live one. A claim that a harness
# can fail is only evidence once the harness has been seen to fail; and `nv_mutate.py` shipped
# 19 of 28 entries as a whole because its anchors never compiled, so an unrun control is not a
# control.
# ---------------------------------------------------------------------------
import contextlib
import io
import os
import pathlib
import sys

SLOP = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(SLOP))
import oracle_py  # noqa: E402  -- after sys.path, before anything can import tinygrad

PIN_ENV = "MM_LIFT_GATE_PINNED"   # one re-exec only; never a loop
DIED_RC = 2                      # distinct from 1 = "ran, and found a broken port"

# (label, opname, [src values], dtype-attr)
BIN = [
  ("add", "ADD", [(3, 4), (-3, 4), (-3, -4), (0, -5), (-5, 0), (2**31, 2**31 - 1),
                  (-2**31, -2**31 + 1), (0, 0), (2**40, -2**40)]),
  ("sub", "SUB", [(3, 4), (-3, 4), (-3, -4), (3, -4), (-3, 4), (0, 0), (5, 5), (4, 5)]),
  ("mul", "MUL", [(3, 4), (-3, 4), (-3, -4), (0, -5), (7, -8), (-2**31, 2), (2**31, 3),
                  (2**40, 2**20)]),
  ("max", "MAX", [(3, 4), (-3, 4), (3, -4), (-3, -4), (0, 0), (2**40, -2**40)]),
  ("cmplt", "CMPLT", [(3, 4), (-3, 4), (4, 3), (-4, -3), (3, 3), (-3, -3), (2**40, -2**40)]),
  ("cmpne", "CMPNE", [(3, 4), (-3, 4), (4, 3), (-4, -3), (3, 3), (-3, -3), (5, 5)]),
  ("andint", "AND", [(5, 255), (0, 255), (-1, 255), (5, 0), (2**31, 7), (-2**31, 7),
                     (8, 255), (255, 8), (2**40, 2**30)]),
  # A NEGATIVE MASK CONSTANT IS **NOT A FIXTURE, AND THAT IS THE FINDING**. Measured:
  # `UOp(Ops.AND, src=(CONST(5), CONST(-1)))` has dtype `weakint`, not `int32`, because
  # `promo_dtype` promotes an `int` against a negative `int` past the signed lattice -- and
  # `weakint`'s limits are 800 bits, so the answer is already outside the window before the
  # gate is consulted. The AND arm's `s1_vmax >= 0` conjunct is a dtype-promotion
  # artefact: the state it refuses is not reachable as an INTEGER, so no integer fixture
  # can reach it and no fixture of any kind can separate the conjunct from its absence.
  ("andneg", "AND", [(5, -1)]),
  ("xor", "XOR", [(5, -1), (-5, -1), (0, -1), (2**31, -1), (5, 2), (5, 5)]),
  ("shl", "SHL", [(1, 3), (-1, 3), (255, 4), (-8, 2), (2**40, 8), (7, 0), (7, 65)]),
  ("shr", "SHR", [(1, 3), (-1, 3), (255, 4), (-8, 2), (-9, 1), (2**40, 8), (7, 0)]),
]
BOOLOPS = [
  ("orb", "OR", [(True, False), (False, True), (True, True), (False, False)]),
  ("andb", "AND", [(True, False), (False, True), (True, True), (False, False)]),
]
# Ops that carry no binary arm and must therefore FALL THROUGH to `(dtype.min, dtype.max)`
FALLTHROUGH = [
  # `THREEFRY` and `LOAD` are NOT here and the reason is in the code: `THREEFRY`'s dtype is
  # `uint64` and `LOAD`'s src is a CONST whose `buf_uop` is itself, so neither fixture's
  # dtype is the `int32` the Bend side names. `UOp.__init__` takes no `dtype` -- tinygrad
  # DERIVES it -- so a fixture whose derived dtype is not the one the row names cannot be
  # gated. `CMPEQ` derives `bool`, which both sides agree on, and it is the op with NO arm
  # in the binary block, which is the whole point of this family.
  ("ft_cmpeq", "CMPEQ", (2, 3), "boolean"),
]
# THE `self.dtype is not dtypes.void` GUARD ON RANGE/SPECIAL IS NOT EXERCISED, and it is
# not reachable rather than untested: `dtype_from_uop` derives a RANGE's and a SPECIAL's
# dtype from `src[0].dtype`, which is an integer CONST, so neither can ever BE void. The
# arm is kept (a `Bool.pick` on `dt_is.is_void(d)`) and `mm.range`'s comment says so.
# ops OUTSIDE the binary block, each with its own src arity
THREE = [
  ("where1", "WHERE", [1, 3, -4], "int32"),
  ("where2", "WHERE", [1, -3, 4], "int32"),
  ("where3", "WHERE", [0, 3, 4], "int32"),
  # PAD OVER A FLOAT SOURCE. `min(1.5, 0)` is the INTEGER 0 in CPython, so this row is the
  # only one that can tell the `F32` comparison from the saturating one.
  ("padf", "PAD", [1.5, 0, 1], "float32"),
  ("padn", "PAD", [-1.5, 0, 2], "float32"),
]
MV = [("RESHAPE", 1), ("EXPAND", 1), ("PERMUTE", 1), ("SHRINK", 1), ("FLIP", 1),
      ("INDEX", 1), ("STAGE", 1), ("AFTER", 1), ("DETACH", 1), ("COPY", 1),
      ("CONTIGUOUS_BACKWARD", 1), ("PAD", 3)]
CONSTS = [("c0", 0), ("c1", 1), ("cm1", -1), ("c31", 2**31), ("cf", 1.5), ("cfn", -1.5),
          ("cb", True), ("cbf", False)]
RANGES = [("range4", 4), ("range0", 0), ("rangen3", -3)]
STACKS = [("stack1", [3]), ("stack2", [1, -2]), ("stack3", [1, -2, 5]), ("stack4", [-2**31, 2**31])]
PARAMS = [("param0", 3, 7), ("param1", -2**40, -1), ("param2", 0, 0)]
# rows where CPython is UNBOUNDED and the port saturates: emitted `lfx_`, never equal-gated
SAT = [("sat_add", "ADD", 2**63, 2**63), ("sat_sub", "SUB", -2**63, 2**63),
       ("sat_mul", "MUL", 2**63, 2), ("sat_addneg", "ADD", -2**63, -2**63)]

M64 = (1 << 64) - 1


def u32(v):
  return v & 0xFFFFFFFF


def i64(v):
  # `H.i64_of_hi_lo(hi, lo)` puts the HIGH word FIRST -- `H.i64_text` prints `hi:lo` and the
  # committed `mm_*` rows read that way (`mm_add_small 0:12` is the number 12). Getting
  # these two the wrong way round makes every magnitude `v * 2**32`, which saturates every
  # product and was 97 of this gate's 123 rows disagreeing before it was measured.
  return u32(v >> 32), u32(v)


def cp_bnd(v):
  """one CPython `_min_max` endpoint as the port's `bnd_show` spelling."""
  if v == float('-inf'):
    return "NInf"
  if v == float('inf'):
    return "PInf"
  if isinstance(v, float):
    return "F" + (f"{v:g}" if v.is_integer() else repr(v))
  if v is False or v == 0:
    return "+0:0" if v is not True else "+0:1"
  if v is True or v == 1 and isinstance(v, bool):
    return "+0:1"
  return ("-" if v < 0 else "+") + str(abs(v) >> 32) + ":" + str(abs(v) & 0xFFFFFFFF)


def cp_pair(a, b):
  return f"lo={cp_bnd(a)} hi={cp_bnd(b)}"


def lit(v):
  h, l = i64(v)
  return f"H.i64_of_hi_lo({h}, {l})"


def f32(v):
  """A Python float as an exact `F32` EXPRESSION, because Bend has no float literal.

  `F32.from_nat` truncates, so `1.5` written as `F32.from_nat(1n)` is `1` and the gate
  disagrees on a value that looks right -- which is the whole `F32` story this repo keeps
  re-measuring. `1.5` is `3 / 2`, and every fp8/fp16 maximum in the dtype table is an
  integer, so a division by two covers the only non-integer float bound tinygrad has."""
  if float(v).is_integer():
    e = f"F32.from_nat({int(abs(v))}n)"
  else:
    e = f"F32.div(F32.from_nat({int(abs(v) * 2)}n), F32.from_nat(2n))"
  return f"F32.neg({e})" if v < 0 else e


def cst(v):
  if isinstance(v, bool):
    return f"O.CBool{{{'True{}' if v else 'False{}'}}}"
  if isinstance(v, float):
    return f"O.CFloat{{{f32(v)}}}"
  return f"O.CInt{{{lit(v)}}}"


def stack_call(vals):
  n = len(vals)
  return 'lf_c%d(%s)' % (n, ', '.join(bnd(v) for v in vals))


def bnd(v):
  """One Python number as the port's SIGN-AND-MAGNITUDE `Bnd`, spelled directly.

  NOT through `mm.i64.to_bnd`, and the reason is the width: `mm.i64.to_bnd` reads the
  two's-complement SIGN BIT, so any magnitude at or above `2**63` -- which `BndInt`'s
  UNSIGNED 64-bit magnitude holds comfortably -- comes back NEGATIVE. `2**63 + 2**63` is
  the saturation fixture and it needs `neg = False` with a magnitude of `2**63`, which is
  exactly the value the sign-extending reader cannot produce."""
  if isinstance(v, bool):
    return f"bnd_tf({'True{}' if v else 'False{}'})"
  if isinstance(v, float):
    # a float bound's lower half is the ONLY place PAD compares the two classes, and it
    # compares them in `F32` rather than saturating -- so the fixture names the value
    return f"bnd_f({f32(v)})"
  return f"BndInt{{{'True{}' if v < 0 else 'False{}'}, {lit(abs(v))}}}"


DT = {"int32": "S.int32()", "float32": "S.single()", "bool": "S.boolean()",
       "boolean": "S.boolean()"}


def run():
  from tinygrad import dtypes
  from tinygrad.uop.ops import UOp, Ops, ParamArg
  from tinygrad.uop.ops import InvalidType
  O = Ops

  def mk(op, vals, dt):
    # `UOp.__init__` takes no `dtype`: tinygrad DERIVES it, so a fixture's dtype is a
    # consequence of its srcs and not something the gate chooses. That is why the Bend
    # side spells `S.int32()`/`S.boolean()` and why a fixture CPython cannot build is a
    # fixture the port never sees either.
    try:
      return UOp(op, src=tuple(UOp(O.CONST, arg=v) for v in vals))
    except Exception:
      return None

  out = []
  for label, opn, pairs in BIN:
    for a, b in pairs:
      for dt in ("int32",):
        n = mk(getattr(O, opn), (a, b), dt)
        if n is None:
          continue
        lo, hi = n._min_max
        if max(abs(lo), abs(hi)) > M64:
          continue                      # a float-dtype arm saturates the port; not this table
        if isinstance(lo, float) or isinstance(hi, float):
          continue                      # CPython's own float arithmetic, not this table's
        out.append((f"lf_{label}_{dt}_{a}_{b}", cp_pair(lo, hi),
                    f'lf_row("{label}_{dt}_{a}_{b}", mm.lift(O.Ops{opn}{{}}, lf_c2({bnd(a)}, {bnd(b)}), O.ANone{{}}, {DT[dt]}))'))
  for label, opn, pairs in BOOLOPS:
    for a, b in pairs:
      n = mk(getattr(O, opn), (a, b), "bool")
      if n is None:
        continue
      lo, hi = n._min_max
      out.append((f"lf_{label}_{a}_{b}", cp_pair(lo, hi),
                  f'lf_row("{label}_{a}_{b}", mm.lift(O.Ops{opn}{{}}, lf_c2({bnd(a)}, {bnd(b)}), O.ANone{{}}, S.boolean()))'))
  for entry in FALLTHROUGH:
    label, opn, (a, b) = entry[0], entry[1], entry[2]
    dt = entry[3] if len(entry) > 3 else "int32"
    n = mk(getattr(O, opn), (a, b), dt)
    if n is None:
      continue
    lo, hi = n._min_max
    out.append((f"lf_{label}", cp_pair(lo, hi),
                f'lf_row("{label}", mm.lift(O.Ops{opn}{{}}, lf_c2({bnd(a)}, {bnd(b)}), O.ANone{{}}, {DT[dt]}))'))
  for label, opn, vals, dt in THREE:
    n = mk(getattr(O, opn), vals, dt)
    if n is None:
      continue
    lo, hi = n._min_max
    out.append((f"lf_{label}", cp_pair(lo, hi),
                f'lf_row("{label}", mm.lift(O.Ops{opn}{{}}, lf_c3({bnd(vals[0])}, {bnd(vals[1])}, {bnd(vals[2])}), O.ANone{{}}, {DT[dt]}))'))
  for opn, n in MV:
    vals = (3,) * n
    node = mk(getattr(O, opn), vals, "int32")
    if node is None:
      continue
    lo, hi = node._min_max
    out.append((f"lf_mv_{opn.lower()}", cp_pair(lo, hi),
                f'lf_row("mv_{opn.lower()}", mm.lift(O.Ops{opn}{{}}, {stack_call(vals)}, O.ANone{{}}, S.int32()))'))
  for label, v in CONSTS:
    node = UOp(O.CONST, arg=v)
    lo, hi = node._min_max
    out.append((f"lf_{label}", cp_pair(lo, hi),
                f'lf_row("{label}", mm.lift(O.OpsCONST{{}}, lf_c0(), O.APy{{{cst(v)}}}, S.int32()))'))
  # `Invalid` is a CONST whose arg is not a number, and CPython's arm skips it
  node = UOp(O.CONST, arg=InvalidType())
  lo, hi = node._min_max
  out.append(("lf_cinv", cp_pair(lo, hi),
              # `Invalid`'s dtype is `bool` BY CONSTRUCTION -- `dtype_from_uop` says "Invalid
              # is always bool, the promo lattice bottom" -- so the row names `bool` and NOT
              # the int32 every other CONST row names. Writing `int32` here put int32's limits
              # on both lanes' default path and disagreed with CPython by 2**31.
              'lf_row("cinv", mm.lift(O.OpsCONST{}, lf_c0(), O.APy{O.CInvalid{}}, S.boolean()))'))
  node = UOp(O.CONST, arg=float('nan'))
  lo, hi = node._min_max
  out.append(("lf_cnan", cp_pair(lo, hi),
              'lf_row("cnan", mm.lift(O.OpsCONST{}, lf_c0(), O.APy{O.CFloat{F32.div(F32.from_nat(0n), F32.from_nat(0n))}}, S.single()))'))
  for label, v in RANGES:
    node = UOp(O.RANGE, src=(UOp(O.CONST, arg=v),))
    lo, hi = node._min_max
    out.append((f"lf_{label}", cp_pair(lo, hi),
                f'lf_row("{label}", mm.lift(O.OpsRANGE{{}}, lf_c1({bnd(v)}), O.ANone{{}}, S.int32()))'))
    # a SPECIAL's dtype is `dtypes.void` BY CONSTRUCTION (ops.py:1123), so the arm's
    # `self.dtype is not dtypes.void` guard is False and it lands on the dtype limits
    node = UOp(O.SPECIAL, src=(UOp(O.CONST, arg=v),))
    lo, hi = node._min_max
    out.append((f"lf_spec{label[5:]}", cp_pair(lo, hi),
                f'lf_row("spec{label[5:]}", mm.lift(O.OpsSPECIAL{{}}, lf_c1({bnd(v)}), O.ANone{{}}, S.int32()))'))
  for label, vals in STACKS:
    node = UOp(O.STACK, src=tuple(UOp(O.CONST, arg=v) for v in vals))
    lo, hi = node._min_max
    out.append((f"lf_{label}", cp_pair(lo, hi),
                f'lf_row("{label}", mm.lift(O.OpsSTACK{{}}, {stack_call(vals)}, O.ANone{{}}, S.int32()))'))
  for label, a, b in PARAMS:
    for opn, pa in (("PARAM", UOp(O.PARAM, arg=ParamArg(0, dtypes.i32, None, (a, b)))),
                    ("ALLOC", UOp(O.ALLOC, arg=ParamArg(0, dtypes.i32, (b - a + 1), (a, b))))):
      lo, hi = pa._min_max
      nm = label if opn == "PARAM" else f"{label}_{opn.lower()}"
      out.append((f"lf_{nm}", cp_pair(lo, hi),
                  f'lf_row("{nm}", mm.lift(O.Ops{opn}{{}}, lf_c0(), lf_pa({lit(a)}, {lit(b)}), S.int32()))'))
  return out, SAT


def dupe_names(rows):
  """Row names this fixture list prints MORE THAN ONCE, with how often.

  MEASURED 2026-10-04, and it was invisible to everything that had run this file. `SUB`'s pair
  list carries `(-3, 4)` twice -- positions 1 and 4 -- so the list produces eight `sub` rows
  with SEVEN distinct names, and `uop/fold.bend:5862` and `:5865` print the same
  `lf_sub_int32_-3_4` twice. A `diff` of the two lanes is GREEN over it (both sides have the
  duplicate, so the line multisets match) and so is any comparison keyed on NAME (the dict keeps
  the last and the first is gone with nothing saying so). Only a COUNT OF LINES against a count
  of names sees it, which is why `.agents/slop/mmfold/mmfold-lane.py` reports `printed twice`
  beside every row count.

  The fixture is NOT deleted here. Deleting it makes `--emit-bend` stop emitting the second line
  while `fold.bend` keeps it, which trades a duplicated measurement for an unexplained port row
  -- a worse defect, and one in a file this unit must not edit. The duplicate is REPORTED, and
  the fix belongs to whoever owns `fold.bend`: drop `fold.bend:5865`.
  """
  seen = {}
  for name, *_ in rows:
    seen[name] = seen.get(name, 0) + 1
  return {n: c for n, c in seen.items() if c > 1}


def emit_py():
  rows, sat = run()
  for name, pair, _ in rows:
    print(f"{name} {pair}")
  for name, opn, a, b in sat:
    print(f"lf_{name} {port_sat(opn, a, b)}")
  # the CPython numbers the saturating rows REPLACE, as diagnostics the `^lf_` gate does
  # not read -- the same treatment `mm-bl-gate.py` gives the four width probes
  for name, opn, a, b in sat:
    print(f"satcp_{name} {cp_real(opn, a, b)}")
  for name, c in sorted(dupe_names(rows).items()):
    print(f"DUPLICATE {name} printed {c} times -- one case measured twice, not two cases")


def emit_bend():
  rows, sat = run()
  for _, _, line in rows:
    print(line)
  for name, opn, a, b in sat:
    print(f'lf_row("{name}", mm.lift(O.Ops{opn}{{}}, lf_c2({bnd(a)}, {bnd(b)}), O.ANone{{}}, S.int32()))')


def cp_real(opn, a, b):
  from tinygrad.uop.ops import UOp, Ops
  n = UOp(getattr(Ops, opn), src=(UOp(Ops.CONST, arg=a), UOp(Ops.CONST, arg=b)))
  return f"lo={n._min_max[0]} hi={n._min_max[1]}"


def port_sat(opn, a, b):
  from tinygrad.uop.ops import UOp, Ops, ParamArg
  from tinygrad.uop.ops import InvalidType
  n = UOp(getattr(Ops, opn), src=(UOp(Ops.CONST, arg=a), UOp(Ops.CONST, arg=b)))
  lo, hi = n._min_max
  def clip(v):
    if v > M64 or v < -(2 ** 63):
      return "PInf" if v > 0 else "NInf"
    return cp_bnd(v)
  return f"lo={clip(lo)} hi={clip(hi)}"


def pin_or_reexec():
  """Run under the interpreter `oracle_py` names, whichever one launched this file.

  `resolve()` exits 2 with `Nothing was checked.` when it cannot name one, so a caller that
  sees rc 2 knows the run never happened and did not merely find nothing. Its refusal goes to
  STDERR, and a refusal nobody reads on STDOUT is the defect this file is fixing -- so the
  `SystemExit` is caught and re-announced as `DIED` on STDOUT as well."""
  try:
    with contextlib.redirect_stderr(buf := io.StringIO()):
      exe = oracle_py.resolve()[0]
  except SystemExit as e:
    why = next((l.strip() for l in buf.getvalue().splitlines() if l.strip()), "no detail")
    die(f"oracle_py refused to name an interpreter: {why}")
  if os.path.realpath(sys.executable) == os.path.realpath(exe):
    return exe
  if os.environ.get(PIN_ENV):
    die("re-exec landed on an interpreter oracle_py did not name")
  os.environ[PIN_ENV] = exe
  os.execv(exe, [exe, str(pathlib.Path(__file__).resolve()), *sys.argv[1:]])


def die(why):
  """`DIED` on STDOUT and rc 2. The exit code alone is not enough: three harnesses here read
  STDOUT and count lines, and a line is what separates "no rows" from "no run"."""
  print(f"DIED mm-lift-gate {why}")
  sys.stderr.write(f"mm-lift-gate: DIED {why}\n  Nothing was checked.\n")
  raise SystemExit(DIED_RC)


def selftest():
  """The death path, EXERCISED TWICE, once per refusal `oracle_py` can make.

  Both run in a throwaway tree so nothing here touches the live one, and the layout matters:
  `oracle_py` derives its repo as `parents[1]` of the file's directory, so the copy must sit at
  `<tmp>/repo/.agents/slop/` for `<tmp>/repo/.venv` to be the `.venv` it looks for. Case 1
  deletes that `.venv`, which is `resolve()`'s `ORACLE PYTHON MISSING`. Case 2 keeps a
  `.venv/bin/python` that is a shim running a site-less interpreter, which is the LITERAL
  original defect -- a python that exists and cannot import tinygrad -- and is
  `resolve()`'s `CANNOT IMPORT tinygrad`. Two different refusals, because a control that can
  only produce one answer is not a control.

  `pass` is on purpose: an unrun control is not a control, so a fixture that fails to set up
  reports FAIL rather than the number it hoped for.
  """
  import shutil
  import subprocess
  import tempfile

  shim = "#!/bin/sh\nexec /opt/homebrew/bin/python3 -S \"$@\"\n"
  ok = True
  for label, mkvenv in (("no .venv (resolve: PYTHON MISSING)", False),
                        ("a .venv whose python cannot import tinygrad (resolve: CANNOT IMPORT)", True)):
    with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR", None)) as td:
      repo = pathlib.Path(td) / "repo"
      dst = repo / ".agents" / "slop"
      dst.mkdir(parents=True)
      for f in ("mm-lift-gate.py", "oracle_py.py"):
        shutil.copy2(SLOP / f, dst / f)
      if mkvenv:
        vpy = repo / ".venv" / "bin"
        vpy.mkdir(parents=True)
        p = vpy / "python"
        p.write_text(shim)
        p.chmod(0o755)
      r = subprocess.run([sys.executable, str(dst / "mm-lift-gate.py")],
                         capture_output=True, text=True, timeout=600)
      said = [l for l in r.stdout.splitlines() if l.startswith("DIED ")]
      good = r.returncode == DIED_RC and len(said) == 1
      ok = ok and good
      print(f"selftest {label}\n  rc={r.returncode} (want {DIED_RC})  "
            f"stdout DIED lines={len(said)} (want 1)  {'PASS' if good else 'FAIL'}")
      for l in said:
        print(f"  {l}")
      if not good:
        print("  stderr:", (r.stderr.strip().splitlines() or ["<none>"])[-1])
  print("selftest:", "PASS" if ok else "FAIL -- a death did not announce itself")
  raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
  if "--selfcheck" in sys.argv:
    selftest()
  try:
    pin_or_reexec()
    if "--emit-bend" in sys.argv:
      emit_bend()
    elif "--emit-rows" in sys.argv:
      rows, _ = run()
      for name, pair, _ in rows:
        print(f"{name} {pair}")
    else:
      emit_py()
  except SystemExit:
    raise
  except BaseException as e:
    die(f"{type(e).__name__}: {e}")