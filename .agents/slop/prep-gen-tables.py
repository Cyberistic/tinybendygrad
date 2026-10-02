#!/usr/bin/env python3
"""prep-gen-tables.py -- EMIT the six `PMEntry` tables for prepare.bend from
tinygrad's OWN PatternMatchers.  Nothing here is transcribed by hand: `pat.op`
is `pdict`'s key and `pat.early_reject` is ops.py:1477, both read off the live
objects."""
import os, sys
os.environ["DEBUG"] = "0"; os.environ["UPAT_COMPILE"] = "0"; os.environ["JIT"] = "0"
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from tinygrad.uop.ops import UOp, Ops, PatternMatcher
import tinygrad.schedule.prepare as P
from tinygrad.uop.movement import mop_cleanup

def bename(o): return "O.Ops" + o.name + "{}"
def benames(os_, sort=False):
  """`pat.op` is a TUPLE in the UPat's DECLARED order (ops.py:1454) and
  `early_reject` is a SET (ops.py:1477), so only the reject set is sorted."""
  if not os_: return "Nil{}"
  xs = sorted(os_, key=lambda x: x.name) if sort else list(os_)
  return "[" + ", ".join(bename(o) for o in xs) + "]"

def emit(nm, pm):
  print(f"def {nm}() -> O.PMEntrys:")
  print(f"  O.PMEntrys{{[")
  for i, (pat, f) in enumerate(pm.patterns):
    print(f"    O.PMEntry{{{i}, {benames(pat.op)}, {benames(pat.early_reject, True)}}},"
          f"  # {i} {' '.join(sorted(x.name for x in pat.op))} rej={' '.join(sorted(x.name for x in pat.early_reject)) or '-'} "
          f"slen={int(bool(pat.strict_length))} rlen={pat.required_len} any={int(bool(pat.is_any))} nalts={0 if pat.src is None else len(pat.src)} "
          f"name={pat.name or '-'}")
  print("  ]}")
  print()

print("# --- emitted by .agents/slop/prep-gen-tables.py ---")
emit("pr_fma_table", P.pm_fold_moved_after)
emit("pr_mop_table", P.pm_mops)
emit("pr_inl_table", P.pm_inline_calls)
emit("pr_dsk_table", P.pm_disk_copy)
emit("pr_ear_table", P.earliest_rewrites)
emit("pr_mcl_table", mop_cleanup)

# the per-rule DATA the gate prints: slen/rlen/isany/nalts/name
print("def pr_fma_data() -> List<&2, String>:")
print('  ["' + '", "'.join(f"{int(bool(p.strict_length))},{p.required_len},{int(bool(p.is_any))},{0 if p.src is None else len(p.src)},{p.name or '-'}" for p, _ in P.pm_fold_moved_after.patterns) + '"]')
print()
for nm, pm in (("mop", P.pm_mops), ("inl", P.pm_inline_calls), ("dsk", P.pm_disk_copy),
               ("ear", P.earliest_rewrites), ("mcl", mop_cleanup)):
  print(f"def pr_{nm}_data() -> List<&2, String>:")
  print('  ["' + '", "'.join(f"{int(bool(p.strict_length))},{p.required_len},{int(bool(p.is_any))},{0 if p.src is None else len(p.src)},{p.name or '-'}" for p, _ in pm.patterns) + '"]')
  print()

# pdict: op -> ordered rule indices, per table
for nm, pm in (("fma", P.pm_fold_moved_after), ("mop", P.pm_mops), ("inl", P.pm_inline_calls),
               ("dsk", P.pm_disk_copy), ("ear", P.earliest_rewrites), ("mcl", mop_cleanup)):
  keys = sorted(pm.pdict.keys(), key=lambda o: o.name)
  print(f"def pr_{nm}_pdict() -> List<&2, O.PMEntry>:")
  print(f"  [{', '.join(f'O.PMEntry{{{benames([o])}, ' + str(len(pm.pdict[o])) + '}' for o in keys)}]")
  print(f"# pr_{nm}_keys = {len(keys)}")
  for o in keys:
    print(f"# pr_{nm}_pd_{o.name} = {','.join(str(pm.pdict[o].index(e)) for e in pm.pdict[o])}")
  print()
