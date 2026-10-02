#!/usr/bin/env python3
"""DIFF THE WHOLE `name=value` LINE for `renderer/amd/dsl.bend`.

WHY WHOLE LINES. Two units lost complete mutation tables to a harness that
compared ROW NAMES: a name-comparing harness reported 0 for all 30 mutations in
one unit and 0 for all 68 in another, because every row kept its name and only
its value moved. So this reads `name=value`, splits ONCE at the first `=`, and
compares the two halves. The value is the thing under test; the name is only
there to say which fact.

A row present in ONE side and not the other is a MISSING or an EXTRA and is
always a failure -- a silent drop is how a gate turns green by printing less.

    usage: .venv/bin/python .agents/slop/dsl_gate.py [--mutate FILE REGEX REPL]
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BEND = ROOT / "bin/bend"
PORT = ROOT / "tinybendygrad/renderer/amd/dsl.bend"
ORACLE = ROOT / ".agents/slop/dsl_oracle.txt"


def run(path):
  r = subprocess.run([str(BEND), str(path)], capture_output=True, text=True)
  return r.stdout + r.stderr


def parse(text):
  out = {}
  for line in text.splitlines():
    if "=" not in line:
      continue
    k, v = line.split("=", 1)
    out[k] = v
  return out


def main():
  if "--mutate" in sys.argv:
    i = sys.argv.index("--mutate")
    src, rx, repl = Path(sys.argv[i + 1]), sys.argv[i + 2], sys.argv[i + 3]
    work = src.with_suffix(".mut.bend")
    body = src.read_text()
    if not re.search(rx, body):
      print(f"MUTATION DID NOT APPLY: {rx}")
      sys.exit(2)
    work.write_text(re.sub(rx, repl, body, count=1))
    print(f"mutated {rx} -> {repl}")
    print(run(work)[:4000])
    return
  port = parse(run(PORT))
  orc = parse(ORACLE.read_text())
  bad = []
  for k in sorted(set(port) | set(orc)):
    a, b = port.get(k), orc.get(k)
    if a != b:
      bad.append((k, a, b))
  for k, a, b in bad:
    print(f"MISMATCH {k}\n  port   {a}\n  oracle {b}")
  print(f"rows port={len(port)} oracle={len(orc)} matched={len(set(port) & set(orc))} "
        f"mismatched={len(bad)} missing={len(set(orc) - set(port))} extra={len(set(port) - set(orc))}")
  sys.exit(1 if bad else 0)


main()