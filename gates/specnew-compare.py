#!/usr/bin/env python3
"""The MAP for the two node shapes upstream's `spec.py:104` and `spec.py:125` decide, and
THE PLANT for the rules that decide them.

    .venv/bin/python gates/specnew-compare.py            # the map
    .venv/bin/python gates/specnew-compare.py --plant    # the plant and its control

WHAT THIS IS. `gates/specreach.bend` is the map for the port's `spec_full` over three
fixtures and `gates/specreach-map.rows` is its reading. This file is the same shape for a
DIFFERENT question: "DO THE PORT'S TWO NEW RULES -- `spec.py:104`'s AFTER-on-a-scalar-ALU
and `spec.py:125`'s STORE-value-matches-its-target -- DECIDE THE SAME NODES UPSTREAM
DECIDES?" The two lanes are `gates/specnew.bend` (the port) and `gates/specnew-oracle.py`
(CPython), and the population is the two fixtures, six tables each: TWELVE cells.

THE PLANT, AND WHY IT IS A TEXT EDIT. `--plant` copies the WORKING COPY of `spec.bend`
beside itself, edits the COPY, and runs the probe against it. It never reads `git show
HEAD:` -- a plant that reads HEAD plants nothing the moment HEAD carries the defect's fix,
and three units scored green under `--falsify` for exactly that reason. The plant changes
ONE THING: the dispatch arm that names the AFTER-on-a-scalar-ALU rule, so the rule is in
the table and cannot fire. That is the port's own named defect class -- "a tag that stops
selecting the rule it was written for lands on a DIFFERENT rule" -- and the `after_alu`
rows MUST MOVE. The control adds a COMMENT and the rows MUST NOT.

THE CONTROL'S COMMENT-ONLY-NESS IS PROVED, NOT ASSERTED. `_code_only` is
`gates/specreach-gate.py`'s, which is `checks/port-compile-gate.py`'s `strip_comments()`
PLUS A BLANK-LINE DROP -- and the blank-line drop is what makes a WHOLE-LINE comment at
column 0 count as comment-only, because a comment on its own line leaves an EMPTY line
once the comment is stripped and comparing LINE LISTS would call that "not comment-only".
"""
import argparse
import importlib.util
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
PROBE = HERE / "specnew.bend"
ORACLE = HERE / "specnew-oracle.py"
SPEC = ROOT / "tinybendygrad" / "uop" / "spec.bend"
PLANT_SPEC = ROOT / "tinybendygrad" / "uop" / "spec-plant.bend"
PLANT_PROBE = HERE / "specnew-plant.bend"

sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED  # noqa: E402

KEYS = ("sh", "te", "sp", "hq", "sk", "sf")
FIXTURES = ("after_alu", "store_bad")


def _specreach_gate():
  """`gates/specreach-gate.py` BY PATH, for its `_code_only` and its `run_probe`.

  `_code_only` is the comment stripper from `checks/port-compile-gate.py` PLUS a
  BLANK-LINE DROP, and re-typing it here would be a SECOND copy of the question -- and
  the two would drift. Importing it is how the copy is avoided.
  """
  spec = importlib.util.spec_from_file_location("specreach_gate", HERE / "specreach-gate.py")
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def run_probe(probe: Path) -> tuple[str, str]:
  """Run the probe under the lock and under `checks/bounded.py`, and return (stdout, verdict).

  THE VERDICT IS THE TOKEN AND NOT THE EXIT STATUS: `checks/bounded.py`'s own header records
  a unit that lost 425 rows by believing the status. The lock is taken PER INVOCATION --
  a command that runs many bends and holds it for the whole command makes every other unit
  wait.
  """
  p = subprocess.run([str(BENDLOCK), "--", str(PY), str(BOUNDED), "--mb", "2048", "--",
                      str(BEND), str(probe)], capture_output=True, text=True, cwd=ROOT)
  token = next((l for l in p.stderr.splitlines() if l.startswith("[bounded]")), "[bounded] NOT RUN")
  return p.stdout, token


def rows(text: str) -> dict[str, str]:
  """Every `name_key=value` row of a probe's output."""
  out = {}
  for line in text.splitlines():
    m = re.match(r"^(\w+?)_(\w+)=(\d)$", line.strip())
    if m:
      out[f"{m.group(1)}_{m.group(2)}"] = m.group(3)
  return out


# --------------------------------------------------------------------------- the plant
PLANT_ANCHOR = "    case 20: sh_20(fx, self)"
PLANT_EDIT = "    case 20: sh_19(fx, self)"
CONTROL_ANCHOR = "# spec.py:104 (UPat(Ops.AFTER, src=(UPat(GroupOp.ALU),)"
CONTROL_EDIT = "# THE CONTROL: a comment.\n# spec.py:104 (UPat(Ops.AFTER, src=(UPat(GroupOp.ALU),"


def plant(gate) -> int:
  """THE PLANT AND ITS CONTROL. Both are TEXT EDITS of a COPY, never of the tree."""
  original = SPEC.read_text()
  for name, anchor in (("PLANT", PLANT_ANCHOR), ("CONTROL", CONTROL_ANCHOR)):
    if anchor not in original:
      print(f"REFUSED: the {name}'s anchor {anchor!r} is not in {SPEC.relative_to(ROOT)} as it "
            f"stands. THE PLANT IS A TEXT EDIT ON THE WORKING COPY, so an anchor that moved "
            f"means the plant must be re-anchored -- NOT that it should fall back to reading git.")
      return REFUSED
  probe_src = PROBE.read_text()
  imp = "./../tinybendygrad/uop/spec.bend"
  if imp not in probe_src:
    print(f"REFUSED: the plant's probe import {imp!r} is not in {PROBE.relative_to(ROOT)} as it "
          f"stands. Re-anchor the plant; do not fall back to reading git.")
    return REFUSED
  base = rows(run_probe(PROBE)[0])
  if not base:
    print("REFUSED: the unplanted probe printed no rows, so the plant has nothing to move.")
    return REFUSED
  bad = 0
  try:
    # 1. THE PLANT: the dispatch arm that names the new AFTER rule names a different rule,
    #    so the rule is in the table and cannot fire. The `after_alu` rows MUST MOVE.
    PLANT_SPEC.write_text(original.replace(PLANT_ANCHOR, PLANT_EDIT))
    PLANT_PROBE.write_text(probe_src.replace(imp, "./../tinybendygrad/uop/spec-plant.bend"))
    planted = rows(run_probe(PLANT_PROBE)[0])
    moved = {k: (base.get(k), planted.get(k)) for k in base if base.get(k) != planted.get(k)}
    print(f"PLANT    one dispatch arm edited ({PLANT_ANCHOR.strip()} -> {PLANT_EDIT.strip()})")
    print(f"         rows before={base}")
    print(f"         rows after ={planted}")
    print(f"         moved={moved}")
    if not moved:
      print("  THE PLANT DID NOT FIRE: the rows did not move, so this probe cannot see the rule.")
      bad += 1
    if any(not k.startswith("after_alu") for k in moved):
      print("  THE PLANT MOVED THE WRONG ROWS: only the AFTER fixture's rows may move.")
      bad += 1
    # 2. THE CONTROL: a comment, and NOTHING else. The rows MUST NOT MOVE.
    comment_src = original.replace(CONTROL_ANCHOR, CONTROL_EDIT)
    PLANT_SPEC.write_text(comment_src)
    comment = rows(run_probe(PLANT_PROBE)[0])
    same_code = gate._code_only(comment_src) == gate._code_only(original)
    print(f"CONTROL  a whole-line comment added, comment-only={same_code}")
    print(f"         rows before={base}")
    print(f"         rows after ={comment}")
    if comment != base:
      print("  THE CONTROL IS NOT A CONTROL: the rows moved on a comment-only edit.")
      bad += 1
    if not same_code:
      print("  THE CONTROL IS NOT A CONTROL: the edit changed the CODE, so it was not "
            "comment-only -- and a control that edits more than it meant to is not a control.")
      bad += 1
  finally:
    for p in (PLANT_SPEC, PLANT_PROBE):
      if p.exists():
        p.unlink()
  print(f"\n=== plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
  return FAIL if bad else PASS


# --------------------------------------------------------------------------- the map
def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--plant", action="store_true", help="run the plant and its control")
  args = ap.parse_args()
  gate = _specreach_gate()
  if args.plant:
    return plant(gate)
  out, token = run_probe(PROBE)
  if "WITHIN-LIMITS" not in token:
    print(token)
    return REFUSED
  cp = subprocess.run([str(PY), str(ORACLE)], capture_output=True, text=True, cwd=ROOT)
  if cp.returncode != 0:
    print(cp.stderr[-800:])
    return REFUSED
  port = rows(out)
  cpy = rows(cp.stdout)
  differ = 0
  print("# fixture\tkey\tport\tcpython\tagree")
  for fixture in FIXTURES:
    for key in KEYS:
      name = f"{fixture}_{key}"
      pv, cv = port.get(name, "?"), cpy.get(name, "?")
      same = pv == cv
      differ += 0 if same else 1
      print(f"{fixture}\t{key}\t{pv}\t{cv}\t{'yes' if same else 'NO'}")
  print(f"# DIFFER over {len(FIXTURES) * len(KEYS)} cells: {differ}")
  print(f"#   {token.strip()}")
  if differ:
    print(f"\n=== specnew-compare: {differ} cell(s) differ ===")
    return FAIL
  print("\n=== specnew-compare: the port and CPython agree on every cell ===")
  return PASS

# NO `if __name__ == "__main__"` GUARD, and that is deliberate rather than an omission.
# `gates/gates-pop.py` clause I DISCOVERS gates by that AST node, so a census that carries one
# becomes a gate, lands in the ledger, and turns the meta-gate red for the crime of being a
# census. Run this file BY PATH; `raise SystemExit` at top level keeps the exit status.
raise SystemExit(main())
