#!/usr/bin/env python3
"""move `name`'s def block to just above the def called `before`."""
import re, sys
path, name, before = sys.argv[1], sys.argv[2], sys.argv[3]
L = open(path).read().split('\n')
pat = re.compile(r'^def ([A-Za-z_][A-Za-z0-9_.]*)[(<]')

def span(n):
  hits = [i for i, l in enumerate(L) if (m := pat.match(l)) and m.group(1) == n]
  assert len(hits) == 1, (n, hits)
  i = hits[0]; j = i + 1
  while j < len(L) and L[j].startswith((' ', '\t')): j += 1
  while j < len(L) and L[j].strip() == '' and (j + 1 < len(L) and L[j + 1].startswith((' ', '\t'))): j += 1
  return i, j

i, j = span(name)
block = L[i:j]
del L[i:j]
k, _ = span(before)
# the target's own leading comment lines come with it
while k > 0 and L[k - 1].startswith('#'): k -= 1
L[k:k] = block
open(path, 'w').write('\n'.join(L))
print(f"moved {name} above {before} (now line {k + 1})")
