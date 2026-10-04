#!/usr/bin/env python3
"""rebase-shadow.py -- prove a rebase oracle can be RED by perturbing THE TREE IT READS,
without touching a `.bend` file or `tinygrad/`.

WHY A SECOND PERTURBATION INSTRUMENT. `rebase-break.py` perturbs the PORT, which is the right
move for a gate differ. It is the WRONG move for two of the oracles in BASE_ORACLES:

  * `codegen/opt/search.bend` belongs to a LIVE agent. Perturbing it for the ~40 seconds a
    break proof takes would put a deliberately-wrong file in front of an agent who is writing
    to it, and my revert would land on top of their save. That is the concurrency hazard in
    agent-core.md, and it is not worth 40 seconds of coverage.
  * a rebase oracle's INPUT IS THE TREE. `rebase-oracle-search.py` answers a question about
    `tinygrad/codegen/opt/search.py`'s `actions` list. A red proof that leaves the table
    alone proves only that the differ works, which `rebase-break.py` already shows.

SO: shadow the tree. Every file is a SYMLINK into the real tree, so nothing is copied and
nothing can be damaged; one file is replaced by a real, perturbed copy; the oracle is re-run
with `TG_TREE` pointed at the shadow; and the verdict is the row DELTA.

The proof that matters: a row must MOVE, and the row that moves must be one the oracle
claims to answer. An oracle that returns the same 12 rows whatever the table says is
answering nothing, and this is the only test that can tell.

    python3 .agents/slop/rebase-shadow.py --oracle .agents/slop/rebase-oracle-search.py \
        --file tinygrad/codegen/opt/search.py --find SUBST --replace SUBST
"""
import argparse, os, pathlib, shutil, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]



# ── THE ROW READER IS `rebase-gate.py`'s OWN, LOADED BY PATH AND NOT COPIED ──────────────
# Measured by reader-fork-census.py on this corpus: 51 of 52 text readers disagreed with
# `rows()` on at least one of six row shapes, and four of them carried a docstring
# claiming to BE it. This file used to be one of them.
# ⚠ NOT FREE, and the census prints the load: of 1,440 lane files under .agents/slop
# (289,262 lines), 44,345 are F2 `py=`-tail lines and 2,370 are F3 two-space lines --
# so a fork that did not fold the tail was reading a DIFFERENT STRING on ~15% of lanes,
# and one that skipped F3 was blind to ~0.8%. Those are the sizes of what was wrong.
_RG = importlib.util.spec_from_file_location("rebase_gate", pathlib.Path(__file__).resolve() / "rebase-gate.py")
_rebase_gate = importlib.util.module_from_spec(_RG)
_RG.loader.exec_module(_rebase_gate)
rows = _rebase_gate.rows


def shadow(src, dst):
  """A symlink farm with `src`'s shape. `copytree(symlinks=True)` copies a symlink AS a
  symlink, so 289 files cost 289 links and no bytes -- which is why perturbing a 19M tree
  is a two-second operation and not a copy."""
  if dst.exists():
    shutil.rmtree(dst)
  shutil.copytree(src, dst, symlinks=True)


def unshadow(dst, rel):
  """Replace one symlink with a real, writable copy, so the perturbation cannot reach the
  tree it came from. A symlink left in place here is a way to edit upstream by accident."""
  p = dst / rel
  assert p.is_symlink() or p.exists(), f"{rel} is not in the shadow tree"
  if p.is_symlink():
    src = pathlib.Path(os.readlink(p))
    p.unlink()
    shutil.copy2(src, p)
  return p


def run(oracle, tree):
  e = dict(os.environ, DEV="NULL", TG_TREE=str(tree))
  return subprocess.run([str(REPO / ".venv/bin/python"), str(oracle)], cwd=REPO,
                        capture_output=True, text=True, env=e)


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--oracle", required=True)
  ap.add_argument("--tree", default=str(HERE / "opstree"))
  ap.add_argument("--file", required=True, help="tree-relative path, e.g. tinygrad/...py")
  ap.add_argument("--find", required=True)
  ap.add_argument("--replace", required=True)
  a = ap.parse_args()

  src, dst = pathlib.Path(a.tree).resolve(), HERE / "rebase" / "shadow-tree"
  shadow(src, dst)
  before = run(a.oracle, dst)
  if before.returncode != 0:
    print("ABORT: the oracle does not run against the UNPERTURBED shadow tree\n"
          + before.stderr[-800:])
    return 1
  r0 = rows(before.stdout)
  print(f"BREAK PROOF (tree)  {a.oracle}")
  print(f"  tree={dst.relative_to(REPO)}  rows={len(r0)}")

  p = unshadow(dst, a.file)
  text = p.read_text()
  if text.count(a.find) != 1:
    print(f"  ABORT: {a.find!r} occurs {text.count(a.find)} times in {a.file}; "
          "it must occur exactly ONCE or this proves nothing")
    return 1
  p.write_text(text.replace(a.find, a.replace))
  print(f"  perturbed {a.file}: {a.find[:60]!r} -> {a.replace[:60]!r}")

  after = run(a.oracle, dst)
  if after.returncode != 0:
    print("  RED PROOF FAILED: the oracle now ERRORS instead of reporting a disagreement. "
          "An oracle that cannot survive a changed table cannot gate a rebase.\n"
          + after.stderr[-800:])
    return 1
  r1 = rows(after.stdout)
  moved = sorted(k for k in set(r0) & set(r1) if r0[k] != r1[k])
  print(f"  rows the perturbation moved: {moved}")
  for k in moved:
    print(f"    {k}: {r0[k]!r} -> {r1[k]!r}")
  shutil.rmtree(dst)
  if not moved:
    print("  RED PROOF FAILED: the perturbation moved NO row, so the oracle does not read "
          "the thing it claims to read")
    return 1
  print(f"  RED PROVED: {len(moved)} row(s) moved with the table; shadow tree removed")
  return 0


if __name__ == "__main__":
  sys.exit(main())