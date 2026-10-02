#!/usr/bin/env python3
"""A/B one oracle across the landing: the tree as it is NOW vs the tree as it was BEFORE.

`rw-oracle.py` measures the WORKING tree (it does `sys.path.insert(0, repo_root)`), so its
rows are a function of what is vendored. Landing a batch therefore changes what it
measures, and "the oracle disagrees" does not by itself say whether the landing caused it.

PRE is reconstructed by blob, not by `git stash`: the working tree with each of the listed
files put back to `PRE_REV:<file>`. `git stash` is not available -- ten agents share this
working copy.

PASS `HEAD` for PRE_REV when the working tree was clean before the landing. `HEAD:<file>`
is the repo's COMMITTED blob per file, which is exactly the pre-landing content, and it is
per-file so mixed states are fine. Do NOT pass the PIN as a blanket pre-image: putting all
of a batch's files at the pin makes the tree unimportable (that is exactly how `search.py`
at the pin kills `import tinygrad.codegen.opt.search`), the oracle dies and prints NOTHING,
and every row comes back PRE=None -- a PRE that measures nothing while looking like a
measurement. The first version of this run did that and reported "23 rows MOVED".

  usage: rebase-ab-oracle.py <oracle.py> <rev-of-PRE> <file> [<file>…]
        (no file list  ->  PRE == POST, which measures nothing and says so)
"""
import os, shutil, subprocess as sp, sys, tempfile
from pathlib import Path
REPO = Path(__file__).resolve().parents[2]
PIN = "6c3d401cf324"
ORACLE = sys.argv[1]
PRE_REV = sys.argv[2]
FILES = sys.argv[3:]


def git(*a):
  return sp.run(["git", *a], cwd=REPO, capture_output=True, text=True)


def build(pre: bool):
  W = Path(tempfile.mkdtemp(prefix="ab."))
  sp.run(f'cd "{REPO}" && git archive {PIN} | tar -x -C "{W}"', shell=True, check=True)
  shutil.rmtree(W / "tinygrad")
  shutil.copytree(REPO / "tinygrad", W / "tinygrad")
  for f in FILES:
    if not pre: continue
    blob = git("show", f"{PRE_REV}:{f}")
    if blob.returncode: sys.exit(f"cannot read PRE {f}")
    (W / f).write_text(blob.stdout)
  return W


def run(W):
  r = sp.run([str(REPO / ".venv/bin/python"), str(REPO / ORACLE)], cwd=W,
             env=dict(os.environ, DEV="NULL", PYTHONPATH=str(W)), capture_output=True, text=True)
  return dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l and not l.startswith("#"))


if not FILES:
  sys.exit("no file list: PRE would equal POST and the A/B would measure nothing")

post = run(build(False))
pre = run(build(True))
moved = [(k, pre.get(k), post.get(k)) for k in sorted(set(pre) | set(post)) if pre.get(k) != post.get(k)]
print(f"  oracle {ORACLE}   PRE=pin-blob-of-each-listed-file   POST=working tree")
print(f"  {len(post)} rows POST, {len(pre)} rows PRE, {len(moved)} rows MOVED\n")
for k, a, b in moved:
  print(f"  MOVED {k}:  PRE={a}   POST={b}")
if not moved: print("  (no row moved)")
