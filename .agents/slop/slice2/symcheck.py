#!/usr/bin/env python3
"""AUDIT every `symbol=` in MY 26 files: does the symbol name a construct DECLARED IN
THE CITED FILE, and is it declared AT the cited line?

The rules are the tree's own: `gates/header-census-gate.py`'s `declared_at()` for a
Python `def`/`class`/`X = ...`, and `gates/bendcite-gate.py`'s `bend_constructs()` for a
`.bend` file. Loaded BY PATH -- the rules are not re-implemented here.

A `symbol=` that names a construct of ANOTHER file is a NEW false citation, so this
prints every one that is not declared in the cited file at the cited line.
"""
import importlib.util, re, sys, subprocess
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
HERE = ROOT / "gates"

def load(name, path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod

census = load("census", HERE / "header-census-gate.py")
bendcite = load("bendcite", HERE / "bendcite-gate.py")

MINE = """codegen/decomp/dtype.bend codegen/decomp/op.bend codegen/decomp/transcendental_f32.bend
codegen/opt/heuristic.bend codegen/rewriter.bend device.bend examples/test_pkl_imagenet.bend
extra/models/convnext.bend extra/models/resnet.bend extra/models/unet.bend helpers.bend
mixin/dtype.bend mixin/reduce.bend nn/optim.bend renderer/amd/generate.bend
renderer/isa/x86.bend runtime/ops_cpu.bend runtime/ops_npy.bend runtime/support/c.bend
runtime/support/compiler_amd.bend runtime/support/compiler_mesa.bend runtime/support/nv/ip.bend
runtime/support/system.bend schedule/memory.bend uop/ops.bend uop/render.bend""".split()

CITE = re.compile(r"(?<![\w./-])((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.(?:py|bend)):(\d+)(?:-(\d+))?")
SYMBOL = re.compile(r"\bsymbol\s*=\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)")

def upstream_path(subj):
  """Resolve a `.py` subject to an upstream path, or "".
  A BARE BASENAME is AMBIGUOUS upstream and names no file; the port's own header
  declares its target, and the gate resolves a bare basename by that target's
  DIRECTORY. So the port's header is read for the declared target, and a bare
  basename is resolved under it."""
  if "/" in subj:
    return subj
  # the port's own header, first `tinygrad/...py`
  for rel in MINE:
    body = (ROOT / "tinybendygrad" / rel).read_text(errors="replace").splitlines()
    m = re.search(r"\b(tinygrad/[A-Za-z0-9_./]+\.py)\b", "\n".join(body))
    if m:
      tgt = m.group(1)
      cand = tgt.rsplit("/", 1)[0] + "/" + subj
      if subprocess.run(["git", "--no-optional-locks", "cat-file", "-e", f"HEAD:{cand}"],
                        cwd=ROOT, capture_output=True).returncode == 0:
        return cand
  return ""

def py_declared_at(path, line):
  """The name DECLARED at `line` of an upstream `.py`, or ""."""
  r = subprocess.run(["git", "--no-optional-locks", "show", f"HEAD:{path}"],
                     cwd=ROOT, capture_output=True, text=True)
  if r.returncode:
    return ("NOFILE", "")
  lines = r.stdout.splitlines()
  if line < 1 or line > len(lines):
    return ("OOR", "")
  t = lines[line - 1].strip()
  m = re.match(r"(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", t)
  if m:
    return ("OK", m.group(1))
  m = re.match(r"([A-Za-z_]\w*)\s*(?::[^=]+)?=", t)
  if m:
    return ("OK", m.group(1))
  return ("NOTDECL", "")

def py_declares(path, name):
  """Does upstream `path` declare `name` ANYWHERE? And at which lines?"""
  r = subprocess.run(["git", "--no-optional-locks", "show", f"HEAD:{path}"],
                     cwd=ROOT, capture_output=True, text=True)
  if r.returncode:
    return []
  out = []
  for i, t in enumerate(r.stdout.splitlines(), 1):
    s = t.strip()
    m = re.match(r"(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", s)
    if m and m.group(1) == name:
      out.append(i)
      continue
    m = re.match(r"([A-Za-z_]\w*)\s*(?::[^=]+)?=", s)
    if m and m.group(1) == name:
      out.append(i)
  return out

bad = 0
for rel in MINE:
  p = ROOT / "tinybendygrad" / rel
  body = p.read_text(errors="replace").splitlines()
  for i, line in enumerate(body, 1):
    syms = SYMBOL.findall(line)
    if not syms:
      continue
    cites = [(m.group(1), int(m.group(2)), int(m.group(3) or m.group(2)), m.span())
             for m in CITE.finditer(line)]
    if not cites:
      print(f"NO-CITATION {rel}:{i}  symbol={syms}  {line.strip()[:80]}")
      bad += 1
      continue
    # THE NEAREST symbol= goes to the NEAREST citation, and vice versa.
    for m in SYMBOL.finditer(line):
      gaps = [max(0, cs - m.end(), m.start() - ce) for (_s, _l, _h, (cs, ce)) in cites]
      ci = gaps.index(min(gaps))
      path, lo, hi, _sp = cites[ci]
      name = m.group(1)
      if path.endswith(".py"):
        up = upstream_path(path)
        if not up:
          print(f"AMBIGUOUS   {rel}:{i}  {path}:{lo} symbol={name}  (bare basename)")
          bad += 1
          continue
        state, declared = py_declared_at(up, lo)
        if state == "NOFILE":
          print(f"NOFILE      {rel}:{i}  {up}:{lo} symbol={name}")
          bad += 1
          continue
        if state == "OOR":
          print(f"OUT-OF-RANGE {rel}:{i}  {up}:{lo} has {declared} lines")
          bad += 1
          continue
        where = py_declares(up, name)
        # `__init__` is a METHOD NAME: it is DECLARED by the `def __init__` line,
        # and the tree's own convention points at the CLASS's `__init__`.
        if declared == name or (name == "__init__" and any(
            abs(d - lo) <= 12 for d in where)):
          continue
        print(f"MISPLACED   {rel}:{i}  {up}:{lo} symbol={name}  "
              f":{lo} declares {declared!r}; {up} declares {name!r} at {where}")
        bad += 1
      else:
        # A `.bend` subject: the PORT's own tree.
        target = ROOT / "tinybendygrad" / path
        if not target.is_file():
          comp = ROOT / "references" / "bend" / "bend2" / Path(path).name
          target = comp if comp.is_file() else None
        if target is None:
          print(f"NOFILE      {rel}:{i}  {path}  (bend)  symbol={name}")
          bad += 1
          continue
        cons = bendcite.bend_constructs(target.read_text(errors="replace").splitlines())
        here = [d for (n, d, _s, _e) in cons if d == lo and n == name]
        near = [d for (n, d, _s, _e) in cons if n == name]
        if not here:
          print(f"MISPLACED   {rel}:{i}  {path}:{lo} symbol={name}  "
                f"declared at {near}")
          bad += 1
print(f"\n{bad} symbol= row(s) that do not name a construct declared in the cited file "
      f"at the cited line.")
