#!/usr/bin/env python3
"""SURFACE2 stage 1 -- RE-MEASURE the Tensor surface from the tree.

Denominator comes from ast.parse on the REAL tinygrad/tensor.py, not from a note.
Run: .venv/bin/python .agents/slop/surface2/stage1-recensus.py
"""
import ast, os, sys, collections

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
PY = os.path.join(ROOT, "tinygrad", "tensor.py")
BD = os.path.join(ROOT, "tinybendygrad", "tensor.bend")


def upstream_defs():
  """57 defs in class Tensor, per AST."""
  src = open(PY).read()
  tree = ast.parse(src)
  cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "Tensor")
  out = []
  for n in cls.body:
    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
      out.append((n.name, n.lineno))
  return out


def bend_defs():
  """(name, lineno) for every def in the port file."""
  out = []
  for i, line in enumerate(open(BD).read().splitlines(), 1):
    s = line.lstrip()
    if s.startswith("def ") or s.startswith("Type ") and "def " in s:
      rest = s.split("def ", 1)[1]
      name = rest.split("(", 1)[0].strip().split(".", 1)[-1]
      if name:
        out.append((name, i))
  return out


def main():
  up = upstream_defs()
  bd = bend_defs()
  names = [n for n, _ in up]
  print("DENOMINATOR (AST, class Tensor):", len(up))
  buckets = collections.Counter()
  for n, ln in up:
    if n.startswith("__"):
      buckets["dunder"] += 1
    elif n.startswith("_"):
      buckets["private"] += 1
    else:
      buckets["public"] += 1
  print("  by kind:", dict(buckets))
  print("PORT defs in tensor.bend:", len(bd))
  print("TOTAL tensor.bend lines:", sum(1 for _ in open(BD)))
  for n, ln in up:
    print("UPSTREAM %-24s %d" % (n, ln))


if __name__ == "__main__":
  main()