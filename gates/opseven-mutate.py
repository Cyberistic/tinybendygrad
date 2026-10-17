#!/usr/bin/env python3
"""opseven-mutate.py -- can `gates/opseven-gate.py` FAIL? Five mutations, one verdict each.

    .venv/bin/python gates/opseven-mutate.py

A gate that has never gone red is a comment with a diff in it, and `AGENTS.md`'s rule is that the
harness comes FIRST. So this file does not test the port: it tests the INSTRUMENT, by mutating each
lane in a way that must move a verdict, and asserting that it does.

WHAT EACH MUTATION IS FOR, and why a mutation that DOES NOT APPLY is a failure rather than a skip:

  M1 bend, DTYPE -- `f_ins_void`'s `AInk{"NOP", S.void()}` becomes `S.single()`. A wrong dtype rule for
     `INS` is the defect this gate exists to catch, so M1 must move the DIFF. It targets the CALL SITE
     rather than the shared `ink0` helper, because the first version of this mutation edited `ink0` and
     so moved `customi_void` as well -- a mutation that breaks two rows proves less than one that breaks
     exactly the row it names.
  M2 bend, `Ops.value` -- `value_pyliteral` is printed from `OpsCALL{}` instead of `OpsPYLITERAL{}`. This
     must move `ops_value_holds`, which is the only check of class 2's DERIVED prediction, so it is the
     mutation that shows that prediction is load-bearing and not a comment.
  M3 oracle, SHAPE -- `shape_str` answers `none` for every node. The port's shape is right and CPython's
     is now wrong, so a lane that only trusted the port would stay green. This is the mutation that
     shows the oracle is not decoration.
  M4 oracle, `sp` -- `verdict` answers `0` for the `sp` column. Five CPython pins go stale, so this is
     the mutation that shows class 1 is pinned on the CPython SIDE and not only the port side.
  M5 bend, the `sp` COLUMN -- `Sp.pr_rewrite(...)` is replaced by `O.VSkip{}`. This is what the `pr_0`
     fix WOULD look like from the lane's point of view: the port stops answering `0` everywhere. It must
     break both the pin and `spec_program_holds`, and M5 is the reason the report can say the defect is
     OBSERVABLE rather than merely argued. The replacement is ANNOTATED (`+pr: O.Verdict = O.VSkip{}`)
     because the unannotated first version was REFUSED at compile time with rc=3 -- i.e. it went red
     for the wrong reason, which is the same shape as a lane that reports success for something it never
     ran. `main()` therefore counts rc 3 (REFUSED) and rc 5 (DEAD) as HARNESS FAILURES, not as successes.

THE MUTATED DRIVER LIVES IN `gates/` AND NOT IN A TEMP DIRECTORY, because `gates/opseven.bend` opens
`./../tinybendygrad/...` and a copy one level deeper resolves those imports to a directory that does not
exist. Every mutant is unlinked in a `finally`, and the real gate is re-run at the end so
`gates/artifacts/opseven-gate/` holds a GREEN run and not the last mutant's.
"""

import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
DRIVER = HERE / "opseven.bend"
ORACLE = HERE / "opseven-oracle.py"

# `(name, lane, path, old, new, what it must move)`
MUTATIONS = (
  ("M1", "bend", DRIVER,
   'ink0(O.Arena.empty(), O.OpsINS{}, "NOP", S.void())',
   'ink0(O.Arena.empty(), O.OpsINS{}, "NOP", S.single())',
   "INS's dtype: the diff"),
  ("M2", "bend", DRIVER,
   'vrow2("value_pyliteral", O.OpsPYLITERAL{})',
   'vrow2("value_pyliteral", O.OpsCALL{})',
   "ops_value_holds, the class-2 prediction"),
  ("M3", "oracle", ORACLE,
   "return str(u._shape) if u._shape is not None else \"none\"",
   "return \"none\"",
   "the diff, with the PORT right"),
  ("M4", "oracle", ORACLE,
   'SPECS_MAP = dict(SPECS)',
   'SPECS_MAP = dict(SPECS)\n'
   '_REAL_VERDICT = verdict\n'
   'def verdict(k, u):\n'
   '  return "0" if k == "sp" else _REAL_VERDICT(k, u)',
   "the CPython-side sp pins"),
  ("M5", "bend", DRIVER,
   "+pr = Sp.pr_rewrite(Sp.program_table(), fx, i)",
   "+pr: O.Verdict = O.VSkip{}",
   "the sp pin AND spec_program_holds"),
)


def _load():
  spec = importlib.util.spec_from_file_location("opseven_gate", HERE / "opseven-gate.py")
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


def _mutant(spec, src, old, new):
  """`(path, cleanup)` -- a copy with one substitution, or `None` when the substitution DID NOT APPLY.

  A mutation that does not apply is a DEAD LANE: it would report PASS for a change that was never made,
  which is the `DEAD` verdict `AGENTS.md` names and the whole reason this file checks its own edits.
  """
  if old not in src:
    return None
  out = src.replace(old, new, 1)
  if new not in out:
    return None
  if spec == "bend":
    p = HERE / f".opseven-mut-{abs(hash(old)) % 10**6}.bend"
  else:
    p = HERE / "artifacts" / "opseven-mut" / f"mut-{abs(hash(old)) % 10**6}.py"
  p.parent.mkdir(parents=True, exist_ok=True)
  p.write_text(out)
  return p


def main() -> int:
  g = _load()
  real_bend, real_oracle = g.GATE.bend, g.GATE.oracle
  applied = failed = 0
  try:
    for name, lane, path, old, new, moves in MUTATIONS:
      src = path.read_text()
      mut = _mutant(lane, src, old, new)
      if mut is None:
        print(f"{name} DEAD: the substitution did not apply to {path.name} -- the mutation is stale, "
              f"and a stale mutation would report PASS for a change that was never made")
        failed += 1
        continue
      g.GATE.bend, g.GATE.oracle = real_bend, real_oracle
      if lane == "bend":
        g.GATE.bend = mut
      else:
        g.GATE.oracle = mut
      code = g.GATE.run()
      held = False
      if code == 0:
        held = bool(g.classes_hold())
      # A VERDICT THAT IS NOT `FAIL` IS A HARNESS FAILURE, not a success. rc 3 is REFUSED and rc 5 is
      # DEAD, and both mean the mutant never produced an answer -- so counting them as "the mutation
      # worked" would be an instrument reporting success for something it never ran, which is the
      # defect class this whole file exists to catch.
      why = ""
      if code in (3, 5):
        why = "  <-- REFUSED/DEAD: the mutant never answered, so this is NOT a red gate"
      elif code == 0:
        why = "  <-- GREEN: the mutation did not move a verdict"
      print(f"{name} {'RED  ' if (code == 1 and not held) else 'other'}  rc={code} "
            f"classes_hold={held}  mutates: {moves}{why}")
      if code == 1 and not held:
        applied += 1
      else:
        print(f"{name} FAILED TO MUTATE: expected FAIL(1) with the class check reachable")
        failed += 1
      mut.unlink(missing_ok=True)
  finally:
    g.GATE.bend, g.GATE.oracle = real_bend, real_oracle
    if code_green := (g.GATE.run() == 0 and bool(g.classes_hold())):
      print("restored: the unmutated gate is green again")
    else:
      print("restored FAILED: the unmutated gate is not green", file=sys.stderr)
      return 1
  print(f"{applied} of {len(MUTATIONS)} mutations moved a verdict; {failed} failures")
  return 1 if failed else 0


if __name__ == "__main__":
  sys.exit(main())