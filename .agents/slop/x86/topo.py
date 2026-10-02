#!/usr/bin/env python3
"""topo.py -- order the defs of a .bend file so every name is declared before use.

Bend refuses a forward reference and reports it as "an unfilled law is a dead claim",
which names the SYMBOL and not the line, so the fix loop for a long file is dozens of
compile cycles. This does it in one pass.

Blocks are a run of comment lines plus the `def`/`type` they document. Dependencies
are every `Ns.name` / `name` the block body mentions that some block DEFINES. The
sort is a stable Kahn walk, so blocks with no dependency between them keep their
written order and the diff stays reviewable.

  usage: .venv/bin/python .agents/slop/x86/topo.py FILE.bend [--check]
"""
import re, sys, pathlib

path = pathlib.Path(sys.argv[1])
check = "--check" in sys.argv
text = path.read_text()
lines = text.split("\n")

# ---- split into blocks ---------------------------------------------------------
blocks, cur = [], []
for l in lines:
    if re.match(r"^(def|type|law)\s", l) and cur and not any(
        re.match(r"^(def|type|law)\s", x) for x in cur):
        blocks.append(cur); cur = [l]
    else:
        cur.append(l)
if cur: blocks.append(cur)
blocks = [b for b in blocks if any(x.strip() for x in b)]

DEF = re.compile(r"^(?:def|type|law)\s+([A-Za-z_][\w.]*)")

def key_of(b):
    for l in b:
        m = DEF.match(l)
        if m: return m.group(1)
    return None

header = blocks[0]
body = [b for b in blocks[1:] if key_of(b)]
trailer = [b for b in blocks[1:] if not key_of(b)]

defined = {key_of(b) for b in body}
CALL = re.compile(r"\b([A-Z][A-Za-z0-9_]*\.[a-z_][\w.]*|Enc\.[a-z_][\w.]*)\b")

def deps(b):
    txt = "\n".join(b)
    out = set()
    for m in CALL.finditer(txt):
        nm = m.group(1)
        if nm in defined and nm != key_of(b): out.add(nm)
    return out

# Kahn, stable by original index
idx = {key_of(b): i for i, b in enumerate(body)}
pending = {key_of(b): deps(b) for b in body}
order = []
left = {i: b for i, b in enumerate(body)}
remaining = {i: set(deps(b)) for i, b in left.items()}
done = set()
while remaining:
    ready = [i for i in remaining if not (remaining[i] - done)]
    if not ready:
        sys.stderr.write("CYCLE among: %s\n" % sorted(
            left[i] and key_of(left[i]) for i in remaining)[:8]); sys.exit(2)
    i = min(ready)
    order.append(left[i]); done.add(key_of(left[i])); del remaining[i]

out = "\n".join(header) + "\n" + "\n\n".join("\n".join(b) for b in order + trailer) + "\n"
if check:
    print("UNCHANGED" if out == text else "WOULD REORDER")
    sys.exit(0 if out == text else 1)
path.write_text(out)
print(f"ordered {len(order)} defs")
