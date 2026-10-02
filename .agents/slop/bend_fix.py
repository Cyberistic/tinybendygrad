#!/usr/bin/env python3
"""Drive `./bin/bend FILE --check-only` to green: hoist, then mark `+`, forever.

Same as `.agents/slop/bend_drive.py` but INFINITE-LOOP TOLERANT and it prints
only the LAST few edits, because on a large file each compile cycle costs tens
of seconds and a chatty driver buries the signal. `--check-only` exits 1 even on
a clean file (`dtype.bend` has 14 permanently unfilled laws), so the verdict is
the FIRST LINE and never the exit status.

    usage: .venv/bin/python .agents/slop/bend_fix.py FILE [--bend ./bin/bend]
"""
import subprocess
import sys
from pathlib import Path

path = Path(sys.argv[1])
BEND = sys.argv[3] if len(sys.argv) > 3 else "./bin/bend"
HERE = Path(__file__).resolve().parent


def check():
  r = subprocess.run([BEND, str(path), "--check-only"], capture_output=True, text=True)
  return r.stdout + r.stderr


def fix(script):
  r = subprocess.run([sys.executable, str(HERE / script), str(path), "--", BEND],
                     capture_output=True, text=True)
  return r.stdout.strip().splitlines()[0] if r.stdout.strip() else ""


last = []
for i in range(500):
  err = check()
  if "ALL PROOFS CHECK" in err:
    print(f"GREEN after {i} edits; last: {last[-3:]}")
    print(err.splitlines()[0])
    sys.exit(0)
  if "a filled definition" in err:
    msg = fix("bend_hoist.py")
  elif "consumed more than once" in err:
    msg = fix("bend_plus_fix.py")
  else:
    print(f"STOPPED on a non-mechanical error after {i} edits")
    print("\n".join(err.splitlines()[:12]))
    sys.exit(1)
  if msg.startswith("no ") or "declined" in msg:
    print(f"STOPPED: the fixer declined after {i} edits: {msg}")
    print("\n".join(err.splitlines()[:12]))
    sys.exit(1)
  last.append(msg)
print("did not converge in 500 edits")
sys.exit(1)