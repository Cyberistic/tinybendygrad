"""bnxtdev.bend -- A `do` BLOCK'S LAST LINE MUST BE A BARE MONADIC ACTION.

    do IO<R>:
      x : T <- action          # a BINDING -- fine anywhere except last
      action                   # the last line: a bare action

A `do` block whose last line is a binding does not terminate, and the parse
error is reported at the NEXT `def`, which reads like the next def is malformed
and is not. This cost several compile cycles on this file and the symptom is
actively misleading, so the rule gets a checker:

    python3 .agents/slop/dobind.py tinybendygrad/runtime/support/rdma/bnxtdev.bend

Run it after every edit that adds or moves a `do` block.
"""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'tinybendygrad/runtime/support/rdma/bnxtdev.bend'
lines = open(path).read().split('\n')
bad = 0
blocks = 0
i = 0
while i < len(lines):
    if re.match(r'^\s*do IO<', lines[i]):
        blocks += 1
        indent = len(lines[i]) - len(lines[i].lstrip())
        j = i + 1
        last = None
        while j < len(lines):
            ln = lines[j]
            if not ln.strip():
                j += 1
                continue
            if len(ln) - len(ln.lstrip()) <= indent:
                break
            last = (j, ln)
            j += 1
        if last is None:
            bad += 1
            print(f"EMPTY do-block opened at line {i + 1}")
        elif '<-' in last[1]:
            bad += 1
            print(f"do-block opened at line {i + 1} ENDS IN A BINDING at line "
                  f"{last[0] + 1}: {last[1].strip()!r}")
            print(f"    the last line must be a bare action; this reports at the "
                  f"NEXT def, which looks like that def is broken")
        i = j
        continue
    i += 1
print(f"{path}: {blocks} do-blocks, {bad} BAD -> "
      f"{'clean after' if bad == 0 else 'FIX THESE'}")
sys.exit(1 if bad else 0)