#!/usr/bin/env python3
"""fold-vbase-gate.py -- the port's NINE `vb_` ROWS against CPython's OWN NINE.

    .venv/bin/python gates/fold-vbase-gate.py

WHAT THIS GATES. `tinybendygrad/uop/fold.bend` prints nine `vb_` rows -- one per fixture --
carrying `base`/`unsharded_base`/`storage_base`/`is_virtual` for the same graphs CPython's
`UOp` carries them for. Until this gate existed the comparison was a `diff` written in a
COMMENT (`fold.bend:6454-6458`) and the oracle that made it possible was an UNTRACKED file
under `.agents/slop/` -- the directory this tree is pruning -- so the port's nine rows were
proven by a script nobody ran, against an oracle a prune could delete. `AGENTS.md`: "A GATE'S
REQUIRED INPUT BELONGS BESIDE THE GATE IN GIT". The oracle and the plant are beside this
file now.

THE TWO LANES, AND WHAT EACH ONE IS. The PORT lane is `bin/bend tinybendygrad/uop/fold.bend`
-- the WHOLE driver, of which only the nine `vb_` rows are read; the driver prints 340 rows
and 331 of them are somebody else's subject. The ORACLE lane is `gates/fold-vbase-oracle.py`,
which reads CPython's OWN `UOp.base`/`unsharded_base`/`storage_base`/`is_virtual` properties
off real `UOp`s -- it does not reimplement a fold, because an oracle that recomputes the
thing it is checking agrees with itself.

THE FIVE VERDICTS ARE `gates/gatekit.py`'s, IMPORTED AND NEVER RE-SPELLED: PASS 0, FAIL 1,
REFUSED 3, SKIP 4, DEAD 5. **THERE IS NO SKIP IN THIS GATE, AND ITS ABSENCE IS A CLAIM:** a
side that cannot run is a REFUSAL, not a SKIP, because the thing that would be skipped IS the
measurement -- there is no smaller thing to do instead. `e2e.py`'s SKIP is a stage of a
seven-stage gate; this gate is one comparison.

    PASS      the two lanes' nine rows are byte-identical
    FAIL      they are not, or the population is not the nine declared rows
    REFUSED   a side could not RUN -- a missing oracle, a driver that did not compile
    DEAD      a side RAN and emitted no `vb_` row

A MISSING ORACLE IS NOT A PASS, and it is not a FAIL either: it is the absence of the
precondition the whole claim rests on, and `REFUSED` is what that absence is called.

THE POPULATION IS DECLARED, AND A SHRINK IS A FAIL. `ROWS` is the nine fixture names in the
driver's own order. A row missing from ONE lane is a count failure; a row missing from BOTH
is a count failure too, and that is the case a lane-to-lane comparison alone cannot see --
"0 disagreements over 0 comparisons" is the defect this tree has paid for three times. The
names are also compared IN ORDER, because a driver that reordered two fixtures is a
different table.

WHAT THIS GATE DOES NOT CLAIM. It does not claim the VALUES of any UOp are right -- it
compares two answers about the same nine graphs, and CPython's answer is the reference. It
does not run the NATIVE (`bend -o`) lane, because the claim here is about the fold's
ANSWER and the two lanes are the two answers; a third lane would be a third copy of the
same question. And it does not gate the driver's other 331 rows, which are somebody else's
subject and somebody else's gate.
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gatekit                                                     # noqa: E402
import reporoot                                                    # noqa: E402
from gatekit import BEND, PY, PASS, FAIL, REFUSED, DEAD, VERDICT   # noqa: E402

# THE ROOT, BY THE MARKERS `pyproject.toml`, `tinybendygrad/` AND `tinygrad/` -- and a gate
# that cannot find one exits 3, REFUSED, NOT A VERDICT, rather than measuring a tree it
# could not identify. `gates/reporoot.py` says why the depth is not a number.

# THE NINE FIXTURES, IN THE DRIVER'S OWN ORDER. A DECLARATION and not a count: a count
# cannot see a row that vanished from BOTH lanes, and a name cannot see a row that moved.
ROWS = ("add", "mv", "us", "eus", "abc", "cst", "cast", "wc", "wf")

# THE TWO LANES, AS MODULE GLOBALS so the PLANT can point them at COPIES
# (`gates/fold-vbase-plant.py` sets them and calls `main()`), the shape
# `gates/linearizer_census-gate.py` and `gates/mutkit.py` already use. `None` means "the
# one this tree owns".
DRIVER = None
ORACLE = None


def _say(code, msg):
  """The verdict AND the reason, on ONE line, and the exit is the code.

  A CODE `gatekit.VERDICT` DOES NOT NAME IS NOT A VERDICT, and this file refuses it rather
  than exiting with a number no reader can interpret -- `gates/gates-pop.py`'s `verdict_of`
  says an unassigned code is a REFUSAL, and a gate that returned one would be scored `DEAD`
  by a runner that maps anything outside the five.
  """
  if code not in VERDICT:
    print(f"fold-vbase-gate: REFUSED, NOT A VERDICT -- {code!r} is not one of gatekit's five",
          file=sys.stderr)
    return REFUSED
  print(f"fold-vbase-gate: {VERDICT[code]} -- {msg}")
  return code


def _lanes():
  """`(driver, oracle, why)` -- the two lanes, and the reason there are none."""
  try:
    root = reporoot.root(__file__)
  except reporoot.RootNotFound as e:
    return None, None, str(e)
  # TWO INSTRUMENTS, TWO ROOTS, AND THE GATE REFUSES WHEN THEY DISAGREE. `reporoot` finds
  # the root by a MARKER and `gatekit` names it as `HERE.parent`; if those two ever
  # disagree, the gate would be measuring one tree and naming another, which is the class
  # `gates/gates-pop.py` exists for. A refusal here is not a failure of the port.
  if root != gatekit.ROOT:
    return None, None, (f"the root the marker search found ({root}) is not the root gatekit "
                        f"names ({gatekit.ROOT})")
  driver = DRIVER or (root / "tinybendygrad" / "uop" / "fold.bend")
  oracle = ORACLE or (HERE / "fold-vbase-oracle.py")
  return driver, oracle, ""


def _vb_rows(text):
  """The `vb_` rows of a lane, in the order the lane printed them."""
  return [l for l in (text or "").splitlines() if l.startswith("vb_")]


def _oracle_rows(oracle, root):
  """`(rows, code, why)` -- CPython's lane, and the verdict it earned.

  THE THREE ARMS ARE `gates/gatekit.py`'s OWN (`Gate._oracle`), because that file's header
  says why a fourth shape is not available: an oracle cannot say `DEAD` from its own exit
  code, because 0 already means `PASS` and every other value belongs to somebody else.
  """
  r = subprocess.run([str(PY), str(oracle)], capture_output=True, text=True, cwd=str(root))
  rows = _vb_rows(r.stdout)
  if r.returncode == 0:
    if not rows:
      return None, DEAD, "the oracle ran and emitted no `vb_` row"
    return rows, PASS, ""
  said = gatekit._said(r.stderr)
  if not said and not rows:
    return None, DEAD, (f"the oracle ran, said nothing and emitted no row (rc={r.returncode})")
  return None, REFUSED, (f"the oracle failed rc={r.returncode}: "
                         f"{said[:200] if said else f'it emitted {len(rows)} rows and still failed'}")


def _port_rows(driver, root):
  """`(rows, code, why)` -- the port's lane, and the verdict it earned.

  THE RETRY IS `gates/gatekit.py`'s, and for its own measured reason: `bend`'s machine stack
  overflows on roughly 1 run in 20 and prints NOTHING, which is indistinguishable from "did
  not start". The discriminator is `gatekit._said(stderr)` -- a bend that NAMED its failure
  is not the flake -- and a file that is genuinely cold still fails.
  """
  for tries in range(1, gatekit.TRIES + 1):
    r = subprocess.run([str(BEND), str(driver)], capture_output=True, text=True, cwd=str(root))
    rows = _vb_rows(r.stdout)
    if r.returncode == 0:
      if rows:
        return rows, PASS, ""
      return None, DEAD, "the driver ran and emitted no `vb_` row"
    said = gatekit._said(r.stderr)
    if said:
      return None, REFUSED, f"the driver did not compile: {said[:200]}"
    # rc != 0, nothing said, no rows: the stack flake. 25 tries, and a driver that is
    # genuinely broken still fails on the first one.
  return None, REFUSED, f"the driver produced nothing in {gatekit.TRIES} tries (the stack flake)"


def main():
  driver, oracle, why = _lanes()
  if why:
    print(f"== REFUSED, NOT A VERDICT: {why}", file=sys.stderr)
    return _say(REFUSED, why)
  if not Path(oracle).is_file():
    return _say(REFUSED, f"the oracle {oracle} is MISSING -- a missing oracle is not a pass")
  if not Path(driver).is_file():
    return _say(REFUSED, f"the driver {driver} is MISSING -- a missing driver is not a pass")

  root = gatekit.ROOT
  py, code, why = _oracle_rows(oracle, root)
  if code != PASS:
    return _say(code, why)
  bd, code, why = _port_rows(driver, root)
  if code != PASS:
    return _say(code, why)

  # THE POPULATION, DECLARED. Both lanes must carry exactly the nine declared names, in
  # the declared order -- and a lane that carries a DIFFERENT count is a count failure
  # rather than a diff, because a diff of two different lengths is a diff of the wrong
  # two things.
  pyn = [l.split(" ", 1)[0] for l in py]
  bdn = [l.split(" ", 1)[0] for l in bd]
  want = ["vb_" + r for r in ROWS]
  for tag, names in (("oracle", pyn), ("port", bdn)):
    if names != want:
      missing = [n for n in want if n not in names]
      extra = [n for n in names if n not in want]
      moved = [(a, b) for a, b in zip(pyn, bdn) if a != b][:3] if tag == "port" else []
      return _say(FAIL, f"the {tag} lane holds {len(names)} rows and not the nine declared ones "
                        f"(missing {missing}, unexpected {extra}"
                        + (f", order moved {moved}" if moved else "") + ")")

  bad = [(a, b) for a, b in zip(py, bd) if a != b]
  if bad:
    for port, oracle_line in bad:
      print(f"  {port.split(' ', 1)[0]}")
      print(f"    port   : {port}")
      print(f"    oracle : {oracle_line}")
    return _say(FAIL, f"{len(bad)} of {len(py)} rows disagree byte for byte: "
                      + " ".join(a.split(" ", 1)[0] for a, _ in bad))
  return _say(PASS, f"{len(py)} rows compared byte for byte, 0 divergences; the port's "
                    "`base`/`unsharded_base`/`storage_base`/`is_virtual` agree with CPython's "
                    "own on all nine fixtures")


if __name__ == "__main__":
  sys.exit(main())
