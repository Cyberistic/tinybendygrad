"""CAN THE CENSUS STILL GO RED? -- a plant that ASSERTS the instrument is alive.

THE QUESTION. `checks/e2e.py:543` said `== 5/5` and `:555` said `== 6/6` in a gate that emits seven
stages. Both are now `n/7`. **THE DANGER OF A FIX THAT MAKES A CHECK GO GREEN IS THAT THE CHECK WAS
ALREADY DEAD**, and the warning is not theoretical here: a prior plant in this tree "made the lane emit
nothing while the check scored it as a successful plant". So this plant does not report, it ASSERTS.

EVERY PLANT BELOW INVERTS THE ASSERTION, WHICH IS WHAT MAKES IT ABLE TO FAIL:

  A. PRE-FIX BYTES (planting `5/5`,`6/6` back into a SCRATCH copy). The census MUST be RED and MUST
     name stages 5 and 6. If it is green, the census cannot see this defect and the fix proves nothing.
  B. A DENOMINATOR **THIS FIX NEVER TOUCHED** (`4/7` -> `4/6` in a scratch copy). The census MUST be
     red on stage 4. This is the anti-keyed-to-my-two-strings control: a census that only knows the
     strings I fixed would pass this.
  C. THE LIVE BYTES. The census MUST lose A's two findings and B's finding. If it did not, the fix
     did not travel.

THE SCRATCH COPIES ARE WRITTEN TO A TEMP DIRECTORY AND THE LIVE TREE IS NEVER MUTATED, so this is
`$SAFE TO RUN WITH NOTHING ELSE COMPILING`: it starts no compiler, no browser, no `bend`, and it reads
`checks/e2e.py` only through argv. `verdicts.py` takes `[TRANSCRIPT] [GATE]`, so planting is a PATH,
which is the cheapest possible instrument -- there is no file to restore and nothing to leak into the
working copy if the process dies mid-run.

    usage: .venv/bin/python .agents/slop/e2edenom/plant.py      # rc 0 iff every plant fired
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PY = str(REPO / ".venv/bin/python")
CENSUS = REPO / ".agents/slop/e2estage8/verdicts.py"
TRANSCRIPT = REPO / ".agents/slop/e2epy/artifacts/live.port.out"
GATE = REPO / "checks/e2e.py"

# THE DENOMINATOR ROW, AND IT IS THE ONLY LINE THIS PARSES. `verdicts.py` prints
# `gate SAYS 7 denominator(s), from the gate source: 1->7 ...` and that row is what it derived FROM
# THE GATE'S OWN `say("== n/m` LITERALS -- so it is the finding under test, not a proxy for it.
SAYS = re.compile(r"^--- gate SAYS .*: (.*)$", re.M)
FAIL = re.compile(r"^DENOMINATOR FAIL: (.*)$", re.M)


def census(gate: Path) -> tuple[int, str, list[str], str]:
    """`(rc, the gate-SAYS row, the findings, the transcript)`, all from ONE run of the instrument."""
    p = subprocess.run([PY, str(CENSUS), str(TRANSCRIPT), str(gate)], cwd=REPO,
                       capture_output=True, text=True)
    out = p.stdout + p.stderr
    says = SAYS.search(out)
    return p.returncode, (says.group(1) if says else "<no gate SAYS row>"), FAIL.findall(out), out


def planted(text: str, old: str, new: str, where: str) -> str:
    """A one-site edit that REFUSES to be silent: zero matches is a failed plant, not a passing one."""
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"PLANT {where}: expected exactly 1 occurrence of {old!r}, found {n} -- "
                         "the text this plant was written against has moved")
    return text.replace(old, new)


def main() -> int:
    live = GATE.read_text()
    # PLANT A IS THE PRE-FIX BYTES, TAKEN FROM HEAD RATHER THAN REBUILT, so "pre-fix" is not a
    # reconstruction this script could get wrong in the same direction as the fix it is testing.
    pre = subprocess.run(["git", "show", "HEAD:checks/e2e.py"], cwd=REPO,
                         capture_output=True, text=True, check=True).stdout
    if "== 5/5" not in pre or "== 6/6" not in pre:
        raise SystemExit("PLANT A: HEAD no longer carries the pre-fix defect, so this control is void")

    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="e2edenom-") as td:
        td = Path(td)
        gates = {
            "A pre-fix bytes": td / "A.py",
            "B untouched denominator 4/7 -> 4/6": td / "B.py",
            "C the live bytes": td / "C.py",
        }
        gates["A pre-fix bytes"].write_text(pre)
        gates["B untouched denominator 4/7 -> 4/6"].write_text(
            planted(live, 'say("== 4/7 gate"', 'say("== 4/6 gate"', "B"))
        gates["C the live bytes"].write_text(live)

        rows = {label: census(g) for label, g in gates.items()}

        for label, (rc, says, fails, _out) in rows.items():
            print(f"--- {label}: rc={rc}, {len(fails)} finding(s)")
            print(f"      gate SAYS {says}")
            for f in fails:
                print(f"      FAIL {f[:96]}")

        # A: THE INSTRUMENT MUST SEE THE DEFECT WE JUST FIXED.
        _, says_a, fails_a, _ = rows["A pre-fix bytes"]
        if "5->5" not in says_a or "6->6" not in says_a:
            failures.append(f"A: gate SAYS is {says_a!r}; the planted pre-fix denominators are absent, "
                            "so plant A did not take and this control measured nothing")
        if not any("stage 5" in f and "5/5" in f for f in fails_a):
            failures.append("A: the census did NOT report stage 5's `5/5` -- IT IS NOT LOOKING")
        if not any("stage 6" in f and "6/6" in f for f in fails_a):
            failures.append("A: the census did NOT report stage 6's `6/6` -- IT IS NOT LOOKING")

        # B: AND IT MUST SEE A WRONG DENOMINATOR IN A PLACE THIS FIX NEVER WENT.
        _, says_b, fails_b, _ = rows["B untouched denominator 4/7 -> 4/6"]
        if "4->6" not in says_b:
            failures.append(f"B: gate SAYS is {says_b!r}; the 4/6 plant did not take")
        if not any("stage 4" in f and "4/6" in f for f in fails_b):
            failures.append("B: the census did NOT report stage 4's `4/6` -- it is keyed to the two "
                            "strings this fix happened to touch")

        # C: AND THE FIX MUST HAVE TRAVELLED -- the same instrument, same transcript, two fewer banners.
        _, says_c, fails_c, _ = rows["C the live bytes"]
        if re.sub(r"\s+", "", says_c) != "1->72->73->74->75->76->77->7":
            failures.append(f"C: gate SAYS is {says_c!r}; the live banners are not all n/7")
        for gone, f in (("5/5", "5/5"), ("6/6", "6/6")):
            if any(gone in x and "own banner" in x for x in fails_c):
                failures.append(f"C: the census STILL reports the {gone} banner defect against the live file")

    print()
    if failures:
        print("PLANT FAILED -- the census did not behave as a gate:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("PLANT OK -- A and B both went RED, so this green is a FIX and not a DEAD INSTRUMENT; "
          "C lost exactly the two banner findings.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
