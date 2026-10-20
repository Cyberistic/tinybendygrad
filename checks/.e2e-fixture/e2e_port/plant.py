#!/usr/bin/env python3
"""e2e_port/plant.py -- APPLY ONE TEXTUAL MUTATION, AND REFUSE A VACUOUS ONE.

    .venv/bin/python plant.py <file> <old> <new>

`e2e_negctl.sh:107` writes its plants inline and `run-kernel.sh:178` has to notice
for itself that a `sed` matched nothing.  A control whose target text is not in the
file reports that fact rather than silently passing -- which is the only reason the
first vacuous control was noticed at all.  So the check is here, once, and it is an
`assert`-shaped refusal: exactly ONE occurrence is required, and any other count is
an error with the count in the message.

A mutation of a DATA VALUE rather than of text (the oracle's `answer_u32[37]`) is a
different shape and is written where it happens, in `run-port-mm.sh`.
"""
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
s = p.read_text()
old, new = sys.argv[2], sys.argv[3]
n = s.count(old)
if n != 1:
    sys.exit(f"VACUOUS PLANT: {p} contains {n} copies of the target text, not 1:\n  {old!r}")
p.write_text(s.replace(old, new))
print(f"    planted {p.name}: 1 site, {len(old)} -> {len(new)} bytes")
