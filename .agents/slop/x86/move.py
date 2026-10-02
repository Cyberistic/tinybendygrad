#!/usr/bin/env python3
"""move.py <DEF> <CALLER> -- put DEF's block immediately above CALLER's, by NAME.

Both names are matched on `def NAME(` EXACTLY, because `def Enc.emit.tail(` and
`def Enc.emit.tail.of(` share a prefix and a prefix match moves the wrong block --
which is what `mv.py`'s `endswith` did for an hour.
"""
import re, sys, pathlib
p = pathlib.Path("tinybendygrad/renderer/isa/x86.bend")
L = p.read_text().split("\n")


def blk(name):
  for i, l in enumerate(L):
    if re.match(rf"^def {re.escape(name)}\(", l):
      j = i + 1
      while j < len(L) and not re.match(r"^(def|type) ", L[j]):
        j += 1
      return i, j
  raise KeyError(name)


a, b = blk(sys.argv[1])
block = L[a:b]
del L[a:b]
caller = sys.argv[2]
if caller.isdigit():
  # a LINE number (the compiler's caret line): walk back to the `def` that owns it
  i = int(caller) - 1
  while i >= 0 and not re.match(r"^(def|type) ", L[i]):
    i -= 1
  at = i
else:
  at = blk(caller)[0]
L[at:at] = block + [""]
p.write_text("\n".join(L))
print(f"moved {sys.argv[1]} above {L[at].split('(')[0]}")
