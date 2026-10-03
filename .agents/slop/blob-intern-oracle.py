#!/usr/bin/env python3
"""blob-intern-oracle.py -- the CPython lane for the `blob_*` rows of
`tinybendygrad/uop/ops.bend`. Driven by `.agents/slop/blob-intern-gate.sh`, which diffs
these rows against the Bend's interpreted AND native lanes.

    .venv/bin/python .agents/slop/blob-intern-oracle.py                # upstream tree
    TG_TREE=. .venv/bin/python .agents/slop/blob-intern-oracle.py      # the vendored pin

THE QUESTION. `Arg` spelled a BINARY's `bytes` as `ABlob{n: U32}` -- the LENGTH -- and
`eq_arg.ABlob` compared `n`, so two DIFFERENT blobs of the same length were one ucache
key and one arena node. `tinygrad/uop/ops.py:201` keys on
`(op, src, arg, tag, type(arg))`, so the key holds the `arg` OBJECT and dict equality
compares `bytes` CONTENT-WISE. Measured on the pristine port (hash d662cccb): two
4-byte blobs interned to arena index `1,1` with `Arena.next - 1 == 1`.

THE FIXTURE IS THE TEST. `b"aaaa"` against `b"bbbb"`: EQUAL LENGTH, UNEQUAL CONTENT. A
fixture of DIFFERENT lengths is satisfied by a length key, which is why the bug sat in a
green gate -- and it is also why the third cell (`b"aa"`, a different length) is kept:
"different length" and "different content" are separate claims and a port can pass one
while failing the other.

EVERY `blob_*` ROW IS A MEASUREMENT TAKEN BY CALLING CPYTHON, never a literal: each
`cell` returns what it observed and the nine gate rows are printed from those returns.
The `blobdiag_*` rows are the raw per-cell facts, printed so that a reader can see WHICH
call produced a gate row rather than being asked to trust a number.

MEASURED TRAP, in this file's own first draft, and it is the same wrong answer as the
bug under test: `ucache` holds WEAKREFS and `UOp.__del__` (ops.py:248) does
`del ucache[(op, src, arg, tag, type(arg))]`. So `u = UOp(...a); u = UOp(...b)`
evaluates the right side FIRST, registering b's key, and only then releases the old `u`
-- whose `__del__` deletes a key BY VALUE and so deletes the key it just registered. A
node count measured that way reads 1 for two DISTINCT blobs. Every cell here keeps its
nodes alive in `KEEP` and never rebinds the holding name.
"""
import os
import sys

TG_TREE = os.environ.get('TG_TREE', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'opstree'))
sys.path.insert(0, TG_TREE)

import tinygrad.uop.ops as O  # noqa: E402
from tinygrad.uop import Ops  # noqa: E402
from tinygrad.uop.ops import UOp  # noqa: E402

# The sweep: six DISTINCT blobs whose lengths run 0,1,2,3,4,4 -- the LAST TWO ARE THE
# SAME LENGTH AND DIFFERENT CONTENT, which is the point. Measured: with six DISTINCT
# lengths a length-summary key passes the sweep outright, so the equal-length tail is
# what makes the sweep see the same claim `blob_len_diff_content` makes.
SWEEP = (b"", b"a", b"ab", b"abc", b"abcd", b"abce")

# every node ever made, so nothing is collected while a count is being read
KEEP: list = []


class Cell:
  """One pair of BINARYs interned on a FRESH ucache, and what was observed about them."""

  def __init__(self, label: str, x: bytes, y: bytes):
    O.UOpMetaClass.ucache.clear()
    self.u, self.v = UOp(Ops.BINARY, src=(), arg=x), UOp(Ops.BINARY, src=(), arg=y)
    KEEP.append((self.u, self.v))
    self.label, self.count = label, len(O.UOpMetaClass.ucache)
    print(f"blobdiag_is_{label}={self.u is self.v}")
    print(f"blobdiag_count_{label}={self.count}")
    print(f"blobdiag_arg_{label}={','.join(str(b) for b in self.u.arg)},"
          f"{','.join(str(b) for b in self.v.arg)}")
    print(f"blobdiag_shape_{label}={tuple(self.u.shape)}")

  @property
  def same(self) -> bool:
    return self.u is self.v


def sweep() -> None:
  """The port's `blob_sweep` / `blob_sweep_count` over `SWEEP`, answered the same way.

  Each blob is interned TWICE and both nodes must be the same one, and the i-th DISTINCT
  blob must get a node of its own -- which is what `len(ucache)` measures.
  """
  O.UOpMetaClass.ucache.clear()
  pairs = [(UOp(Ops.BINARY, src=(), arg=b), UOp(Ops.BINARY, src=(), arg=b)) for b in SWEEP]
  KEEP.extend(pairs)
  print(f"blob_sweep={all(u is v for u, v in pairs) and len(O.UOpMetaClass.ucache) == len(SWEEP)}")
  print(f"blob_sweep_count={len(O.UOpMetaClass.ucache)}")


def content_semantics() -> None:
  """Why CONTENT and not a digest, read off the live objects rather than argued."""
  print(f"blobdiag_bytes_eq={b'aaaa' == b'bbbb'}")
  print(f"blobdiag_bytes_hash_eq={hash(b'aaaa') == hash(b'bbbb')}")
  print(f"blobdiag_type={type(b'aaaa').__name__}")
  # `type(arg)` is the fifth key component, so bytes and tuple-ints are DIFFERENT keys
  # upstream. The port has one `ABlob` arm for both plus MSELECT's int, which is a
  # separate and already-recorded infidelity (the TODO on `UOp.mselect`).
  print(f"blobdiag_type_differs_from_tuple={type(b'aaaa') is not type((1, 2))}")


if __name__ == '__main__':
  same_content = Cell("same_content", b"aaaa", b"aaaa")
  len_diff = Cell("same_len_diff_content", b"aaaa", b"bbbb")
  diff_len = Cell("diff_len", b"aaaa", b"aa")

  print(f"blob_interns={same_content.same}")
  print(f"blob_len_diff_content={not len_diff.same}")
  print(f"blob_diff_len={not diff_len.same}")
  print(f"blob_count_same={same_content.count}")
  print(f"blob_count_len_diff_content={len_diff.count}")
  print(f"blob_shape={tuple(same_content.u.shape)}")
  print(f"blob_content={','.join(str(b) for b in same_content.u.arg)}")
  sweep()
  content_semantics()