#!/usr/bin/env python3
"""MEASURE BEFORE LANDING: what would a PERMISSIVE `REF` add to `checks/repro-paths.py`?

The current pattern is a 5-item SUFFIX SET, so a report may name a real path with any other
extension and this instrument cannot see it. The doctrine-shaped replacement is a permissive
extraction intersected with the FILESYSTEM (`os.path.exists`), which needs no list.

A permissive pattern can also pull in prose that merely LOOKS like a path, and every such token
becomes a false DANGLING row. That cost is a NUMBER, so this measures it: same committed reports,
both patterns, the DELTA. Reads only; writes stdout.
"""
import importlib.util
import os
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
_spec = importlib.util.spec_from_file_location("rp", ROOT / "checks" / "repro-paths.py")
rp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rp)

# BOTH PATTERNS ARE SPELLED HERE, INCLUDING THE ONE THIS UNIt REPLACED. Reading the OLD one out of
# `checks/repro-paths.py` would make this probe compare the change to ITSELF the moment it landed --
# MEASURED: after landing it printed 7 lines and `ADDED 0`, which is a green about nothing.
OLD = re.compile(r"(?:^|\s)((?:\.agents/slop/|checks/|gates/)[\w./-]+\.(?:sh|py|bend|mjs|json))")
PERMISSIVE = re.compile(r"(?:^|\s)((?:\.agents/slop/|checks/|gates/)[\w./-]*\.[A-Za-z0-9]+)")


def scan(rx):
    named, patterns = {}, set()
    for rel in rp.committed_reports():
        for m in rx.finditer(rp.report_text(rel)):
            p = m.group(1)
            if rp.PATTERN.search(p):
                patterns.add(p)
            else:
                named.setdefault(p, set()).add(rel)
    return named


reports = rp.committed_reports()
cur, new = scan(OLD), scan(PERMISSIVE)
added = sorted(set(new) - set(cur))
gone = sorted(set(cur) - set(new))
exist = [p for p in added if (ROOT / p).exists()]
dangle = [p for p in added if not (ROOT / p).exists()]

print(f"reports scanned        : {len(reports)}")
print(f"named, OLD suffix set  : {len(cur)}")
print(f"named, permissive      : {len(new)}")
print(f"ADDED by permissive    : {len(added)}   ({len(exist)} resolve, {len(dangle)} would be DANGLING)")
print(f"LOST by permissive     : {len(gone)}")
print(f"  extensions of the {len(added)} added: "
      + ", ".join(f"{e or '<none>'}={n}" for e, n in Counter(os.path.splitext(p)[1] for p in added).most_common(14)))
print(f"  -- the {len(dangle)} would-be DANGLING, i.e. the false-positive risk --")
for p in dangle[:30]:
    print(f"     {p}\n        named by: {', '.join(sorted(new[p])[:2])}")
