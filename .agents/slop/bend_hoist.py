#!/usr/bin/env python3
"""Move a def UP to just before the first def that uses it, until Bend is happy.

Bend 2.0.34 in this repo wants a definition before its first use. The
`.go`-helper and cascade idioms both write the wrapper first and the helper
after, which does not compile; `bend_plus_fix.py` fixes the OTHER error (a
parameter consumed twice) and this one fixes this error. Together they are the
two compile-cycle taxes in this repo, and both are mechanical.

It moves ONE def per run and only ever moves a def EARLIER, so it terminates.

    usage: .venv/bin/python .agents/slop/bend_hoist.py FILE [--bend ./bin/bend]
"""
import re
import subprocess
import sys
from pathlib import Path

path = Path(sys.argv[1])
BEND = sys.argv[3] if len(sys.argv) > 3 else "./bin/bend"
DEF = re.compile(r"(?m)^def ([A-Za-z_][A-Za-z_0-9.]*)\(")
UNFILLED = re.compile(r"expected : a filled definition.*?\n- observed : (\S+)", re.S)


def blocks(text):
  starts = [m.start() for m in DEF.finditer(text)]
  out = []
  for i, st in enumerate(starts):
    en = starts[i + 1] if i + 1 < len(starts) else len(text)
    out.append((DEF.match(text, st).group(1), st, en))
  return out


r = subprocess.run([BEND, str(path), "--check-only"], capture_output=True, text=True)
err = r.stdout + r.stderr
m = UNFILLED.search(err)
if not m:
  print("no unfilled-definition error")
  print("\n".join(err.splitlines()[:8]))
  sys.exit(0 if "ALL PROOFS CHECK" in err else 1)
name = m.group(1)
text = path.read_text()
bs = blocks(text)
head = text[:bs[0][1]]
byname = {n: (s, e) for n, s, e in bs}
names = [n for n, _, _ in bs]
if name not in byname:
  print(f"{name} is not a def in this file (a missing helper?)")
  sys.exit(1)
ms, me = byname[name]
# the USING def is the one Bend named in `Location:`, which is exact. Falling
# back to "the first def that mentions it" picks the wrong one whenever a helper
# and its wrapper both mention it.
loc = re.search(r"(?m)^Location: (\S+)", err)
user = loc.group(1) if loc else None
if user not in byname or user == name:
  user = None
  for n, s, e in bs:
    if n != name and re.search(rf"(?<![\w.]){re.escape(name)}\b", text[s:e]):
      user = n
      break
if user is None or names.index(user) > names.index(name):
  print(f"{name}: already defined before its user, nothing to hoist")
  print("\n".join(err.splitlines()[:8]))
  sys.exit(1)
blk = text[ms:me].rstrip()
# rebuild with the block inserted immediately before `user`
text2 = text[:ms] + text[me:]
us2 = text2.index(f"def {user}(")
path.write_text(text2[:us2] + blk + "\n\n" + text2[us2:])
print(f"{name}: hoisted above {user}")