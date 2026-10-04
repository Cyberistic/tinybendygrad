#!/usr/bin/env python3
"""ops-key-probe.py -- MEASURE the five disputed comparators against `ops.py:201`'s key.

    .venv/bin/python .agents/slop/ops-key-probe.py

`UOpMetaClass.__call__` keys on `(op, src, arg, tag, type(arg))` (ops.py:201). The key
HOLDS `arg`, so dict equality compares it by the arg's OWN `__eq__`. A comparator weaker
than that merges two nodes CPython keeps apart; a comparator STRONGER than that splits two
nodes CPython merges. Both are fidelity defects and they are measured here in the
direction each one fails.

THE FIXTURE IS THE TEST. Every pair below differs in EXACTLY ONE FIELD of the arg and
nowhere else. A pair that differed in some other field would be satisfied by a
comparator that drops the one under test, which is the whole failure being looked for.

  * `aux` / `grad_fxn`   -- `CallInfo` (ops.py:1400), a frozen dataclass with FIVE
    fields. `ops.py:549` reads `arg.aux`, so `aux` is not inert.
  * `estimates`          -- `KernelInfo` (ops.py:1342), FIVE fields.
  * `target`             -- `ProgramInfo` (ops.py:1352), SEVEN fields.
  * `vmin_vmax`          -- `ParamArg.vmin_vmax: tuple[PyConst, PyConst]|None`
    (ops.py:30) where `PyConst = float|int|bool` (dtype.py:38). The port spells this
    `PyRange{lo: H.I64, hi: H.I64}`, so a float or bool bound is not representable.
  * `tag`                -- `ops.py:201` puts `type(arg)` in the key and NOT
    `type(tag)`, so `tag=True` and `tag=1` are ONE key in CPython (`True == 1` and
    `hash(True) == hash(1)`).

`TG_TREE` picks the tree, exactly as `ops-oracle.py` does.
"""

import os
import sys

TAG = os.environ.get("TG_TREE", ".agents/slop/opstree")
if TAG != ".":
  sys.path.insert(0, TAG)

from tinygrad.uop.ops import UOp, Ops, ParamArg, KernelInfo, ProgramInfo, CallInfo  # noqa: E402
from tinygrad.uop.ops import UOpMetaClass  # noqa: E402
from tinygrad import dtypes  # noqa: E402
from tinygrad.dtype import ConstFloat  # noqa: E402
# The REAL field types, not stand-ins. What decides whether a field is in the key is the
# dataclass `__eq__` of the record that HOLDS it, so `aux` is measured with hcq2's real
# `HCQInfo` (the only thing upstream ever puts there) and `target` with the real `Target`.
from tinygrad.runtime.support.hcq2 import HCQInfo  # noqa: E402
from tinygrad.renderer import Estimates  # noqa: E402
from tinygrad.device import Target  # noqa: E402

# `grad_fxn: Callable|None` is a Python function object. Two DISTINCT function objects
# are two distinct values, which is the cell that matters for the key.
def _gf_a():
  return None


def _gf_b():
  return None


_GF_A, _GF_B = _gf_a, _gf_b

print(f"#probe_tree={TAG}")

# `ucache` holds weakrefs and `UOp.__del__` deletes BY KEY BY VALUE, so every node built
# here is retained for the whole probe. A pair that is not kept can delete the key it
# just registered and `is` then answers about a node the cache has forgotten.
KEEP = []


def cell(build):
  """One pair on a FRESH ucache, plus the node COUNT that pair produced.

  The count must be read INSIDE the cell: the cache accumulates, so a `len` after two
  cells is the union and not the cell.
  """
  UOpMetaClass.ucache.clear()
  u, v = build()
  KEEP.append((u, v))
  return u, v, len(UOpMetaClass.ucache)


# ---------------------------------------------------------------------------
# 1. `aux` -- the FIRST question, because `ops.py:549` READS it:
#     `if isinstance(arg, CallInfo) and hasattr(aux:=arg.aux, "written_bufs")`.
#     Two CALLs identical in name, precompile, precompile_backward and dtype, differing
#     ONLY in `aux`.
# ---------------------------------------------------------------------------
_ci_body = UOp.sink(UOp.const(1, dtypes.int32))


def _mk_call(aux, grad_fxn=None):
  body = UOp.sink(UOp.const(1, dtypes.int32))
  return UOp(Ops.CALL, src=(body,), arg=CallInfo(name="k", precompile=False,
                                                  precompile_backward=False, aux=aux,
                                                  grad_fxn=grad_fxn))


# `written_bufs` is the field `ops.py:549` walks, so the fixture uses it. The buffer
# entries are held as trace numbers in that rewrite and as UOps in the live record; a
# plain int is enough to make the two records unequal, and `HCQInfo` is a frozen
# dataclass so the comparison is fieldwise.
_u0, _u1, _un0 = cell(lambda: (_mk_call(HCQInfo(device=("0:0",), written_bufs=(0,))),
                               _mk_call(HCQInfo(device=("0:0",), written_bufs=(1,)))))
print(f"aux_written_bufs_splits={_u0 is not _u1}")
print(f"aux_written_bufs_nodes={_un0}")

_u2, _u3, _un1 = cell(lambda: (_mk_call(HCQInfo(device=("0:0",), written_bufs=(0, 1))),
                               _mk_call(HCQInfo(device=("0:0",), written_bufs=(0, 1)))))
print(f"aux_equal_interns={_u2 is _u3}")

_u4, _u5, _un2 = cell(lambda: (_mk_call(HCQInfo(device=("0:0",))), _mk_call(None)))
print(f"aux_none_vs_obj_splits={_u4 is not _u5}")

_u6, _u7, _un3 = cell(lambda: (_mk_call(None, grad_fxn=None), _mk_call(None, grad_fxn=_GF_B)))
print(f"grad_fxn_splits={_u6 is not _u7}")
print(f"grad_fxn_nodes={_un3}")

# ---------------------------------------------------------------------------
# 2. `estimates` -- `KernelInfo` (ops.py:1342) is a frozen dataclass with FIVE fields
#    and `estimates` is the fourth. Two SINKs identical in name, applied_opts,
#    opts_to_apply and beam, differing ONLY in `estimates`.
# ---------------------------------------------------------------------------


def _mk_kernel(estimates):
  body = UOp.sink(UOp.const(1, dtypes.int32))
  return UOp(Ops.SINK, src=(), arg=KernelInfo(name="k", applied_opts=(), opts_to_apply=None,
                                              estimates=estimates, beam=0))


_k0, _k1, _kn0 = cell(lambda: (_mk_kernel(Estimates(ops=1)), _mk_kernel(Estimates(ops=2))))
print(f"estimates_splits={_k0 is not _k1}")
print(f"estimates_nodes={_kn0}")

_k2, _k3, _kn1 = cell(lambda: (_mk_kernel(Estimates(ops=1)), _mk_kernel(Estimates(ops=1))))
print(f"estimates_equal_interns={_k2 is _k3}")

_k4, _k5, _kn2 = cell(lambda: (_mk_kernel(Estimates(ops=1)), _mk_kernel(None)))
print(f"estimates_none_splits={_k4 is not _k5}")

# ---------------------------------------------------------------------------
# 3. `target` -- `ProgramInfo` (ops.py:1352) is a frozen dataclass with SEVEN fields and
#    `target` is the last. Two PROGRAMs identical in the six others, differing ONLY in
#    `target`.
# ---------------------------------------------------------------------------


def _mk_program(target):
  body = UOp.sink(UOp.const(1, dtypes.int32))
  return UOp(Ops.PROGRAM, src=(body,), arg=ProgramInfo(global_size=(1, 1, 1), local_size=(1, 1, 1),
                                                       vars=(), globals=(), outs=(), ins=(),
                                                       target=target))


_p0, _p1, _pn0 = cell(lambda: (_mk_program(Target(arch="sm_120")), _mk_program(Target(arch="sm_90"))))
print(f"target_splits={_p0 is not _p1}")
print(f"target_nodes={_pn0}")

_p2, _p3, _pn1 = cell(lambda: (_mk_program(Target(arch="sm_120")), _mk_program(Target(arch="sm_120"))))
print(f"target_equal_interns={_p2 is _p3}")

# ---------------------------------------------------------------------------
# 4. `vmin_vmax` -- `PyConst = float|int|bool` (dtype.py:38) and
#    `ParamArg.vmin_vmax: tuple[PyConst, PyConst]|None` (ops.py:30). The port's
#    `PyRange{lo: H.I64, hi: H.I64}` cannot hold a float or a bool, so the fixture is a
#    pair that differs ONLY in `vmin_vmax`, and the third pair asks whether the int/float
#    split upstream's `type(arg)` does NOT make for a NESTED value is made anyway.
# ---------------------------------------------------------------------------


def _mk_param(vm, dtype=dtypes.int32):
  return UOp(Ops.PARAM, src=(), arg=ParamArg(slot=0, dtype=dtype, vmin_vmax=vm))


_v0, _v1, _vn0 = cell(lambda: (_mk_param((0, 1)), _mk_param((0, 2))))
print(f"vmin_vmax_int_splits={_v0 is not _v1}")
print(f"vmin_vmax_int_nodes={_vn0}")

_v2, _v3, _vn1 = cell(lambda: (_mk_param((0, 1.0)), _mk_param((0, 2.0))))
print(f"vmin_vmax_float_splits={_v2 is not _v3}")
print(f"vmin_vmax_float_nodes={_vn1}")

# A float bound against an int bound of the same value. `type(arg)` is `ParamArg` for
# both, so upstream does NOT split them -- which is the cell that decides whether a
# `Const`-valued `PyRange` compared with `eq_const` (which DOES split bool from int)
# would over-split here.
_v4, _v5, _vn2 = cell(lambda: (_mk_param((0, 1.0)), _mk_param((0, 1))))
print(f"vmin_vmax_float_vs_int_interns={_v4 is _v5}")

_v6, _v7, _vn3 = cell(lambda: (_mk_param((False, True)), _mk_param((0, 1))))
print(f"vmin_vmax_bool_vs_int_interns={_v6 is _v7}")

# The signed zeros: `ConstFloat` hashes `bits`, so upstream KEEPS THESE APART even though
# IEEE says they are equal. `PyRange{H.I64}` cannot express the distinction.
_v8, _v9, _vn4 = cell(lambda: (_mk_param((0, ConstFloat(-0.0)), dtypes.float32),
                                _mk_param((0, ConstFloat(0.0)), dtypes.float32)))
print(f"vmin_vmax_signed_zero_splits={_v8 is not _v9}")

# And the top-level CONST cell, which is the ONE place upstream's key carries a type:
# `type(arg)` separates `True` from `1` at the top but NOT inside a `ParamArg`.
_c0, _c1, _cn0 = cell(lambda: (UOp(Ops.CONST, src=(), arg=True), UOp(Ops.CONST, src=(), arg=1)))
print(f"const_bool_vs_int_splits={_c0 is not _c1}")

# ---------------------------------------------------------------------------
# 5. `type(tag)` -- `ops.py:201` carries `type(arg)` and NOT `type(tag)`, so two tags
#    that compare equal are ONE key. `True == 1` and `hash(True) == hash(1)`.
# ---------------------------------------------------------------------------
_t0, _t1, _tn0 = cell(lambda: (UOp(Ops.SINK, src=(), arg=None, tag=True),
                               UOp(Ops.SINK, src=(), arg=None, tag=1)))
print(f"tag_bool_vs_int_interns={_t0 is _t1}")
print(f"tag_bool_vs_int_nodes={_tn0}")

_t2, _t3, _tn1 = cell(lambda: (UOp(Ops.SINK, src=(), arg=None, tag=True),
                               UOp(Ops.SINK, src=(), arg=None, tag=False)))
print(f"tag_true_vs_false_splits={_t2 is not _t3}")

_t4, _t5, _tn2 = cell(lambda: (UOp(Ops.SINK, src=(), arg=None, tag=None),
                               UOp(Ops.SINK, src=(), arg=None, tag=0)))
print(f"tag_none_vs_zero_interns={_t4 is _t5}")

# `rtag(self, tag=True)` -- ops.py:258. What `rtag()` with no argument produces, and
# whether that equals a node built with `tag=True` directly.
_b0 = UOp.sink(UOp.const(1, dtypes.int32))
_b1 = _b0.rtag()
print(f"rtag_default_tag={_b1.tag!r}")
print(f"rtag_type={type(_b1.tag).__name__}")
print(f"rtag_is_rtag={_b0.rtag() is _b1}")

KEEP.clear()
UOpMetaClass.ucache.clear()