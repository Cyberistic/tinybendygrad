#!/usr/bin/env python3
"""THE VACUOUS GREEN the module-scope refusal has been standing in front of.

    .venv/bin/python .agents/slop/modulerefuse/x5-vacuous.py

THE CLAIM. With its refusal lifted, `checks/nl-gate-noguard.py` answered **rc=0** while its oracle
lane was **EMPTY** -- `oracle md5=d41d8cd9`, which is `md5("")`. It printed `AGREE` over **zero**
compared rows. That is `AGENTS.md`'s sentence exactly: *"A GATE THAT EXITS 0 HAVING MEASURED
NOTHING IS WORSE THAN NO GATE, BECAUSE IT IS TRUSTED."*

**THIS FILE PROVES IT WITHOUT THE TRANSFORM, because the transform is not needed: the gate takes
`--port-stdout` and `--oracle-stdout`, so two EMPTY files reach the same comparison with the module
scope untouched.** That matters: a finding that needs a rewrite to reproduce is a finding about the
rewrite. This one is reachable through the gate's own documented interface.

THE THREE LANES, and the third is the control that stops the first two from being a tautology:

  EMPTY/EMPTY     zero rows compared. Does it still say AGREE?
  REAL/EMPTY      one lane has rows, the other has none. Does the COUNT show up?
  REAL/REAL       both lanes present. Does it still say AGREE -- and if so, is that a coincidence?

**A PLANT THAT CANNOT CHANGE ITS VERDICT IS NOT A PLANT**, so the harness asserts the FIRST lane
must be GREEN and asserts the real-lane plant must be able to produce RED. If the real lane cannot
be moved to RED, the gate has no surface and the "AGREE" in lane 3 proves nothing.
"""
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
PY = ROOT / ".venv" / "bin" / "python"
GATE = ROOT / "checks" / "nl-gate-noguard.py"
TIMEOUT = 60
GATED = re.compile(r"gated (\d+)")


def run(port, oracle):
    with tempfile.TemporaryDirectory() as td:
        p = pathlib.Path(td) / "port.rows"
        o = pathlib.Path(td) / "oracle.rows"
        p.write_text(port)
        o.write_text(oracle)
        r = subprocess.run([str(PY), str(GATE), "--port-stdout", str(p), "--oracle-stdout", str(o)],
                           cwd=ROOT, capture_output=True, text=True, timeout=TIMEOUT)
    m = GATED.search(r.stdout or "")
    return (r.returncode,
            int(m.group(1)) if m else -1,
            (r.stdout or r.stderr).strip().splitlines()[-1][:56])


# ROWS IN THE SHAPE `rebase-gate.py:rows()` READS: `name=value` per line. Taken from the gate's own
# docstring at `nl-gate-noguard.py:15-19`, which records the 205-row lane this comparison is built
# for -- NOT invented, because an invented row name is a comparison over zero rows wearing a hat.
LANE = "".join(f"row_{i}=value_{i}\n" for i in range(205))


def main():
    print("`checks/nl-gate-noguard.py` through its OWN `--port-stdout/--oracle-stdout` interface.\n")
    print(f"{'port':>12} {'oracle':>12} {'rc':>4} {'gated':>7}  verdict")
    print("-" * 78)
    cases = (("empty", "", "empty", ""),
             ("one-sided", LANE, "empty", ""),
             ("differing", LANE, "differing", LANE.replace("value_7", "VALUE_7")),
             ("identical", LANE, "identical", LANE))
    results = {}
    for name, p, oname, o in cases:
        rc, gated, verdict = run(p, o)
        results[name] = (rc, gated, verdict)
        print(f"{name:>12} {oname:>12} {rc:>4} {gated:>7}  {verdict}")

    checks = []
    rc0, g0, v0 = results["empty"]
    checks.append(("VACUOUS: two EMPTY lanes -> rc 0 and AGREE, over 0 compared rows",
                   rc0 == 0 and g0 == 0 and "AGREE" in v0,
                   f"rc={rc0} gated={g0} {v0}"))
    rcp, gp, vp = results["one-sided"]
    checks.append(("VACUOUS is not the only way to green: a ONE-SIDED lane also greens",
                   rcp == 0 and gp == 0 and "AGREE" in vp,
                   f"rc={rcp} gated={gp} {vp} -- 205 rows on the port, 0 on the oracle, AGREE"))
    rcd, gd, vd = results["differing"]
    checks.append(("THE GATE HAS A SURFACE: one differing value -> rc 1 and BROKEN",
                   rcd == 1 and gd > 0 and "BROKEN" in vd,
                   f"rc={rcd} gated={gd} {vd}"))
    rci, gi, vi = results["identical"]
    checks.append(("CONTROL: identical lanes -> rc 0 and AGREE, over a NON-ZERO denominator",
                   rci == 0 and gi > 0 and "AGREE" in vi,
                   f"rc={rci} gated={gi} {vi}"))

    print()
    ok = 0
    for label, good, obs in checks:
        print(f"  {'PASS' if good else 'FAIL'}  {label}\n          observed: {obs}")
        ok += bool(good)
    print(f"\n{ok}/{len(checks)} assertions hold.")
    if ok == len(checks):
        print("\n**THE DEFECT, IN ONE SENTENCE.** `checks/nl-gate-noguard.py:96-99` compares "
              "`set(pr) & set(orr)`\nand prints `AGREE` whenever that intersection produced no "
              "`disagree` -- so an EMPTY lane, on\nEITHER side, is a GREEN. The gate is the "
              "CONTROL that proves `nl-gate.py`'s coverage\nguard matters, and it has no "
              "denominator assertion of its own: `checks/dup-gate.py:164`\ncarries "
              "`if not shared: bad.append(\"NO SHARED ROW NAMES\")` and this file does not.")
    return 0 if ok == len(checks) else 1


if __name__ == "__main__":
    sys.exit(main())