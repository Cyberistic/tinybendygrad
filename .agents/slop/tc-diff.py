#!/usr/bin/env python3
"""tc-diff.py -- compare the Bend run against the CPython oracle, WHOLE
`name=value` LINES and never row names.

The oracle files are `.agents/slop/tc-rows-coef.txt` (from `tc-gen.py rows`) and
`.agents/slop/tc-rows-value.txt` (from `tc-value.py`).  A row the Bend file does
not print is a MISSING row and is reported as such, because a missing row and a
right row look identical in a name-only diff.
"""
import sys

BEND = '.agents/slop/tc-rows-bend.txt'
ORACLE = ['.agents/slop/tc-rows-coef.txt', '.agents/slop/tc-rows-value.txt']


def load(path):
  d = {}
  for L in open(path):
    L = L.rstrip('\n')
    if '=' not in L or L.startswith(('SOME', 'ALL', 'Error', '-', 'Location',
                                    'Use ', '  ')):
      continue
    k, v = L.split('=', 1)
    d[k] = v
  return d


def main():
  bend = load(BEND)
  orc = {}
  for p in ORACLE:
    orc.update(load(p))
  same = [k for k in orc if k in bend and bend[k] == orc[k]]
  diff = [(k, orc[k], bend[k]) for k in orc if k in bend and bend[k] != orc[k]]
  miss = [k for k in orc if k not in bend]
  extra = [k for k in bend if k not in orc]
  print(f'oracle rows : {len(orc)}')
  print(f'bend rows   : {len(bend)}')
  print(f'agree       : {len(same)}')
  print(f'DISAGREE    : {len(diff)}')
  print(f'missing     : {len(miss)}')
  print(f'extra       : {len(extra)}')
  for k, o, b in sorted(diff):
    print(f'  DIFF {k}: oracle={o} bend={b}')
  for k in sorted(miss)[:80]:
    print(f'  MISS {k} (oracle={orc[k]})')
  for k in sorted(extra)[:40]:
    print(f'  EXTRA {k}={bend[k]}')


if __name__ == '__main__':
  main()