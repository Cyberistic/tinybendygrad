#!/usr/bin/env python3
"""The pm_bufferize FORK, as a rule count. See the module docstring in the sibling file.

Upstream moved `pm_bufferize` off the Compiled INSTANCE and onto the CLASS:
  device.py@HEAD   `pm_bufferize: Any = None`                                  (declaration)
  hcq2.py@HEAD     `Compiled.pm_bufferize = PatternMatcher([...])`             (definition)
  ops_*.py@HEAD    `Compiled.pm_bufferize += PatternMatcher([...])`            (extensions)
Our device.py@07ff64a still builds `self.pm_bufferize` in __init__ and our
ops_cuda/nv/qcom still extend the INSTANCE table.

So a tree with hcq2@HEAD and device.py behind has TWO tables, and hcq2 reads only the
CLASS one. Nothing raises; the per-device placeholder rules simply never reach it, and
"not bufferized" is a missing rewrite, not an error. This prints the class table's rule
count with every backend module imported, which is the number that differs.
"""
import os, subprocess as sp, sys, tempfile, shutil
from pathlib import Path
REPO = Path(sys.argv[1]).resolve()
PIN = "6c3d401cf324"
CAND = sys.argv[2:]
# NO DEFAULT FILE LIST, ON PURPOSE. An earlier version of this file defaulted to a
# hard-coded six-file candidate; a run with no arguments therefore overlaid NOTHING, and
# `sys.argv[2:]` was empty so the loop body never ran -- the UNMODIFIED working tree was
# measured and printed under the label "MINIMAL 6", as `CLASS ABSENT / INSTANCE 1 rule`.
# An empty list that silently measures a different tree than the label claims is the same
# class of bug as a relative row check. So: refuse, and say what to pass.
if not CAND:
  sys.exit("usage: rebase-pm-fork.py <repo> <tinygrad/file.py>…   (no default list)")

W = Path(tempfile.mkdtemp(prefix="pmfork."))
sp.run(f'cd "{REPO}" && git archive {PIN} | tar -x -C "{W}"', shell=True, check=True)
shutil.rmtree(W / "tinygrad")
shutil.copytree(REPO / "tinygrad", W / "tinygrad")
for f in CAND:
  (W / f).write_bytes(sp.check_output(["git", "show", f"upstream/master:{f}"], cwd=REPO))

PROBE = r'''
import importlib
from tinygrad.device import Compiled, Device
# Every backend module, imported explicitly: under DEV=NULL five of the six never load,
# and a backend that never loads contributes no rules -- which would read as a clean tree.
for m in ("ops_null","ops_cuda","ops_metal","ops_nv","ops_qcom","ops_rdma"):
  try: importlib.import_module("tinygrad.runtime."+m)
  except Exception as e: print(f"  !! {m}: {type(e).__name__}: {e}")
d = Device["NULL"]
cls = getattr(Compiled, "pm_bufferize", None)
inst = d.__dict__.get("pm_bufferize")
print("  CLASS   Compiled.pm_bufferize          :", "ABSENT" if cls is None else f"{len(cls.patterns)} rules")
print("  INSTANCE Device['NULL'].__dict__ entry :", "ABSENT (one table)" if inst is None else f"{len(inst.patterns)} rules  <-- FORK")
'''
r = sp.run([sys.executable, "-c", PROBE], cwd=W,
           env=dict(os.environ, DEV="NULL", PYTHONPATH=str(W)), capture_output=True, text=True)
print(r.stdout or r.stderr[-1500:])
shutil.rmtree(W)
