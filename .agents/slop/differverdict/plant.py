#!/usr/bin/env python3
"""THE PLANT. A comparison that has never rejected anything is not a comparison.

I plant a change in `checks/differ.py` that this project's own rule forbids -- a pin moved
to match the code -- and ask whether cmp.py catches it. The pins at differ.py:128 are the
ones the brief says were "all stale and had to be repinned"; moving one is exactly the
"a pin moved to match the code is a gate deleted" shape.

The plant is reverted in the same breath, and the revert is verified by sha256, because a
swap-and-restore in a file other agents share is a blind spot (REACH.md, FLIPR unit).
"""
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
TARGET = ROOT / ".agents/slop/differverdict/root/checks/differ.py"
SLOP = ROOT / ".agents/slop/differverdict"

OLD = '"not-comparable": "0",'
NEW = '"not-comparable": "16",'   # the value the cold substrate actually produces

before = hashlib.sha256(TARGET.read_bytes()).hexdigest()
src = TARGET.read_text()
assert src.count(OLD) == 1, f"plant anchor not unique: {src.count(OLD)}"
print(f"anchor found {src.count(OLD)}x; editing {TARGET.relative_to(ROOT)}")
TARGET.write_text(src.replace(OLD, NEW))
after = hashlib.sha256(TARGET.read_bytes()).hexdigest()
print(f"sha256 before={before[:16]}  after={after[:16]}  changed={before != after}")
assert before != after, "the plant did not change the file -- the edit is a no-op"

# Run the Python driver over the planted code and let cmp.py judge it against the oracle.
subprocess.run(["sh", "-c", "cd root && rm -rf runs/graphcmp/D && mkdir -p runs/graphcmp/D && "
                "env -u PYTHONPATH .venv/bin/python checks/differ.py run >/dev/null 2>&1"],
               cwd=SLOP, check=False)
rc = subprocess.run(["rm", "-rf", "python-planted"], cwd=SLOP, check=False)
subprocess.run(["sh", "-c", "mkdir -p python-planted && cp root/runs/graphcmp/D/* python-planted/"],
               cwd=SLOP, check=False)
print(f"planted run rc={rc.returncode}")

try:
    TARGET.write_text(src)
    restored = hashlib.sha256(TARGET.read_bytes()).hexdigest()
    print(f"REVERTED. sha256 now={restored[:16]}  identical_to_original={restored == before}")
    assert restored == before, "the restore did not reproduce the original bytes"
finally:
    shutil.copy(ROOT / "checks/differ.py", TARGET)  # belt and braces: the canonical source
    assert hashlib.sha256(TARGET.read_bytes()).hexdigest() == hashlib.sha256(
        (ROOT / "checks/differ.py").read_bytes()).hexdigest()
print("differ.py in the scratch root is byte-identical to checks/differ.py again")