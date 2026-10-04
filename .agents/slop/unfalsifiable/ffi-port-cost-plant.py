#!/usr/bin/env python3
"""ffi-port-cost-plant.py -- can the libclang numbers go RED, and are they X/X?

THE HEADLINE, pre-fix, from the committed tool:
    denominator   : 324 symbols exported by the binary
    coverage      : 324/324 = 100.0%
    mechanically derivable : 307/324 (95%) have no absent-type blocker
    need a layout decision : 203 by-value struct or unresolvable type
    BLOCKED                : 17

TWO DEFECTS, both CANNOT-FAIL:
  A. `denom` was `len({f.name for f in fns})` -- the SAME set as the numerator -- so
     coverage was `N/N` and no binary was read. The label "symbols exported by the
     binary" was false, and the `len(uniq) > denom` guard was unreachable because
     the two sides were the same set.
  B. "mechanically derivable" was `len(uniq) - len(blocked)`, a not-count of
     blockers. 203 of those 307 are the CBYVAL/OPAQUE set the same run labels "needs
     one layout convention" and "per-struct decision, not mechanical".

THIS FILE, for each of them, runs a PLANT (a change that MUST move a number) and a
DISARM (a change that must NOT), in $TMPDIR copies. The live binding file and the
live tool are never written.

  0  BASELINE, twice, from the live tree.
  1  PLANT A -- delete one declaration from a COPY of the binding file. Pre-fix this
     gave `323/323 = 100.0%`: coverage that survives losing the thing it covers.
  2  DISARM A -- append a comment to a COPY. Nothing may move.
  3  PLANT B -- the audit's LANDING plant, which I did not re-derive: put one
     `c_int64` in the decorator of a declaration the tool's own BLOCKED list
     excludes. 307 -> 306 and BLOCKED 17 -> 18.
  4  DISARM B -- put the same `c_int64` in a declaration that is ALREADY blocked
     (`clang_Type_getSizeOf`). Nothing may move, because the blocker set is a set.
     This is the audit's failed plant #1, kept as a control so it is not re-attempted.
  5  FAIL-SAFE -- point --dylib at a path that does not exist. Coverage must be
     reported NOT MEASURABLE, with no percentage anywhere in the output.

RUN:
  env -u PYTHONPATH LC_ALL=C .venv/bin/python \\
    .agents/slop/unfalsifiable/ffi-port-cost-plant.py
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SLOP = os.path.join(REPO, ".agents/slop")
BIND = os.path.join(REPO, "tinygrad/runtime/autogen/libclang.py")
PY = os.path.join(REPO, ".venv/bin/python")
TMP = os.path.join(tempfile.gettempdir(), "unfals")

PRE_FIX = os.path.join(SLOP, "unfalsifiable/pre-fix-ffi-port-cost.py")

# The lines the two numbers live on, so a plant can be shown as a NUMBER and not as a
# diff. Whole-line match, never a row name -- the agent-core rule.
KEYS = (re.compile(r"^(entry points|denominator|coverage|resolve rate)\b"),
        re.compile(r"^(mechanical outright|need a layout decision|blocked|total|"
                   r"no absent-type blocker|mechanically derivable|BLOCKED)\b"),
        re.compile(r"^\s*(declared but NOT exported|exported but NOT declared)"))


def run(tool, bind, *extra):
  e = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
  e["LC_ALL"] = "C"
  r = subprocess.run([PY, tool, "--pybind", bind, *extra], capture_output=True,
                     text=True, env=e, cwd=REPO, timeout=1800)
  return r.stdout, r.returncode


def numbers(text):
  out = []
  for ln in text.splitlines():
    if any(p.match(ln) for p in KEYS):
      out.append(re.sub(r"\s+", " ", ln).strip())
  return out


def show(label, text, rc):
  print(f"  rc={rc}")
  for ln in numbers(text):
    print("   ", ln)


def copy_bind(tag):
  d = os.path.join(TMP, tag)
  shutil.rmtree(d, ignore_errors=True)
  os.makedirs(d)
  dst = os.path.join(d, "libclang.py")
  shutil.copy(BIND, dst)
  return dst


def mutate(path, old, new):
  src = open(path).read()
  mut = src.replace(old, new)
  assert mut != src, f"plant text not found verbatim: {old!r}"
  open(path, "w").write(mut)


def delete_one_declaration(path):
  """Remove ONE `@dll.bind`-decorated declaration. The shape, read from the file:
  `@dll.bind(<ctypes>)\\ndef clang_x(...) -> T: ...` on two consecutive lines.
  The count moving is asserted by the caller, so this cannot silently degrade into a
  no-op -- which is how four of the audit's five plants failed."""
  src = open(path).read()
  m = re.search(r"@dll\.bind\([^\n]*\)\ndef clang_[A-Za-z0-9_]+\([^\n]*\)\s*->[^:]*:\s*\.\.\.\n",
                src)
  assert m, "no @dll.bind declaration block matched"
  drop = m.group(0)
  name = re.search(r"def (clang_[A-Za-z0-9_]+)", drop).group(1)
  open(path, "w").write(src.replace(drop, "", 1))
  return name


def main():
  os.makedirs(TMP, exist_ok=True)
  tool = os.path.join(SLOP, "ffi-port-cost.py")

  print("=" * 78)
  print("0  BASELINE from the live tree, TWICE (a memoized answer is measured twice)")
  t1, rc1 = run(tool, BIND)
  t2, rc2 = run(tool, BIND)
  show("POST-FIX live", t1, rc1)
  print(f"    second run identical: {t1 == t2}   rc={rc2}")
  pre_text, pre_rc = run(PRE_FIX, BIND)
  show("PRE-FIX (as committed)", pre_text, pre_rc)

  print("=" * 78)
  print("1  PLANT A -- delete one declaration. PRE-FIX: coverage stays 100.0%.")
  p = copy_bind("ffi-plantA")
  name = delete_one_declaration(p)
  print(f"    deleted declaration: {name}")
  pa, prc = run(PRE_FIX, p)
  show("PRE-FIX", pa, prc)
  pt, prc2 = run(tool, p)
  show("POST-FIX", pt, prc2)

  print("=" * 78)
  print("2  DISARM A -- append a comment. Nothing may move.")
  d = copy_bind("ffi-disarmA")
  with open(d, "a") as f:
    f.write("\n# an appended comment: no declaration, no ctype, nothing\n")
  da, drc = run(tool, d)
  show("POST-FIX", da, drc)
  print(f"    identical to the live baseline: {numbers(da) == numbers(t1)}")

  print("=" * 78)
  print("3  PLANT B -- one c_int64 in the decorator of a NOT-blocked declaration")
  p = copy_bind("ffi-plantB")
  old = "@dll.bind(CXIndex, ctypes.c_int32, ctypes.c_int32)"
  new = "@dll.bind(CXIndex, ctypes.c_int32, ctypes.c_int64)"
  mutate(p, old, new)
  pb, brc = run(tool, p)
  show("POST-FIX", pb, brc)
  print(f"    BLOCKED moved 17 -> 18: "
        f"{any(re.match(r'blocked : 18', n) for n in numbers(pb))}")

  print("=" * 78)
  print("4  DISARM B -- add an int64 ARGUMENT to an ALREADY-blocked declaration.")
  print("   The audit lists this as failed plant #1: the blocker set is a SET, and the")
  print("   declaration is already in it, so nothing may move.")
  d = copy_bind("ffi-disarmB")
  src = open(d).read()
  m = re.search(r"@dll\.bind\([^\n]*\)\ndef clang_Type_getSizeOf\(", src)
  assert m, "clang_Type_getSizeOf's @dll.bind not found"
  old = m.group(0)
  new = "@dll.bind(ctypes.c_int64, CXType, ctypes.c_int64)\ndef clang_Type_getSizeOf("
  print(f"    {old!r}\n -> {new!r}")
  mutate(d, old, new)
  db, drc = run(tool, d)
  show("POST-FIX", db, drc)
  print(f"    identical to the live baseline: {numbers(db) == numbers(t1)}")

  print("=" * 78)
  print("5  FAIL-SAFE -- --dylib at a path that does not exist")
  ft, frc = run(tool, BIND, "--dylib", "/nonexistent/libclang.dylib")
  show("POST-FIX", ft, frc)
  pct = [ln for ln in ft.splitlines() if "%" in ln and "coverage" in ln]
  print(f"    any coverage PERCENTAGE printed: {bool(pct)}  ({pct})")
  print(f"    'NOT MEASURABLE' printed: {'NOT MEASURABLE' in ft}")
  return 0


if __name__ == "__main__":
  sys.exit(main())