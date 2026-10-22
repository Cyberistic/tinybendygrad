#!/usr/bin/env python3
"""fold-vbase-plant.py -- THE GATE'S OWN PLANT: three states, on COPIES.

    .venv/bin/python gates/fold-vbase-plant.py

A GATE THAT CANNOT GO RED IS A LABEL, not a gate -- `checks/differ.py`'s own plant 3 says so,
and `differ.py` measures it by perturbing a thing and watching the verdict move. This file is
that measurement for `gates/fold-vbase-gate.py`, and it asserts THREE STATES, in the order a
reader needs them:

    1  the UNMUTATED control PASSES (exit 0) -- the green the other two are read against
    2  a PORT ROW PERTURBED makes it FAIL (exit 1) -- the gate SEES a wrong `vb_` row
    3  a MISSING ORACLE makes it REFUSE (exit 3) -- an absent precondition is not a pass

THE THIRD IS THE ONE THAT MATTERS MOST, and it is the one a gate is most likely to get wrong:
an oracle that is not there is a comparison that was never made, and the failure mode is a
green that says "0 disagreements" over ZERO comparisons -- the defect this tree has paid for
three times. A gate that cannot refuse is a gate that cannot fail.

EVERYTHING HAPPENS ON A COPY. The port's `tinybendygrad/` tree is COPIED into a temporary
directory and the mutation is applied THERE, because a `.bend` file imports its neighbours
RELATIVE TO ITS OWN PATH: a copy of ONE file anywhere else cannot resolve them and answers
"the substrate did not warm" -- a REFUSED exit for the wrong reason, and a harness that
reports "the mutation was found" because the file did not compile has learned nothing. So the
WHOLE TREE is copied (12 MB, one `shutil.copytree`), and the copy is measured.

AND THE MUTATION IS THE PORT'S OWN, READ FROM ITS OWN TABLE. `gates/fold-vbase-mutate.py`
holds the ten mutations of the `vb_` rows and the one control; this file LOADS that table BY
PATH and takes `P6` from it, so the gate's plant and the port's plant cannot disagree about
what a mutation is -- a second copy of the table is a second contract with no generator.
`P6` is "the weak set is `is_float`, so weakint is not weak", which the port's own table
records as moving exactly ONE row (`vb_wc`), the row that carries weakint over a
device-carrying buffer.

A MUTATION THAT DOES NOT APPLY IS NOT REPORTED AS ZERO. The port's plant says so in its own
words -- "DID NOT APPLY -- the old text is not in the file. NOT REPORTED AS 0." -- and this
file says it in the same words, because a harness which cannot tell "the edit changed
nothing" from "the edit changed everything" IS the defect.

THE BEND LOCK, AND WHY IT IS AN ENVIRONMENT VARIABLE. This file runs `bend` twice, and
`bend` at 1-2 GiB a piece is not something two units may run at once. The lock this tree
uses is a DIRECTORY in the operator's temporary area, and that path is a property of the
SESSION and not of the repository -- so a committed script may not hardcode it. `BEND_LOCK`
names it when the operator sets it, and the file says so in its own output when it does not.

AND `FOLD_VBASE_TREE` NAMES THE TREE THE PLANT COPIES, for the same reason and a second
one: the substrate is SHARED, and another unit's in-flight edit to `tinybendygrad/uop/ops.bend`
can leave the live tree not compiling at all -- MEASURED 2026-10-22, this tree's own
`fold.bend` did not compile for the whole of one measurement window because of exactly that.
A plant cannot measure a tree that does not build, and it must not FIX another unit's file
either, so the tree it copies is a parameter and it defaults to the live one.
"""
import importlib.util
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import reporoot                                                    # noqa: E402
from gatekit import PASS, FAIL, REFUSED                            # noqa: E402

# THE MUTATION THE PLANT USES, AND WHY THIS ONE. See the header: it is read from the
# port's own table, by path, so there is ONE table of mutations in this tree.
MUTATION = "P6"


def _load(path, name):
  """A MODULE, LOADED BY PATH -- `gates/` is not a package, and putting it on `sys.path`
  would make the name bindable by anything in the tree."""
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


class Lock:
  """THE BEND LOCK, HELD FOR THE WHOLE PLANT, and RELEASED BY `finally`.

  A `mkdir` is the lock: it is atomic, it leaves a DIRECTORY a reader can see, and it
  cannot be created twice. `BEND_LOCK` names it; without that variable the plant says so
  and runs anyway, because a plant that refuses to run is not a measurement either.
  """

  def __init__(self, path):
    self.path, self.held, self.waited = Path(path) if path else None, False, 0

  def __enter__(self):
    if self.path is None:
      return self
    t0 = time.time()
    while True:
      try:
        self.path.mkdir(parents=True)
        self.held = True
        break
      except FileExistsError:
        time.sleep(2)
    self.waited = time.time() - t0
    return self

  def __exit__(self, *exc):
    if self.held:
      try:
        self.path.rmdir()
      except OSError:
        pass
      self.held = False
    return False


def _run_gate(gate_mod, driver, oracle):
  """The gate, with its two lanes pointed at the given paths, and its verdict."""
  keep_d, keep_o = gate_mod.DRIVER, gate_mod.ORACLE
  gate_mod.DRIVER, gate_mod.ORACLE = driver, oracle
  try:
    return gate_mod.main()
  finally:
    gate_mod.DRIVER, gate_mod.ORACLE = keep_d, keep_o


def main():
  # THE ROOT, BY THE MARKERS `pyproject.toml`, `tinybendygrad/` AND `tinygrad/` -- and a
  # plant that cannot find one exits 3, REFUSED, NOT A VERDICT, rather than copying a tree
  # it could not identify. `gates/reporoot.py` says why the depth is not a number.
  try:
    root = reporoot.root(__file__)
  except reporoot.RootNotFound as e:
    print(f"== REFUSED, NOT A VERDICT: {e}", file=sys.stderr)
    return REFUSED
  gate_mod = _load(HERE / "fold-vbase-gate.py", "fold_vbase_gate")
  mutate_mod = _load(HERE / "fold-vbase-mutate.py", "fold_vbase_mutate")
  live_oracle = HERE / "fold-vbase-oracle.py"

  # THE MUTATION, FROM THE PORT'S OWN TABLE, AND IT MUST EXIST.
  muts = {mid: (what, old, new) for mid, what, old, new in mutate_mod.MUTATIONS}
  if MUTATION not in muts:
    print(f"fold-vbase-plant: REFUSED -- the port's own mutation table has no {MUTATION!r}, so "
          "there is nothing to perturb")
    return REFUSED
  what, old, new = muts[MUTATION]

  lock = Lock(os.environ.get("BEND_LOCK"))
  src_tree = Path(os.environ.get("FOLD_VBASE_TREE") or (root / "tinybendygrad"))
  bad = []
  with lock:
    if lock.path is None:
      print("fold-vbase-plant: BEND_LOCK is not set, so this plant is running `bend` WITHOUT the "
            "tree's lock -- set it to a directory nobody else holds")
    else:
      print(f"fold-vbase-plant: took the bend lock after {lock.waited:.0f}s")
    if src_tree != root / "tinybendygrad":
      print(f"fold-vbase-plant: copying {src_tree} and not the live tree")
    with tempfile.TemporaryDirectory() as td:
      scratch = Path(td) / "tinybendygrad"
      shutil.copytree(src_tree, scratch)
      copy = scratch / "uop" / "fold.bend"
      pristine = copy.read_text()
      if old not in pristine:
        print(f"fold-vbase-plant: REFUSED -- {MUTATION} DID NOT APPLY, the old text is not in the "
              "file. NOT REPORTED AS 0.")
        return REFUSED

      # 1 -- THE CONTROL. The UNMUTATED copy must PASS, or the FAIL below would mean nothing.
      rc = _run_gate(gate_mod, copy, live_oracle)
      ok = rc == PASS
      print(f"  {'PASS' if ok else 'FAIL'}  1: the UNMUTATED copy PASSES (rc={rc}, want "
            f"{PASS}) -- the green the other two are read against")
      if not ok:
        bad.append(f"the unmutated copy returned {rc}, expected {PASS}")

      # 2 -- THE PERTURBED PORT ROW. One `vb_` row's value changes, so the port DISAGREES with
      # the oracle and the gate must FAIL rather than shrug.
      copy.write_text(pristine.replace(old, new, 1))
      rc = _run_gate(gate_mod, copy, live_oracle)
      ok = rc == FAIL
      print(f"  {'PASS' if ok else 'FAIL'}  2: a PORT ROW PERTURBED makes the gate FAIL (rc={rc}, "
            f"want {FAIL}) -- {MUTATION}: {what}")
      if not ok:
        bad.append(f"the perturbed copy returned {rc}, expected {FAIL}")
      copy.write_text(pristine)

      # 3 -- THE MISSING ORACLE. An absent precondition is a REFUSAL and never a pass.
      rc = _run_gate(gate_mod, copy, scratch / "no-such-oracle.py")
      ok = rc == REFUSED
      print(f"  {'PASS' if ok else 'FAIL'}  3: a MISSING ORACLE makes the gate REFUSE (rc={rc}, "
            f"want {REFUSED}) -- a comparison that was never made is not a pass")
      if not ok:
        bad.append(f"the missing oracle returned {rc}, expected {REFUSED}")

  # AND THE TREE ITSELF, ONCE, so the control above is not the only thing that could pass: the
  # gate must also PASS on the tree it is pointed at. It is the SAME tree the plant copied --
  # `FOLD_VBASE_TREE` names one, and the live one is the default -- because a plant that
  # measured one tree and then checked another would be two measurements wearing one name.
  tree_driver = src_tree / "uop" / "fold.bend"
  rc = _run_gate(gate_mod, tree_driver, live_oracle)
  ok = rc == PASS
  print(f"  {'PASS' if ok else 'FAIL'}  4: the tree itself PASSES (rc={rc}, want {PASS}) -- "
        f"{tree_driver}")
  if not ok:
    bad.append(f"the tree returned {rc}, expected {PASS}")

  print(f"--plant: {'GREEN' if not bad else 'RED: ' + '; '.join(bad)}")
  return 0 if not bad else 1


if __name__ == "__main__":
  sys.exit(main())
