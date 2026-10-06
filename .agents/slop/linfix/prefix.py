#!/usr/bin/env python3
"""prefix.py -- qualify the moved `Opt` types in postrange.bend with `O.`.

The types moved up to uop/ops.bend (which postrange already imports as O), so
every reference in postrange must be qualified. Non-comment lines only, and a
negative lookbehind so an already-qualified `O.OPTARG` is not re-qualified.
"""
import pathlib
import re

p = pathlib.Path("tinybendygrad/codegen/opt/postrange.bend")
src = p.read_text().splitlines(keepends=True)

# longest first so OPS_TC is not clipped by a later rule
NAMES = ["OPTOPS", "OPTARG", "OPS_TC", "OPS_SPLIT", "OPS_PADTO", "OPS_SWAP",
         "OA_NONE", "OA_INT", "OA_SPLIT", "OA_TC", "SPL", "OPT", "TC"]
RULES = [(re.compile(r"(?<![\w.])" + re.escape(n) + r"\b"), "O." + n) for n in NAMES]

out, changed = [], 0
for ln in src:
    if ln.lstrip().startswith("#"):
        out.append(ln)
        continue
    new = ln
    for rx, rep in RULES:
        new = rx.sub(rep, new)
    if new != ln:
        changed += 1
    out.append(new)

p.write_text("".join(out))
print(f"lines changed: {changed} of {len(src)}")
