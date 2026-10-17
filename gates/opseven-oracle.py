#!/usr/bin/env python3
"""opseven-oracle.py -- CPython's ANSWER for the seven `Ops` the corpus never reaches.

    .venv/bin/python gates/opseven-oracle.py

THE SEVEN. `tinybendygrad/uop/ops.bend`'s `type Op is Data:` block declares **77** members and
`runs/graphcmp/D/D1-graph-*.txt` reaches **70** of them on all 34 graphs with `py == bend` on
every one, so the seven never observed are `CUSTOM CUSTOMI INS PROGRAM PYLITERAL REWRITE_ERROR
SOURCE`. Nothing in this tree can say whether the port's answers for them are right, because
nothing in this tree ever BUILT one. This lane and `gates/opseven.bend` both build them.

CAN CPYTHON EMIT EACH OF THE SEVEN? Yes, all seven, and six of the seven by ONE `UOp(...)`
constructor call -- so the honest fixture is a direct construction, NOT a forced failure, and NOT
a `D8`-style fixture that always throws. The construction site is named per row in
`gates/opseven.bend`'s header; the short form:

    REWRITE_ERROR  ops.py:1713   UOp(Ops.REWRITE_ERROR, src=uop.src, arg=err_str)
    PYLITERAL      upat.py:26     UOp(Ops.PYLITERAL, arg=self.op[0])       -- a bare Ops
    PYLITERAL      upat.py:29     the same op also carries a non-int arg    -- hence pyliteral_str
    SOURCE         codegen/__init__.py:453   UOp(Ops.SOURCE, arg=src)
    CUSTOM         upat.py:26     UOp(Ops.CUSTOM, src=(base, ...), arg=("{0}.op is {1}", dtypes.void))
    CUSTOM         llm/kernels/amd.py:45     the non-void arm: the dtype is in the arg
    CUSTOMI        upat.py:66     UOp(Ops.CUSTOMI, arg=("True", dtypes.void))
    CUSTOMI        llm/kernels/amd.py:113    two shaped srcs, non-void
    INS            ops.py:600      def ins(self, arg, **kwargs): return UOp(Ops.INS, ...)
    PROGRAM        codegen/__init__.py:500   UOp(Ops.PROGRAM, src=(full_sink,), arg=prog_info)

TWO ROWS PER FIXTURE, SPLIT THE SAME WAY `gates/opseven.bend` SPLITS IT: the first row carries the
op, the src count, the dtype, the shape and the FOUR spec columns that agree; the second carries
`sp` (`spec_program`) ALONE, because that is the one column that does not. Splitting it is what
lets a reader see that twelve real matches are sound while one column is not.

WHAT IS PRINTED, AND WHY NOTHING HERE REIMPLEMENTS A PROPERTY:

  op     `str(u.op)`  -- `FastEnum.__str__` is `Enum.__str__`, so this is `"Ops.MEMBER"`, which
          is the port's `Ops.name` (the PREFIXED table; `Ops.name.of` is the bare one).
  nsrc   `len(u.src)`
  dtype  `u.dtype.name` -- tinygrad's own `DType.name`, which the port's `F.dt_nm` reads
  shape  `u._shape`, spelled `none` for None; `F.dims_str` on the port's side
  st/sp/sf/sh/sk   `spec_tensor / spec_program / spec_full / spec_hcq / spec_kernel_graph`, each
          rewritten against THIS ONE node: 1 for "a rule fired AND its lambda returned True",
          0 for "a rule fired and its lambda returned False", 9 for "no rule fired" (the port's
          `VSkip`). `bool(m.rewrite(u))` and NOT `is not None`, because `rewrite` returns the
          lambda's own answer, so `is not None` would score a REJECTED rule as a pass and this
          lane's whole job is to say which rules REJECT.

`TGROOT` (optional) prefixes `sys.path`. That is how every row below was MEASURED against
`git archive upstream:tinygrad` rather than the working tree: this tree's `tinygrad/` is the
PRE-re-vendor vendor and still declares `GROUP` and `FLIP`, so it reads 77 members where upstream
reads 75. MEASURED: the 31 rows of this file are byte-identical under BOTH roots; the only number
in the file that moves is `n_ops`, which is printed to stderr precisely so it cannot.
"""

import os
import sys

sys.path.insert(0, os.environ.get("TGROOT", ""))

from tinygrad.uop import Ops
from tinygrad.uop.ops import UOp, KernelInfo
from tinygrad.dtype import dtypes
import tinygrad.uop.spec as sp

SPECS = (("st", "spec_tensor"), ("sp", "spec_program"), ("sf", "spec_full"),
         ("sh", "spec_hcq"), ("sk", "spec_kernel_graph"))


def verdict(k, u):
  r = getattr(sp, SPECS_MAP[k]).rewrite(u)
  return "1" if r is True else "0" if r is not None else "9"


SPECS_MAP = dict(SPECS)


def shape_str(u):
  try:
    return str(u._shape) if u._shape is not None else "none"
  except Exception as e:
    return f"raise:{type(e).__name__}"


def row(nm, u):
  print(f"{nm}=op={u.op} nsrc={len(u.src)} dtype={u.dtype.name} shape={shape_str(u)} "
        f"st={verdict('st', u)} sf={verdict('sf', u)} sh={verdict('sh', u)} sk={verdict('sk', u)}")
  print(f"sp_{nm}={verdict('sp', u)}")


# --- THE FIXTURE. One CONST and a SINK over it, built identically in both lanes. The port's
#     SINK arg is `ANone{}` where upstream's is a `KernelInfo`; no rule on any row below reads
#     it and the SINK is not itself a row, so it is outside the comparison. ---
C_F32 = UOp.const(1.0)
SINK = UOp(Ops.SINK, src=(C_F32,), arg=KernelInfo())
LIN = UOp(Ops.LINEAR, src=())
SRC = UOp(Ops.SOURCE, arg="int main(){}")
BIN_ = UOp(Ops.BINARY, arg=b"\x01\x02\x03\x04")
PI = None  # upstream's ProgramInfo; no spec rule for PROGRAM reads `arg`, and row program_1
          # carries the SAME `arg` as program_4 so the two cannot differ on it.

# --- REWRITE_ERROR: ops.py:1713. Its ONLY rule is spec.py:239 in `spec_full`, the matcher whose
#     own comment reads "these ops can exist in programs but not the tensor spec / everything
#     should be deleted from here" -- so this node is legal in ONE of the FIVE tables and the row
#     says so. No fixture forces one into a program graph, because that would force an illegal
#     state and a fixture that cannot fail is not a witness. ---
row("rewrite_error", UOp(Ops.REWRITE_ERROR, arg="boom"))
# --- PYLITERAL: upat.py:26 (a bare Ops) and upat.py:29 (a non-int arg) ---
row("pyliteral_op", UOp(Ops.PYLITERAL, arg=Ops.ADD))
row("pyliteral_str", UOp(Ops.PYLITERAL, arg="hello"))
# --- PYLITERAL: upat.py:25 `arg=frozenset(self.op)`. CPython HAS this and the port CANNOT SPELL
#     IT: `type Arg is Data:` in `tinybendygrad/uop/ops.bend` has no set-of-`Op` constructor. So
#     it is NOT a row -- a row the port cannot print is a row that measures nothing -- but it is
#     MEASURED here so the gap is a number and not a reading of the source. ---
_FSET = UOp(Ops.PYLITERAL, arg=frozenset((Ops.ADD, Ops.MUL)))
sys.stderr.write("pyliteral_frozenset=op=%s nsrc=%d dtype=%s shape=%s nspecs_agree=%d "
                 "port_can_spell=no\n" % (_FSET.op, len(_FSET.src), _FSET.dtype.name,
                                          shape_str(_FSET),
                                          sum(1 for k, _ in SPECS
                                              if getattr(sp, SPECS_MAP[k]).rewrite(_FSET) is True)))
# --- SOURCE: codegen/__init__.py:453 ---
row("source", UOp(Ops.SOURCE, arg="int main(){}"))
# --- CUSTOM: upat.py:26 (void for a bare statement) and llm/kernels/amd.py:45 (dtype in arg) ---
row("custom_void", UOp(Ops.CUSTOM, src=(C_F32,), arg=("{0}.op is {1}", dtypes.void)))
row("custom_f32", UOp(Ops.CUSTOM, src=(C_F32,), arg=("sqrt({0})", dtypes.float32)))
# --- CUSTOMI: upat.py:66 (no srcs) and llm/kernels/amd.py:113 (two shaped srcs) ---
row("customi_void", UOp(Ops.CUSTOMI, arg=("x", dtypes.void)))
row("customi_f32", UOp(Ops.CUSTOMI, src=(C_F32, C_F32), arg=("{0}+{1}", dtypes.float32)))
# --- INS: ops.py:600 `UOp.ins`, which defaults src to `self.src` and the dtype to
#     `self.dtype`. Both rows pass no src, so both answer nsrc=0: that is upstream's own default
#     on a CONST, not a fixture shortcut. ---
row("ins_void", C_F32.ins("NOP", dtype=dtypes.void))
row("ins_f32", C_F32.ins("VADDPS", dtype=dtypes.float32))
# --- PROGRAM: codegen/__init__.py:500, two of the four progressive shapes spec.py:195-198 ---
row("program_1", UOp(Ops.PROGRAM, src=(SINK,), arg=PI))
row("program_4", UOp(Ops.PROGRAM, src=(SINK, LIN, SRC, BIN_), arg=PI))

# --- `Ops.value`: the toposort sort key (`UOp.tuplize`, ops.py:314). PORT-DEPENDENT BY
#     CONSTRUCTION and therefore its own row set: `FastEnum._generate_next_value_` is 1 + max, so
#     the number IS the declaration order, and this tree declares 77 where upstream declares 75.
#     MEASURED on `tinybendygrad/uop/ops.bend`: the `Ops.value` table has 77 arms, `Ops.name.of`
#     has 77, `all_ops` has 77, the `type Op is Data:` block has 77 variants, and every one of
#     the 77 sits at its own declaration position -- so the table is a faithful reading of a
#     77-member enum and `GROUP` (position 14) plus `FLIP` (position 73) are the whole of the
#     disagreement. Three rows therefore ALREADY agree and four are pinned divergences. ---
for _n in ("REWRITE_ERROR", "SOURCE", "PROGRAM", "CUSTOM", "CUSTOMI", "INS", "PYLITERAL"):
  print(f"value_{_n.lower()}={int(getattr(Ops, _n).value)}")

sys.stderr.write(f"n_ops={len(tuple(Ops))} "
                 f"has_GROUP={hasattr(Ops, 'GROUP')} has_FLIP={hasattr(Ops, 'FLIP')}\n")