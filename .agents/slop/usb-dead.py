#!/usr/bin/env python3
"""DEAD-DEF CHECK for tinybendygrad/runtime/support/usb.bend.

`schedule/indexing.bend`'s three mutations found three functions that were
written, commented, and NEVER CALLED, and a def nothing calls is invisible to
every other check: it cannot break a row and it cannot fix one.

A def is DEAD when no other def and no row mentions its name. The `main` chain is
excluded because it exists only to be called.
"""
import io
import re
import sys

P = sys.argv[1] if len(sys.argv) > 1 else "tinybendygrad/runtime/support/usb.bend"
src = io.open(P).read()
lines = src.split("\n")

names = []
for i, l in enumerate(lines):
    m = re.match(r"^def ([\w.]+)\(", l)
    if m:
        names.append((m.group(1), i))

# Blank only the DEFINING NAME, never the rest of its line: a one-line def calls
# its callees on the same line, and blanking the line reports them dead.
body = "\n".join(re.sub(r"^def ([\w.]+)\(", "def _(", l) for l in lines)
dead = []
for nm, i in names:
    if nm.startswith("main"):
        continue
    # `Def.name` is used as `name(...)` at a call site; the DEF line itself is not
    # in `body`, so any mention at all is a use.
    if not re.search(r"\b" + re.escape(nm) + r"\b", body):
        dead.append((nm, i + 1))
print(f"{len(names)} defs, {len(dead)} dead")
for nm, ln in dead:
    print(f"  DEAD {nm} (line {ln})")
sys.exit(1 if dead else 0)