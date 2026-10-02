#!/usr/bin/env python3
"""REWRITE the `_set` rows of sqtt_gen.py so they are DERIVED, not hardcoded.

The first version of those four rows answered from a literal in the def, and the
literal had `special = 2` at list POSITION 15 where the real answer is
`special = 1` at OPCODE 22 -- an INDEX CONFUSION. `TS_DELTA_SHORT` is opcode 15
and `TS_DELTA_OR_MARK` is opcode 22, and a hardcoded list confuses them silently.
This rewrites the generator to fold the sets out of the per-opcode tuples.

Run after editing `.agents/slop/sqtt_gen.py`'s `g_decode` block by hand; it is
idempotent.

    usage: .venv/bin/python .agents/slop/sqtt_fix_sets.py
"""
import pathlib
import re

P = pathlib.Path(__file__).resolve().parent / "sqtt_gen.py"
s = P.read_text()

NEW = '''  for tag in ["RDNA3", "RDNA4", "CDNA"]:
    # DERIVED, NOT HARDCODED. `decode_info[opcode]` is the FIVE-tuple `decode()`
    # unpacks at :611 -- nib_count, delta_lo, delta_mask, delta_mul, special --
    # and the four SETS are folded out of the concatenated tuples with a STRIDE
    # of five. The first version answered from a literal and had `special = 2` at
    # list POSITION 15 where the real answer is `special = 1` at OPCODE 22:
    # TS_DELTA_SHORT is opcode 15 and TS_DELTA_OR_MARK is opcode 22, and a
    # hardcoded list confuses them silently. Bend has no `List<List<U32>>`, so the
    # tuples are concatenated and the stride IS the tuple width -- which is
    # itself a fact from :558-560 and a def, so a wrong width moves every row.
    a(f'    srow("di_{tag}_mul_set", set_text(di_{tag}_flat(), 3))')
    a(f'    srow("di_{tag}_special_set", set_text(di_{tag}_flat(), 4))')
    a(f'    srow("di_{tag}_lo_set", set_text(di_{tag}_flat(), 1))')
    a(f'    srow("di_{tag}_mask_set", set_text(di_{tag}_flat(), 2))')
'''

s = re.sub(r"  for tag in \[\"RDNA3\", \"RDNA4\", \"CDNA\"\]:\n    di = \{[^}]*\}\[tag\]\n(?:.*\n)*?    a\(f'    srow\(\"di_\{tag\}_special_set\", sp_text\(\"\{tag\}\"\)\)'\)",
           NEW, s, count=1)

FLAT = '''  a('\\n# --- THE PER-OPCODE SETS, DERIVED ' + "-" * 42)
  a('# `decode_info[opcode] = (cls, _size_nibbles, lo, mask, mul, special)` (:558-560)')
  a('# and `decode()` unpacks five of those six at :611. The PORT keeps the five')
  a('# and CONCATENATES them, because Bend has no `List<List<U32>>`; `set_text`')
  a('# then walks with a STRIDE of five. The stride is a def, not a literal.')
  for _tag in ["RDNA3", "RDNA4", "CDNA"]:
    _di = {"RDNA3": sqtt._DECODE_INFO_RDNA3, "RDNA4": sqtt._DECODE_INFO_RDNA4,
           "CDNA": sqtt._DECODE_INFO_CDNA}[_tag]
    _flat = []
    for _op in sorted(_di):
      _c, _nib, _lo, _mask, _mul, _sp = _di[_op]
      _flat += [_nib, _lo, _mask % (2 ** 32), _mul, _sp]
    a(f'def di_{_tag}_flat() -> List<&2, U32>: [{",".join(str(x) for x in _flat)}]')

'''
if "def di_RDNA3_flat()" not in s:
  s = s.replace("  a('\\n# --- P  THE DERIVED PROPERTIES '", FLAT + "  a('\\n# --- P  THE DERIVED PROPERTIES '")

P.write_text(s)
print("sqtt_gen.py rewritten" if "set_text(di_" in s else "NO CHANGE")