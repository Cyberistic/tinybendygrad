#!/usr/bin/env python3
"""Drive `./bin/bend FILE --check-only` to green through the two mechanical
compile-cycle taxes, then print the verdict.

  * "expected : a filled definition ... observed : X"  -> hoist X above its user
    (`.agents/slop/bend_hoist.py`)
  * "observed : X (consumed more than once)"           -> mark `+X`
    (`.agents/slop/bend_plus_fix.py`)

Both edits are single-parameter / single-def, so this cannot wander; and it
STOPS on any other error rather than looping, because an unexpected error is
information, not a tax to pay.

`--check-only` exits 1 even on a clean file when `dtype.bend` has unfilled laws
(14 of them, permanently), so the verdict is the FIRST LINE and never the status.

    usage: .venv/bin/python .agents/slop/bend_drive.py FILE [--bend ./bin/bend]
"""
import subprocess
import sys
from pathlib import Path

path = Path(sys.argv[1])
BEND = sys.argv[3] if len(sys.argv) > 3 else "./bin/bend"
HERE = Path(__file__).resolve().parent


def run(script):
  return subprocess.run([sys.executable, str(HERE / script), str(path), "--", BEND],
                        capture_output=True, text=True).stdout


for i in range(400):
  r = subprocess.run([BEND, str(path), "--check-only"], capture_output=True, text=True)
  err = r.stdout + r.stderr
  if "ALL PROOFS CHECK" in err:
    print(f"GREEN after {i} edits")
    print(err.splitlines()[0])
    sys.exit(0)
  if "a filled definition" in err:
    out = run("bend_hoist.py")
  elif "consumed more than once" in err:
    out = run("bend_plus_fix.py")
  else:
    print(f"STOPPED on a non-mechanical error after {i} edits")
    print("\n".join(err.splitlines()[:12]))
    sys.exit(1)
  if "no " in out.splitlines()[0] if out.splitlines() else True:
    print(f"STOPPED: the fixer declined after {i} edits")
    print(out.strip()[:400])
    print("\n".join(err.splitlines()[:12]))
    sys.exit(1)
  print(out.splitlines()[0])
print("did not converge in 400 edits")
sys.exit(1)