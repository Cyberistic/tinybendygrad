#!/usr/bin/env python3
"""The GATE for the spec fold: the port's fold and CPython's fold must AGREE on EVERY cell the
two lanes print -- eight shapes times six tables, DISCOVERED from the lanes' own rows.

    .venv/bin/python gates/specfold-gate.py            # the gate
    .venv/bin/python gates/specfold-gate.py --plant    # the plant and its control

THE SUBJECT. `d4160980e` moved eight tests out of the port's rule BODIES and into the port's
rule CONDITIONS, so the port's conditions say exactly what upstream's PATTERNS say. The class
it fixed is one: a rule whose port condition is STRICTER than upstream's pattern reaches
nodes upstream's scan cannot reach, and the two sides then disagree -- not about the node,
but about WHICH RULE SPEAKS. Upstream's fold is first-wins and a pattern that does not match
means "move on"; the port's `O.pm_when` returns `VSkip{}` when its condition is false, which
is the same "move on".

THE TWO LANES, and they are built from DIFFERENT construction sites on purpose: the port
mints its nodes from `tinybendygrad/uop/ops.bend`'s constructors (`gates/specfold.bend`) and
the oracle mints them from upstream's `UOp` (`gates/specfold-oracle.py`), so agreement is
evidence and not a tautology.

THE POPULATION, AND WHY IT IS EVERY CELL THE LANES PRINT. It WAS twelve cells, named by hand,
on the criterion "the commit `d4160980e` decides these" -- **A POPULATION TIED TO ONE COMMIT.**
It is now **every cell the two lanes themselves print**: eight shapes times six tables, 48 of
them, DISCOVERED from the lanes' rows and CHECKED at RUN TIME (a lane that stops printing a
cell is a REFUSED gate, not a smaller population).

⇒ AND THE MEASUREMENT THAT FORCED IT. Reversing `d4160980e` AND `32e6633d0` in a FROZEN COPY
(a `git archive` of HEAD with both patches reverse-applied to `tinybendygrad/uop/spec.bend`, and
the gate loaded FROM that copy so it reads THAT copy's `spec.bend`) makes **20 of the 48 cells
disagree**. **THE OLD TWELVE CAUGHT 12. THE EIGHT IT MISSED WERE ALL OUTSIDE THE POPULATION**,
and four of the eight were the `buffer0` cells the gate graded OUT BY NAME. **⇒ A POPULATION
THAT EXCLUDES CELLS IS A POPULATION THAT CANNOT SEE A DEFECT IN THE CELLS IT EXCLUDES.**

"THE COMMIT'S JOB", KEPT AS THE SUBJECT'S HISTORY. `d4160980e` moved eight tests out of the
port's rule BODIES and into the port's rule CONDITIONS, so the port's conditions say exactly
what upstream's PATTERNS say. The class it fixed is one: a rule whose port condition is
STRICTER than upstream's pattern reaches nodes upstream's scan cannot reach, and the two sides
then disagree -- not about the node, but about WHICH RULE SPEAKS. Upstream's fold is
first-wins and a pattern that does not match means "move on"; the port's `O.pm_when` returns
`VSkip{}` when its condition is false, which is the same "move on".

"BOTH FOLDS SKIP" IS REPORTED, NOT A CRITERION. When upstream's pattern cannot match,
upstream's scan CONTINUES and, if no later rule claims the node, upstream answers `None` (`9`
here). That is a REAL property of a cell and the gate prints it per cell -- but **it is not an
exclusion.** A cell where some OTHER rule claims the node is a cell whose verdict is that other
rule's business; **a cell where the port claims and upstream does not is A DIVERGENCE, and that
is the gate's subject.** MEASURED: the port's `sh_16` (PARAM), `sh_17` (BUFFER), `te_3` (PARAM)
and `kg_4` (PARAM) still carry the OLD upstream's `src=()` -- ZERO srcs -- where the current
upstream's `spec.py:92`, `:93`, `:160` and `:263` all carry `src=(p_size,)` or
`src=(UPat(Ops.STACK, src=()),)`, which is EXACTLY ONE src. So for a zero-src BUFFER the
port's `sh_17` fires and says `False` where upstream's `spec.py:93` cannot match and the
scan continues. **⇒ AT THE COMMITTED TREE ALL 48 CELLS AGREE, AND THE GATE GRADES THEM ALL.**

THE PLANT, AND WHY IT IS A TEXT EDIT. `--plant` copies the WORKING COPY of
`gates/specfold.bend` beside itself, edits the COPY, and runs THE WHOLE GATE against it. It
never reads `git show HEAD:` -- a plant that reads HEAD plants nothing the moment HEAD
carries the fix, and three units scored green under `--falsify` for exactly that reason. The
plant perturbs the fixture's DTYPE -- the RESHAPE's shape goes from f32 to int32 -- so the
port's `te_5` matches and the port answers `1` where upstream answers `9`: THE GATE MUST GO
RED. The control is a BYTE-IDENTICAL copy and the gate MUST STAY GREEN.

DO NOT RUN THIS UNDER `checks/bendlock.sh`. Every bend run here takes the lock ITSELF, one
per invocation, and an outer lock would wait on itself.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HERE = ROOT / "gates"
PY = ROOT / ".venv" / "bin" / "python"
BOUNDED = ROOT / "checks" / "bounded.py"
BEND = ROOT / "bin" / "bend"
BENDLOCK = ROOT / "checks" / "bendlock.sh"
PROBE = HERE / "specfold.bend"
ORACLE = HERE / "specfold-oracle.py"

sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED  # noqa: E402

TABLES = ("sh", "te", "sp", "hq", "sk", "sf")

# THE EIGHT SHAPES, and the three of them that are CONTROLS -- a shape the commit's diff
# does not decide, so its rows must not move when the commit is reversed.
SHAPES = ("reshape_f32", "reshape_i32", "range2", "range1",
          "backedge_int", "backedge_bool", "buffer0", "alloc0")

# THE POPULATION, AND WHY IT IS NO LONGER A HAND LIST.
#
# IT WAS: twelve cells named by hand, on the criterion "the commit `d4160980e` decides these".
# **⇒ THAT WAS A POPULATION TIED TO ONE COMMIT, AND THE TREE's DOCTRINE SAYS A POPULATION MUST
# BE DERIVED BY DISCOVERY.**  IT IS NOW: **EVERY CELL THE TWO LANES THEMSELVES PRINT**, which is
# `SHAPES x TABLES` -- 48 -- and it is CHECKED AT RUN TIME that both lanes printed exactly that
# many rows, so a lane that stops measuring a cell is REFUSED, not a smaller population.
#
# **⇒ AND THE MEASUREMENT THAT FORCED THIS.**  REVERSING `d4160980e` AND `32e6633d0` IN A FROZEN
# COPY (a `git archive` of HEAD with both patches reverse-applied to `tinybendygrad/uop/spec.bend`)
# MAKES **20** OF THE 48 CELLS DISAGREE.  **THE OLD TWELVE-CAUGHT 12 OF THEM.  THE EIGHT IT
# MISSED WERE ALL OUTSIDE THE POPULATION, AND FOUR OF THE EIGHT WERE THE `buffer0` CELLS THE
# GATE GRADED OUT BY NAME.**  **⇒ A POPULATION THAT EXCLUDES CELLS IS A POPULATION THAT CANNOT
# SEE A DEFECT IN THE CELLS IT EXCLUDES.**
#
# THE ANNOTATION, KEPT.  "BOTH FOLDS SKIP" (`9` on both sides) IS A REAL PROPERTY OF A CELL AND IT
# IS NOW REPORTED PER CELL -- but it is NOT AN EXCLUSION.  A cell where both folds claim is a cell
# whose verdict is that rule's business, and a cell where the port claims and upstream does not is
# A DIVERGENCE, which is EXACTLY WHAT THE GATE IS FOR.
#
# THE RULE NAME, KEPT AS PROVENANCE.  `RULE_OF_CELL` names the rule that CHANGED at each commit,
# so a reader can see which rule a cell's verdict is about.  **IT IS AN ANNOTATION AND NOT A
# CRITERION: THE POPULATION IS DERIVED, AND THE ANNOTATION IS NOT CONSULTED WHEN GRADING.**
RULE_OF_CELL = {
  ("reshape_f32", "te"): "te_5", ("range2", "sh"): "sh_12", ("range2", "te"): "sh_12",
  ("range2", "hq"): "sh_12", ("backedge_int", "sh"): "sh_15", ("backedge_int", "te"): "sh_15",
  ("backedge_int", "hq"): "sh_15", ("buffer0", "sk"): "kg_5", ("alloc0", "te"): "te_2",
  ("alloc0", "sp"): "pr_4", ("alloc0", "sk"): "kg_6", ("alloc0", "sf"): "te_2",
}

# THE RULE THAT SPEAKS FOR A CELL WHERE THE PORT CLAIMS AND UPSTREAM DOES NOT.  REPORTED, NOT
# HIDDEN, AND NOT AN EXCLUSION.  `sh_16`/`sh_17`/`te_3`/`kg_4` still carry the OLD upstream's
# `src=()`, so the port's fold claims a zero-src PARAM/BUFFER where the current upstream's does
# not -- a REAL DIVERGENCE THE GATE NOW GRADES INSTEAD OF EXPLAINING AWAY.
NOT_DECIDED = {
  ("buffer0", "sh"): "sh_17 -- the port's shared BUFFER rule still says `nsrc_is(0)`",
  ("buffer0", "te"): "sh_17 -- the port's shared BUFFER rule still says `nsrc_is(0)`",
  ("buffer0", "sp"): "sh_17 -- the port's shared BUFFER rule still says `nsrc_is(0)`",
  ("buffer0", "hq"): "sh_17 -- the port's shared BUFFER rule still says `nsrc_is(0)`",
  ("buffer0", "sf"): "sh_17 -- the port's shared BUFFER rule still says `nsrc_is(0)`",
}


def run_probe(probe: Path) -> tuple[str, str]:
  """Run the port lane under the lock and under `checks/bounded.py`; return (stdout, token).

  THE VERDICT IS THE TOKEN AND NOT THE EXIT STATUS: `checks/bounded.py`'s own header records
  a unit that lost 425 rows by believing the status. The lock is taken PER INVOCATION -- a
  command that runs many bends and holds it for the whole command makes every other unit
  wait.
  """
  p = subprocess.run([str(BENDLOCK), "--", str(PY), str(BOUNDED), "--mb", "2048", "--",
                      str(BEND), str(probe)], capture_output=True, text=True, cwd=ROOT)
  token = next((l for l in p.stderr.splitlines() if l.startswith("[bounded]")), "[bounded] NOT RUN")
  return p.stdout, token


def run_oracle() -> tuple[str, int]:
  p = subprocess.run([str(PY), str(ORACLE)], capture_output=True, text=True, cwd=ROOT)
  return p.stdout, p.returncode


def rows(text: str) -> dict[str, str]:
  """Every `name_key=value` row of a lane's output."""
  out = {}
  for line in text.splitlines():
    m = re.match(r"^(\w+?)_(\w+)=(\d)$", line.strip())
    if m:
      out[f"{m.group(1)}_{m.group(2)}"] = m.group(3)
  return out


def population(port: dict[str, str], cpy: dict[str, str]) -> list[tuple[str, str]]:
  """THE POPULATION, DERIVED FROM THE TWO LANES' OWN ROWS.

  A cell is a (shape, table) pair that BOTH lanes printed a row for.  The lanes are the
  discoverers -- the port lane prints one row per fixture per table, and the CPython lane
  prints one row per shape per table -- so a cell that one lane stops printing is a cell the
  gate REFUSES over (see `main`), not a cell that quietly leaves the population.
  """
  out = []
  for shape in SHAPES:
    for t in TABLES:
      name = f"{shape}_{t}"
      if name in port and name in cpy:
        out.append((shape, t))
  return out


def grade(port: dict[str, str], cpy: dict[str, str]) -> tuple[list[str], list[str]]:
  """Grade the two lanes against each other. Return (problems, report lines).

  THE GRADE IS ONE CLAIM, AND IT IS NOW THE WHOLE POPULATION: **the port's spec fold and
  CPython's spec fold AGREE on every cell the two lanes print.**  A cell that disagrees is a
  FAIL.  There is no class of cell that is excluded from the claim, because MEASURED: reversing
  `d4160980e` and `32e6633d0` makes 20 of the 48 cells disagree, the old twelve-cell population
  caught 12, and the 8 it missed were ALL outside it.

  "BOTH FOLDS SKIP" (`9` on both sides) is REPORTED per cell and is NOT a criterion: a cell
  where both folds claim is a cell whose verdict is that rule's business, and a cell where the
  port claims and upstream does not is A DIVERGENCE -- which is the gate's subject.
  """
  bad: list[str] = []
  lines: list[str] = []
  cells = population(port, cpy)
  for shape, t in cells:
    name = f"{shape}_{t}"
    pv, cv = port[name], cpy[name]
    same = pv == cv
    rule = RULE_OF_CELL.get((shape, t), "-")
    both_skip = pv == "9" and cv == "9"
    lines.append(f"  {name:22s} rule={rule:6s} port={pv} cpython={cv} "
                 f"agree={'yes' if same else 'NO'} both-skip={'ok' if both_skip else 'claimed'}")
    if not same:
      bad.append(f"{name}: the port answers {pv} and CPython answers {cv}"
                 + (f" -- {NOT_DECIDED[(shape, t)]}" if (shape, t) in NOT_DECIDED else ""))
  lines.append(f"  {len(cells)} cell(s) graded; {sum(1 for c in cells if port[f'{c[0]}_{c[1]}'] == cpy[f'{c[0]}_{c[1]}'])} agree")
  return bad, lines


# --------------------------------------------------------------------------- the plant
PLANT_ANCHOR = "O.ADt{S.single()}, O.TNone{})\n  O.UOp.new(O.Found.ar(shp), O.OpsRESHAPE{}"
PLANT_EDIT = "O.ADt{S.int32()}, O.TNone{})\n  O.UOp.new(O.Found.ar(shp), O.OpsRESHAPE{}"


def verdict_of_probe(probe: Path) -> tuple[int, dict[str, str]]:
  """Run the WHOLE GATE against one driver file. Return (exit status, the port's rows)."""
  out, token = run_probe(probe)
  port = rows(out)
  cpy_out, rc = run_oracle()
  cpy = rows(cpy_out)
  if "WITHIN-LIMITS" not in token or rc != 0 or len(port) != len(cpy):
    return REFUSED, port
  bad, _ = grade(port, cpy)
  return (FAIL if bad else PASS), port


def plant() -> int:
  """THE PLANT AND ITS CONTROL. Both are TEXT EDITS of a COPY, never of the tree."""
  src = PROBE.read_text()
  if PLANT_ANCHOR not in src:
    print(f"REFUSED: the plant's anchor is not in {PROBE.relative_to(ROOT)} as it stands. THE PLANT "
          "IS A TEXT EDIT ON THE WORKING COPY, so an anchor that moved means the plant must be "
          "re-anchored -- NOT that it should fall back to reading git.")
    return REFUSED
  plant_probe = HERE / "specfold-plant.bend"
  control_probe = HERE / "specfold-control.bend"
  bad = 0
  try:
    base_status, base = verdict_of_probe(PROBE)
    if not base:
      print("REFUSED: the unplanted probe printed no rows, so the plant has nothing to move.")
      return REFUSED
    print(f"BASELINE  the gate against the unplanted driver: {'PASS' if base_status == PASS else 'FAIL'}")
    if base_status != PASS:
      print("  THE BASELINE IS NOT GREEN, so a plant that goes red would prove nothing.")
      bad += 1

    # 1. THE PLANT: the fixture's dtype goes from f32 to int32, so the port's `te_5` MATCHES
    #    and the port answers `1` where upstream answers `9`. THE GATE MUST GO RED.
    plant_probe.write_text(src.replace(PLANT_ANCHOR, PLANT_EDIT))
    plant_status, planted = verdict_of_probe(plant_probe)
    moved = {k: (base.get(k), planted.get(k)) for k in base if base.get(k) != planted.get(k)}
    print(f"PLANT     one dtype perturbed in the driver's fixture (the RESHAPE's shape f32 -> int32)")
    print(f"          rows moved={moved}")
    print(f"          the gate against the planted driver: {'PASS' if plant_status == PASS else 'FAIL'}")
    if plant_status != FAIL:
      print("  THE PLANT DID NOT GO RED: the gate still passes with a broken fixture.")
      bad += 1
    if not moved:
      print("  THE PLANT DID NOT MOVE ANY ROW: this lane cannot see the rule it grades.")
      bad += 1
    if any(not k.startswith("reshape_f32") for k in moved):
      print("  THE PLANT MOVED THE WRONG ROWS: only the RESHAPE fixture's rows may move.")
      bad += 1

    # 2. THE CONTROL: a BYTE-IDENTICAL copy. The gate MUST STAY GREEN and no row may move.
    control_probe.write_text(src)
    control_status, control = verdict_of_probe(control_probe)
    same_bytes = control_probe.read_bytes() == PROBE.read_bytes()
    moved_control = {k for k in base if base.get(k) != control.get(k)}
    print(f"CONTROL   a byte-identical copy of the driver, byte-identical={same_bytes}")
    print(f"          rows moved={sorted(moved_control)}")
    print(f"          the gate against the control driver: {'PASS' if control_status == PASS else 'FAIL'}")
    if control_status != PASS:
      print("  THE CONTROL IS NOT A CONTROL: the gate went red on a byte-identical copy.")
      bad += 1
    if moved_control:
      print("  THE CONTROL IS NOT A CONTROL: the rows moved on a byte-identical copy.")
      bad += 1
    if not same_bytes:
      print("  THE CONTROL IS NOT A CONTROL: the copy is not byte-identical.")
      bad += 1
  finally:
    for p in (plant_probe, control_probe):
      if p.exists():
        p.unlink()
  print(f"\n=== specfold-gate --plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
  return FAIL if bad else PASS


# --------------------------------------------------------------------------- the gate
def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--plant", action="store_true", help="run the plant and its control")
  args = ap.parse_args()
  if args.plant:
    return plant()

  out, token = run_probe(PROBE)
  port = rows(out)
  cpy_out, rc = run_oracle()
  cpy = rows(cpy_out)
  if "WITHIN-LIMITS" not in token:
    print(token)
    print("REFUSED: the port lane did not finish inside its bounds, so it measured nothing.")
    return REFUSED
  if rc != 0:
    print(cpy_out[-2000:])
    print("REFUSED: the CPython lane failed, so there is no second side to compare against.")
    return REFUSED
  if len(port) != len(SHAPES) * len(TABLES) or len(cpy) != len(SHAPES) * len(TABLES):
    print(f"REFUSED: the lanes printed {len(port)} and {len(cpy)} rows; the census is "
          f"{len(SHAPES) * len(TABLES)}. A lane that printed fewer rows has not measured them all.")
    return REFUSED

  print("# shape\ttable\tport\tcpython\tagree")
  for shape in SHAPES:
    for t in TABLES:
      name = f"{shape}_{t}"
      pv, cv = port.get(name, "?"), cpy.get(name, "?")
      print(f"{shape}\t{t}\t{pv}\t{cv}\t{'yes' if pv == cv else 'NO'}")
  print()

  bad, lines = grade(port, cpy)
  cells = population(port, cpy)
  print(f"THE POPULATION: {len(cells)} cell(s), DERIVED FROM THE TWO LANES' OWN ROWS "
        f"(every shape x table both lanes printed)")
  for line in lines:
    print(line)
  if bad:
    print(f"\n=== specfold-gate: FAIL: {len(bad)} problem(s) ===")
    for b in bad:
      print(f"  {b}")
    return FAIL
  print(f"\n=== specfold-gate: PASS: the port's fold and CPython's fold agree on all "
        f"{len(cells)} cells the two lanes print ===")
  return PASS


if __name__ == "__main__":
  raise SystemExit(main())
