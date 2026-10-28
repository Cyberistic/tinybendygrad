#!/usr/bin/env python3
"""AUDIT every `symbol=` in MY 26 files against `gates/todo-cite-gate.py`'s OWN rule.

THE RULE, quoted from the gate: a `symbol=` names an upstream construct, so
  1. the cited file must DECLARE it, and
  2. the cited line must DECLARE it (`symbol-decl`), be inside its BODY
     (`symbol-body`), its RANGE must cover the declaration (`symbol-range`), or the
     cited line must NAME it (`symbol-named`).

This prints the rows that do NOT satisfy (1), and the rows that satisfy (1) only
through the WEAKEST of (2) -- because `symbol-named` is a mention, not a pointer.

Loaded BY PATH: the upstream corpus and the span index are the gate's own.
"""
import importlib.util, re, subprocess, sys
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
HERE = ROOT / "gates"

def load(name, path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod

todo = load("todo", HERE / "todo-cite-gate.py")
census = load("census", HERE / "header-census-gate.py")

MINE = """codegen/decomp/dtype.bend codegen/decomp/op.bend codegen/decomp/transcendental_f32.bend
codegen/opt/heuristic.bend codegen/rewriter.bend device.bend examples/test_pkl_imagenet.bend
extra/models/convnext.bend extra/models/resnet.bend extra/models/unet.bend helpers.bend
mixin/dtype.bend mixin/reduce.bend nn/optim.bend renderer/amd/generate.bend
renderer/isa/x86.bend runtime/ops_cpu.bend runtime/ops_npy.bend runtime/support/c.bend
runtime/support/compiler_amd.bend runtime/support/compiler_mesa.bend runtime/support/nv/ip.bend
runtime/support/system.bend schedule/memory.bend uop/ops.bend uop/render.bend""".split()

pin = subprocess.run(["git", "--no-optional-locks", "rev-parse", "refs/remotes/upstream/master"],
                    cwd=ROOT, capture_output=True, text=True).stdout.strip()
corpus = todo.Corpus(pin)

weak = 0
bad = 0
for rel in MINE:
  p = ROOT / "tinybendygrad" / rel
  lines = p.read_text(errors="replace").splitlines()
  _f, _l, blk = census.header_block(lines)
  tgt = census.declared_target(blk)
  prefer = tgt[len("tinygrad/"):].rsplit("/", 1)[0] if tgt.startswith("tinygrad/") else ""
  for rec in todo.symbol_field_records(p, rel, census):
    for c in rec["cites"]:
      if c["where"] != "own" or not c["symbol"]:
        continue
      subj, lo, hi, sym = c["subject"], c["lo"], c["hi"], c["symbol"]
      path, how = corpus.resolve(subj, prefer)
      if not path:
        print(f"NOFILE    {rel}:{rec['at']}  {subj}:{lo} symbol={sym}  ({how})")
        bad += 1
        continue
      ulines = corpus.text(path).splitlines()
      spans = todo.body_spans(ulines)
      last = sym.split(".")[-1]
      decls = [d for (d, first, last_, kind) in spans.get(last, [])] if spans else []
      if not decls:
        print(f"NOT-DECLARED {rel}:{rec['at']}  {path}:{lo} symbol={sym}  "
              f"({path} declares no `{last}`)")
        bad += 1
        continue
      if lo in decls:
        how_hold = "symbol-decl"
      elif any(d <= lo for d in decls):
        how_hold = "symbol-body"
      elif any(lo <= d <= hi for d in decls):
        how_hold = "symbol-range"
      elif re.search(rf"\b{re.escape(last)}\b", "\n".join(ulines[lo - 1:hi])):
        how_hold = "symbol-named"
      else:
        print(f"WRONG-LINE {rel}:{rec['at']}  {path}:{lo} symbol={sym}  "
              f"declared at {decls}")
        bad += 1
        continue
      if how_hold == "symbol-named":
        print(f"WEAK(named) {rel}:{rec['at']}  {path}:{lo} symbol={sym}  "
              f"declared at {decls} -- the line MENTIONS it, it does not point at it")
        weak += 1
print(f"\n{bad} FALSE row(s) and {weak} weak-mention row(s).")
