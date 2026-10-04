#!/usr/bin/env python3
"""PLANT 2: the sort. The first plant moved nothing because `PINS` is read only by
`unhealthy()`, which `run` never calls -- a statement about the plant, not a pass.

This one plants inside the code path `run` DOES execute and write: the `D2-bytediff.txt`
concatenation order (`differ.py:288-289`). Reversing the sort must reorder the concatenated
report, so `cmp.py` must reject. Same discipline: unique anchor, sha256 before/after, and a
verified restore.
"""
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
SLOP = ROOT / ".agents/slop/differverdict"
WARM = SLOP / "warm"          # use the WARM root: a cold substrate hides everything
TARGET = WARM / "checks/differ.py"

OLD = 'for f in sorted(D.glob("D2-cmp-*.txt")))'
NEW = 'for f in sorted(D.glob("D2-cmp-*.txt"), reverse=True))'

before = hashlib.sha256(TARGET.read_bytes()).hexdigest()
src = TARGET.read_text()
assert src.count(OLD) == 1, f"anchor not unique: {src.count(OLD)}"
TARGET.write_text(src.replace(OLD, NEW))
after = hashlib.sha256(TARGET.read_bytes()).hexdigest()
print(f"planted the SORT. sha256 {before[:16]} -> {after[:16]}  changed={before != after}")
assert before != after

try:
    subprocess.run(["sh", "-c",
                    "rm -rf runs/graphcmp/D && mkdir -p runs/graphcmp/D && "
                    "env -u PYTHONPATH .venv/bin/python checks/differ.py run >/dev/null 2>&1"],
                   cwd=WARM, check=False)
    subprocess.run(["sh", "-c",
                    "rm -rf ../warm-planted && mkdir -p ../warm-planted && "
                    "cp runs/graphcmp/D/* ../warm-planted/"], cwd=WARM, check=False)
    n = len(list((SLOP / "warm-planted").iterdir()))
    print(f"planted run produced {n} files")
finally:
    TARGET.write_text(src)
    back = hashlib.sha256(TARGET.read_bytes()).hexdigest()
    print(f"REVERTED. sha256 {back[:16]}  identical={back == before}")
    assert back == before
    shutil.copy(ROOT / "checks/differ.py", TARGET)
print("warm-root differ.py restored from the canonical source")
sys.exit(0)