#!/usr/bin/env python3
"""blob-fix-toggle.py -- put the BLOB FIX in, or take it out, with the rest of the tree
held still, so `blob-rows.py` can measure the fix's blast radius and NOTHING ELSE's.

    .venv/bin/python .agents/slop/blob-fix-toggle.py --build   # write both variants
    .venv/bin/python .agents/slop/blob-fix-toggle.py off       # fix OUT
    .venv/bin/python .agents/slop/blob-fix-toggle.py on        # fix IN
    .venv/bin/python .agents/slop/blob-fix-toggle.py --restore # fix IN, unconditionally

WHY THIS EXISTS. A concurrent agent landed ~130 lines of `s5` "MOVERS, ROUND TWO" into
`tinybendygrad/uop/ops.bend` DURING this unit and had them rebased out again; they also
reverted this file once underneath it (another agent's `jj restore`, hash d662cccb ->
ff233f8e), which removed the first application of the fix. So any `before`/`after`
pair of whole-tree snapshots straddles somebody else's edit and the diff cannot be
attributed.

So both variants are built ONCE from the SAME current file by applying or
reverse-applying exactly this unit's edits, and the two variants are stored here rather
than in `$TMPDIR` -- an oracle in `$TMPDIR` has been gone before the commit and its
comparison became unreproducible.

The edits are the EIGHT the fix consists of, written out as literal pairs rather than
as markers, so the reversal needs nothing but this script:
  1 the `Arg` doc comment for `ABlob`
  2 the `ABlob` FIELD TYPE (`n: U32` -> `bs: List<&2, U32>`)
  3 the `eq_arg.ABlob` comment and body
  4 `eq_arg.sel`'s `ABlob` arm
  5 `UOp.mselect`'s comment and construction
  6 the BLOB helper block (inserted)
  7 the `main` wiring (inserted)
  8 `s5.ga.arena`'s MSELECT node -- OPTIONAL, because a concurrent agent's version of
    that fixture came and went inside this unit; absent from a tree is not an error.
"""
import os
import patch_not_apply as PNA
import shutil
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SLOP = os.path.join(REPO, '.agents/slop')
REAL = os.path.join(REPO, 'tinybendygrad/uop/ops.bend')
ON = os.path.join(SLOP, 'ops-blob-on.bend')
OFF = os.path.join(SLOP, 'ops-blob-off.bend')

BLOB_BANNER = "# ---------------------------------------------------------------------------\n# BLOB --"
MSTACK_BANNER = "# ---------------------------------------------------------------------------\n# MSTACK -- ops.py:770"
WIRING = "    # --- THE BLOB LANE."

DOC_ON = """#   bytes                   ABlob      BINARY arg; the BYTES themselves, as a list of
#                                     byte values. `ops.py:201`'s key holds the `bytes`
#                                     OBJECT, so the key compares CONTENT -- see the
#                                     BLOB block above `t_blob_*` for the measurement
#                                     and for why `ABlob{n: U32}` was wrong."""
DOC_OFF = "#   bytes                   ABlob      BINARY arg; only its length is read"

EQ_ON = """# CONTENT, NOT A SUMMARY. This arm used to compare `U32.is_eq(n, y1)` on an
# `ABlob{n: U32}` -- the LENGTH -- and two different same-length blobs were then the
# same ucache key: ONE node where `ops.py:201`'s key, which holds the `bytes` object
# and lets dict equality compare bytes content-wise, has two. Measured on the pristine
# tree before the fix: two BINARY nodes with 4-byte args interned to arena index `1,1`
# and `Arena.next - 1 == 1`; CPython answers `False` and `2`. `eq_u32` is the file's
# structural list equality -- the SAME def `eq_arg.ATuple` and `eq_tag.TTuple` compare
# with, so a blob is compared exactly as an axis tuple or a tag tuple is: elementwise,
# order-sensitive, and length-sensitive because the empty/non-empty cases are arms.
def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: eq_u32(bs, y1)
    case _: False{}"""
EQ_OFF = """def eq_arg.ABlob(y: Arg, +n: U32) -> Bool:
  match y:
    case ABlob{y1}: U32.is_eq(n, y1)
    case _: False{}"""

MSEL_ON = """# `mselect` -- ops.py:772. `UOp(Ops.MSELECT, src=(self,), arg=arg)` where `arg` is
# an INT -- a shard index into a multi-device tensor. `ABlob` is the arena's existing
# "a bare number in the arg" arm, and reusing it is the honest choice over minting a new
# one: MSELECT's arg is a number and nothing else reads it. Since `ABlob` now holds BYTES
# rather than a length, the int is the ONE-BYTE blob `[k]` -- which is injective in `k`,
# so two different shard indices are still two different keys, and it is what the key
# needs since `eq_arg.ABlob` reads content. The op is in the key too, so an MSELECT's
# `[k]` can never collide with a BINARY's bytes.
# TODO(p3): `type(arg)` in `ops.py:201` separates an `int` arg from a `bytes` one and
# this arm does not; if a later unit must tell them apart ON ONE NODE that is a NEW `Arg`
# arm and `eq_arg` grows an arm with it."""
MSEL_OFF = """# `mselect` -- ops.py:772. `UOp(Ops.MSELECT, src=(self,), arg=arg)` where `arg` is
# an INT -- a shard index into a multi-device tensor. `ABlob{n: U32}` is the
# arena's existing "a bare U32 in the arg" arm, and reusing it is the honest
# choice over minting a new one: MSELECT's arg is a number and nothing else reads
# it. TODO(p3): if a later unit must tell an MSELECT index from a BLOB count on
# one node, that is a NEW `Arg` arm and `eq_arg` grows an arm with it."""

EDITS = [
  ("the Arg doc comment for ABlob", DOC_ON, DOC_OFF),
  ("the ABlob field type", "  ABlob{bs: List<&2, U32>}\n", "  ABlob{n: U32}\n"),
  ("eq_arg.ABlob", EQ_ON, EQ_OFF),
  ("eq_arg.sel's ABlob arm", "    case ABlob{bs}: eq_arg.ABlob(y, bs)\n",
   "    case ABlob{n}: eq_arg.ABlob(y, n)\n"),
  ("UOp.mselect's comment", MSEL_ON, MSEL_OFF),
  ("UOp.mselect's construction", "  UOp.new(ar, OpsMSELECT{}, [self], ABlob{[k]}, TNone{})\n",
   "  UOp.new(ar, OpsMSELECT{}, [self], ABlob{k}, TNone{})\n"),
]
# OPTIONAL: a concurrent agent's `s5.ga.arena` fixture, present only while their change is.
OPTIONAL = [
  ("s5.ga.arena's MSELECT node", "Node{OpsMSELECT{}, [1, 2], ABlob{[0]}, TNone{}}",
   "Node{OpsMSELECT{}, [1, 2], ABlob{0}, TNone{}}"),
]


def seg(text, start, end):
  i = text.index(start)
  return text[i:text.index(end, i)]


def off(src: str) -> str:
  for label, on, revert in EDITS + OPTIONAL:
    if src.count(on) == 0:
      if any(label == o[0] for o in OPTIONAL):
        print(f'blob-fix-toggle: {label} {PNA.not_applied("-- not in this tree")}')
        continue
      PNA.fail(f'{label}: the with-fix text occurs {src.count(on)}x')
    assert src.count(on) == 1, (label, src.count(on))
    src = src.replace(on, revert)
  for start, end in ((BLOB_BANNER, MSTACK_BANNER), (WIRING, "    # --- THE AXIS CPYTHON LANE.")):
    block = seg(src, start, end)
    assert src.count(block) == 1, (start, src.count(block))
    src = src.replace(block, "")
  # the reversal is COMPLETE when the old spelling is the only one left. A `case
  # ABlob{n}: eq_arg.ABlob(y, n)` mentions `ABlob{n` too, so the count is on the FIELD
  # DECLARATION, which occurs exactly once.
  assert src.count("  ABlob{n: U32}\n") == 1 and "ABlob{bs: List<&2, U32>}" not in src, \
    "the reversal left a with-fix site behind"
  return src


def main() -> None:
  mode = sys.argv[1] if len(sys.argv) > 1 else '--restore'
  if mode == '--build':
    on = open(REAL, encoding='utf-8').read()
    assert 'ABlob{bs: List<&2, U32>}' in on, 'the live tree does not have the fix'
    off_text = off(on)
    open(ON, 'w', encoding='utf-8').write(on)
    open(OFF, 'w', encoding='utf-8').write(off_text)
    print(f'blob-fix-toggle: ON  {len(on.splitlines())} lines -> {ON}')
    print(f'blob-fix-toggle: OFF {len(off_text.splitlines())} lines -> {OFF}')
    return
  src = ON if mode in ('on', '--restore') else OFF
  shutil.copyfile(src, REAL)
  print(f'blob-fix-toggle: fix {"IN" if src is ON else "OUT"} ({mode})')


if __name__ == '__main__':
  main()