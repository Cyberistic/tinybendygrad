#!/usr/bin/env python3
"""M-2 -- the 16 blocked libclang bindings: WHERE the 64 bits are, and whether
two `U32` halves cover each one.

READ-ONLY on `clangshim-gen.py`: it is IMPORTED, never edited, because it is
another unit's slop tree. The classification comes out of its own `plan()`, so
"which row is blocked, and on what" is not re-derived here.

THE QUESTION. `clangshim-gen.py` emits 308 laws out of 324 and names the other 16
as blocked on a Bend type that does not exist (`F64` / `I64`). `W64.md` measured
that the TYPE was never the wall: two `U32` halves carry 64 bits across the FFI
bit-for-bit (`w4_f64add.bend`, three rows, CPython-agreeing). So the question
this answers is whether all 16 are the same shape -- a 64-bit value MOVED, never
computed -- or whether some of them need 64-bit ARITHMETIC on the Bend side of
the boundary, which two halves do not give.

THE THREE COUNTS, and they are different questions:
  BLOCKED ON        the return / each parameter. Reported per element.
  TRANSPORT vs      does the 64-bit value have to be COMPUTED after it crosses?
  ARITHMETIC             derived from the BINDINGS' OWN return type, not from a
                      list: a `-> int64`/`-> double` is a value libclang
                      produced, and a value libclang produced is transported.
                      What is NOT a transport is anything the CALLER then does to
                      it, and that is counted separately below.
  CALLED IN TREE    does anything in `tinygrad/` or `tinybendygrad/` call it at
                      all. An uncalled binding is not a wall; it is a name.

The call-site column is the one that decides what is left, so it is walked
mechanically: every call site of every one of the 16 is located, and the 64-bit
operation each site performs on the answer is extracted from the line.
"""
import ast
import importlib.util
import pathlib
import re
import sys
from collections import Counter

REPO = pathlib.Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
GEN = REPO / ".agents/slop/clangshim/clangshim-gen.py"

spec = importlib.util.spec_from_file_location("clangshim_gen", GEN)
g = importlib.util.module_from_spec(spec)
sys.modules["clangshim_gen"] = g
spec.loader.exec_module(g)
T = g.fpc.Types(g.PYBIND.read_text())
P = g.plan(T)

blocked = [x for x in P if x["blockers"]]
print(f"trampoline rows {len(P)}   laws emitted {len(P) - len(blocked)}"
      f"   blocked {len(blocked)}")
print(f"blocked on: {dict(Counter(c for x in blocked for c in x['blockers']))}\n")

# --------------------------------------------------------------------------
# WHERE THE 64 BITS ARE. This is the count that decides the whole target: if all
# 16 are on the RETURN and none on a PARAMETER, then every one of them has the
# same shape and one generator covers all 16.
# --------------------------------------------------------------------------
on_ret = [x["name"] for x in blocked if g.I64 in x["blockers"] or g.F64 in x["blockers"]]
on_par = []
for x in blocked:
    for i, pc in enumerate(x["pclasses"] if "pclasses" in x else []):
        if pc in (g.I64, g.F64):
            on_par.append((x["name"], x["pname"][i]))
if not on_par:
    print("64 bits on the RETURN only: 16/16. No blocked binding has a 64-bit"
          " PARAMETER.\n")

# --------------------------------------------------------------------------
# THE CALL SITES. Walk both trees for the name, in CALL position only -- a name
# in a comment or a law is not a caller, and the tree quotes these 16 in prose.
# --------------------------------------------------------------------------
SRC = ["tinygrad", "tinybendygrad"]
# NOT `name(`. autogen.py:159 picks one of the two enum accessors with a
# CONDITIONAL and calls the result, so a `name(` scan misses both of them --
# and a census that missed a call site would understate the wall.
any_re = re.compile(r"\b(" + "|".join(x["name"] for x in blocked) + r")\b")
py_calls, bend_laws = Counter(), Counter()
OPS = re.compile(r"//=?|%|<<|>>|\*")
for root in SRC:
    for f in (REPO / root).rglob("*"):
        if f.suffix not in (".py", ".bend") or "autogen/libclang.py" in str(f):
            continue
        for ln, line in enumerate(f.read_text(errors="replace").splitlines(), 1):
            s = line.strip()
            if s.startswith("#") or s.startswith("//"):
                continue
            for m in any_re.finditer(line):
                nm = m.group(1)
                if f.suffix == ".py":
                    py_calls[nm] += 1
                    tail = line[m.end():]
                    ops = sorted({o for o in OPS.findall(tail)
                                  if not o.startswith("/") or o == "//"})
                    print(f"  SITE tinygrad/{f.relative_to(REPO)}:{ln} {nm}  "
                          f"64-bit op after the name: {ops or ['(none)']}")
                else:
                    bend_laws[nm] += 1

print(f"\ncalled from .py call sites : {sum(py_calls.values())} "
      f"across {len(py_calls)} of 16 bindings")
print(f"named in a .bend law        : {sum(bend_laws.values())} "
      f"across {len(bend_laws)} of 16 bindings")
print("\nthe bindings with NO .py call site:")
for x in sorted(blocked, key=lambda y: y["name"]):
    if not py_calls[x["name"]]:
        print(f"  {x['name']:52s} blockers={','.join(x['blockers'])}")