#!/usr/bin/env python3
"""Add `+` to a parameter Bend says is "consumed more than once".

Bend 2.0.34 requires a consumed binder to be marked `+`, and a def that reads
the same parameter twice (once to build the test, once to build the message) is
easy to write and tedious to fix one compile cycle at a time -- `dsl.bend` took
nine cycles on this alone. This reads the FIRST error, adds the `+`, and repeats
until Bend stops complaining about consumption. It edits ONE parameter of ONE def
per run, so it cannot wander.

    usage: .venv/bin/python .agents/slop/bend_plus_fix.py FILE [--bend ./bin/bend]
"""
import re
import subprocess
import sys
from pathlib import Path

path = Path(sys.argv[1])
BEND = sys.argv[3] if len(sys.argv) > 3 else "./bin/bend"
CONSUME = re.compile(r"expected : (\w+)\s*\n- observed : \1 \(consumed more than once\)")
DEF = re.compile(r"(?m)^def ([A-Za-z_][A-Za-z_0-9.]*)\(")


def first_error():
  r = subprocess.run([BEND, str(path), "--check-only"], capture_output=True, text=True)
  return r.stdout + r.stderr


def def_span(text, name):
  for m in DEF.finditer(text):
    if m.group(1) == name:
      i = text.index("(", m.start())
      depth, j = 0, i
      while j < len(text):
        if text[j] == "(":
          depth += 1
        elif text[j] == ")":
          depth -= 1
          if depth == 0:
            return i, j
        j += 1
  return None


err = first_error()
m = CONSUME.search(err)
if not m:
  print("no consumption error")
  print(err.splitlines()[:8])
  sys.exit(0 if "ALL PROOFS CHECK" in err else 1)
param = m.group(1)
name = re.search(r"(?m)^Location: (\S+)", err).group(1)
text = path.read_text()
span = def_span(text, name)
if span is None:
  print(f"cannot locate def {name}")
  sys.exit(1)
lo, hi = span
params = text[lo:hi]
new = re.sub(rf"(?<![\w+]){re.escape(param)}\s*:", f"+{param}:", params, count=1)
if new == params:
  print(f"{name}: no bare `{param}:` to mark")
  sys.exit(1)
path.write_text(text[:lo] + new + text[hi:])
print(f"{name}: marked +{param}")