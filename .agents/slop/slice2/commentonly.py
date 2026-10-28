#!/usr/bin/env python3
"""THE COMMENT-ONLY PROOF, for MY 26 files.

Every file I touched must strip to the SAME CODE HASH as `HEAD` after
`checks/port-compile-gate.py`'s `strip_comments()`, blank lines dropped.

`strip_comments()` is LOADED BY PATH: the rule is the instrument's, and a second
copy of it is a contract with no generator.
"""
import hashlib, importlib.util, subprocess, sys
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
spec = importlib.util.spec_from_file_location("pcg", ROOT / "checks/port-compile-gate.py")
pcg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pcg)

MINE = """codegen/decomp/dtype.bend codegen/decomp/op.bend codegen/decomp/transcendental_f32.bend
codegen/opt/heuristic.bend codegen/rewriter.bend device.bend examples/test_pkl_imagenet.bend
extra/models/convnext.bend extra/models/resnet.bend extra/models/unet.bend helpers.bend
mixin/dtype.bend mixin/reduce.bend nn/optim.bend renderer/amd/generate.bend
renderer/isa/x86.bend runtime/ops_cpu.bend runtime/ops_npy.bend runtime/support/c.bend
runtime/support/compiler_amd.bend runtime/support/compiler_mesa.bend runtime/support/nv/ip.bend
runtime/support/system.bend schedule/memory.bend uop/ops.bend uop/render.bend""".split()

def code_hash(text: str) -> str:
  stripped = pcg.strip_comments(text)
  kept = [ln for ln in stripped.split("\n") if ln.strip()]
  return hashlib.sha256("\n".join(kept).encode()).hexdigest()

bad = 0
for rel in MINE:
  path = "tinybendygrad/" + rel
  live = (ROOT / path).read_text(errors="replace")
  head = subprocess.run(["git", "--no-optional-locks", "show", f"HEAD:{path}"],
                        cwd=ROOT, capture_output=True, text=True).stdout
  a, b = code_hash(live), code_hash(head)
  same = a == b
  if not same:
    bad += 1
  print("%-6s %-50s live=%s head=%s" % ("SAME" if same else "DIFFER", path, a[:16], b[:16]))
print(f"\n{bad} of {len(MINE)} file(s) DIFFER in code.")
raise SystemExit(1 if bad else 0)
