#!/usr/bin/env python
# mm-dt-gate.py -- the CPython oracle for the DTYPE LIMITS, which are the twenty
# answers `_min_max`'s final `return self.dtype.min, self.dtype.max` hands back.
#
# THE SAME ZERO-TRANSCRIPTION RULE. There is nothing to generate here -- a dtype limit is
# a CONSTANT, not a computed function of a fixture pair -- so the discipline is different
# and STRICTER: the expectation is `dtypes.<name>.min` and `dtypes.<name>.max` READ FROM
# CPython, one call each, and the Bend side is a LITERAL RECORD PATTERN whose fields a
# human typed. There is no third copy to disagree with, because there are only two.
#
# What makes that safe is the SHAPE of the gate: a row is
#     bl_dt_<name> lo=<Bound> hi=<Bound>
# and `Bound` is a four-way union whose two infinite arms and whose sign bit are all
# visible in the printed string. A transposed `min`/`max` pair, a dropped sign, or a
# `uint64` answered as `int64` all change the STRING, so a mistake here cannot hide.
#
#     .venv/bin/python .agents/slop/mm-dt-gate.py                 > $OUT/dt-py.txt
#     ./bin/bend tinybendygrad/uop/fold.bend                  > $OUT/dt-bend.txt
#     diff $OUT/dt-py.txt <(grep '^bl_dt_' $OUT/dt-bend.txt)
#
# `TG_TREE` OVERRIDES WHERE `tinygrad` IS READ FROM, and it exists because another agent
# edits `tinygrad/uop/ops.py` mid-session and a half-synchronised tree makes
# `from tinygrad import dtypes` fail on an unrelated import error -- which is the
# "cold-compile failure naming a def that is not in your file" hazard from agent-core, in
# Python. Point it at a `git archive HEAD tinygrad` snapshot and the oracle reads the
# COMMITTED tinygrad regardless of what the working tree is doing. The dtype limits did
# not change in either direction; only the import was at risk.
import os
import sys

TG_TREE = os.environ.get('TG_TREE', '.')
sys.path.insert(0, TG_TREE)
from tinygrad import dtypes  # noqa: E402

M64 = (1 << 64) - 1


def bnd(v):
  """One CPython limit as the port's `Bound` spelling.

  `-inf`/`inf` are the two arms a float dtype has and no integer does. A `bool` and
  `void` dtype's limits are Python's `False` and `True`, which are NOT numbers -- and
  they are printed as `+0:0`/`+0:1` because every consumer of a bound (`resolve`'s
  `vmin == vmax`, `shard_shape`'s `int(x)`, `variable`'s `vmin_vmax is not None`)
  compares them NUMERICALLY, which in Python is what `False == 0` and `True == 1` mean.
  Anything past the port's sign-plus-u64 window is `NInf`/`PInf`, which is the sound
  over-approximation the header names; `weakint` is the one dtype where it bites."""
  if v is False:
    return "+0:0"
  if v is True:
    return "+0:1"
  if v == float('-inf'):
    return "NInf"
  if v == float('inf'):
    return "PInf"
  if isinstance(v, float):
    # `F32.show` prints an integral float without its point -- `F32.from_nat(448n)` shows
    # `448` -- so the SPELLING is normalised here and only here. The VALUE is CPython's
    # and is never touched: a dtype whose limit were 448.5 would still print `F448.5`.
    return "F" + (f"{v:g}" if v.is_integer() else repr(v))
  m = abs(v)
  if m > M64:
    return "NInf" if v < 0 else "PInf"
  return ("-" if v < 0 else "+") + f"{m >> 32}:{m & 0xFFFFFFFF}"


# THE TWENTY, in dtype.bend's own rank order, so the diff reads against the same order
# `promo_mask` and `dt_by_rank` are written in. CPython is the SOURCE of the names and
# the values; nothing here is transcribed except the NAME LIST, which is what makes the
# gate total -- a dtype added to dtype.bend without a row here shows as a missing line.
#
# `bend` is the SPEC's name for the same dtype, and the four that differ are tinyspec's
# C spellings kept because the spec IR has them: `half`/`single`/`double` for
# float16/float32/float64 and `fp8*` for float8_*. A wrong mapping is a compile error
# or a wrong `match` arm, never a silently-passing row, so this column carries no risk.
ORDER = [
  ("boolean", dtypes.bool, "boolean"),
  ("weakint", dtypes.weakint, "weakint"),
  ("int8", dtypes.i8, "int8"),
  ("uint8", dtypes.u8, "uint8"),
  ("int16", dtypes.i16, "int16"),
  ("uint16", dtypes.u16, "uint16"),
  ("int32", dtypes.i32, "int32"),
  ("uint32", dtypes.u32, "uint32"),
  ("int64", dtypes.i64, "int64"),
  ("uint64", dtypes.u64, "uint64"),
  ("weakfloat", dtypes.weakfloat, "weakfloat"),
  ("float8_e4m3", dtypes.fp8_ocp[0], "fp8e4m3"),
  ("float8_e4m3fnuz", dtypes.fp8_fnuz[0], "fp8e4m3fnuz"),
  ("float8_e5m2", dtypes.fp8_ocp[1], "fp8e5m2"),
  ("float8_e5m2fnuz", dtypes.fp8_fnuz[1], "fp8e5m2fnuz"),
  ("float16", dtypes.f16, "half"),
  ("bfloat16", dtypes.bf16, "bfloat16"),
  ("float32", dtypes.f32, "single"),
  ("float64", dtypes.f64, "double"),
  ("void", dtypes.void, "void"),
]


# THE WIDTHS NO DTYPE HAS, and they are HERE BECAUSE OF A MUTATION, NOT BECAUSE OF A
# DTYPE. `bnd_int`'s guard is `bits > 64`; changing it to `bits > 65` (DT1) moves NOTHING
# on the twenty rows, because tinygrad's widths are 8/16/32/64 and 800 and none of them is
# in (64, 800]. These four rows are that zero's fixture.
#
# There is no CPython dtype of width 65, so there is no `dtypes.<name>.min` to read. What
# IS CPython is the FORMULA -- `dtype.py`'s `-2**(bitsize-1)` and `2**bitsize - 1 + min` --
# so `cp_bits` below is that formula's own output applied to the width, and the row shows
# CPython's magnitude in BITS against the port's saturated pair. Both answers are printed,
# which is the rule: a designed divergence is GATED BOTH WAYS, not reconciled.
WIDTHS = [(65, True), (65, False), (127, True), (800, True)]


def emit_bend():
  """The Bend half of each row, GENERATED from the same ORDER list the Python half
  reads. There is nothing to transcribe: the row's payload is the CPython limit itself,
  and the arm it reaches is decided by the `Dt` literal the row names."""
  for name, _dt, bend in ORDER:
    print(f'    dt_row("{name}", bnd_lim(S.{bend}(), False{{}}), bnd_lim(S.{bend}(), True{{}}))')
  for w, sgn in WIDTHS:
    print(f'    dt_w("w{w}_{"signed" if sgn else "unsigned"}", {w}, False{{}})')


def emit_py():
  for name, dt, _bend in ORDER:
    print(f"bl_dt_{name} lo={bnd(dt.min)} hi={bnd(dt.max)}")
  for w, sgn in WIDTHS:
    lo = -(1 << (w - 1)) if sgn else 0
    hi = (1 << w) - 1 + lo
    tag = "signed" if sgn else "unsigned"
    print(f"bl_w_{w}_{tag} cp_bits={abs(lo).bit_length()}/{hi.bit_length()} "
          f"port=NInf,PInf")


if __name__ == "__main__":
  emit_bend() if "--emit-bend" in sys.argv else emit_py()
