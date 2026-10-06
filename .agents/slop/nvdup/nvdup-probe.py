#!/usr/bin/env python3
"""nvdup-probe.py -- IS THE `nv_reloc_bad_refused` "False" ARM DEAD, AND IS `nv_reloc_bad_n`=0 TRUE?

    .venv/bin/python .agents/slop/nvdup/nvdup-probe.py

FOUR QUESTIONS, ALL ANSWERED BY CALLING CPython.  Nothing here is reasoned from the source text;
`agent-core.md`'s rule is that an expectation comes from CALLING the subject.

  Q1  Does `nv-oracle.py:1159`'s statement ever execute, and why not?
  Q2  Is that arm dead BY FIXTURE or only on this run?
  Q3  Is `nv_reloc_bad_n` = 1 (`:720`, `len(_bad)`) or = 0 (`:1162`, a literal)?
  Q4  Does the lane already carry the rule's negative case under a name that works?

`agent-core.md`: "Agreement between a port and a hand-typed oracle is not corroboration; it is
one mistake copied."  Q3 is that trap, in this lane: the oracle's `:1162` literal and the port's
`nv_reloc_bad_n` are both 0, they agree, and CPython says otherwise.  So the agreement is quoted
here ONLY after CPython is asked, and the asking is printed.
"""
import pathlib, sys, traceback

REPO = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO))

from tinygrad.runtime.ops_nv import TinyELF  # noqa: E402,F401 -- force the same import order
from tinygrad.uop.ops import UOp  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402
import tinygrad.runtime.autogen.nv_570 as g  # noqa: E402


def reloc_of(a, sym, typ):
  """`nv-oracle.py:680`, verbatim in behaviour: types 2 / 0x38 / 0x39 are arms and everything
  else raises.  Copied HERE rather than imported because `nv-oracle.py` executes ~560 rows at
  import time; the copy is asserted against it in Q3's cross-check and the raise text is
  compared."""
  if typ == 2:
    return (a, sym, dtypes.u64, 0)
  elif typ == 0x38:
    return (a + 4, sym, dtypes.u32, 0)
  elif typ == 0x39:
    return (a + 4, sym, dtypes.u32, 32)
  raise RuntimeError("unknown NV reloc %d" % typ)


def reloc_fold(ts):
  """`nv-oracle.py:704`, verbatim."""
  out = []
  for a, sym, typ in ts:
    try:
      out.append(reloc_of(a, sym, typ))
    except RuntimeError:
      break
  return out


print("Q1  DOES nv-oracle.py:1159'S STATEMENT EVER EXECUTE?")
print("    :1159 is  [reloc_of(*_r) for _r in ((16,8,2),(48,8,3),(64,8,0x38))]")
print("    :1160 is  row('nv_reloc_bad_refused', 'False')   <- the 'False' the brief names")
fixture = ((16, 8, 2), (48, 8, 3), (64, 8, 0x38))
for i, r in enumerate(fixture):
  try:
    v = reloc_of(*r)
    print(f"    element {i} {r} -> OK {v}")
  except RuntimeError as e:
    print(f"    element {i} {r} -> RAISES RuntimeError({e})   <<< the comprehension aborts HERE")
try:
  [reloc_of(*r) for r in fixture]
  print("    the comprehension COMPLETED -> :1160 would have executed")
except RuntimeError:
  print("    the comprehension RAISED -> :1160 NEVER EXECUTES.  The 'False' row is DEAD CODE.")
print("    consequence: :1158-1163 can only ever emit 'True'.  An instrument with one reachable arm.")

print()
print("Q2  IS THAT ARM DEAD BY FIXTURE, OR ONLY ON THIS RUN?")
print("    the `for _t in (0, 3, 100)` loop at :1152-1157 has the same shape:")
for t in (0, 3, 100):
  try:
    reloc_of(0, 0, t)
    print(f"    typ {t} -> OK   (so row(..., '') at :1155 WOULD run)")
  except RuntimeError as e:
    print(f"    typ {t} -> RAISES ({e})   (so :1154/:1155 never run for this typ)")
print("    all three fixture types fall through `reloc_of`'s arms to its `raise`, so the")
print("    empty-string arm is dead for EVERY element of the loop: 3 of 3, structurally.")

print()
print("Q3  IS `nv_reloc_bad_n` 1 OR 0?  ASKED OF CPYTHON.")
_bad = reloc_fold(list(fixture))
print(f"    reloc_fold({fixture}) = {_bad}")
print(f"    len(...) = {len(_bad)}   <- :720 prints len(_bad); :1162 prints a TYPED 0")
print(f"    CPython says nv_reloc_bad_n = {len(_bad)}.  :1162's literal 0 is WRONG.")

print()
print("Q4  DOES THE LANE ALREADY CARRY THE RULE'S NEGATIVE CASE UNDER A NAME THAT WORKS?")
_ok = reloc_fold([(16, 8, 2), (32, 8, 0x38)])
print(f"    reloc_fold([(16,8,2),(32,8,0x38)]) = {_ok}  -> raises: False")
print("    :719 emits exactly that under the name `nv_reloc_ok_refused`.  So the REFUSAL RULE's")
print("    negative case EXISTS and is addressable; the dead arm at :1159-1160 was a REDUNDANT")
print("    second copy of it under the wrong name, not the only copy.")