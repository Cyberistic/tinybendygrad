#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/nn/onnx.bend -- STAGES 1 and 2.

Calls tinygrad's OWN tables and its OWN nested helpers, so a row here is
tinygrad's answer and not a restatement of the port. Every row is written in the
same shape as the Bend row (`nm=value`, no trailing space, `,` separators, join
order) so a byte diff is the test.

    .venv/bin/python .agents/slop/onnx-gate.py                        > /tmp/onnxgate/py.txt
    ./bin/bend tinybendygrad/nn/onnx.bend                             > /tmp/onnxgate/bd.txt
    ./bin/bend tinybendygrad/nn/onnx.bend -o /tmp/onnxgate/nat
    /tmp/onnxgate/nat                                                 > /tmp/onnxgate/nat.txt
    diff /tmp/onnxgate/py.txt /tmp/onnxgate/bd.txt
    diff /tmp/onnxgate/bd.txt /tmp/onnxgate/nat.txt

The nested helpers (`_onnx_pads_to_tiny_pads`, `_auto_pad`, `_resolve_pool_pads`,
`_axes`) are reached by exec-ing `get_onnx_ops`'s body with its final
`return {...}` replaced, so the oracle is tinygrad's CODE and not a second
transcription of it.
"""
import inspect
import tinygrad.nn.onnx as M
from tinygrad.nn.onnx import (OnnxDataType, AttributeType, WireType, Domain,
                              required_input_python_consts, onnx_ops)
from tinygrad.dtype import DTYPES_DICT, dtypes

ODTL = list(OnnxDataType)        # declaration order; codes 1..16 with four holes
ATL = list(AttributeType)        # 1..8
WTL = list(WireType)             # 0..5


def row(nm, v):
  print(f"{nm}={v}")


def wt(c):
  for w in WTL:
    if w.value == c:
      return w
  return None


def odt(c):
  for m in ODTL:
    if m.value == c:
      return m
  return None


# ======================= STAGE 1: THE TABLES ===============================

# `WireType` is an IntEnum, so `WireType[c.value]` is the int and the name lookup
# is `_value2member_map_`; the reverse half is spelled with an explicit dict.
WTN = {w.name: w for w in WTL}
row("onnx_wt", all(WTN[wt(c).name].value == c for c in range(6)))
row("onnx_wt_n", len(WTL) == 6)
row("onnx_wt_tbl", ",".join(wt(c).name for c in range(6)))

ATN = {a.name: a for a in ATL}
row("onnx_at", all(ATN[AttributeType(a.value).name].value == a.value for a in ATL))
row("onnx_at2", all(AttributeType(AttributeType(a.value).to_field_name() and a.value).to_field_name() == a.to_field_name()
                    for a in ATL))
row("onnx_at_n", len(ATL) == 8)
at_cells = []
for a in ATL:
  at_cells.append(a.name)
  at_cells.append(a.to_field_name())
row("onnx_at_tbl", ",".join(at_cells))

ODTN = {m.name: m for m in ODTL}
row("onnx_odt_rt", all(ODTN[OnnxDataType(m.value).name].value == m.value for m in ODTL))
# `to_dtype()` IS `DTYPES_DICT[self.name.lower()]` (:37), so the load-bearing claim
# is that the lower-cased member name is a DTYPES_DICT key AND that the key
# answers the member's own dtype.
row("onnx_odt_rt2", all(m.name.lower() in DTYPES_DICT and DTYPES_DICT[m.name.lower()] is m.to_dtype()
                        for m in ODTL))
row("onnx_odt_n", len(ODTL) == 13)
row("onnx_odt_dt_rt", all(m.to_dtype() is not None for m in ODTL))
row("onnx_odt_all", all(m in ODTL for m in ODTL))

HOLES = [0, 1, 8, 14, 15]
row("onnx_odt_holes_rt", all((c in [m.value for m in ODTL]) == (c == 1) for c in HOLES))


def odt_of_dt(dt):
  for m in ODTL:
    if m.to_dtype() is dt:
      return m.value
  return 0


# `onnx_odt_inv` IS the injectivity claim and needs no second row: if two codes
# mapped onto one dtype, `odt_of_dt` returns the FIRST, so the second code's own
# round trip fails.
row("onnx_odt_inv", all(odt_of_dt(m.to_dtype()) == m.value for m in ODTL))
row("onnx_odt_inv_tbl", ",".join(str(odt_of_dt(m.to_dtype())) for m in ODTL))
row("onnx_odt_inv_neg", odt_of_dt(dtypes.weakfloat) == 0)

row("onnx_odt_tbl", ",".join(m.name for m in ODTL))
row("onnx_odt_ktbl", ",".join(m.name.lower() for m in ODTL))
row("onnx_odt_dtbl", ",".join(m.to_dtype().name for m in ODTL))
row("onnx_odt_holes", ",".join((odt(c).name.lower() if odt(c) else "-") for c in HOLES))
row("onnx_odt_hole_dts", ",".join((odt(c).to_dtype().name if odt(c) else "-") for c in HOLES))

at_by_field = {a.to_field_name(): a.value for a in ATL}
row("onnx_aval_tags", ",".join(str(at_by_field[f]) for f in
                               ["f", "i", "s", "floats", "t", "g", "ints", "strings"]))

DOMS = list(Domain)
row("onnx_dom_tbl", ",".join(f"{d.name}/{d.value}" for d in DOMS))
row("onnx_dom_n", len(DOMS) == 9)
row("onnx_dom_rt", all(Domain.from_onnx(d.value).value == d.value for d in DOMS))
row("onnx_dom_empty", Domain.from_onnx("").value == "ai.onnx")
row("onnx_dom_onnx", Domain.from_onnx("ai.onnx").value == "ai.onnx")
row("onnx_dom_tiny", Domain.from_onnx("org.tinygrad").value == "org.tinygrad")
row("onnx_dom_ms", Domain.from_onnx("com.microsoft").value == "com.microsoft")


def dom_refused(s):
  try:
    Domain.from_onnx(s)
  except ValueError:
    return True
  return False


row("onnx_dom_unknown", dom_refused("org.example.nope"))
row("onnx_dom_unknown2", dom_refused("AI.ONNX"))
row("onnx_dom_unknown3", dom_refused("ai.onnx.ml2"))
row("onnx_dom_training", ",".join(
  str(d in (Domain.AI_ONNX_TRAINING, Domain.AI_ONNX_PREVIEW_TRAINING)) for d in DOMS))

RPC = required_input_python_consts
row("onnx_pc_tbl", ",".join(f"{k}:{','.join(str(i) for i in v)}" for k, v in RPC.items()))
row("onnx_pc_n", len(RPC) == 38)
PCROW = {"ReduceLogSumExp": "reduce", "HannWindow": "hann"}
for nm in ("ReduceLogSumExp", "Adam", "Slice", "Range", "Pad", "Dropout", "HannWindow"):
  row(f"onnx_pc_{PCROW.get(nm, nm.lower())}", ",".join(str(i) for i in RPC.get(nm, ())))
row("onnx_pc_absent", ",".join(str(i) for i in RPC.get("Conv", ())))
row("onnx_pc_absent2", ",".join(str(i) for i in RPC.get("Softmax", ())))
row("onnx_pc_has_hit", 2 in RPC.get("Pad", ()))
row("onnx_pc_has_miss", 0 not in RPC.get("Pad", ()))
row("onnx_pc_has_abs", 0 not in RPC.get("Conv", ()))
row("onnx_pc_has_neg", 3 in RPC.get("Slice", ()))

# =================== STAGE 2: THE OP TABLE AND THE PADS ====================

row("onnx_ops_n", len(onnx_ops) == 171)
row("onnx_ops_ver_n", sum(len(v) for v in onnx_ops.values() if isinstance(v, dict)) == 7)
row("onnx_ops_tbl", ",".join(sorted(onnx_ops.keys())))
row("onnx_ver_tbl", "|".join(
  f"{k}/{o.domain.value}/{o.version}/{f.__name__}"
  for k, v in sorted(onnx_ops.items()) if isinstance(v, dict)
  for o, f in v.items()))
row("onnx_ap_tbl", ",".join(["NOTSET", "SAME_UPPER", "SAME_LOWER", "VALID"]))


class _Runner:
  onnx_ops = onnx_ops


def sel(nm, dom, ver):
  try:
    return M.OnnxRunner._select_op(_Runner(), nm, M.OpSetId(Domain.from_onnx(dom), ver)).__name__
  except NotImplementedError:
    return "ERR"


row("onnx_sel_conv", sel("Conv", "ai.onnx", 1))
row("onnx_sel_conv20", sel("Conv", "ai.onnx", 20))
row("onnx_sel_neg", sel("Neg", "ai.onnx", 1))
row("onnx_sel_isnan", sel("IsNaN", "ai.onnx", 1))
row("onnx_sel_adam", sel("Adam", "ai.onnx", 1))
row("onnx_sel_momentum", sel("Momentum", "ai.onnx", 1))
row("onnx_sel_sm1", sel("Softmax", "ai.onnx", 1))
row("onnx_sel_sm0", sel("Softmax", "ai.onnx", 0))
row("onnx_sel_sm12", sel("Softmax", "ai.onnx", 12))
row("onnx_sel_sm13", sel("Softmax", "ai.onnx", 13))
row("onnx_sel_sm20", sel("Softmax", "ai.onnx", 20))
row("onnx_sel_ms_sm", sel("Softmax", "com.microsoft", 13))
row("onnx_sel_dr5", sel("Dropout", "ai.onnx", 5))
row("onnx_sel_dr6", sel("Dropout", "ai.onnx", 6))
row("onnx_sel_dr99", sel("Dropout", "ai.onnx", 99))
row("onnx_sel_at_onnx", sel("Attention", "ai.onnx", 1))
row("onnx_sel_at_ms", sel("Attention", "com.microsoft", 1))
row("onnx_sel_at_onnx2", sel("Attention", "ai.onnx", 2))
row("onnx_sel_ct_tiny", sel("Contiguous", "org.tinygrad", 1))
row("onnx_sel_ct_tiny5", sel("Contiguous", "org.tinygrad", 5))
row("onnx_sel_ct_onnx", sel("Contiguous", "ai.onnx", 1))
row("onnx_sel_nope", sel("NoSuchOp", "ai.onnx", 1))
row("onnx_ops_rows", True)

_srclines = inspect.getsource(M.get_onnx_ops).split("\n")
_i = [n for n, l in enumerate(_srclines) if l.strip().startswith("return {")][0]
_j = [n for n, l in enumerate(_srclines) if l.startswith("def get_onnx_ops")][0]
_body = "\n".join(l[2:] for l in _srclines[_j + 1:_i])
_ns = dict(M.__dict__)
exec(compile("def _probe():\n" + "\n".join("  " + l for l in _body.split("\n")) +
             "\n  return (_onnx_pads_to_tiny_pads,_auto_pad,_resolve_pool_pads,_axes)\n",
             "probe", "exec"), _ns)
P2T, AP, RPP, AXES = _ns["_probe"]()


def i64pair(v):
  """`H.i64_text` is `hi:lo`; Python prints the same pair so a negative pad is
  legible on both sides of the diff instead of needing mental arithmetic."""
  v &= 0xFFFFFFFFFFFFFFFF
  return f"{v >> 32}:{v & 0xFFFFFFFF}"


def i64s(vs):
  return ",".join(i64pair(v) for v in vs)


for nm, pads in [("4", (1, 2, 3, 4)), ("6", (1, 2, 3, 4, 5, 6)),
                 ("6c", (1, 1, 1, 1, 1, 1)), ("1", (1,)), ("0", ()),
                 ("neg", (0, 0, 0, 0, 0, 5)), ("zero", (0, 0, 0, 0)),
                 ("8", (9, 8, 7, 6, 5, 4, 3, 2)), ("odd", (1, 2, 3))]:
  row(f"onnx_p2t_{nm}", i64s(P2T(pads)))
row("onnx_p2t_rows", True)

for nm, pads, up in [("ns", (0, 0), False), ("su33", (3, 3), True), ("sl33", (3, 3), False),
                     ("su24", (2, 4), True), ("su5", (5,), True), ("sl5", (5,), False),
                     ("sl123", (1, 2, 3), False), ("su_neg1", (-1,), True),
                     ("sl_neg5", (-5,), False), ("su_neg2", (-2, 1), True),
                     ("empty", (), True), ("odd2", (0, 1), True)]:
  row(f"onnx_ap_{nm}", i64s(AP(pads, "SAME_UPPER" if up else "SAME_LOWER")))
row("onnx_ap_rows", True)


class _X:
  def __init__(s, sh):
    s.shape = tuple(sh)


def rpp(is_, p_, k_, s_, ap):
  # `p_` and `s_` arrive ALREADY through `make_tuple(x, len(k_)*2)`, which is what
  # Python's own signature at :497 guarantees before :498 runs. The fixtures
  # spell the expansion out rather than re-deriving it. `d_` is passed as 1: it
  # is bound at :497 and never read, which is a genuine dead binding in tinygrad.
  return i64s(RPP(_X(list(is_)), tuple(p_), tuple(k_), (1,) * (len(k_) * 2), tuple(s_), ap))


POOL = [
  ("ns0", [32, 32], [0, 0, 0, 0], [3, 3], [1, 1], "NOTSET"),
  ("ns1", [32, 32], [1, 2, 3, 4], [3, 3], [1, 1], "NOTSET"),
  ("ns2", [32, 32], [1, 2], [3, 3], [1, 1], "NOTSET"),
  ("ns3", [32, 32], [0], [3, 3], [1, 1, 1, 1], "NOTSET"),
  ("valid", [32, 32], [0, 0, 0, 0], [3, 3], [1, 1], "VALID"),
  ("su2", [32, 32], [0, 0, 0, 0], [3, 3], [2, 2], "SAME_UPPER"),
  ("sl2", [32, 32], [0, 0, 0, 0], [3, 3], [2, 2], "SAME_LOWER"),
  ("su5", [32, 32], [0, 0, 0, 0], [5, 5], [1, 1], "SAME_UPPER"),
  ("su_dil", [32, 32], [0, 0, 0, 0], [3, 3], [2, 2], "SAME_UPPER"),
  ("su1d", [10], [0, 0], [3], [1], "SAME_UPPER"),
  ("sl3d", [7, 7, 7], [0, 0, 0, 0, 0, 0], [3, 3, 3], [1, 1, 1], "SAME_LOWER"),
  ("su_s3", [8, 8], [0, 0, 0, 0], [3, 3], [3, 3], "SAME_UPPER"),
  ("su_neg", [8, 8], [0, 0, 0, 0], [3, 3], [8, 8], "SAME_UPPER"),
  ("su_k1", [32, 32], [0, 0, 0, 0], [1, 1], [1, 1], "SAME_UPPER"),
  ("su_odd", [10, 10], [0, 0, 0, 0], [4, 4], [3, 3], "SAME_UPPER"),
  ("sl_neg", [2, 2], [0, 0, 0, 0], [3, 3], [4, 4], "SAME_LOWER"),
  ("valid1d", [10], [0, 0], [3], [1], "VALID"),
]
for nm, is_, p_, k_, s_, ap in POOL:
  row(f"onnx_pool_{nm}", rpp(is_, p_, k_, s_, ap))
row("onnx_pool_rows", True)

for nm, axes, noop in [("a", None, 0), ("b", None, 1), ("c", [1], 0), ("d", [0, 2], 1)]:
  r = AXES(axes, noop)
  none = "True" if r is None else "False"
  xs = "" if r is None else ",".join(str(i) for i in r)
  row(f"onnx_axes_{nm}", f"{none}/{xs}")
row("onnx_axes_rows", True)

row("onnx_stage2", True)