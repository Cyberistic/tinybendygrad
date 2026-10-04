#!/usr/bin/env python3
"""blob-fix-toggle.py -- put the BLOB FIX in, or take it out, with the rest of the tree
held still, so `blob-rows.py` can measure the fix's blast radius and NOTHING ELSE's.

    .venv/bin/python .agents/slop/blob-fix-toggle.py --build   # write both variants
    .venv/bin/python .agents/slop/blob-fix-toggle.py off       # fix OUT
    .venv/bin/python .agents/slop/blob-fix-toggle.py on        # fix IN
    .venv/bin/python .agents/slop/blob-fix-toggle.py --restore # fix IN, unconditionally

WHY THIS EXISTS. A concurrent agent landed ~130 lines of `s5` "MOVERS, ROUND TWO" into
`tinybendygrad/uop/ops.bend` DURING this unit, and separately reverted this file once
underneath it (another agent's `jj restore`, hash d662cccb -> ff233f8e, which also
removed the first application of this fix). So the naive `before` snapshot in
`.agents/slop/blobrows/before` and any `after` snapshot taken now differ by BOTH that
agent's 130 lines AND this fix, and the diff cannot be attributed.

So both variants are built ONCE, from the SAME current file, by applying or
reverse-applying exactly this unit's nine text edits and its two insertions:

  ON  == the current tree
  OFF == the current tree with: the ABlob doc comment, the `Arg` field type, the
         `eq_arg.ABlob` body, `eq_arg.sel`'s arm, `UOp.mselect`'s comment and
         construction, `s5.ga.arena`'s MSELECT node, the BLOB helper block, and the
         `main` wiring. Nothing else.

`diff ON OFF` is therefore exactly this unit's change, and `blob-rows.py` is run once
with each. The variants live in `.agents/slop/`, never in `$TMPDIR`, because an oracle in
`$TMPDIR` has been gone before the commit and its comparison became unreproducible.
"""
import os
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

# (label, present-with-fix, absent-with-fix) -- each must occur exactly ONCE.
EDITS = [
  ("doc comment for ABlob",
   "#   bytes                   ABlob      BINARY arg; the BYTES themselves, as a list of\n",
   "#   bytes                   ABlob      BINARY arg; only its length is read\n"),
  ("type Arg's ABlob field", "  ABlob{bs: List<&2, U32>}\n", "  ABlob{n: U32}\n"),
  ("eq_arg.sel's ABlob arm",
   "    case ABlob{bs}: eq_arg.ABlob(y, bs)\n", "    case ABlob{n}: eq_arg.ABlob(y, n)\n"),
  ("UOp.mselect construction",
   "  UOp.new(ar, OpsMSELECT{}, [self], ABlob{[k]}, TNone{})\n",
   "  UOp.new(ar, OpsMSELECT{}, [self], ABlob{k}, TNone{})\n"),
  ("s5.ga.arena's MSELECT node",
   "Node{OpsMSELECT{}, [1, 2], ABlob{[0]}, TNone{}}\n",
   "Node{OpsMSELECT{}, [1, 2], ABlob{0}, TNone{}}\n"),
]
# the three that carry a COMMENT BLOCK as well, so they are handled as spans
SPANS = [
  ("eq_arg.ABlob", "# CONTENT, NOT A SUMMARY.", "def eq_arg.AFloat",
   "def eq_arg.ABlob(y: Arg, +n: U32) -> Bool:\n", "def eq_arg.AFloat"),
  ("UOp.mselect comment", "# `mselect` -- ops.py:772\n# an INT", "def UOp.mselect",
   "# `mselect` -- ops.py:772\n# an INT", "def UOp.mselect"),
]


def seg(text, start, end):
  i = text.index(start)
  return text[i:text.index(end, i)]


def off(src: str) -> str:
  """The fix, removed."""
  for label, on, _off in EDITS:
    assert src.count(on) == 1, (label, src.count(on))
    src = src.replace(on, _off)
  for label, on_s, on_e, off_s, off_e in SPANS:
    a, b = seg(src, on_s, on_e), seg(src, off_s, off_e)
    assert src.count(a) == 1, (label, src.count(a))
    src = src.replace(a, b)
  # the helper block and the main wiring, removed whole
  for start, end in ((BLOB_BANNER, MSTACK_BANNER), (WIRING, "    # --- THE AXIS CPYTHON LANE.")):
    b = seg(src, start, end)
    assert src.count(b) == 1, (start, src.count(b))
    src = src.replace(b, "")
  assert "ABlob{" not in src.replace("ABlob{bs", "").replace("ABlob{[", ""), "an ABlob site survived"
  return src


def main() -> None:
  mode = sys.argv[1] if len(sys.argv) > 1 else '--restore'
  if mode == '--build':
    on = open(REAL, encoding='utf-8').read()
    assert 'ABlob{bs: List<&2, U32>}' in on, 'the live tree does not have the fix; re-apply it first'
    open(ON, 'w', encoding='utf-8').write(on)
    open(OFF, 'w', encoding='utf-8').write(off(on))
    print(f'blob-fix-toggle: ON  {len(on.splitlines())} lines -> {ON}')
    print(f'blob-fix-toggle: OFF {len(off(on).splitlines())} lines -> {OFF}')
    return
  src = ON if mode in ('on', '--restore') else OFF
  shutil.copyfile(src, REAL)
  print(f'blob-fix-toggle: fix {"IN" if src is ON else "OUT"} ({mode})')


if __name__ == '__main__':
  main()