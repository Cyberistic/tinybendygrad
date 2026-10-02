#!/usr/bin/env python3
"""MUTATION SWEEP for `renderer/amd/dsl.bend`: one edit per PORTED RULE.

WHAT IT DOES. Each entry names a rule, a regex, and a replacement. It applies the
edit to a scratch copy, runs the INTERPRETED lane, and diffs the WHOLE
`name=value` line of every row -- not the row NAME. A name-comparing harness
reported 0 for all 30 mutations in one unit and 0 for all 68 in another, because
the names all stayed put and only the values moved.

A CONSTANTS sweep (`-c`) applies `+1` to ONE numeric constant def at a time, and
its value is its BLIND LIST: `renderer/isa/x86.bend`'s sweep found none of the
logic defects and a RULES sweep found all of them. Both are run here for that
reason and the blind list is reported, not hidden.

    usage: .venv/bin/python .agents/slop/dsl_mutate.py [-c]
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BEND = ROOT / "bin/bend"
PORT = ROOT / "tinybendygrad/renderer/amd/dsl.bend"
WORK = ROOT / "tinybendygrad/renderer/amd/_dsl_mut.bend"

# (rule, regex, replacement). Each regex must hit EXACTLY ONCE or the run stops.
RULES = [
  ("M01 reg_tables names forward: FLAT_SCRATCH_LO's offset",
   r'(Nm\{"FLAT_SCRATCH_LO", )102', r"\g<1>103"),
  ("M02 reg_tables names reverse: FLAT_SCRATCH_LO's offset",
   r'(Nm\{"FLAT_SCRATCH_LO", )102', r"\g<1>103"),
  ("M03 reg_tables walk keeps the FIRST hit, not the last",
   r"Bool\.pick\(String, Bool\.and\(Bool\.not\(found\), h\), nm, got\)",
   "Bool.pick(String, h, nm, got)"),
  ("M04 pairs: EXEC's offset",
   r'Nm\{"EXEC", 126', 'Nm{"EXEC", 127'),
  ("M05 float_enc: 1.0's offset",
   r'Nm\{"2\.0", 244\},\n   Nm\{"-2\.0", 245', 'Nm{"2.0", 245},\n   Nm{"-2.0", 246'),
  ("M06 fmt arm 1 boundary: v starts at 257",
   r"def FMT_V_LO\(\) -> U32: 256", "def FMT_V_LO() -> U32: 257"),
  ("M07 fmt arm 2 boundary: s ends at 105",
   r"def FMT_S_HI\(\) -> U32: 106", "def FMT_S_HI() -> U32: 105"),
  ("M08 fmt arm 3: the PAIR width test is sz == 2",
   r"def FMT_PAIR_SZ\(\) -> U32: 2", "def FMT_PAIR_SZ() -> U32: 3"),
  ("M09 fmt arm 5: ttmp starts at 109",
   r"def FMT_TTMP_LO\(\) -> U32: 108", "def FMT_TTMP_LO() -> U32: 109"),
  ("M10 fmt arm 6: inline ints start at 129",
   r"def FMT_INT_LO\(\) -> U32: 128", "def FMT_INT_LO() -> U32: 129"),
  ("M11 fmt arm 7: inline negatives start at 194",
   r"def FMT_NEG_LO\(\) -> U32: 193", "def FMT_NEG_LO() -> U32: 194"),
  ("M12 fmt bracket rule: sz > 1 becomes sz > 0",
   r"def BRACKET_MULTI\(\) -> U32: 1", "def BRACKET_MULTI() -> U32: 0"),
  ("M13 fmt suffix ORDER: abs is applied before .h",
   r"fmt_suffix\.neg\(Rg\.neg\(r\), fmt_suffix\.abs",
   "fmt_suffix.neg(Rg.neg(r), fmt_suffix.hir"),
  ("M14 fmt `sz or self.sz`: the truthiness test becomes a presence test",
   r"def fmt_sz\(\+sz_ov: U32, \+r: Rg\) -> U32: Bool\.pick\(U32, U32\.is_zero\(sz_ov\)",
   "def fmt_sz(+sz_ov: U32, +r: Rg) -> U32: Bool.pick(U32, U32.is_gt(sz_ov"),
  ("M15 __getitem__ index bound: >= becomes >",
   r"def reg_at\(\+key: U32, \+key_neg: Bool, \+r: Rg\) -> Res:\n  reg_at\.go\(Bool\.or\(key_neg, U32\.is_ge\(key, Rg\.sz\(r\)\)\)",
   "def reg_at(+key: U32, +key_neg: Bool, +r: Rg) -> Res:\n  reg_at.go(Bool.or(key_neg, U32.is_gt(key, Rg.sz(r)))"),
  ("M16 slice bound: stop >= sz becomes stop > sz",
   r"reg_slice\.go\(Bool\.or\(Bool\.or\(start_neg, stop_neg\), U32\.is_ge\(stop, Rg\.sz\(r\)\)\)",
   "reg_slice.go(Bool.or(Bool.or(start_neg, stop_neg), U32.is_gt(stop, Rg.sz(r)))"),
  ("M17 BitField mask: (1<<bits)-1 becomes (1<<bits)",
   r"U32\.sub\(U32\.shln\(1, U32\.to_nat\(bf_bits\(f\)\)\), 1\)", "U32.shln(1, U32.to_nat(bf_bits(f)))"),
  ("M18 BitField set: the clear mask loses its NOT",
   r"U32\.and\(raw, U32\.not\(U32\.shln\(bf_mask\(f\), U32\.to_nat\(Fld\.lo\(f\)\)\)\)\)",
   "U32.and(raw, U32.shln(bf_mask(f), U32.to_nat(Fld.lo(f))))"),
  ("M19 BitField set: the placed value is not shifted",
   r"def bf_set\.placed\(f: Fld, enc: U32\) -> U32: U32\.shln\(enc, U32\.to_nat\(Fld\.lo\(f\)\)\)",
   "def bf_set.placed(f: Fld, enc: U32) -> U32: enc"),
  ("M20 SrcField encode: int 0..64 -> 129 + v",
   r"Res\{U32\.add\(INT_OFF_BASE\(\), n\), \"\"\}", "Res{U32.add(INT_OFF_BASE(), U32.add(n, 1)), \"\"}"),
  ("M21 SrcField encode: -16..-1 -> 191 - v",
   r"Res\{U32\.sub\(NEG_OFF_BASE\(\), n\), \"\"\}", "Res{U32.sub(U32.sub(NEG_OFF_BASE(), n), 1), \"\"}"),
  ("M22 SrcField encode: the literal marker is 254",
   r"case False\{\}: Res\{LIT_MARKER\(\), \"\"\}", "case False{}: Res{254, \"\"}"),
  ("M23 SrcField encode: the range subtraction becomes a no-op",
   r"case True\{\}: Res\{U32\.sub\(off, Fld\.rlo\(f\)\), s\}", "case True{}: Res{off, s}"),
  ("M24 VGPRField .h ORs bit 7 instead of SETTING it",
   r"Bool\.pick\(U32, set, U32\.or\(enc, VGPR_HI_MASK\(\)\), enc\)",
   "Bool.pick(U32, set, enc, U32.or(enc, VGPR_HI_MASK()))"),
  ("M25 VGPRField .h: the .h flag is dropped",
   r"def vgpr_hbit\(v: Ov, f: Fld\) -> Bool: Bool\.and\(Ov\.hi\(v\), U32\.is_eq\(bf_bits\(f\), VGPR_HI_BITS\(\)\)\)",
   "def vgpr_hbit(v: Ov, f: Fld) -> Bool: False{}"),
  ("M26 AlignedSGPRField: the bare int 0 is no longer accepted",
   r"def al_forms\(f: Fld, \+v: Ov\) -> Bool: Bool\.and\(U32\.is_eq\(Ov\.k\(v\), OV_INT\(\)\), U32\.is_zero\(Ov\.off\(v\)\)\)",
   "def al_forms(f: Fld, +v: Ov) -> Bool: False{}"),
  ("M27 AlignedSGPRField: the shift is the alignment, not bit_length-1",
   r"def al_shift_of\(f: Fld\) -> U32: U32\.sub\(Fld\.align\(f\), 1\)", "def al_shift_of(f: Fld) -> U32: Fld.align(f)"),
  ("M28 VDSTYField: the low bit is not inverted",
   r"def vdsty_low\(vdstx_off: U32\) -> U32: U32\.xor\(U32\.and\(U32\.sub\(vdstx_off, VDSTY_LO\(\)\), 1\), VDSTY_XOR\(\)\)",
   "def vdsty_low(vdstx_off: U32) -> U32: U32.and(U32.sub(vdstx_off, VDSTY_LO()), 1)"),
  ("M29 modifier bits: src1's bit 2 becomes bit 1",
   r"def MOD_SRC1_BIT\(\) -> U32: 2", "def MOD_SRC1_BIT() -> U32: 1"),
  ("M29b modifier bits: vdst's opsel bit 3 becomes bit 2",
   r"def MOD_VDST_BIT\(\) -> U32: 8", "def MOD_VDST_BIT() -> U32: 4"),
  ("M29c modifier bits: src0's bit 1 becomes bit 4",
   r"def MOD_SRC0_BIT\(\) -> U32: 1", "def MOD_SRC0_BIT() -> U32: 4"),
  ("M30 mod_merge: the `or 0` guard is dropped",
   r"Bool\.pick\(U32, Bool\.and\(has, U32\.is_zero\(bits\)\), Bool\.pick\(U32, has, U32\.or\(given, bits\), bits\), 0\)",
   "Bool.pick(U32, False{}, Bool.pick(U32, has, U32.or(given, bits), bits), 0)"),
  ("M31 _needs_literal: the int range becomes 0..63",
   r"def inl_int_val\(n: U32\) -> Bool: U32\.is_le\(n, INT_MAX\(\)\)", "def inl_int_val(n: U32) -> Bool: U32.is_lt(n, INT_MAX())"),
  ("M32 op_regs: max(1, v // 32) becomes v // 32",
   r"def op_regs_of\(bits: U32\) -> U32: U32\.max\(REG_MIN\(\), U32\.div\(bits, REG_STRIDE\(\)\)\)",
   "def op_regs_of(bits: U32) -> U32: U32.div(bits, REG_STRIDE())"),
  ("M33 op_bits cndmask arm: the 32 becomes 64",
   r"def ADJ_SRC2_BITS\(\) -> U32: 32", "def ADJ_SRC2_BITS() -> U32: 64"),
  ("M34 op_bits addr: NULL becomes 123",
   r"def ADJ_SADDR_NULL\(\) -> U32: 124", "def ADJ_SADDR_NULL() -> U32: 123"),
  ("M35 op_bits addr: SCRATCH stops being exempt",
   r"def addr_exempt\(\+cls: String\) -> Bool: Bool\.or\(String\.eq\(cls, \"SCRATCH\"\), String\.eq\(cls, \"VSCRATCH\"\)\)",
   "def addr_exempt(+cls: String) -> Bool: False{}"),
  ("M36 op_bits vaddr: max(1, ..) is dropped",
   r"U32\.mul\(U32\.max\(REG_MIN\(\), U32\.add\(offen, idxen\)\), ADJ_VADDR_MULT\(\)\)",
   "U32.mul(U32.add(offen, idxen), ADJ_VADDR_MULT())"),
  ("M37 f8f6f4: the * 32 is dropped",
   r"def mfma_bits\.w\(a: U32, b: U32\) -> U32: U32\.mul\(a, REG_STRIDE\(\)\)",
   "def mfma_bits.w(a: U32, b: U32) -> U32: a"),
  ("M38 f8f6f4: the vgprs table's FIFTH entry (4: 4) is dropped",
   r"Bool\.pick\(U32, U32\.is_eq\(x, 4\), MFMA_B4\(\), MFMA_DEFAULT\(\)\)",
   "MFMA_DEFAULT()"),
  ("M39 num_srcs: the first rung returns 2",
   r"case False\{\}: NSRC_MAX\(\)", "case False{}: NSRC_TWO()"),
  ("M40 _variant_suffix: 250 becomes 251",
   r"case 250n: Some\{\"_DPP16\"\}", "case 251n: Some{\"_DPP16\"}"),
  ("M41 _variant_suffix: 249 always says _SDWA",
   r"Some\{Bool\.pick\(String, is_cdna, \"_SDWA\", \"_DPP8\"\)\}", "Some{\"_SDWA\"}"),
  ("M42 _canonical_name: vsrc0 stops folding onto s0",
   r'Nm\{"vsrc0", 0\}', 'Nm{"vsrc0", 9}'),
  ("M43 _base_size: // 8 becomes // 4",
   r"def base_size\(hi_max: U32\) -> U32: U32\.div\(U32\.add\(hi_max, BASE_SIZE_ROUND\(\)\), BASE_SIZE_DIV\(\)\)",
   "def base_size(hi_max: U32) -> U32: U32.div(U32.add(hi_max, BASE_SIZE_ROUND()), 4)"),
  ("M44 no_resize: the 240..255 exemption starts at 241",
   r"def NORESIZE_C\(\) -> U32: 240", "def NORESIZE_C() -> U32: 241"),
  ("M45 exempt_width: the 106..127 exemption ends at 126",
   r"def EXEMPT_HI1\(\) -> U32: 127", "def EXEMPT_HI1() -> U32: 126"),
]

CONST_RE = re.compile(r"(?m)^def ([A-Z][A-Za-z_0-9]*)\(\) -> U32: (-?\d+)$")


def rows(path):
  r = subprocess.run([str(BEND), str(path)], capture_output=True, text=True)
  out = {}
  for line in (r.stdout + r.stderr).splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k] = v
  return out


def main():
  base = rows(PORT)
  body = PORT.read_text()
  rules = RULES
  if "-c" in sys.argv:
    rules = []
    for m in CONST_RE.finditer(body):
      name, val = m.group(1), int(m.group(2))
      rx = rf"(?m)^def {name}\(\) -> U32: {val}$"
      rules.append((f"C {name} {val} +1", rx, f"def {name}() -> U32: {val + 1}"))
  moved, blind, errored = [], [], []
  for name, rx, repl in rules:
    n = len(re.findall(rx, body))
    if n != 1:
      errored.append((name, f"regex hit {n} times"))
      continue
    WORK.write_text(re.sub(rx, repl, body, count=1))
    try:
      got = rows(WORK)
    except Exception as e:                                   # noqa: BLE001
      errored.append((name, f"{type(e).__name__}"))
      continue
    diff = [k for k in set(base) | set(got) if base.get(k) != got.get(k)]
    (moved if diff else blind).append((name, diff))
  WORK.unlink(missing_ok=True)
  for name, d in moved:
    print(f"MOVED {len(d):3d}  {name}\n        rows: {', '.join(sorted(d)[:6])}")
  print(f"\nMOVED {len(moved)}  BLIND {len(blind)}  ERRORED {len(errored)} of {len(rules)}")
  if blind:
    print("BLIND LIST:")
    for name, _ in blind:
      print(f"  {name}")
  if errored:
    print("ERRORED:")
    for name, why in errored:
      print(f"  {name}: {why}")


main()