#!/usr/bin/env python3
"""preamble-oracle.py -- the ONE declaration the `kern2` fixture withholds, captured from
LIVE CPython, never typed.

`ClangRenderer.render_vector_prefix(dt, count)` is upstream's own function for this
(`cstyle.py:308-309`) and `_render_defines` is what puts it in front of a body
(`cstyle.py:311`, `cstyle.py:64`). `cstyle.bend`'s `emit_min()` fixture carries an EMPTY
`vecs` list, so the row's own text names a type nothing ever defined -- that is the whole of
§1b of CSTYLE-LIVE, restated as an executable oracle.

  usage: preamble-oracle.py            -> prints ONE line of C
"""
import sys

sys.path.insert(0, ".")
from tinygrad import dtypes  # noqa: E402
from tinygrad.device import Device  # noqa: E402


def main():
  r = Device["CPU"].renderer
  # LIVE call into the CPU backend's own renderer. Not a literal.
  print(r.render_vector_prefix(dtypes.float32, 4), end="")
  return 0


if __name__ == "__main__":
  sys.exit(main())