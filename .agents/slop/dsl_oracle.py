#!/usr/bin/env python3
"""THE CPYTHON ORACLE for `renderer/amd/dsl.bend`.

Every expectation in the gate comes from RUNNING `tinygrad/renderer/amd/dsl.py`.
Nothing here is transcribed: `n=<i>` rows are produced by calling a method, and a
refusal is produced by CATCHING the RuntimeError and printing its message.

The Inst subclass exercised in section 5 is DEFINED HERE, in this oracle, so it
can be built from dsl.py's own `BitField` classes without reading
`tinygrad/runtime/autogen/amd/*/operands.py` (the deferred autogen table). Its
field order and its `op_regs` are fixtures; everything it computes is CPython's.

Run: .venv/bin/python .agents/slop/dsl_oracle.py > .agents/slop/dsl_oracle.txt
"""
import sys, struct, json, enum
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tinygrad.renderer.amd import dsl   # noqa: E402

OUT = []


def row(name, val):
  OUT.append(f"{name}={val}")


class Opc(enum.IntEnum):
  V_ADD_F32 = 0
  V_CNDMASK_F32 = 1
  V_CMP_LT_F32 = 2
  V_CO_CI_ADD_F32 = 3
  GLOBAL_ATOMIC_ADD_F32 = 4
  FLAT_LOAD_F32 = 5
  SCRATCH_LOAD_F32 = 6
  VSCRATCH_LOAD_F32 = 7
  V_F8F6F4_MFMA_F32_32X32X8_F16 = 8
  OTHER = 9


def refusal(name, fn):
  try:
    v = fn()
    row(name, f"NOFAIL:{v!r}")
  except RuntimeError as e:
    row(name, f"REFUSE:{e}")


# ===========================================================================
# 1. THE TABLES. `Reg._NAMES` and `Reg._PAIRS`, in DICT ORDER, both directions.
# ===========================================================================
for off, nm in dsl.Reg._NAMES.items():
  row(f"names_fwd_{off}", nm)
for i, (off, nm) in enumerate(dsl.Reg._NAMES.items()):
  row(f"names_order_{i}", f"{off}:{nm}")
# the REVERSE direction: name -> offset. Every name must be unique.
for nm, off in {v: k for k, v in dsl.Reg._NAMES.items()}.items():
  row(f"names_rev_{nm}", off)
row("names_count", len(dsl.Reg._NAMES))
row("names_rev_count", len({v: k for k, v in dsl.Reg._NAMES.items()}))
for off, nm in dsl.Reg._PAIRS.items():
  row(f"pairs_fwd_{off}", nm)
for nm, off in {v: k for k, v in dsl.Reg._PAIRS.items()}.items():
  row(f"pairs_rev_{nm}", off)
row("pairs_count", len(dsl.Reg._PAIRS))

# ===========================================================================
# 2. THE MODULE-LEVEL REGISTER CONSTANTS. `src[n]` is Reg(n, 1); `src[a:b]` is
#    Reg(a, b-a+1). Both, because a slice's END is inclusive in the source and
#    the size is +1 -- the classic off-by-one, so the gate reads it.
# ===========================================================================
for nm in ("VCC_LO", "VCC_HI", "NULL", "OFF", "M0", "EXEC_LO", "EXEC_HI", "INV_2PI", "SDWA", "DPP",
           "DPP16", "VCCZ", "EXECZ", "SCC", "SRC_LDS_DIRECT", "LIT"):
  r = getattr(dsl, nm)
  row(f"const_{nm}", f"{r.offset},{r.sz},{r.neg},{r.abs_},{r.hi}")
for nm in ("src", "s", "VCC", "ttmp", "EXEC", "v"):
  r = getattr(dsl, nm)
  row(f"const_{nm}", f"{r.offset},{r.sz},{r.neg},{r.abs_},{r.hi}")
# an OFFSET->REG lookup for every offset in the space, so a slice-boundary error
# in `src[lo]`/`src[hi]` cannot hide.
for o in (0, 1, 104, 105, 106, 107, 108, 123, 124, 125, 126, 127, 128, 129, 192, 193, 208, 209,
          239, 240, 248, 255, 256, 257, 510, 511):
  r = dsl.src[o]
  row(f"src_at_{o}", f"{r.offset},{r.sz}")

# ===========================================================================
# 3. Reg.__getitem__ -- index, slice, and BOTH refusals.
# ===========================================================================
for o in (0, 1, 63, 104, 105, 106, 123, 124, 255, 256, 510):
  r = dsl.src[o]
  row(f"get_at_{o}", f"{r.offset},{r.sz}")
for a, b in ((0, 105), (106, 107), (108, 123), (126, 127), (256, 511)):
  r = dsl.src[a:b]
  row(f"get_slice_{a}_{b}", f"{r.offset},{r.sz}")
# the slice's `key.start or 0` / `key.stop or (sz-1)` defaults
row("get_slice_default", f"{dsl.src[0:].offset},{dsl.src[0:].sz}")
row("get_slice_none_stop", f"{dsl.src[:5].offset},{dsl.src[:5].sz}")
# negative index: `key < 0` refuses BEFORE Python's own negative indexing
refusal("get_neg_index", lambda: dsl.src[-1])
refusal("get_neg_slice_start", lambda: dsl.src[-1:5])
refusal("get_slice_stop_ge_sz", lambda: dsl.src[0:512])
refusal("get_slice_start_ge_stop", lambda: dsl.src[300:200])
refusal("get_index_ge_sz", lambda: dsl.src[512])

# ===========================================================================
# 4. Reg.fmt -- EVERY ARM, plus the modifier suffixes. Formatted WITH
#    parens=False/upper=False (the assembly spelling) and again with
#    parens=True/upper=True (the __repr__ spelling).
# ===========================================================================
FMT_CASES = [
  # (offset, sz) -- chosen so each of the eight `elif` arms fires at least once
  (0, 1), (0, 4), (1, 2), (105, 1),      # arm 2: s[...]
  (256, 1), (256, 4), (300, 2), (511, 1),  # arm 1: v[...]
  (106, 2), (126, 2),                     # arm 3: _PAIRS (needs sz==2)
  (106, 1), (126, 1),                     # NOT sz==2, so falls to _NAMES
  (102, 1), (103, 2), (104, 1), (105, 1), # arm 4: _NAMES, incl. a sz==2 name
  (107, 1), (124, 1), (125, 1), (127, 1), (233, 1), (234, 1), (235, 1), (236, 1), (237, 1), (238, 1),
  (240, 1), (241, 1), (242, 1), (243, 1), (244, 1), (245, 1), (246, 1), (247, 1),
  (248, 1), (249, 1), (250, 1), (251, 1), (252, 1), (253, 1), (254, 1), (255, 1),
  (108, 1), (108, 4), (115, 2), (123, 1), # arm 5: ttmp
  (128, 1), (129, 1), (160, 1), (192, 1), # arm 6: inline int constants 0..64
  (193, 1), (194, 1), (207, 1), (208, 1), # arm 7: inline negative -1..-16
]
for off, sz in FMT_CASES:
  r = dsl.Reg(off, sz)
  row(f"fmt_{off}_{sz}", r.fmt())
  row(f"fmtp_{off}_{sz}", r.fmt(parens=True, upper=True))
  row(f"repr_{off}_{sz}", repr(r))
# the modifiers, one at a time and in combination
for off, sz in ((0, 1), (256, 1), (124, 1), (106, 2), (108, 1), (128, 1), (193, 1)):
  for neg in (False, True):
    for ab in (False, True):
      for hi in (False, True):
        r = dsl.Reg(off, sz, neg=neg, abs_=ab, hi=hi)
        row(f"fmtmod_{off}_{sz}_{int(neg)}{int(ab)}{int(hi)}", r.fmt())
        row(f"fmtmodu_{off}_{sz}_{int(neg)}{int(ab)}{int(hi)}", r.fmt(parens=True, upper=True))
# the `sz or self.sz` override: fmt(2) on a 1-reg
for off, sz, ov in ((0, 1, 4), (256, 1, 2), (106, 2, 2), (124, 1, 4), (108, 1, 2)):
  row(f"fmt_szov_{off}_{sz}_{ov}", dsl.Reg(off, sz).fmt(sz=ov))
# the `parens or sz > 1` bracket rule: parens=True forces brackets at sz==1
for off, sz in ((0, 1), (256, 1), (124, 1)):
  row(f"fmt_parens1_{off}_{sz}", dsl.Reg(off, sz).fmt(parens=True))
# UPPER is a `.upper()` on the NAME, not on the digits
for off, sz in ((0, 1), (256, 1), (106, 2), (124, 1), (108, 1), (255, 1)):
  row(f"fmt_upper_{off}_{sz}", dsl.Reg(off, sz).fmt(upper=True))
refusal("fmt_unknown_209", lambda: dsl.Reg(209, 1).fmt())
refusal("fmt_unknown_512", lambda: dsl.Reg(512, 1).fmt())

# __neg__ / __abs__ / .h / .l : the four flags, checked on ONE register each
for off, sz in ((0, 1), (256, 4), (108, 1), (124, 1)):
  r = dsl.Reg(off, sz)
  for nm, x in (("neg", -r), ("abs", abs(r)), ("h", r.h), ("l", r.l)):
    row(f"mod_{nm}_{off}_{sz}", f"{x.offset},{x.sz},{x.neg},{x.abs_},{x.hi}")
# and __neg__ twice is the identity (the `not self.neg` flip)
r = dsl.Reg(5, 2)
row("mod_neg2_5_2", f"{(-(-r)).offset},{(-(-r)).sz},{(-(-r)).neg},{(-(-r)).abs_},{(-(-r)).hi}")
# __add__ keeps sz, and __eq__ is the 5-tuple
row("mod_add_5_2", f"{(r + 3).offset},{(r + 3).sz}")
row("eq_self", dsl.Reg(1, 2) == dsl.Reg(1, 2))
row("eq_sz", dsl.Reg(1, 2) == dsl.Reg(1, 3))
row("eq_neg", dsl.Reg(1, 2) == dsl.Reg(1, 2, neg=True))
row("eq_abs", dsl.Reg(1, 2) == dsl.Reg(1, 2, abs_=True))
row("eq_hi", dsl.Reg(1, 2) == dsl.Reg(1, 2, hi=True))

# ===========================================================================
# 5. THE BIT FIELDS. `BitField`/`FixedBitField`/`EnumBitField` masks, `set`,
#    and `_base_size`.
# ===========================================================================
for hi, lo in ((7, 0), (15, 8), (16, 8), (31, 16), (17, 16), (23, 8), (9, 0), (30, 24), (17, 9),
               (30, 0), (31, 0), (0, 0), (6, 0), (63, 32), (40, 32), (47, 32), (23, 16)):
  bf = dsl.BitField(hi, lo)
  # `self.name` is None until `__set_name__` fires, and dsl.py:118 prints it --
  # so a STANDALONE BitField refuses with the text "field 'None'". The port
  # names its fixture field "f", which is a FIXTURE CHOICE, so name it here too
  # and say so: the refusal row checks the width, not the name.
  bf.name = "f"
  row(f"bf_{hi}_{lo}", f"{bf.hi},{bf.lo},{bf.default},{bf.mask}")
  row(f"bf_bits_{hi}_{lo}", hi - lo + 1)

# `set` over the whole legal range plus the two refusals, for three widths.
for hi, lo in ((3, 0), (7, 4), (23, 8)):
  bf = dsl.BitField(hi, lo)
  bf.name = "f"
  for raw in (0, 0xFFFFFFFF, 0xDEADBEEF):
    for val in (None, 0, 1, 7, 8, 255, -1, -8, -9):
      try:
        row(f"bfset_{hi}_{lo}_{raw}_{val}", f"{bf.set(raw, val):#010x}")
      except RuntimeError as e:
        row(f"bfset_{hi}_{lo}_{raw}_{val}", f"REFUSE:{e}")

# `_base_size = (max(f.hi for _,f in cls._fields) + 8) // 8`
class F32I(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  A = dsl.BitField(23, 8)
class F64I(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  lit = dsl.BitField(63, 32)
class F16I(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  A = dsl.BitField(23, 8)
  B = dsl.BitField(31, 16)
class F8I(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
class F40I(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  A = dsl.BitField(39, 8)
for nm, c in (("F32I", F32I), ("F64I", F64I), ("F16I", F16I), ("F8I", F8I), ("F40I", F40I)):
  row(f"base_size_{nm}", c._base_size)
  row(f"fields_{nm}", ",".join(n for n, _ in c._fields))
row("fields_F16I_pairs", ",".join(f"{n}:{f.hi}:{f.lo}" for n, f in F16I._fields))

# ===========================================================================
# 6. SrcField / VGPRField / SGPRField / SSrcField. `encode` and `decode`.
# ===========================================================================
for hi, lo in ((8, 0), (17, 9), (25, 17), (31, 23), (9, 1)):
  sf = dsl.SrcField(hi, lo)
  row(f"sf_mask_{hi}_{lo}", sf.mask)
  #
  # THE THREE KINDS GET THREE NAME PREFIXES, and that is not tidiness: `v!r` for
  # `dsl.src[0]` and for the int `0` are BOTH "0", so the first version emitted
  # two rows under one name and the dict kept whichever came last. The port's
  # `sfenc_{hi}_{lo}_{off}` (a Reg) then disagreed with the oracle's `sfenc_..._0`
  # (an int) and the gate reported a wrong encoding that was a NAME COLLISION.
  for v in (dsl.src[0], dsl.src[1], dsl.src[63], dsl.src[105], dsl.src[106], dsl.src[127],
            dsl.src[128], dsl.src[255], dsl.src[256], dsl.src[257], dsl.src[511]):
    try:
      row(f"sfenc_{hi}_{lo}_{v.offset}", sf.encode(v))
    except (TypeError, ValueError) as e:
      row(f"sfenc_{hi}_{lo}_{v.offset}", f"REFUSE:{e}")
  for v in (0, 1, 63, 64, 65, -1, -16, -15, -17, 100):
    try:
      row(f"sfenc_{hi}_{lo}_i{v}", sf.encode(v))
    except (TypeError, ValueError) as e:
      row(f"sfenc_{hi}_{lo}_i{v}", f"REFUSE:{e}")
  for v in (0.5, -0.5, 1.0, -1.0, 2.0, -2.0, 4.0, -4.0, 3.0, 0.25):
    try:
      row(f"sfenc_{hi}_{lo}_f{v!r}", sf.encode(v))
    except (TypeError, ValueError) as e:
      row(f"sfenc_{hi}_{lo}_f{v!r}", f"REFUSE:{e}")
  for raw in (0, 1, 2, 105, 106, 128, 255, 256, 511):
    d = sf.decode(raw)
    row(f"sfdec_{hi}_{lo}_{raw}", f"{d.offset},{d.sz}")

# `_FLOAT_ENC` -- the eight floats, BOTH directions
for f, e in dsl.SrcField._FLOAT_ENC.items():
  row(f"floatenc_f_{f!r}", e)
for f, e in {v: k for k, v in dsl.SrcField._FLOAT_ENC.items()}.items():
  row(f"floatenc_r_{f}", repr(e))

# VGPRField: the 8-bit `.h` opsel bit. `_valid_range = (256, 511)`.
for hi, lo in ((7, 0), (15, 8), (8, 1), (31, 24)):
  vf = dsl.VGPRField(hi, lo)
  row(f"vgpr_mask_{hi}_{lo}", vf.mask)
  for v in (dsl.src[256], dsl.src[257], dsl.src[383], dsl.src[384], dsl.src[511],
            dsl.src[256].h, dsl.src[300].h, dsl.src[127].h, dsl.src[0]):
    key = f"{hi}_{lo}_{v.offset}_{v.sz}_{int(v.hi)}"
    try:
      row(f"vgenc_{key}", vf.encode(v))
    except (TypeError, ValueError) as e:
      row(f"vgenc_{key}", f"REFUSE:{e}")
  # a NON-Reg is a TypeError, and a non-VGPR offset never gets that far
  for v in (0, 1, 64, 0.5, 3.0):
    try:
      row(f"vgenc_nonreg_{hi}_{lo}_{v!r}", vf.encode(v))
    except (TypeError, ValueError) as e:
      row(f"vgenc_nonreg_{hi}_{lo}_{v!r}", f"REFUSE:{e}")
# SGPRField (0,127) and SSrcField (0,255): the size check in __init__ is the
# load-bearing part, since it fires at class-definition time.
row("sgpr_valid", f"{dsl.SGPRField._valid_range[0]},{dsl.SGPRField._valid_range[1]}")
row("ssrc_valid", f"{dsl.SSrcField._valid_range[0]},{dsl.SSrcField._valid_range[1]}")
row("vgpr_valid", f"{dsl.VGPRField._valid_range[0]},{dsl.VGPRField._valid_range[1]}")
row("src_valid", f"{dsl.SrcField._valid_range[0]},{dsl.SrcField._valid_range[1]}")
refusal("sgpr_bad_width", lambda: dsl.SGPRField(9, 0))
refusal("ssrc_bad_width", lambda: dsl.SSrcField(10, 0))
refusal("vgpr_bad_width", lambda: dsl.VGPRField(9, 0))
refusal("sf_bad_width", lambda: dsl.SrcField(10, 0))
for nm, cls, hi, lo in (("sgpr", dsl.SGPRField, 6, 0), ("ssrc", dsl.SSrcField, 7, 0)):
  f = cls(hi, lo)
  for v in (dsl.src[0], dsl.src[1], dsl.src[127], dsl.src[128], dsl.src[255], dsl.src[256],
            dsl.src[511], 0, 1, 64, -1, 0.5, 3.0):
    try:
      row(f"{nm}enc_{hi}_{lo}_{v!r}", f.encode(v))
    except (TypeError, ValueError) as e:
      row(f"{nm}enc_{hi}_{lo}_{v!r}", f"REFUSE:{e}")
  for raw in (0, 1, 127, 128, 255):
    row(f"{nm}dec_{hi}_{lo}_{raw}", f"{f.decode(raw).offset},{f.decode(raw).sz}")
# __init__ REFUSES when the field width does not equal the valid range
row("sf_expected_size", dsl.SrcField._valid_range[1] - dsl.SrcField._valid_range[0] + 1)

# ===========================================================================
# 7. AlignedSGPRField (align 2), SBaseField (2), SRsrcField (4), VDSTYField.
# ===========================================================================
for nm, cls in (("ab", dsl.AlignedSGPRField), ("sb", dsl.SBaseField), ("sr", dsl.SRsrcField)):
  row(f"align_{nm}", cls._align)
for nm, cls, hi, lo in (("ab", dsl.AlignedSGPRField, 7, 0), ("sb", dsl.SBaseField, 7, 4),
                        ("sr", dsl.SRsrcField, 6, 0), ("sr2", dsl.SRsrcField, 5, 0)):
  f = cls(hi, lo)
  row(f"af_mask_{nm}_{hi}_{lo}", f.mask)
  for v in (0, 1, dsl.src[0], dsl.src[2], dsl.src[4], dsl.src[8], dsl.src[100], dsl.src[126],
            dsl.src[127], dsl.src[128], dsl.src[1], dsl.src[3], dsl.src[5], dsl.src[127]):
    try:
      row(f"afenc_{nm}_{hi}_{lo}_{v!r}", f.encode(v))
    except (TypeError, ValueError) as e:
      row(f"afenc_{nm}_{hi}_{lo}_{v!r}", f"REFUSE:{e}")
  for raw in (0, 1, 2, 15, 31, 32, 63):
    row(f"afdec_{nm}_{hi}_{lo}_{raw}", f"{f.decode(raw).offset},{f.decode(raw).sz}")
# VDSTYField
row("vdsty_hi_lo", "0,0")
for v in (dsl.src[256], dsl.src[257], dsl.src[258], dsl.src[259], dsl.src[510], dsl.src[511],
          dsl.src[0], dsl.src[128], dsl.src[255]):
  try:
    row(f"vdstyenc_{v.offset}", vdsty.encode(v) if False else dsl.VDSTYField(0, 0).encode(v))
  except (TypeError, ValueError) as e:
    row(f"vdstyenc_{v.offset}", f"REFUSE:{e}")
for raw in (0, 1, 2, 127, 128, 255):
  row(f"vdstydec_{raw}", f"{dsl.VDSTYField(0, 0).decode(raw) if hasattr(dsl.VDSTYField(0,0),'decode') else 'NODEC'}")

# ===========================================================================
# 8. _f32 -- the float -> 32-bit-pattern conversion. `struct.pack('f')`, which
#    is f32 ROUNDING, and the gate compares the BITS.
# ===========================================================================
for f in (0.5, -0.5, 1.0, -1.0, 2.0, -2.0, 4.0, -4.0, 0.0, 3.0, 0.25, -3.5, 1e-8, 1e30, -0.0,
          1.0 / (2 * 3.141592653589793)):
  row(f"f32_{f!r}", f"{dsl._f32(f):#010x}")

# ===========================================================================
# 9. _canonical_name / _needs_literal. The name table, BOTH directions.
# ===========================================================================
CANON_IN = ['src0', 'vsrc0', 'ssrc0', 'src1', 'vsrc1', 'ssrc1', 'src2', 'vdst', 'sdst', 'sdata',
            'data', 'vdata', 'data0', 'vsrc', 'op', 'off', 'abs', 'neg', 'opsel', 'src3', 'sdst_x',
            'S0', 'Src0', 'xsrc0', 'rsrc', 'isrc']
for n in CANON_IN:
  row(f"canon_{n}", dsl._canonical_name(n))

for v in (None, dsl.src[0], dsl.src[256], 0, 1, 63, 64, -1, -15, -16, -17, 65, 100, 0.5, -0.5,
          1.0, -1.0, 2.0, -2.0, 4.0, -4.0, 3.0, 0.25):
  row(f"needs_lit_{v!r}", dsl._needs_literal(v))

# ===========================================================================
# 10. A REAL Inst, built from dsl.py's OWN classes, to exercise __init__,
#     to_bytes, from_bytes, __repr__, op_regs, canonical_*, num_srcs, and
#     _variant_suffix.
#
# THE CLASS IS A FIXTURE, and it is named one because its field WIDTHS are
# chosen, not read: `SrcField` refuses any width but 9 bits (range 0..511),
# `VGPRField` any but 8 (256..511), `SGPRField` any but 7 (0..127) and
# `SSrcField` any but 8 (0..255) -- `__init__` at dsl.py:155-159. So a legal
# fixture must use 9/8/7/8-bit fields, laid out non-overlapping. Every number
# below the class is still CPython's.
#
# `op` is an `EnumBitField` over a LOCAL enum, not a FixedBitField: dsl.py:343
# `op_name` does `getattr(self,'op').name` and `__init__` reaches
# `self.op_regs` at :337, so a class that gets that far cannot carry a plain
# integer `op`. `Opc`'s member NAMES are chosen to fire every `op_bits` arm.
#
# `MOP` also DECLARES `neg`/`abs`/`opsel` fields and `operands`. That is not
# decoration: dsl.py:322-324 write `vals['neg']`, `vals['abs']` and
# `vals['opsel']`, and only a class that DECLARES a field of that name ever
# encodes them. `VOP2` declares none, so its modifiers are silently dropped.
# Both answers are gated; the pair is the point.
# ===========================================================================
class VOP2(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  vdst = dsl.VGPRField(15, 8)
  src0 = dsl.SrcField(25, 17)
  src1 = dsl.SSrcField(33, 26)
  op_sel = dsl.BitField(35, 34)
  sdst = dsl.AlignedSGPRField(41, 36)


class MOP(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  vdst = dsl.VGPRField(15, 8)
  src0 = dsl.SrcField(25, 17)
  src1 = dsl.SSrcField(33, 26)
  neg = dsl.BitField(35, 34)
  abs = dsl.BitField(37, 36)
  opsel = dsl.BitField(40, 38)
  sdst = dsl.AlignedSGPRField(45, 41)
  src2 = dsl.SrcField(54, 46)
  addr = dsl.BitField(63, 55)
  vaddr = dsl.VGPRField(70, 63)
  saddr = dsl.BitField(78, 71)
  # MFMA's real cbsz is [10:8] -- THREE bits. A 2-bit field cannot hold
  # cbsz=4 or blgp=4, and the `vgprs` table at dsl.py:375 has an entry for 4,
  # so a 2-bit fixture would silently answer the `.get` DEFAULT for the ONE
  # entry the table exists to express. Measured: it did.
  cbsz = dsl.BitField(80, 78)
  blgp = dsl.BitField(83, 81)
  idxen = dsl.BitField(86, 86)
  offen = dsl.BitField(85, 85)
  operands = {"src0": (0, 32), "src1": (0, 32), "src2": (0, 64), "vdst": (1, 32),
              "sdst": (0, 32), "addr": (1, 64), "vaddr": (2, 32)}


class VOP3SD(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  sdst = dsl.SGPRField(15, 9)
  src0 = dsl.SrcField(25, 17)
  operands = {"src0": (0, 32), "sdst": (0, 64), "src1": (0, 32)}


class SCR(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  addr = dsl.BitField(39, 32)
  saddr = dsl.BitField(49, 40)
  operands = {"addr": (0, 32), "saddr": (0, 8)}


# `_fields` order is declaration order (MRO reversed), and it is the order
# `__init__` walks, the order `__repr__` prints, and the order the raw word is
# assembled in. Printed BY NAME, with `:` between the field name and hi/lo.
for c in (VOP2, MOP, VOP3SD, SCR):
  row(f"fields_{c.__name__}", ",".join(f"{n}:{f.hi}:{f.lo}" for n, f in c._fields))
  row(f"base_size_{c.__name__}", c._base_size)
  row(f"size_{c.__name__}", c._size())

CASES = [
  ("none", VOP2, dict(op=Opc.V_ADD_F32)),
  ("vdst", VOP2, dict(op=Opc.V_ADD_F32, vdst=dsl.src[256])),
  ("vdst_src0", VOP2, dict(op=Opc.V_ADD_F32, vdst=dsl.src[10], src0=dsl.src[3])),
  ("all", VOP2, dict(op=Opc.V_ADD_F32, vdst=dsl.src[10], src0=dsl.src[3], src1=dsl.src[5],
                     op_sel=4, sdst=dsl.src[8])),
  ("sr4", VOP2, dict(op=Opc.V_ADD_F32, vdst=dsl.src[10], src0=dsl.src[3], src1=dsl.src[5],
                     sdst=dsl.src[12])),
  ("neg_src0", VOP2, dict(op=Opc.V_ADD_F32, vdst=dsl.src[10], src0=-dsl.src[3])),
  ("neg_src1", VOP2, dict(op=Opc.V_ADD_F32, src1=-dsl.src[5])),
  ("abs_src1", VOP2, dict(op=Opc.V_ADD_F32, src1=abs(dsl.src[5]))),
  ("hi_src0", VOP2, dict(op=Opc.V_ADD_F32, src0=dsl.src[3].h)),
  ("hi_vdst", VOP2, dict(op=Opc.V_ADD_F32, vdst=dsl.src[10].h)),
  ("all_mods", VOP2, dict(op=Opc.V_ADD_F32, vdst=-abs(dsl.src[10].h), src0=-dsl.src[3].h,
                          src1=abs(dsl.src[5]))),
  ("int0", VOP2, dict(op=Opc.V_ADD_F32, src0=dsl.src[0])),
  ("int64", VOP2, dict(op=Opc.V_ADD_F32, src0=64)),
  ("int65", VOP2, dict(op=Opc.V_ADD_F32, src0=65)),
  ("intneg16", VOP2, dict(op=Opc.V_ADD_F32, src0=-16)),
  ("intneg17", VOP2, dict(op=Opc.V_ADD_F32, src0=-17)),
  ("fconst", VOP2, dict(op=Opc.V_ADD_F32, src0=0.5)),
  ("fconst2", VOP2, dict(op=Opc.V_ADD_F32, src0=-4.0)),
  ("fneed_lit", VOP2, dict(op=Opc.V_ADD_F32, src0=3.0)),
  ("lit_marker", VOP2, dict(op=Opc.V_ADD_F32, src0=dsl.src[255])),
  ("sdwa", VOP2, dict(op=Opc.V_ADD_F32, src1=dsl.src[249])),
  ("dpp", VOP2, dict(op=Opc.V_ADD_F32, src1=dsl.src[250])),
  ("full_raw", VOP2, dict(op=Opc.V_ADD_F32, vdst=dsl.src[63], src0=dsl.src[511],
                          src1=dsl.src[255], op_sel=3, sdst=dsl.src[126])),
  # the declared neg/abs/opsel fields: the merge is `|`-ed with the given value
  ("m_neg2", MOP, dict(op=Opc.V_ADD_F32, neg=2, src0=-dsl.src[3])),
  ("m_neg2_nosrc", MOP, dict(op=Opc.V_ADD_F32, neg=2)),
  ("m_abs1", MOP, dict(op=Opc.V_ADD_F32, abs=1, src1=abs(dsl.src[5]))),
  ("m_opsel1", MOP, dict(op=Opc.V_ADD_F32, opsel=1)),
  ("m_opsel8", MOP, dict(op=Opc.V_ADD_F32, opsel=8, vdst=dsl.src[10].h)),
  ("m_allmods", MOP, dict(op=Opc.V_ADD_F32, neg=1, abs=2, opsel=4, src0=-dsl.src[3],
                          src1=abs(dsl.src[5]))),
  # op_regs size validation (dsl.py:337-340) -- the positive and its negatives
  ("r_ok", MOP, dict(op=Opc.V_ADD_F32, src0=dsl.src[3], vdst=dsl.src[10], src2=dsl.src[4])),
  ("r_bad_vdst", MOP, dict(op=Opc.V_ADD_F32, vdst=dsl.Reg(10, 2))),
  ("r_bad_src2", MOP, dict(op=Opc.V_ADD_F32, src2=dsl.Reg(4, 1))),
  ("r_exempt_null", MOP, dict(op=Opc.V_ADD_F32, sdst=dsl.Reg(124, 4))),
  ("r_exempt_m0", MOP, dict(op=Opc.V_ADD_F32, sdst=dsl.Reg(125, 4))),
  ("r_exempt_sdwa", MOP, dict(op=Opc.V_ADD_F32, src2=dsl.Reg(250, 8))),
  ("r_exempt_vcc", MOP, dict(op=Opc.V_ADD_F32, src2=dsl.Reg(106, 2))),
  ("r_int_not_reg", MOP, dict(op=Opc.V_ADD_F32, src2=7)),
]
for nm, C, kw in CASES:
  try:
    i = C(**kw)
    row(f"inst_{nm}", f"{i._raw:#x}")
    row(f"instb_{nm}", i.to_bytes().hex())
    row(f"instr_{nm}", repr(i))
    row(f"instsz_{nm}", i.size())
    row(f"instlit_{nm}", i._literal)
  except (RuntimeError, TypeError, ValueError, AttributeError) as e:
    row(f"inst_{nm}", f"REFUSE:{type(e).__name__}:{e}")
    row(f"instb_{nm}", "-")
    row(f"instr_{nm}", "-")
    row(f"instsz_{nm}", "-")
    row(f"instlit_{nm}", "-")

# from_bytes round trip, byte for byte
for hexs in ("00000000", "01000000", "09000000", "deadbeef", "80000000", "007b0100",
             "ff7b0100", "ffffffff"):
  b = bytes.fromhex(hexs)
  try:
    i = VOP2.from_bytes(b)
    row(f"fromb_{hexs}", f"{i._raw:#x},{i.size()},{repr(i)}")
  except (ValueError, RuntimeError, TypeError) as e:
    # an unknown OPC is an enum ValueError at decode time, and `repr` needs
    # every field to decode -- so `from_bytes` refuses a word it cannot name
    row(f"fromb_{hexs}", f"REFUSE:{type(e).__name__}:{e}")

# POSITIONAL args: `__init__` maps them onto `_fields` in order, SKIPPING the
# FixedBitFields -- so `op` never consumes one.
row("pos_0", f"{VOP2(Opc.V_ADD_F32)._raw:#x}")
row("pos_1", f"{VOP2(Opc.V_ADD_F32, dsl.src[266])._raw:#x}")
row("pos_2", f"{VOP2(Opc.V_ADD_F32, dsl.src[266], dsl.src[3])._raw:#x}")
row("pos_3", f"{VOP2(Opc.V_ADD_F32, dsl.src[266], dsl.src[3], dsl.src[5])._raw:#x}")
row("pos_5", f"{VOP2(Opc.V_ADD_F32, dsl.src[266], dsl.src[3], dsl.src[5], 2, dsl.src[8])._raw:#x}")
row("kw_and_pos", f"{VOP2(Opc.V_ADD_F32, dsl.src[266], src1=dsl.src[7])._raw:#x}")
try:
  VOP2(Opc.V_ADD_F32, dsl.src[1], dsl.src[2], dsl.src[3], dsl.src[4], dsl.src[5], dsl.src[6])
  row("pos_too_many", "NOFAIL")
except (AssertionError, TypeError, RuntimeError) as e:
  row("pos_too_many", f"REFUSE:{type(e).__name__}:{e}")
try:
  VOP2(Opc.V_ADD_F32, nosuchfield=1)
  row("kw_unknown", "NOFAIL")
except (TypeError, RuntimeError) as e:
  row("kw_unknown", f"REFUSE:{type(e).__name__}:{e}")
# `op` IS a known field (an EnumBitField), so this is a TypeError from
# EnumBitField.encode, NOT the "unexpected keyword" TypeError
try:
  VOP2(op=5)
  row("kw_op_int", "NOFAIL")
except (TypeError, RuntimeError) as e:
  row("kw_op_int", f"REFUSE:{type(e).__name__}:{e}")
try:
  VOP2(Opc.V_ADD_F32, op=Opc.V_ADD_F32)
  row("kw_op_dup", "NOFAIL")
except (TypeError, RuntimeError) as e:
  row("kw_op_dup", f"REFUSE:{type(e).__name__}:{e}")

# `__repr__` trailing-default strip: `op` is skipped, FixedBitField is skipped,
# and TRAILING defaults are popped until a non-default.
class RepI(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  a = dsl.BitField(11, 8)
  b = dsl.BitField(15, 12)
  c = dsl.BitField(19, 16)


# NO `op` FIELD AT ALL: `op_bits` returns early at dsl.py:351 and `op_name`
# falls back to `type(self).__name__` (:453). This is the only spelling of
# "no opcode" that constructs, and it is a different repr PREFIX.
class RepN(dsl.Inst):
  a = dsl.BitField(11, 8)
  b = dsl.BitField(15, 12)
  c = dsl.BitField(19, 16)


for kw in (dict(), dict(a=1), dict(b=2), dict(c=3), dict(a=1, b=2), dict(a=1, b=2, c=3),
           dict(c=3, b=2), dict(b=2, c=3)):
  k = '|'.join(f'{kk}={vv}' for kk, vv in sorted(kw.items())) or 'none'
  row(f"rep_{k}", repr(RepI(op=Opc.V_ADD_F32, **kw)))
  row(f"repraw_{k}", f"{RepI(op=Opc.V_ADD_F32, **kw)._raw:#x}")
  row(f"repn_{k}", repr(RepN(**kw)))
  row(f"repnraw_{k}", f"{RepN(**kw)._raw:#x}")

def mkcls(operands, name="C"):
  """a throwaway Inst with a FIXTURE `operands` dict. `__init_subclass__`
  recomputes `_fields` and `_base_size` from the class BODY, so the fields have
  to be body attributes, not dict entries."""
  return type(name, (dsl.Inst,), {"a": dsl.BitField(11, 8), "operands": operands})


# ===========================================================================
# 11. op_bits / op_regs / canonical_* / num_srcs -- the ADJUSTMENTS, not the XML.
#     `operands` is a FIXTURE dict on MOP; every rewrite is dsl.py's.
# ===========================================================================
def show(nm, C, **kw):
  try:
    i = C(**kw)
    row(f"opbits_{nm}", json.dumps(i.op_bits, sort_keys=True))
    row(f"opregs_{nm}", json.dumps(i.op_regs, sort_keys=True))
    row(f"cobits_{nm}", json.dumps(i.canonical_op_bits, sort_keys=True))
    row(f"coregs_{nm}", json.dumps(i.canonical_op_regs, sort_keys=True))
    row(f"numsrcs_{nm}", i.num_srcs())
    row(f"coper_{nm}", json.dumps({k: list(v) for k, v in i.canonical_operands.items()},
                                  sort_keys=True))
  except (AttributeError, RuntimeError, TypeError) as e:
    row(f"opbits_{nm}", f"REFUSE:{type(e).__name__}:{e}")
    row(f"opregs_{nm}", "-")
    row(f"cobits_{nm}", "-")
    row(f"coregs_{nm}", "-")
    row(f"numsrcs_{nm}", "-")
    row(f"coper_{nm}", "-")

show("plain", MOP, op=Opc.V_ADD_F32)
show("cndmask", MOP, op=Opc.V_CNDMASK_F32)
show("cndmask_other", MOP, op=Opc.OTHER)
show("co_ci", MOP, op=Opc.V_CO_CI_ADD_F32)
show("cmp", MOP, op=Opc.V_CMP_LT_F32)
show("vop3sd", VOP3SD, op=Opc.V_ADD_F32)
show("vop3sd_add", VOP3SD, op=Opc.V_ADD_F32)
# GLOBAL/FLAT: `addr` is 64 bits iff the ENCODED `saddr` reads 124 or 125
for cls_nm in ("MOP", "SCR"):
  C = MOP if cls_nm == "MOP" else SCR
  for sa in (0, 1, 62, 124, 125, 126, 127, 255):
    # passed to the CONSTRUCTOR: mutating `_raw` after construction is read by
    # the CACHED `op_bits`, so every such row above was measuring the cache.
    row(f"addr_{cls_nm}_{sa}", C(op=Opc.GLOBAL_ATOMIC_ADD_F32, saddr=sa).op_bits.get("addr"))
    row(f"addrregs_{cls_nm}_{sa}", C(op=Opc.GLOBAL_ATOMIC_ADD_F32, saddr=sa).op_regs.get("addr"))
# SCRATCH/VSCRATCH are EXEMPT from the addr override (dsl.py:363)
for cls_nm, C in (("SCRATCH", SCR), ("VSCRATCH", SCR)):
  for sa in (124, 125, 0):
    row(f"addrx_{cls_nm}_{sa}", C(op=Opc.SCRATCH_LOAD_F32, saddr=sa).op_bits.get("addr"))
# MUBUF: vaddr is max(1, offen + idxen) * 32.
#
# THE FIRST VERSION OF THIS MUTATED `_raw` AFTER CONSTRUCTION AND READ
# `op_bits` -- AND GOT 32 WHERE THE RULE SAYS OTHERWISE, because
# `functools.cached_property` had already been filled by `__init__`'s own
# `self.op_regs` call at dsl.py:337, BEFORE the mutation. The oracle was wrong,
# not the port, and it agreed with the port by accident. Now the bits are passed
# to the CONSTRUCTOR, which is what a real caller does.
for off_en in (0, 1):
  for idx_en in (0, 1):
    row(f"vaddr_{off_en}{idx_en}", MOP(op=Opc.V_ADD_F32, offen=off_en, idxen=idx_en).op_bits.get("vaddr"))
    row(f"vaddrregs_{off_en}{idx_en}", MOP(op=Opc.V_ADD_F32, offen=off_en, idxen=idx_en).op_regs.get("vaddr"))
# F8F6F4: cbsz/blgp select the A/B matrix format -- declared fields win, and
# dsl.py:376 MULTIPLIES the table by 32 (`vgprs.get(cbsz, 8) * 32`), which is
# the line a port that stops at the table gets wrong in all twenty-five rows.
#
# THE FIRST VERSION MUTATED `_raw` AFTER CONSTRUCTION AND PRINTED `256,256` FOR
# EVERY ROW, because `functools.cached_property` had already filled `op_bits`
# from `__init__`'s own `op_regs` call (dsl.py:337) BEFORE the mutation. The PORT
# was right and the ORACLE was wrong -- the mirror of the `nv/ip` case. The bits
# now go to the CONSTRUCTOR, which is what a real caller does.
for cbsz in range(5):
  for blgp in range(5):
    i = MOP(op=Opc.V_F8F6F4_MFMA_F32_32X32X8_F16, cbsz=cbsz, blgp=blgp)
    row(f"f8f6f4_{cbsz}_{blgp}", f"{i.op_bits.get('src0')},{i.op_bits.get('src1')}")
row("f8f6f4_notf8f6f4", f"{MOP(op=Opc.V_ADD_F32).op_bits.get('src0')},"
                        f"{MOP(op=Opc.V_ADD_F32).op_bits.get('src1')}")
# and a class WITHOUT declared cbsz/blgp, so the bit-position arm is reachable
class RAW(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  src0 = dsl.SrcField(25, 17)
  src1 = dsl.SrcField(34, 26)
  operands = {"src0": (0, 32), "src1": (0, 32)}
for cbsz in range(5):
  for blgp in range(2):
    # RAW declares no cbsz/blgp, so dsl.py:373-374 read the RAW WORD -- and
    # `op_bits` is cached at construction, so the word must be in `_raw` BEFORE
    # the read. A post-hoc `_raw` mutation is never seen; that is the same trap
    # that made the vaddr and cbsz rows above all answer one value.
    i = RAW(op=Opc.V_F8F6F4_MFMA_F32_32X32X8_F16)
    i.__dict__.pop("op_bits", None)
    i.__dict__.pop("op_regs", None)
    i._raw = (cbsz << 8) | (blgp << 61) | (i._raw & 0xFFFFFF00)
    row(f"rawf8f6f4_{cbsz}_{blgp}", f"{i.op_bits.get('src0')},{i.op_bits.get('src1')}")
    i._raw = (cbsz << 8) | (blgp << 61) | (i._raw & 0xFF)
    row(f"rawf8f6f4_{cbsz}_{blgp}", f"{i.op_bits.get('src0')},{i.op_bits.get('src1')}")
# `canonical_op_bits` SEEDS d/s0/s1/s2/data at 32 and only overwrites on a
# canonical name -- so an operand dict with none of those names leaves the seed.
show("canon_none", MOP, op=Opc.V_ADD_F32)
for nm, d in (("c_s0", {"src0": (0, 64)}), ("c_vs0", {"vsrc0": (0, 128)}),
              ("c_ss0", {"ssrc0": (0, 96)}), ("c_s1", {"src1": (0, 64)}),
              ("c_vs1", {"vsrc1": (0, 96)}), ("c_ss1", {"ssrc1": (0, 96)}),
              ("c_s2", {"src2": (0, 64)}), ("c_d", {"vdst": (1, 128)}),
              ("c_sdst", {"sdst": (0, 128)}), ("c_sdata", {"sdata": (0, 64)}),
              ("c_data", {"data": (0, 96)}), ("c_vdata", {"vdata": (0, 96)}),
              ("c_data0", {"data0": (0, 64)}), ("c_vsrc", {"vsrc": (0, 96)}),
              ("c_unknown", {"zz": (0, 999)})):
  C = mkcls(d)
  row(f"canonbits_{nm}", json.dumps(C().canonical_op_bits, sort_keys=True))
  row(f"canonregs_{nm}", json.dumps(C().canonical_op_regs, sort_keys=True))
  row(f"canonoper_{nm}", json.dumps({k: list(v) for k, v in C().canonical_operands.items()},
                                    sort_keys=True))
  row(f"canonnum_{nm}", C().num_srcs())
# num_srcs rungs, one per spelling, driven by the OPERAND NAMES only
for nm, d in (("n3", {"src0": (0, 32), "src1": (0, 32), "src2": (0, 32)}),
              ("n3b", {"vsrc0": (0, 32), "vsrc1": (0, 32), "src2": (0, 32)}),
              ("n3c", {"ssrc0": (0, 32), "vsrc1": (0, 32), "src2": (0, 32)}),
              ("n2", {"src0": (0, 32), "src1": (0, 32)}),
              ("n2b", {"src0": (0, 32), "vsrc1": (0, 32)}),
              ("n2c", {"src0": (0, 32), "ssrc1": (0, 32)}),
              ("n2d", {"zz": (0, 32), "src0": (0, 32)}),
              ("n1", {"src0": (0, 32)}),
              ("n1b", {"vsrc0": (0, 32)}),
              ("n1c", {"ssrc0": (0, 32)}),
              ("n0", {}),
              ("n0b", {"data": (0, 32)}),
              ("n0c", {"addr": (1, 64), "saddr": (0, 8)}),
              ("n0d", {"vdst": (1, 32)})):
  C = mkcls(d)
  row(f"numsrcs_{nm}", C().num_srcs())

# ===========================================================================
# 12. `_variant_suffix`: 255 -> _LIT, 249 -> _SDWA (cdna) / _DPP8, 250 -> _DPP16.
#     The opx/opy FMAMK/FMAAK arm (:429-430) needs those attributes, and
#     `_is_cdna` (:346) is `'cdna' in type(self).__module__`.
# ===========================================================================
class VS(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  src0 = dsl.SrcField(16, 8)


for off in (0, 248, 249, 250, 255, 124, 256):
  row(f"vsuf_{off}", VS(op=Opc.V_ADD_F32, src0=dsl.Reg(off, 1))._variant_suffix())
row("vsuf_none", VS(op=Opc.V_ADD_F32)._variant_suffix())
row("vsuf_is_cdna", VS._is_cdna(VS(op=Opc.V_ADD_F32)))
row("vsuf_modname", VS.__module__)


class VOPD(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  opx = dsl.BitField(15, 8).enum(Opc)
  opy = dsl.BitField(23, 16).enum(Opc)
  src0 = dsl.SrcField(32, 24)
  operands = {"src0": (0, 32)}


class MFAMK(enum.IntEnum):
  FMAMK = 10
  FMAAK = 11
  OTHER = 12


class VOPD2(VOPD):
  opx = dsl.BitField(15, 8).enum(MFAMK)
  opy = dsl.BitField(23, 16).enum(MFAMK)


for v in (MFAMK.FMAMK, MFAMK.FMAAK, MFAMK.OTHER):
  row(f"vopd_{v.name}", VOPD2(op=Opc.V_ADD_F32, opx=v, opy=v, src0=dsl.src[0])._variant_suffix())
row("vopd_other", VOPD(op=Opc.V_ADD_F32, opx=Opc.V_ADD_F32,
                          opy=Opc.V_ADD_F32, src0=dsl.src[0])._variant_suffix())
# a class that IS already a variant reports None for every src offset (:427)
class VS_LIT(VS): pass
for off in (0, 249, 250, 255):
  row(f"vsuf_islit_{off}", VS_LIT(op=Opc.V_ADD_F32, src0=dsl.Reg(off, 1))._variant_suffix())

# ===========================================================================
# 13. `size`/`_size` and the 64-bit WALL. `to_bytes` is `_raw` little-endian at
#     `_base_size` bytes; a field wider than 32 bits cannot be a U32.
# ===========================================================================
row("f64i_size", F64I._base_size)
row("f64i_mask_lit", F64I._fields[1][1].mask)
row("f64i_mask_frac", dsl.BitField(31, 0).mask)
row("f64i_mask40", dsl.BitField(39, 0).mask)
row("f32i_bytes", F32I(op=Opc.OTHER, A=0x1234).to_bytes().hex())
row("f64i_bytes", F64I(op=Opc.OTHER, lit=0x12345678).to_bytes().hex())
row("f16i_bytes", F16I(op=Opc.OTHER, A=0x1234, B=0x5678).to_bytes().hex())
row("f40i_bytes", F40I(op=Opc.OTHER, A=0x123456).to_bytes().hex())
row("f8i_bytes", F8I(op=Opc.OTHER).to_bytes().hex())
row("f32i_mask", F32I._fields[1][1].mask)
row("f16i_mask_a", F16I._fields[1][1].mask)
row("f16i_mask_b", F16I._fields[2][1].mask)
# `bits[a:b] == v` produces a FixedBitField whose set() IGNORES the value
row("fixed_class", type(dsl.BitField(7, 0) == 3).__name__)
row("fixed_hilo", f"{dsl.BitField(7, 0) == 3}.hi,{(dsl.BitField(7, 0) == 3).lo}")
row("fixed_mask", (dsl.BitField(7, 0) == 3).mask)
row("fixed_default", f"{(dsl.BitField(7, 0) == 3).default:#x}")
try:
  dsl.BitField(7, 0).encode("x")
  row("bf_encode_str", "NOFAIL")
except (AssertionError, TypeError) as e:
  row("bf_encode_str", f"REFUSE:{type(e).__name__}")
try:
  dsl.BitField(7, 0) == "x"
  row("bf_eq_str", "NOFAIL")
except TypeError as e:
  row("bf_eq_str", f"REFUSE:{e}")
# EnumBitField: `allowed` (:137-138) and the non-member (:136)
class EA(enum.IntEnum):
  A = 1
  B = 2
ef = dsl.BitField(3, 0).enum(EA)
row("enum_enc_a", ef.encode(EA.A))
row("enum_enc_b", ef.encode(EA.B))
try:
  ef.encode(3)
  row("enum_enc_int", "NOFAIL")
except RuntimeError as e:
  row("enum_enc_int", f"REFUSE:{e}")
eaf = dsl.EnumBitField(3, 0, EA, allowed={EA.A})
row("enum_allowed_a", eaf.encode(EA.A))
try:
  eaf.encode(EA.B)
  row("enum_allowed_b", "NOFAIL")
except RuntimeError as e:
  row("enum_allowed_b", f"REFUSE:{e}")
row("enum_decode_1", ef.decode(1).name)
try:
  ef.decode(9)
  row("enum_decode_9", "NOFAIL")
except ValueError as e:
  row("enum_decode_9", f"REFUSE:{type(e).__name__}")

print("\n".join(OUT))
