#!/usr/bin/env python3
"""presence.py -- the witness set: for each FAIL needle, is it in the file the CENSUS read,
and where else in the tracked tree does it live?

The census resolves `subject` by ROOT-exact then a unique suffix.  This reproduces the
resolution, then asks git grep where the needle is elsewhere.

usage: .venv/bin/python .agents/slop/residual/presence.py
"""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PAIRS = [
  ("BASE_ORACLES", "codegen/decomp/dtype.bend"),
  ("cfunc_buf", "uop/ops.bend"),
  ("pad_name", "viz/serve.bend"),
  ("main", "renderer/cstyle.bend"),
  ("randn_like23_g", "mixin/rand.bend"),
  ("nv_errstr_N", "runtime/ops_nv.bend"),
  ("WHAT IS PORTED, DEF BY DEF", "runtime/ops_nv.bend"),
  ("md5 -q", "codegen/decomp/dtype.bend"),
  ("file:line", "runtime/dtype.c"),
  ("DLL._loaded_", "runtime/support/c.py"),
  ("Scheduler.reduce_axes", "codegen/opt/postrange.py"),
  ("encode_submit", "runtime/support/hcq2.py"),
  ("pm_dispatch_m case 0", "uop/ops.bend"),
  ("WITHIN-LIMITS", "uop/render.bend"),
  ("WITHIN-LIMITS", "uop/upat.bend"),
  ("parse, don't validate", "spec/ops.md"),
  ("a basename match is not a reference", "capstream/refsplit.py"),
  ("ABlob{n}", "uop/ops.bend"),
  ("#rebase_inner", "uop/spec.bend"),
  ("sha256", "renderer/cstyle.bend"),
  ("belts-disagree", "mixin/dtype.bend"),
  ("array", "engine/realize.bend"),
  ("ARTIFACTS-FRESH", "checks/runs-artifacts.py"),
  ("ABlob{bs}", "uop/ops.bend"),
  ("pad_name", "viz/cli.bend"),
  ("DLL._loaded_", "runtime/support/c.bend"),
  ("setup_ring", "runtime/support/am/amdev.bend"),
  ("encode_submit", "runtime/support/hcq2.bend"),
]
TRACKED = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout.splitlines()
IDX: dict[str, list[str]] = {}
for p in TRACKED:
  i = p.find("/")
  while i != -1:
    IDX.setdefault(p[i:], []).append(p)
    i = p.find("/", i + 1)


def resolve(subj: str) -> str | None:
  if (ROOT / subj).is_file():
    return subj
  hit = IDX.get("/" + subj)
  return hit[0] if hit and len(hit) == 1 else None


for needle, subj in PAIRS:
  real = resolve(subj)
  try:
    here = real is not None and needle in (ROOT / real).read_text(errors="replace")
  except OSError:
    here = False
  r = subprocess.run(["git", "grep", "-l", "-F", "--", needle], cwd=ROOT,
                     capture_output=True, text=True)
  others = [x for x in r.stdout.splitlines() if x and x != real][:3]
  tag = "PRESENT" if here else "ABSENT "
  print(f"{tag}  {needle!r:38s} in {real or subj}  |  elsewhere: "
        f"{', '.join(others) if others else '-'}")
