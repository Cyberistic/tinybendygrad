#!/usr/bin/env python3
"""blob-verify-independent.py -- an INDEPENDENT re-derivation of the nine `blob_*` gate
rows, by a DIFFERENT method from `.agents/slop/blob-intern-oracle.py`.

    .venv/bin/python .agents/slop/blob-verify-independent.py            # upstream tree
    TG_TREE=. .venv/bin/python .agents/slop/blob-verify-independent.py  # vendored pin

WHY A SECOND ORACLE. `agent-core.md`: "Agreement between a port and a hand-typed oracle is
not corroboration; it is one mistake copied." The gate's oracle reads `len(ucache)`, and
this one reads the CACHE KEYS themselves and asks what they contain. If both agree, two
different observations agree.

THE TRAP THIS AVOIDS. `ucache` holds WEAKREFS and `UOp.__del__` (ops.py:248) does
`del ucache[(op, src, arg, tag, type(arg))]` -- deletes BY KEY, BY VALUE. So a cell that
rebinds the name holding a node (`u = UOp(...); u = UOp(...)`) evaluates the right side
first, registers the new key, then releases the old node, whose `__del__` deletes the key
it JUST registered. `len(ucache)` then reads 1 for two DISTINCT blobs -- the exact number
the defect produces. Here every node is appended to `HELD` on creation and the holding name
is never rebound, and the key contents are printed so the claim is checkable by reading.
"""
import os
import sys

TG_TREE = os.environ.get('TG_TREE', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'opstree'))
sys.path.insert(0, TG_TREE)

import tinygrad.uop.ops as O  # noqa: E402
from tinygrad.uop import Ops  # noqa: E402
from tinygrad.uop.ops import UOp  # noqa: E402

HELD: list = []
SWEEP = (b"", b"a", b"ab", b"abc", b"abcd", b"abce")


def intern_pair(x: bytes, y: bytes):
  """Two BINARYs on a FRESH ucache; return (same?, keycount, the two nodes)."""
  O.UOpMetaClass.ucache.clear()
  u = UOp(Ops.BINARY, src=(), arg=x)
  v = UOp(Ops.BINARY, src=(), arg=y)
  HELD.append((u, v))
  return (u is v), len(O.UOpMetaClass.ucache), u, v


def keys_of():
  return sorted(repr(k) for k in O.UOpMetaClass.ucache.keys())


def main() -> None:
  print("== same content: b'aaaa' vs b'aaaa' ==")
  same, n_same, u, _ = intern_pair(b"aaaa", b"aaaa")
  print(f"blob_interns={same}")
  print(f"blob_count_same={n_same}")
  print(f"blob_shape={tuple(u.shape)}")
  print(f"blob_content={','.join(str(b) for b in u.arg)}")
  print(f"  keys={keys_of()}")

  print("== SAME LENGTH, DIFFERENT CONTENT: b'aaaa' vs b'bbbb' (the fixture) ==")
  same2, n_2, _, _ = intern_pair(b"aaaa", b"bbbb")
  print(f"blob_len_diff_content={not same2}")
  print(f"blob_count_len_diff_content={n_2}")
  print(f"  keys={keys_of()}")

  print("== DIFFERENT LENGTH: b'aaaa' vs b'aa' ==")
  same3, _, _, _ = intern_pair(b"aaaa", b"aa")
  print(f"blob_diff_len={not same3}")

  print("== sweep: six distinct blobs, lengths 0,1,2,3,4,4 ==")
  O.UOpMetaClass.ucache.clear()
  pairs = [(UOp(Ops.BINARY, src=(), arg=b), UOp(Ops.BINARY, src=(), arg=b)) for b in SWEEP]
  HELD.extend(pairs)
  n_sweep = len(O.UOpMetaClass.ucache)
  print(f"blob_sweep={all(p is q for p, q in pairs) and n_sweep == len(SWEEP)}")
  print(f"blob_sweep_count={n_sweep}")
  print(f"  keys={keys_of()}")

  print("== why CONTENT, not a digest, and not a length: the facts ==")
  print(f"  b'aaaa'==b'bbbb' -> {b'aaaa' == b'bbbb'}")
  print(f"  hash(b'aaaa')==hash(b'bbbb') -> {hash(b'aaaa') == hash(b'bbbb')}")
  print(f"  len(b'aaaa')==len(b'bbbb') -> {len(b'aaaa') == len(b'bbbb')}")
  print(f"  type(arg) is bytes -> {type(b'aaaa').__name__}")


if __name__ == '__main__':
  main()
