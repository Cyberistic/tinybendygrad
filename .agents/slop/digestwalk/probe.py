#!/usr/bin/env python3
"""Read-only probe for `checks/differ.py`'s `substrate_digest()`.

It imports `checks/differ.py` (no compile, no `bend`, no corpus loop) and calls the
generator's own function, so the digest measured here is the digest the gate writes.
Nothing here is an oracle: it prints, it never asserts.

USAGE  .venv/bin/python .agents/slop/digestwalk/probe.py [REPS] [GAP_SECONDS]
"""
import importlib.util
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("differ", ROOT / "checks/differ.py")
differ = importlib.util.module_from_spec(spec)
spec.loader.exec_module(differ)

REPS = int(sys.argv[1]) if len(sys.argv) > 1 else 2
GAP = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0

print(f"# ROOT {ROOT}")
print(f"# SUBSTRATE_WALKS {differ.SUBSTRATE_WALKS}")
print(f"# SUBSTRATE_INPUTS {len(differ.SUBSTRATE_INPUTS)}")
rows = []
for i in range(REPS):
    t0 = time.time()
    d = differ.substrate_digest()
    rows.append(d)
    print(f"reading\t{d}\t{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\tnote=call {i + 1} of {REPS}")
    if i + 1 < REPS:
        time.sleep(GAP)

# THE POPULATION, counted, because a digest with no denominator is not a result.
entries = differ.substrate_entries()
walks = [e for e in entries if e[0].split("/")[0] in differ.SUBSTRATE_WALKS]
named = [e for e in entries if e[0].split("/")[0] not in differ.SUBSTRATE_WALKS]
print(f"# entries total {len(entries)} = walk {len(walks)} + named {len(named)}")
print(f"# walk entries unique {len({e[0] for e in walks})}")
print(f"# named entries {len(named)}, ABSENT among them {sum(1 for e in named if e[1] == 'ABSENT')}")
for rel, blob in sorted(named):
    print(f"# named\t{rel}\t{blob[:16]}\t{'ABSENT' if blob == 'ABSENT' else 'present'}")
for w in differ.SUBSTRATE_WALKS:
    sub = [e for e in walks if e[0].startswith(w + "/")]
    print(f"# walk\t{w}\t{len(sub)}\tfiles hashed")
sys.exit(0 if len(set(rows)) == 1 else 1)