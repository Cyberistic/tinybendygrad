#!/usr/bin/env python3
"""Measure whether the `(path, must_contain, why)` shape is enough for each cite.

For every cite the resolver already carries a NEEDLE (the semantic anchor the
citing sentence expects). Here we count how many LINES of the target file carry
that needle:

  1  -> the anchor is UNIQUE: the line NUMBER is redundant, drop it (IMMUNE)
  >1 -> the anchor is ambiguous; a number (or a longer anchor) is REQUIRED
  0  -> the anchor is gone: the cite is dead whichever instrument you use
"""
from __future__ import annotations

import re

from resolve import NEEDLE, CHECKS, ROOT, read_lines, port_index, CITE
import os

idx = port_index()

# The TIGHTEST anchor that still names the same thing as the citing sentence.
# Used only for the IMMUNE/NEEDS-NUMBER verdict; the resolver keeps the loose one.
REFINED: dict[tuple[str, int], str] = {
    ("checks/env-precond.py", 308): r'^  getenv_int\("DEBUG", 0\)$',
    ("checks/rn-gate.py", 2693): r"def rnd_row\(",
    ("checks/rn-gate.py", 2763): r"def pu_line\(",
    ("checks/differ.py", 4560): r"def UOp\.mselect",
    ("checks/disagree-gate.py", 1057): r"#   dtype: DType = dtypes\.void",
}


def count(ref: str, needle: str) -> tuple[int, int]:
    pat = re.compile(needle)
    best = 0
    for c in idx.get(os.path.basename(ref), []):
        tl = read_lines(os.path.join(ROOT, c)) or []
        best = max(best, sum(1 for t in tl if pat.search(t)))
    return best, len(idx.get(os.path.basename(ref), []))


print("check_file\tcheck_line\tref\tN\tneedle\tmatches\ttargets\tverdict")
for dirpath, _dirs, files in os.walk(CHECKS):
    for f in sorted(files):
        if not f.endswith((".py", ".sh", ".bend")):
            continue
        rel = os.path.relpath(os.path.join(dirpath, f), ROOT)
        for i, line in enumerate(read_lines(os.path.join(CHECKS, f)) or [], 1):
            for m in CITE.finditer(line):
                ref, num = m.group("ref"), int(m.group("num"))
                needle = REFINED.get((rel, num)) or NEEDLE.get((rel, num))
                if needle is None:
                    print(f"{rel}\t{i}\t{ref}\t{num}\t(NARRATIVE)\t-\t-\tHAND")
                    continue
                n, t = count(ref, needle)
                verdict = "IMMUNE" if n == 1 else ("NEEDS-NUMBER" if n > 1 else "DEAD")
                print(f"{rel}\t{i}\t{ref}\t{num}\t{needle}\t{n}\t{t}\t{verdict}")
