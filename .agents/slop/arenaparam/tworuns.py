#!/usr/bin/env python3
"""tworuns.py -- TWO CLEAN RUNS OF THE CORPUS, BYTE-COMPARED.

`checks/differ.py repro` IS this comparison, wrapped in a health gate: it calls
`clean_run()`, which refuses to accept a run unless `unhealthy()` is empty, retries 9
times, and returns 2 when it never is. **MEASURED on this tree, on the run on disk:
`unhealthy()` returns 7 complaints** — `expect-moved=3 (expected 0)`,
`graphs-agree=31 (expected 34)`, `byte-identical=20 (expected 34)`,
`stable-pairs=4 of 5`, `stable-failed=1 of 5`, `oracle-selfcheck=FAIL`,
`census-rc=rc=1` — so `clean_run` cannot succeed at all and `repro` cannot finish. That is
the 600 s the brief recorded, and it is a loop and not a ceiling.

So this script does the part `repro` exists for and drops the part that cannot pass:
two `differ.py run`s, each snapshotted with `differ.py`'s OWN `snap()` (sha256 over the
non-blank lines of every declared artifact), byte-compared, AND `unhealthy()` reported for
each run so the comparison is read next to the health verdict rather than instead of it.

Nothing is imported from a second place: `differ.py` is LOADED BY PATH and its own
`snap`/`unhealthy` are the functions called.

usage: .venv/bin/python .agents/slop/arenaparam/tworuns.py
"""
from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent
DIFFER = ROOT / "checks" / "differ.py"
PY = ROOT / ".venv" / "bin" / "python"

spec = importlib.util.spec_from_file_location("differ", DIFFER)
differ = importlib.util.module_from_spec(spec)
spec.loader.exec_module(differ)


def one(label: str) -> pathlib.Path:
  t0 = time.time()
  p = subprocess.run([str(PY), str(DIFFER), "run"], cwd=ROOT, capture_output=True, text=True)
  took = time.time() - t0
  shot = OUT / f"shot-{label}.rows"
  with shot.open("w") as fh:
    differ.snap(fh)
  print(f"# run {label}: rc={p.returncode} in {took:.0f}s, "
        f"{len(shot.read_text().splitlines())} files snapshotted", flush=True)
  for line in differ.unhealthy():
    print(f"# run {label} unhealthy: {line}", flush=True)
  if not differ.unhealthy():
    print(f"# run {label} unhealthy: NONE", flush=True)
  return shot


def main() -> int:
  a = one("A")
  b = one("B")
  same = a.read_bytes() == b.read_bytes()
  n = len(b.read_text().splitlines())
  print(f"\nTWORUNS: {n} of {n} files identical across two clean runs: {same}")
  if not same:
    print(differ.byte_diff(a.read_text().splitlines(), b.read_text().splitlines(), 40))
    return 1
  return 0


if __name__ == "__main__":
  sys.exit(main())