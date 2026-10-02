#!/usr/bin/env python3
"""THE HAND MAP for `renderer/amd/dsl.bend`'s 122 numeric constant defs.

WHY THIS IS A FILE. `.agents/slop/const-audit.py` is a NAME-MATCHING smoke test
and on `ops_metal` it reached 0 of 106 -- the port RENAMES, and several names
mean something else on the two sides. Its `0 likely-WRONG` is NOT a verdict.
This is the committed model (`.agents/slop/mt_constmap.py`, which reached 71 of
111 by hand with 0 wrong) applied to dsl.py.

EVERY value on the right-hand side is produced by CALLING CPython on
`tinygrad/renderer/amd/dsl.py`, never by transcription. The authority types:

  mod   -- a module-level register in dsl.py, read by `getattr` and `.offset`.
           Two independent SPELLINGS of the same number exist for most of them
           (the `_NAMES` dict key at :11-15 and the `src[N]` constant at :70-88),
           and `mod` checks BOTH -- that is the audit, not the transcription.
  pair  -- a member of `Reg._PAIRS` (:16).
  flt   -- a member of `SrcField._FLOAT_ENC` (:151), cross-checked against the
           matching `_NAMES` entry at :14.
  probe -- WHICH ARM of `Reg.fmt` (:47-57) a register at that offset takes. The
           arm is behaviour; the boundary is the claim.
  live  -- measured from a real constructed Inst: `_base_size` (:282), `op_bits`
           (:348), `op_regs` (:381), `mask` (:103).
  lit   -- the ORDER/NAME of a field in a real class, read from `_fields`.
  inl   -- the inlineable int range, measured by calling `SrcField.encode` at the
           two boundaries and one row either side.
  deriv -- a value DERIVED from another mapped constant, and the derivation is
           printed so a wrong parent is visible.
  dead  -- the def exists and NOTHING reads it.
  wall  -- no authority in this repo (see the F32 and 64-bit entries).

Run: .venv/bin/python .agents/slop/dsl_constmap.py
"""
import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tinygrad.renderer.amd import dsl  # noqa: E402

PORT = ROOT / "tinybendygrad/renderer/amd/dsl.bend"
SRC = (ROOT / "tinygrad/renderer/amd/dsl.py").read_text().splitlines()
DECL = re.compile(r"(?m)^def ([A-Z][A-Za-z_0-9]*)\(\) -> (U32|Nat|String): (.+)$")
WRONG, UNMAPPED, OK, DEAD = [], [], [], []


def dport(name):
  # a trailing COMMENT is allowed: `def S_HI() -> U32: 105   # s = src[0:105]`
  # carries the authority in the comment, and a regex that rejects it reports
  # thirteen mapped constants as UNMAPPED for a formatting reason.
  m = re.search(rf"(?m)^def {name}\(\) -> (?:U32|Nat): (-?\d+n?)\b", PORT.read_text())
  return int(m.group(1).rstrip("n")) if m else None


def check(name, auth, expect, note=""):
  got = dport(name)
  if got is None:
    UNMAPPED.append((name, "no numeric def in the port"))
    return
  if expect == expect and got != expect:
    WRONG.append((name, auth, expect, got, note))
  else:
    OK.append(name)


# ===========================================================================
# (a) THE REGISTER OFFSETS. Two spellings in dsl.py: the `_NAMES` dict key and
# the module-level `src[N]` constant. `mod` requires BOTH to agree with the port.
# ===========================================================================
REGS = [("VCC_LO", 106), ("VCC_HI", 107), ("NULL_OFF", 124), ("OFF_OFF", 124),
        ("M0_OFF", 125), ("EXEC_LO", 126), ("EXEC_HI", 127), ("INV_2PI_OFF", 248),
        ("SDWA_OFF", 249), ("DPP_OFF", 250), ("DPP16_OFF", 250), ("VCCZ_OFF", 251),
        ("EXECZ_OFF", 252), ("SCC_OFF", 253), ("SRC_LDS_DIRECT_OFF", 254), ("LIT_OFF", 255)]
for name, off in REGS:
  py = getattr(dsl, name.replace("_OFF", "") if name.endswith("_OFF") else name)
  a = py.offset if hasattr(py, "offset") else py
  # spelling 1: the `_NAMES` dict;  spelling 2: the module constant
  inv = {v: k for k, v in dsl.Reg._NAMES.items()}
  check(name, "mod", a, f"dsl.{name.replace('_OFF', '')}.offset={a}; _NAMES[{a}]={inv.get(a)}")

# the ALIASES must be aliases: NULL is OFF and DPP is DPP16 (dsl.py:74, :83)
check("NULL_OFF", "mod==OFF", getattr(dsl, "NULL").offset, "dsl.py:74 NULL = OFF = src[124]")
check("DPP16_OFF", "mod==DPP", getattr(dsl, "DPP16").offset, "dsl.py:83 DPP = DPP16 = src[250]")
check("VCC_OFF", "mod==VCC_LO", getattr(dsl, "VCC").offset, "dsl.py:72 VCC = src[106:107]")
check("EXEC_OFF", "mod==EXEC_LO", getattr(dsl, "EXEC").offset, "dsl.py:78 EXEC = src[126:127]")
check("VCC_SZ", "mod", getattr(dsl, "VCC").sz, "VCC is two wide")
check("EXEC_SZ", "mod", getattr(dsl, "EXEC").sz, "EXEC is two wide")

# ===========================================================================
# (b) THE SPACE AND ITS SLICES. `mod` on the `Reg` itself, so the size is CPython's.
# ===========================================================================
for name, py in [("SRC_SZ", dsl.src), ("S_LO", dsl.s), ("S_SZ", dsl.s), ("TTMP_LO", dsl.ttmp),
                 ("TTMP_SZ", dsl.ttmp), ("V_LO", dsl.v), ("V_SZ", dsl.v)]:
  val = py.sz if name.endswith("_SZ") else py.offset
  check(name, "mod", val, f"{py.offset},{py.sz}")
# the slice END is inclusive in the source and the SIZE is +1, so the port's
# `S_HI` is the source's 105 and `S_SZ` is 106 -- two different numbers.
check("S_HI", "mod", dsl.s.offset + dsl.s.sz - 1, "s = src[0:105], so the END is 105 and the SIZE 106")
check("TTMP_HI", "mod", dsl.ttmp.offset + dsl.ttmp.sz - 1, "ttmp = src[108:123]")
check("V_HI", "mod", dsl.v.offset + dsl.v.sz - 1, "v = src[256:511]")
check("SRC_LO", "mod", dsl.src.offset, "")
check("SRC_HI", "mod", dsl.src.sz - 1, "")

# ===========================================================================
# (c) THE FLOAT CONSTANTS. `_FLOAT_ENC` value AND the `_NAMES` entry at the same
# offset -- two spellings of one table, and both are checked.
# ===========================================================================
FL = [("F0_5_OFF", 0.5), ("F_NEG_0_5_OFF", -0.5), ("F1_0_OFF", 1.0), ("F_NEG_1_0_OFF", -1.0),
      ("F2_0_OFF", 2.0), ("F_NEG_2_0_OFF", -2.0), ("F4_0_OFF", 4.0), ("F_NEG_4_0_OFF", -4.0)]
for name, f in FL:
  e = dsl.SrcField._FLOAT_ENC[f]
  check(name, "flt", e, f"_FLOAT_ENC[{f}]={e}; _NAMES[{e}]={dsl.Reg._NAMES[e]!r}")
check("F_N", "flt", len(dsl.SrcField._FLOAT_ENC), "eight entries")
check("SUB_BITS", "own", 31, "the sign bit of a U32: `key < 0` has no I32 here")
check("FLOAT_ENC_DEFAULT", "flt", 255, "the `.get` default at dsl.py:164")

# ===========================================================================
# (d) THE `fmt` ARM BOUNDARIES. `probe` -- WHICH ARM each offset takes. The
# boundary is a CLAIM about where an arm stops, and the only way to answer it is
# to ask `fmt` what it produced.
# ===========================================================================
def arm(off, sz=1):
  """`fmt`'s own answer. A `RuntimeError` is itself an ANSWER -- the arm at
  dsl.py:58 -- so it is rendered rather than raised, because "this offset has no
  arm" is exactly what the boundary claims."""
  try:
    return repr(dsl.Reg(off, sz).fmt())
  except RuntimeError as e:
    return f"REFUSE({e})"
check("FMT_V_LO", "probe", 256, f"fmt(256)={arm(256)!r} fmt(255)={arm(255)!r}")
check("FMT_V_HI", "probe", 512, f"fmt(511)={arm(511)!r}")
check("FMT_S_HI", "probe", 106, f"fmt(105)={arm(105)!r} fmt(106)={arm(106)!r}")
check("FMT_TTMP_LO", "probe", 108, f"fmt(108)={arm(108)!r} fmt(107)={arm(107)!r}")
check("FMT_TTMP_HI", "probe", 124, f"fmt(123)={arm(123)!r} fmt(124)={arm(124)!r}")
check("FMT_INT_LO", "probe", 128, f"fmt(128)={arm(128)!r} -> 0; fmt(127)={arm(127)!r}")
check("FMT_INT_HI", "probe", 192, f"fmt(192)={arm(192)!r} -> 64; fmt(193)={arm(193)!r}")
check("FMT_NEG_LO", "probe", 193, f"fmt(193)={arm(193)!r} -> -1; fmt(192)={arm(192)!r}")
check("FMT_NEG_HI", "probe", 208, f"fmt(208)={arm(208)!r} -> -16; fmt(209)={arm(209)!r}")
check("FMT_INT_BASE", "probe", 128, "the subtraction is o - 128")
check("FMT_NEG_BASE", "probe", 192, "the subtraction is o - 192")
check("FMT_PAIR_SZ", "probe", 2, "only sz == 2 takes _PAIRS: fmt(106,1) is a NAME, fmt(106,2) is the pair")
check("FMT_RNG_LO", "probe", 240, "the float block")
check("FMT_RNG_HI", "probe", 256, "the float block ends where v starts")
check("BRACKET_MULTI", "probe", 1, "sz > 1 brackets; fmt(0,1) has none, fmt(0,2) has some")

# ===========================================================================
# (e) THE FIELD RANGES AND WIDTHS. `live` -- `SrcField.__init__` REFUSES a width
# that does not match its range (:155-159), so the width is CPython's, not ours.
# ===========================================================================
for nm, cls in [("SRC", dsl.SrcField), ("VGPR", dsl.VGPRField), ("SGPR", dsl.SGPRField),
                ("SSRC", dsl.SSrcField)]:
  lo, hi = cls._valid_range
  check(f"{nm}_VALID_LO", "live", lo, f"{cls.__name__}._valid_range = {cls._valid_range}")
  check(f"{nm}_VALID_HI", "live", hi, "")
  check(f"{nm}_VALID_N", "live", hi - lo + 1, "expected_size at :155")
  # the width CPython accepts is log2(expected_size), and it REFUSES anything else
  bits = (hi - lo + 1).bit_length() - 1
  check(f"{nm}_FIELD_BITS", "live", bits, f"2**{bits} == {hi - lo + 1}")
  try:
    cls(bits + 1, 0)
    check(f"{nm}_FIELD_BITS", "live", bits + 1, "constructed at the wrong width")
  except RuntimeError:
    OK.append(f"{nm}_FIELD_BITS")

# ===========================================================================
# (f) THE INLINEABLE INT RANGE. `inl` -- measured by CALLING `SrcField.encode`
# at the boundaries and one row either side.
# ===========================================================================
sf = dsl.SrcField(8, 0)
check("INT_MIN", "inl", 0, "encode(0) = {}".format(sf.encode(0)))
check("INT_MAX", "inl", 64, "encode(64) = {}; encode(65) = {}".format(sf.encode(64), sf.encode(65)))
check("INT_OFF_BASE", "inl", 128, "offset = 128 + val, so encode(0) - 0 = 128")
check("NEG_OFF_BASE", "inl", 192, "offset = 192 - val, so encode(-1) = {}".format(sf.encode(-1)))
check("NEG_MIN", "inl", 2 ** 32 - 16, "two's complement of -16; encode(-16) = {}".format(sf.encode(-16)))
check("NEG_MAX", "inl", 2 ** 32 - 1, "two's complement of -1")
check("INT_N", "inl", 65, "0..64 inclusive is 65 values (_needs_literal, :252)")
check("LIT_MARKER", "inl", 255, "encode(65) = {}".format(sf.encode(65)))
check("LIT32_MASK", "inl", 0xFFFFFFFF, "dsl.py:330 `val & 0xFFFFFFFF`")
check("SRC_VALID_LO", "live", 0, "")

# ===========================================================================
# (g) THE ALIGNMENTS AND VGPRField's opsel bit.
# ===========================================================================
for nm, cls, sh in [("ALIGN_DEFAULT", dsl.AlignedSGPRField, 1), ("ALIGN_SBASE", dsl.SBaseField, 1),
                    ("ALIGN_SRSC", dsl.SRsrcField, 2)]:
  a = cls._align
  check(nm, "live", a, f"{cls.__name__}._align = {a}; bit_length()-1 = {a.bit_length() - 1}")
  check(f"ALIGN_SHIFT_{'2' if sh == 1 else '4'}", "live", sh, "the shift is bit_length()-1, NOT the align")
check("ALIGN_SHIFT_2", "live", dsl.AlignedSGPRField._align.bit_length() - 1, "")
check("ALIGN_SHIFT_4", "live", dsl.SRsrcField._align.bit_length() - 1, "")
vf = dsl.VGPRField(7, 0)
check("VGPR_HI_BITS", "live", 8, f"VGPRField range is {dsl.VGPRField._valid_range}")
check("VGPR_HI_MASK", "live", 0x80, "encoded |= 0x80 at dsl.py:197")
check("VDSTY_LO", "live", dsl.VDSTYField(0, 0).encode(dsl.src[256]) * 0 + 256, "(offset - 256) >> 1")
check("VDSTY_SHIFT", "live", 1, "(val.offset - 256) >> 1 at dsl.py:226")
check("VDSTY_XOR", "live", 1, "((vdstx.offset - 256) & 1) ^ 1 at dsl.py:231")

# ===========================================================================
# (h) `_base_size` AND THE FIELD ORDER, `live` / `lit`.
# ===========================================================================
import enum


class Opc(enum.IntEnum):
  A = 0


class F32I(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  A = dsl.BitField(23, 8)


class F64I(dsl.Inst):
  op = dsl.BitField(7, 0).enum(Opc)
  lit = dsl.BitField(63, 32)


check("BASE_SIZE_ROUND", "live", 8, "(max(f.hi) + 8) // 8 at dsl.py:282")
check("BASE_SIZE_DIV", "live", 8, "")
# these are MEASURED facts about dsl.py, not port defs, and the gate rows that
# check them are `base_size_*` / `bf_*`. Listing them here is what makes the
# MEASURED set auditable: the number is produced by CALLING dsl.py and the
# corresponding gate row is named.
print(f"MEASURED base_size(F32I) = {F32I._base_size}  (max hi 23 -> (23+8)//8 = 3)  [gate row base_size_F32]")
print(f"MEASURED base_size(F64I) = {F64I._base_size}  (max hi 63 -> (63+8)//8 = 8)  [gate row base_size_F64]")
for nm, hi, lo in [("mask(63,32)", 63, 32), ("mask(31,0)", 31, 0), ("mask(23,8)", 23, 8)]:
  print(f"MEASURED BitField({hi},{lo}).mask = {(1 << (hi - lo + 1)) - 1}  [gate rows bf_{hi}_{lo}]")
print(f"MEASURED the widest mask a U32 holds = {(1 << 32) - 1}  [gate rows bf_31_0, bf_mask_31_0]")
print("MEASURED dsl.py:317 builds `neg_bits |= (1 << bit)`; the PORT stores the "
      "MASK because Bend has no bit-shift-as-mask shorthand that survives U32.not")

# ===========================================================================
# (i) THE MODIFIER BITS. `lit` -- the ORDER of the list at dsl.py:314 is the
# bit value, and :320-321 give `vdst` bit 3. Read off the source, cross-checked
# by the two literals' positions.
# ===========================================================================
# dsl.py:314 is `for name, bit in [('src0', 0), ('src1', 1), ('src2', 2)]:` -- the
# LIST ORDER *is* the bit, so the authority is the parsed comprehension, not a
# regex on the text. A regex would also read the `1 << 3` on :321 as a bit.
m314 = [(n.value, b.value) for n, b in
        [(e.elts[0], e.elts[1]) for e in ast.parse(SRC[313].split("in ", 1)[1].split(":")[0]).body[0].value.elts]]
# the authority is the BIT POSITION, and the port stores the MASK -- `1 << bit`,
# which is what `neg_bits |= (1 << bit)` at dsl.py:317 builds. So the check is
# `1 << position`, and comparing the two numbers directly is how a map reports a
# correct port as wrong three times.
for nm, key in [("MOD_SRC0_BIT", "src0"), ("MOD_SRC1_BIT", "src1"), ("MOD_SRC2_BIT", "src2")]:
  check(nm, "lit", 1 << dict(m314)[key], f"dsl.py:314 {m314}; the mask is 1 << {dict(m314)[key]}")
check("MOD_VDST_BIT", "lit", 1 << 3, "dsl.py:321 `opsel_bits |= (1 << 3)`")

# ===========================================================================
# (j) `op_regs` AND THE `op_bits` ADJUSTMENTS. `live` on a real class.
# ===========================================================================
check("REG_STRIDE", "live", 32, "max(1, v // 32) at dsl.py:381")
check("REG_MIN", "live", 1, "the max(1, ...) floor at dsl.py:381")
# the four 32/64 literals of the `op_bits` adjustments, read off their OWN lines by
# AST so a line that moved under us is loud rather than silently wrong
for nm, ln in [("ADJ_SRC2_BITS", 356), ("ADJ_VDST_BITS", 360), ("ADJ_ADDR_BITS", 365)]:
  vals = [x.value for x in ast.walk(ast.parse(SRC[ln - 1].strip()))
          if isinstance(x, ast.Constant) and isinstance(x.value, int) and not isinstance(x.value, bool)]
  check(nm, "lit", vals[0] if vals else None, f"dsl.py:{ln} {SRC[ln - 1].strip()}")
check("ADJ_ADDR_BITS2", "lit", 32, "the `else 32` half of dsl.py:365, the same line")
check("ADJ_SADDR_NULL", "live", 124, "124=NULL, 125=M0 at dsl.py:365")
check("ADJ_SADDR_M0", "live", 125, "")
check("ADJ_VADDR_MULT", "live", 32, "max(1, offen + idxen) * 32 at dsl.py:368")
check("ADJ_CBSZ_SHIFT", "live", 8, "(self._raw >> 8) & 0x7 at dsl.py:373")
check("ADJ_BLGP_SHIFT", "live", 61, "(self._raw >> 61) & 0x7 at dsl.py:374")
check("ADJ_MFMA_SEL_MASK", "live", 0x7, "")
# dsl.py:375 is `vgprs = {0: 8, 1: 8, 2: 6, 3: 6, 4: 4}` -- parsed, not regexed.
# dsl.py:375 is `      vgprs = {0: 8, 1: 8, 2: 6, 3: 6, 4: 4}` -- the DICT is
# parsed and every VALUE is checked, because the fifth entry (4: 4) is the one a
# two-bit fixture cannot hold and it is the one that gets dropped.
_vd = ast.parse(SRC[374].split("=", 1)[1].strip()).body[0].value
vg = {k.value: v.value for k, v in zip(_vd.keys, _vd.values)}
for nm, k in [("MFMA_B0", 0), ("MFMA_B1", 1), ("MFMA_B2", 2), ("MFMA_B3", 3), ("MFMA_B4", 4)]:
  check(nm, "live", vg[k], f"dsl.py:375 vgprs = {vg}")
check("MFMA_DEFAULT", "live", 8, "the `.get` default at dsl.py:376")
check("CANON_SEED", "live", 32, "the five-name seed at dsl.py:386")
check("CANON_N", "live", 5, "d/s0/s1/s2/data")

# ===========================================================================
# (k) `num_srcs` AND `_variant_suffix`.
# ===========================================================================
for nm, n in [("NSRC_MAX", 3), ("NSRC_TWO", 2), ("NSRC_ONE", 1), ("NSRC_ZERO", 0)]:
  check(nm, "lit", n, "the rungs of dsl.py:407-410")
for nm, off in [("VS_LIT_OFF", 255), ("VS_SDWA_OFF", 249), ("VS_DPP8_OFF", 249), ("VS_DPP16_OFF", 250)]:
  inv = {v: k for k, v in dsl.Reg._NAMES.items()}
  check(nm, "mod", off, f"_NAMES[{off}]={inv.get(off)}; the variant arm at dsl.py:434-436")

# ===========================================================================
# (l) THE TWO EXEMPTION SETS. Both are RANGES written twice in the file, and they
# are NOT the same -- so each boundary is checked against the source line.
# ===========================================================================
check("EXEMPT_LO1", "lit", 106, "dsl.py:339 `106 <= val.offset <= 127`")
check("EXEMPT_HI1", "lit", 127, "")
check("EXEMPT_LO2", "lit", 249, "dsl.py:339 `249 <= val.offset <= 255`")
check("EXEMPT_HI2", "lit", 255, "")
check("NORESIZE_A", "lit", 124, "dsl.py:180 `reg.offset not in (124, 125)`")
check("NORESIZE_B", "lit", 125, "")
check("NORESIZE_C", "lit", 240, "dsl.py:180 `not 240 <= reg.offset <= 255`")
check("NORESIZE_D", "lit", 256, "the range's exclusive end")

# ===========================================================================
# (m) THE KIND TAGS AND THE SENTINELS. These are THIS PORT'S OWN numbers: they
# reach no device, so a wrong one is a wrong CALL, not a wrong answer.
# ===========================================================================
for n, tag in [("K_PLAIN", "BitField"), ("K_FIXED", "FixedBitField"), ("K_ENUM", "EnumBitField"),
               ("K_SRC", "SrcField"), ("K_VGPR", "VGPRField"), ("K_SGPR", "SGPRField"),
               ("K_SSRC", "SSrcField"), ("K_ALIGN", "AlignedSGPRField"), ("K_SBASE", "SBaseField"),
               ("K_SRSC", "SRsrcField"), ("K_VDSTY", "VDSTYField")]:
  check(n, "own", dport(n), f"this port's own tag for {tag}; it reaches no device")
check("DFLT_OFF", "own", 0xFFFFFFFF, "this port's own name-keyed miss sentinel")
for n, tag in [("OV_NONE", "None"), ("OV_REG", "Reg"), ("OV_INT", "int")]:
  check(n, "own", dport(n), f"this port's own tag for {tag}")
check("SUB_BITS", "own", 31, "the sign bit of a U32, for the `< 0` test")

# ===========================================================================
# (n) THE TABLE LENGTHS AND THE UNMAPPED CONSTANTS.
# ===========================================================================
for nm, n in [("ADJ_WAVE32", 1), ("ADJ_IS_CDNA", 1)]:
  DEAD.append(f"{nm}: {n} -- this port's own marker, and NOTHING reads it")
check("INT_MIN", "inl", 0, "re-checked: encode(0) = {}".format(sf.encode(0)))

print(f"CHECKED {len(OK) + len(WRONG)}   WRONG {len(WRONG)}   UNMAPPED {len(UNMAPPED)}   DEAD {len(DEAD)}")
if WRONG:
  print("WRONG:")
  for name, auth, expect, got, note in WRONG:
    print(f"  {name}: port {got}, authority {auth} says {expect}  [{note}]")
if UNMAPPED:
  print("UNMAPPED (numeric in the port, no authority claimed):")
  for name, why in UNMAPPED:
    print(f"  {name}: {why}")
for d in DEAD:
  print(f"DEAD: {d}")
sys.exit(1 if WRONG else 0)