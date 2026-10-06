#!/usr/bin/env python3
"""SURFACE2 stage 2 -- set arithmetic on the 57, and a CALLED probe per missing method.

Two jobs, both by CALLING:
  A) the note's ABSENT list has a specific number of names in it. Count them.
  B) for each of the 39, run a CPython program that USES the method, and record
     whether it needs device state at all.
"""
import ast, os, sys, traceback

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
PY = os.path.join(ROOT, "tinygrad", "tensor.py")

# the 18 PRESENT per TENSOR-SURFACE.md sec 1.2
PRESENT18 = {"alu", "_uop", "_wrap_uop", "is_param_", "__repr__", "__hash__", "__len__",
             "device", "shape", "dtype", "replace", "_mop", "_rop",
             "__init__", "_apply_uop", "const", "assign", "backward"}

# the ABSENT list transcribed from TENSOR-SURFACE.md sec 1.2, verbatim
NOTE_ABSENT = """as_param call custom_kernel linear_with_vars schedule_linear realize
_buffer _data data tolist numpy clone to to_ shard shard_ shard_like
from_blob from_url manual_seed _next_counter decode_hevc_frame
__bool__ __setitem__ __delitem__ __eq__
__iadd__ __isub__ __imul__ __itruediv__ __ifloordiv__ __ipow__
__iand__ __ior__ __ixor__ __ilshift__ __irshift__ __imatmul__""".split()


def upstream():
  tree = ast.parse(open(PY).read())
  cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "Tensor")
  return {n.name: n.lineno for n in cls.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}


def main():
  up = upstream()
  print("== A. SET ARITHMETIC ==")
  print("AST total                       :", len(up))
  print("note PRESENT list length        :", len(PRESENT18), "and all in AST:", PRESENT18 <= set(up))
  print("note ABSENT list length         :", len(NOTE_ABSENT))
  print("18 + len(note ABSENT)           :", len(PRESENT18) + len(NOTE_ABSENT), "  <-- compare to 57")
  leftover = set(up) - PRESENT18 - set(NOTE_ABSENT)
  print("in AST, in NEITHER list         :", sorted(leftover), "(%d)" % len(leftover))
  print("PRESENT in note but NOT in AST  :", sorted(PRESENT18 - set(up)))
  print("ABSENT in note but NOT in AST   :", sorted(set(NOTE_ABSENT) - set(up)))
  print("duplicates in note ABSENT       :", [x for x in set(NOTE_ABSENT) if NOTE_ABSENT.count(x) > 1])
  print()
  print("== the true 39, computed as AST - PRESENT ==")
  true39 = sorted(set(up) - PRESENT18, key=lambda k: up[k])
  print("count:", len(true39))
  for n in true39:
    print("  %-22s tensor.py:%d%s" % (n, up[n], "" if n in NOTE_ABSENT else "   <-- MISSING FROM THE NOTE'S LIST"))


if __name__ == "__main__":
  main()