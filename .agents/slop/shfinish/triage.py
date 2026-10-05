#!/usr/bin/env python3
"""Can each remaining .sh gate RUN here? A migration whose rule is 'the Python reproduces the
shell's verdict on every input' cannot be claimed for a shell nobody can execute, so RUNNABILITY
is the denominator for this batch, and it is measured, not guessed: every path-looking token in
the gate is resolved against disk, and `set -u`-style missing prereqs are listed."""
import os, re, json, sys
ROOT = os.getcwd()
GATES = [p for p in json.load(open(os.path.join(ROOT, ".agents/slop/shfinish/census.json")))["gate_sh"]]
FROZEN = (".agents/slop/substrate/oracle-check.sh", ".agents/slop/substrate-check.sh")
TOK = re.compile(r"(?<![\w./-])((?:\.agents|checks|tinybendygrad|examples|extra|gates|oracles|tinygrad|spec|langs|tools|probe|test|docs|references)/[\w./-]+)")
for g in GATES:
    if g in FROZEN:
        print(f"SKIP frozen/shim  {g}"); continue
    src = open(os.path.join(ROOT, g), encoding="utf-8", errors="replace").read()
    miss = []
    for m in sorted(set(TOK.findall(src))):
        if any(c in m for c in "$*?`\\"): continue
        if not os.path.exists(os.path.join(ROOT, m)):
            miss.append(m)
    nrows = len([l for l in src.splitlines() if l.strip()])
    print(f"{'RUNNABLE?' if not miss else 'MISSING  '} {g}  ({nrows} lines)")
    for m in miss: print(f"        MISSING {m}")
