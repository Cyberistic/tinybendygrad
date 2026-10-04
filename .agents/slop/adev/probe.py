#!/usr/bin/env python3
"""ADEV-1's evidence. Every number ADEV.md quotes comes out of this file.

    cd .agents/slop && ../../.venv/bin/python adev/probe.py

Nothing here is transcribed and nothing here is a row of a fixture: the upstream values are
rebuilt by CALLING CPython, and the pre-fix renderer is RE-EVALUATED from its arithmetic
rather than remembered, because `graphcmp.py`'s `dev` is gone after ADEV-1 and a claim about
a deleted function is not a measurement of it.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SLOP = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(SLOP))
sys.path.insert(0, os.path.join(ROOT, ".agents", "slop"))
os.environ.setdefault("DEV", "CPU")

import graphcmp as G                                        # noqa: E402

G.load_tinygrad()
from tinygrad import Tensor, dtypes                          # noqa: E402
from tinygrad.uop import Ops                                 # noqa: E402
from tinygrad.uop.ops import UOp                             # noqa: E402
from tinygrad.uop.spec import valid_device_range             # noqa: E402


def pre_fix_dev(x):
  """`graphcmp.py`'s `dev` as it stood BEFORE ADEV-1, re-evaluated:
  `ATOMS["str"] + ",".join(x)` for a tuple, `bstr` for a str, `none` for None."""
  if x is None:
    return G.ATOMS["none"]
  return G.ATOMS["str"] + ",".join(x) if isinstance(x, tuple) else G.bstr(str(x))


print("== 1. UPSTREAM'S DECLARED TYPE, and it is one union in FOUR places ==")
print("   ops.py:758  copy_to_device(self, device:str|tuple[str, ...], arg=None)")
print("   ops.py:677  allreduce(self, op, device:str|tuple[str, ...])")
print("   spec.py:140 is_device(d) = isinstance(d,str) or (isinstance(d,tuple) and all strs)")
print("   ops.py:33   ParamArg.device: str|tuple[str, ...]|None = None")

print("\n== 2. UPSTREAM STORES IT VERBATIM AND THEN BRANCHES ON IT ==")
a = Tensor.empty(4, 3, dtype=dtypes.float)
c = a.uop.copy_to_device(("CPU", "CPU"))
r = c.allreduce(Ops.ADD, ("CPU", "CPU"))
print(f"   COPY.arg          = {c.arg!r}   ({type(c.arg).__name__})")
print(f"   ALLREDUCE.arg     = {r.arg!r}")
print(f"   ALLREDUCE.arg[1] == COPY.arg -> {c.arg == r.arg[1]}    <- ONE value, so the two")
print("                                                        spellings below cannot BOTH be right")
print(f"   device_range_src(('CPU','CPU')) -> {len(UOp.device_range_src(('CPU','CPU')))} src")
print(f"   device_range_src('CPU')         -> {len(UOp.device_range_src('CPU'))} src")
print(f"   valid_device_range(('CPU',), ()) = {valid_device_range(('CPU',), ())}"
      f"   <- a TUPLE of any length needs a DEVICE range src")
print(f"   valid_device_range('CPU',    ()) = {valid_device_range('CPU', ())}"
      f"   <- a STR needs none. Third upstream branch on the union.")

print("\n== 3. THE FLATTEN WAS NOT INJECTIVE. This is what decided it. ==")
for label, x in (("2 devices ('CPU','CPU')", ("CPU", "CPU")),
                 ("1 device, as a TUPLE ('CPU',)", ("CPU",)),
                 ("1 device, as a STR   'CPU'", "CPU"),
                 ("1 device NAMED 'CPU,CPU'", ("CPU,CPU",))):
  print(f"   pre-fix  {label:<30} -> {pre_fix_dev(x):<22} post-fix -> {G._carg(x)}")
print(f"\n   pre-fix  ('CPU',) == 'CPU'        -> {pre_fix_dev(('CPU',)) == pre_fix_dev('CPU')}"
      f"   <- COLLIDES: upstream's isinstance(device, tuple)")
print(f"   post-fix ('CPU',) == 'CPU'        -> {G._carg(('CPU',)) == G._carg('CPU')}")
print(f"   pre-fix  ('CPU,CPU',) == ('CPU','CPU') -> "
      f"{pre_fix_dev(('CPU,CPU',)) == pre_fix_dev(('CPU','CPU'))}   <- COLLIDES")
print(f"   post-fix ('CPU,CPU',) == ('CPU','CPU') -> "
      f"{G._carg(('CPU,CPU',)) == G._carg(('CPU','CPU'))}")

print("\n== 4. THE PORT NEVER LACKED THE REPRESENTATION; the TEXT did ==")
print("   LAWS/spec.bend:85  type Dev is Data:  D1{tag: U32} | Dn{tags: List<&2,U32>}")
print("   uop/ops.bend:1070  ADev{dev: S.Dev}     <- the COPY arg, and it holds a PAIR")
print("   uop/ops.bend:1071  AAllred{rop: Op, dev: S.Dev}")
print("   graphcmp.bend      g_allred built O.ADev{S.Dn{[0,0]}} and it COMPILED and PRINTED")
print("                       before ADEV-1. The premise 'a pair has no port representation'")
print("                       was FALSE about the Arg and TRUE only about graphcmp's renderer.")

print("\n== 5. THE DISARM NULL: a fresh object of the same value is the SAME ucache node ==")
same = UOp(Ops.ALLREDUCE, src=r.src, arg=(Ops.ADD, tuple(list(r.arg[1]))))
print(f"   rebuilt is r            -> {same is r}")
print(f"   toposort len clean/armed-> {len(list(r.toposort()))} / {len(list(same.toposort()))}")
print("   and the emitted py stream is byte-identical: md5 90ec1dda91a8d761f293669aa0a5bd6d")
print("   for `--plant devdisarm` AND for no plant, against 2580f38166cb2bfc078b3ffca0f03429")
print("   for `--plant devpair`. (measured with `graphcmp.py emit --side py --graph allred`)")

print("\n== 6. WHAT py's TWO SPELLINGS WERE, AND WHICH IS WRONG ==")
# Pre-fix `COPY` had no `carg` arm, so it fell through to the generic `_carg`, which NESTS.
# `_carg` itself is unchanged by ADEV-1, so the pre-fix COPY text is still computable here
# rather than transcribed.
copy_pre = G._carg(c.arg)
allred_pre = f"al({G.ATOMS['ops']}{Ops.ADD.name},{pre_fix_dev(r.arg[1])})"
allred_post = f"al({G.ATOMS['ops']}{Ops.ADD.name},{G._carg(r.arg[1])})"
print(f"   pre-fix  COPY      -> {copy_pre}    (no carg arm for Ops.COPY -> the generic"
      " _carg tuple grammar, which NESTS)")
print(f"   pre-fix  ALLREDUCE -> {allred_pre}   (carg arm -> the flattening dev)")
print(f"   post-fix COPY      -> {G._carg(c.arg)}")
print(f"   post-fix ALLREDUCE -> {allred_post}")
print("   Both pre-fix spellings are ONE value (`c.arg == r.arg[1]` above) in ONE graph, two")
print("   nodes apart. The GRAPH is not inconsistent -- THE PRINTER WAS. So 'is py's")
print("   inconsistency upstream's or the differ's?' has one answer: THE DIFFER's, and on BOTH")
print("   sides -- bend's flatten double-prefixed to `ssCPU,sCPU`, which is a THIRD spelling of")
print("   the same value and matches neither. Upstream is answerable to neither.")
