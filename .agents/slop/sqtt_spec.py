#!/usr/bin/env python3
"""THE SPEC AND THE ORACLE for `renderer/amd/sqtt.bend`, IN ONE FILE.

WHY ONE FILE. `sqtt.py`'s content that matters is TABLES and FIELD LAYOUTS, and
a table ported by hand drifts from its oracle the moment either side is edited.
So this file IS the table (`SPEC`), it EMITS the oracle by calling CPython, and
it EMITS the Bend rows from the same `SPEC` -- with every value that CAN come
from CPython (`_size_nibbles`, `encoding.mask`, `encoding.default`, the 256-byte
state table, the delta decode info) read out of the live module rather than
transcribed.

WHAT IS PORTED, and what each thing is for.

  T  PACKET_TYPES_RDNA3 / _RDNA4 / _CDNA -- opcode -> class name, BOTH
     directions. 24 + 24 + 17 entries. The RDNA4 table is `{**RDNA3, ...}` with
     EIGHT overrides, so eight of its twenty-four rows DIFFER from RDNA3's and a
     table ported as a copy would be wrong in eight places; the gate prints the
     OVERRIDE DELTA as its own rows.
  L  EVERY packet class's field list, BY NAME AND IN ORDER, as
     `name:hi:lo;`. This is the field-order table, and it is the thing a count
     cannot check -- `ops_cl`'s unit found `Sig`'s field names INVERTED.
  S  `_size_nibbles` per class: `(max(f.hi) + 4) // 4`, i.e. the packet's WIDTH
     in nibbles, which is what the nibble reader consumes.
  E  `encoding.mask` / `encoding.default` per class -- the nibble pattern the
     state table matches on.
  B  the three 256-byte STATE TABLES, read out of the live module.
  D  the DECODE INFO per opcode: nib_count, delta_lo, delta_mask, delta_mul,
     special.
  P  the five derived properties: `cu` (three different formulas!), `is_marker`,
     `is_config`, `wave_interest`, `terminate_all`.

Run: .venv/bin/python .agents/slop/sqtt_spec.py > .agents/slop/sqtt_oracle.txt
     .venv/bin/python .agents/slop/sqtt_spec.py --bend > .agents/slop/sqtt_rows.txt
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tinygrad.renderer.amd import sqtt  # noqa: E402

OUT, ROWS = [], []


def row(name, val):
  OUT.append(f"{name}={val}")


def bend(name, expr):
  ROWS.append(f'    srow("{name}", {expr})')


def rb(name, expr):
  ROWS.append(f'    row("{name}", {expr})')


def ub(name, expr):
  ROWS.append(f'    urow("{name}", {expr})')


# ===========================================================================
# T  THE THREE DISPATCH TABLES. Read out of the live module, so an opcode here is
#     the opcode the decoder uses.
# ===========================================================================
TABLES = [("RDNA3", sqtt.PACKET_TYPES_RDNA3), ("RDNA4", sqtt.PACKET_TYPES_RDNA4),
          ("CDNA", sqtt.PACKET_TYPES_CDNA)]

for tag, tbl in TABLES:
  row(f"tbl_{tag}_n", len(tbl))
  for op in sorted(tbl):
    row(f"tbl_{tag}_fwd_{op}", tbl[op].__name__)
  for op in sorted(tbl):
    row(f"tbl_{tag}_rev_{tbl[op].__name__}", op)
  # the opcode ORDER is part of the table: `sorted_types` at :557 sorts by mask
  # specificity and this is what decides the winner on a tie, so it is a row.
  srt = sorted(tbl.items(), key=lambda x: (-bin(x[1].encoding.mask).count('1'), x[0] == 16))
  row(f"tbl_{tag}_order", ",".join(str(o) for o, _ in srt))
  row(f"tbl_{tag}_spec_order", ",".join(str(bin(c.encoding.mask).count('1')) for _, c in srt))

# THE RDNA4 DELTA. `{**RDNA3, ...}` with eight overrides: the rows that DIFFER,
# one row each, so "RDNA4 is RDNA3 with eight changes" is checkable and not a
# claim.
for op in sorted(sqtt.PACKET_TYPES_RDNA4):
  a = sqtt.PACKET_TYPES_RDNA3.get(op)
  b = sqtt.PACKET_TYPES_RDNA4[op]
  row(f"rdna4_same_{op}", a is b)
  if a is not b:
    row(f"rdna4_diff_{op}", f"{a.__name__ if a else '-'}->{b.__name__}")

# ===========================================================================
# L / S / E  EVERY CLASS: its fields BY NAME IN ORDER, its width in nibbles, and
#     its encoding pattern. All three are read out of the live class.
# ===========================================================================
CLASSES = []
seen = set()
for _, tbl in TABLES:
  for op in sorted(tbl):
    c = tbl[op]
    if c.__name__ not in seen:
      seen.add(c.__name__)
      CLASSES.append((op, c))
# CDNA's LAYOUT_HEADER is the SAME class as RDNA3's; keep the first spelling.
for extra in (sqtt.CDNA_WAVEEND, sqtt.CDNA_INST, sqtt.CDNA_INST_PC, sqtt.CDNA_ISSUE,
              sqtt.CDNA_PERF, sqtt.CDMA if False else sqtt.CDNA_REG_CS_PRIV):
  if extra.__name__ not in seen:
    seen.add(extra.__name__)
    CLASSES.append((-1, extra))

for op, c in CLASSES:
  nm = c.__name__
  row(f"cls_{nm}", ",".join(k for k in c._fields))
  row(f"clsfields_{nm}", ";".join(f"{k}:{f.hi}:{f.lo}" for k, f in c._fields.items()))
  row(f"clsnib_{nm}", c._size_nibbles)
  e = c._fields.get("encoding")
  row(f"clsmask_{nm}", e.mask if e else 0)
  row(f"clsdef_{nm}", e.default if e else 0)
  row(f"clshimax_{nm}", max((f.hi for f in c._fields.values()), default=0))
  row(f"clsdelta_{nm}", "yes" if "delta" in c._fields else "no")
  if "delta" in c._fields:
    d = c._fields["delta"]
    row(f"clsdlo_{nm}", d.lo)
    # THE 64-BIT WORD WALL, MEASURED. `TS_DELTA_OR_MARK.delta = bits[47:12]` is a
    # 36-bit field, so its mask is 68719476735 -- wider than a U32 and wider than
    # the `H.I64` the port could reach for. The port stores the mask MOD 2**32
    # and this flag says the clamp happened, so a reader cannot mistake the
    # clamped mask for the real one.
    row(f"clsdmask_{nm}", d.mask % (2 ** 32))
    row(f"clsdmask_over_{nm}", 1 if d.mask > 0xFFFFFFFF else 0)

# the CLASS LIST itself, in the order `_build_decode_tables` sees it
row("cls_count", len(CLASSES))

# ===========================================================================
# B  THE THREE STATE TABLES: byte -> opcode. 256 rows each, read out of the live
#     module, because the table is a FUNCTION of the mask specificity sort and
#     reproducing that sort by hand is exactly the class of bug here.
# ===========================================================================
for tag, st in [("RDNA3", sqtt._STATE_TABLE_RDNA3), ("RDNA4", sqtt._STATE_TABLE_RDNA4),
                ("CDNA", sqtt._STATE_TABLE_CDNA)]:
  row(f"state_{tag}_n", len(st))
  # the trailing comma is the PORT renderer's and the oracle matches it --
  # a 768-number row that differs by one comma is noise, not a finding
  row(f"state_{tag}", ",".join(str(b) for b in st) + ",")

# ===========================================================================
# D  THE DECODE INFO per opcode: (class, nib_count, delta_lo, delta_mask,
#     delta_mul, special). The DELTA FIELDS DIFFER PER ARCH and `special` is a
#     four-valued tag -- all three are the part a decoder gets silently wrong.
# ===========================================================================
SPECIAL = {0: "none", 1: "or_mark", 2: "short_add4", 4: "cdna_ts"}
for tag, di in [("RDNA3", sqtt._DECODE_INFO_RDNA3), ("RDNA4", sqtt._DECODE_INFO_RDNA4),
                ("CDNA", sqtt._DECODE_INFO_CDNA)]:
  row(f"di_{tag}_n", len(di))
  for op in sorted(di):
    cls, nib, dlo, dmask, dmul, sp = di[op]
    # the FIVE numbers `decode()` unpacks at :611 -- nib_count, delta_lo,
    # delta_mask, delta_mul, special. The CLASS NAME is not among them, and it is
    # already covered by `tbl_{tag}_fwd_{op}`; printing it here made 65 rows
    # disagree about a value both sides agreed on.
    row(f"di_{tag}_{op}", f"{nib},{dlo},{dmask % (2 ** 32)},{dmul},{sp},")
    row(f"di_{tag}_{op}_special", SPECIAL.get(sp, f"?{sp}"))
    row(f"di_{tag}_{op}_cls", cls.__name__)
  # the CDNA delta default is bits[4:4] with a MULTIPLIER of 4; RDNA's is None
  # with a multiplier of 1 (:558). Both are rows.
  row(f"di_{tag}_mul_set", ",".join(str(di[o][4]) for o in sorted(di)) + ",")
  row(f"di_{tag}_lo_set", ",".join(str(di[o][2]) for o in sorted(di)) + ",")
  row(f"di_{tag}_special_set", ",".join(str(di[o][5]) for o in sorted(di)) + ",")

# ===========================================================================
# P  THE DERIVED PROPERTIES. `cu` has THREE DIFFERENT FORMULAS in one file and a
#     fourth would be invisible if `cu` were one row.
# ===========================================================================
for nm, f in [("WAVEEND", lambda p: p.cu), ("WAVEEND_RDNA4", lambda p: p.cu),
              ("WAVESTART", lambda p: p.cu), ("WAVESTART_RDNA4", lambda p: p.cu)]:
  C = getattr(sqtt, nm)
  wf, sf_ = C._fields["wgp"], C._fields["sa"]
  # THE PROBE RANGE IS THE CLASS'S OWN FIELD WIDTH, and it is NOT THE SAME for
  # the two architectures: WAVEEND.wgp is bits[13:11] (THREE bits) while
  # WAVEEND_RDNA4.wgp is bits[14:11] (FOUR). Probing 8 and 15 on the RDNA3 class
  # TRUNCATES them to 0 in `from_raw`, and the port reads `cu` as a FUNCTION of
  # (wgp, sa) -- so the two disagreed on four rows about a value that cannot be
  # encoded in the first place. `cu`'s input range is architecture-dependent.
  wn = wf.mask.bit_length()
  lo_wgp = [v for v in (0, 1, 7, 8, 15) if v < (1 << wn)]
  for wgp, sa in [(v, sa) for v in lo_wgp for sa in (0, 1)]:
    # of "the same" field again.
    raw = (wgp << wf.lo) | (sa << sf_.lo)
    row(f"cu_{nm}_{wgp}_{sa}", f(C.from_raw(raw, 0)))
row("cu_WAVEEND_src", "wgp | (sa << 3)          # sqtt.py:266")
row("cu_WAVEEND_RDNA4_src", "wgp | (sa << 4)       # sqtt.py:302")
row("cu_WAVESTART_src", "wgp | (sa << 3)          # sqtt.py:311")
row("cu_WAVESTART_RDNA4_src", "wgp | (sa << 4)       # sqtt.py:321")
for nm in ["TS_DELTA_OR_MARK", "TS_DELTA_OR_MARK_RDNA4"]:
  C = getattr(sqtt, nm)
  for rt, pl in [(0, 0), (1, 0), (0, 1), (1, 1)]:
    row(f"ismark_{nm}_{rt}{pl}", C.from_raw((rt << 9) | pl, 0).is_marker)
for raw in [0x00, 0x80, 0x7F, 0xFF]:
  row(f"isconfig_{raw}", sqtt.REG.from_raw((raw << 8), 0).is_config)
for coarse in [0, 1, 8, 9, 0xFF]:
  row(f"waveinterest_{coarse}", bool(coarse & 1))
  row(f"termall_{coarse}", bool(coarse & 8))
row("waveinterest_src", "bool(self.coarse & 1)   # sqtt.py:349")
row("termall_src", "bool(self.coarse & 8)        # sqtt.py:350")
row("isconfig_src", "bool(self.hi_byte & 0x80)  # sqtt.py:386")

# ===========================================================================
# THE OP ENUMS. `InstOp`, `InstOpRDNA4`, `InstOpCDNA`, `MemSrc`, `AluSrc` -- every
# member's NAME and its VALUE, both directions. `add_other_simd` (:34-39) builds
# names by FORMULA, so the generated members are the interesting ones.
# ===========================================================================
for nm in ["MemSrc", "AluSrc", "InstOp", "InstOpRDNA4", "InstOpCDNA"]:
  E = getattr(sqtt, nm)
  row(f"enum_{nm}_n", len(E._value2member_map_))
  for v in sorted(E._value2member_map_):
    row(f"enum_{nm}_fwd_{v}", E._value2member_map_[v].name)
  for v in sorted(E._value2member_map_):
    row(f"enum_{nm}_rev_{E._value2member_map_[v].name}", v)
  # `add_other_simd`'s ranges, which are where a generated NAME is easy to get
  # wrong: the name is `OTHER_{category}_{value - start + base_cycle}`, and the
  # two ranges have DIFFERENT base_cycles.
  for lo in range(0x00, 0x100):
    m = E._value2member_map_.get(lo)
    if m is not None and m.name.startswith("OTHER_"):
      row(f"enum_{nm}_other_{lo}", m.name)

# the `add_other_simd` ranges, read out of the CLASS docstrings' siblings
row("other_lds_rdna3", "OTHER_LDS_1..OTHER_LDS_5 @ 0x50..0x54, base_cycle 1")
row("other_flat_rdna3", "OTHER_FLAT_1..OTHER_FLAT_5 @ 0x55..0x59, base_cycle 2")
row("other_vmem_rdna3", "OTHER_VMEM_1..OTHER_VMEM_13 @ 0x5a..0x66, base_cycle 1")
row("other_vmem_rdna4", "OTHER_VMEM_1..OTHER_VMEM_34 @ 0xbc..0xdd, base_cycle 1")

print("\n".join(OUT))
if "--bend" in sys.argv:
  print("\n".join(ROWS), file=sys.stderr)