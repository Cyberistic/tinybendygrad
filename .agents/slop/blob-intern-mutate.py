#!/usr/bin/env python3
"""blob-intern-mutate.py -- the mutation table for `eq_arg.ABlob`, and the proof that the
`blob_*` rows fail BEFORE the fix and pass after it.

HARNESS CONTRACT, from `.agents/slop/agent-core.md`: this diffs WHOLE `name=value` LINES
and reports the rows that MOVED BY NAME. A harness that compared only row names would
report 0 for every mutation here, because the name is printed whether or not the value
moved -- and it would report 0 for M3 and M4, which do not change any VALUE, only the
interning.

IT MUTATES `tinybendygrad/uop/ops.bend` IN PLACE and restores it from
`.agents/slop/ops-blob-fixed.pristine.bend` after every step, including on failure. That
snapshot is written by `--snapshot` and MUST be the FIXED file; the pristine-bug file is
never restored over it by accident because the snapshot is taken before the first
mutation and re-taken only on request.

    .venv/bin/python .agents/slop/blob-intern-mutate.py --snapshot
    .venv/bin/python .agents/slop/blob-intern-mutate.py
    .venv/bin/python .agents/slop/blob-intern-mutate.py --restore

M1 IS THE BUG. It is `eq_arg.ABlob`'s ORIGINAL body -- a comparison of the LENGTH --
restated in the new representation, so it is the pre-fix comparator rather than a
different bug wearing the pre-fix comparator's clothes. Everything else is a neighbour of
it, and M3/M4 are the two ways a content comparison can be wrong in the OTHER direction:
a key that separates everything, and a key that separates nothing.
"""
import os
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REAL = os.path.join(REPO, 'tinybendygrad/uop/ops.bend')
PRISTINE = os.path.join(REPO, '.agents/slop/ops-blob-fixed.pristine.bend')
BEND = os.path.join(REPO, 'bin/bend')

FIXED = """# CONTENT, NOT A SUMMARY. This arm used to compare `U32.is_eq(n, y1)` on an
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

LEN = """def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: U32.is_eq(U32.from_nat(List.length(&2, U32, bs)), U32.from_nat(List.length(&2, U32, y1)))
    case _: False{}"""

HEAD1 = """def eq_head(bs: List<&2, U32>, y1: List<&2, U32>) -> Bool:
  match bs y1:
    case Nil{} Nil{}: True{}
    case b <> _ w <> _: U32.is_eq(b, w)
    case _ _: False{}

def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: eq_head(bs, y1)
    case _: False{}"""

NEVER = """def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: False{}
    case _: False{}"""

ALWAYS = """def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: True{}
    case _: False{}"""

MUTATIONS = [
  ("M1", "eq_arg.ABlob: content -> LENGTH (THE ORIGINAL BUG, restated)", LEN),
  ("M2", "eq_arg.ABlob: content -> FIRST BYTE ONLY", HEAD1),
  ("M3", "eq_arg.ABlob: content -> NEVER EQUAL (a key that separates everything)", NEVER),
  ("M4", "eq_arg.ABlob: content -> ALWAYS EQUAL (a key that separates nothing)", ALWAYS),
]

def blob_rows() -> list[str]:
  """The `blob_*` rows of the CURRENT tree, sorted."""
  r = subprocess.run([BEND, 'tinybendygrad/uop/ops.bend'], cwd=REPO, capture_output=True, text=True, timeout=1200)
  return sorted(ln for ln in r.stdout.splitlines() if ln.startswith('blob_'))


def write(body: str) -> None:
  """Put `body` in place of the fixed comparator. `FIXED` includes its comment block, so
  M1..M4 replace the whole block including the prose -- which is also the control's job."""
  s = open(PRISTINE, encoding='utf-8').read()
  assert s.count(FIXED) == 1, f"the fixed comparator is not in the snapshot ({s.count(FIXED)}x)"
  open(REAL, 'w', encoding='utf-8').write(s.replace(FIXED, body))


def restore() -> None:
  shutil.copyfile(PRISTINE, REAL)


def same_as_snapshot() -> bool:
  return os.path.exists(PRISTINE) and open(PRISTINE, 'rb').read() == open(REAL, 'rb').read()


def main() -> None:
  if '--snapshot' in sys.argv:
    assert os.path.exists(REAL)
    shutil.copyfile(REAL, PRISTINE)
    print(f"blob-intern-mutate: snapshot of the FIXED tree -> {PRISTINE}")
    return
  if '--restore' in sys.argv:
    restore()
    print('blob-intern-mutate: restored')
    return

  # THE STALE-SNAPSHOT GUARD, and it is here because it bit this unit. The harness
  # mutates `ops.bend` IN PLACE and restores from `PRISTINE`, so a `PRISTINE` taken
  # before a concurrent agent's edit silently REVERTS that edit when the run ends. It
  # happened: the snapshot was taken while another agent's ~130-line `s5` "MOVERS,
  # ROUND TWO" was in the tree, that change was rebased out, and the restore put the
  # dead 6623-line file back over the live 6306-line one. A restore that can undo
  # somebody else's work must refuse to run on a tree it does not recognise.
  if not same_as_snapshot():
    print(f"blob-intern-mutate: REFUSING. The live tree is not the snapshot:\n"
          f"  live      {open(REAL, 'rb').read().__len__()} bytes\n"
          f"  snapshot  {os.path.getsize(PRISTINE)} bytes\n"
          f"Re-run with --snapshot to accept the live tree, or --restore to overwrite it.",
          file=sys.stderr)
    return 1

  try:
    restore()
    before = blob_rows()
    print(f"blob-intern-mutate: baseline, {len(before)} blob rows")
    for row in before:
      print(f"    {row}")
    for mid, label, body in MUTATIONS:
      write(body)
      after = blob_rows()
      moved = [(b, a) for b, a in zip(before, after) if b != a]
      print(f"\n{mid}: {label}")
      if len(after) != len(before):
        print(f"    ROW COUNT MOVED {len(before)} -> {len(after)}")
      if not moved:
        print("    MOVED NOTHING -- blind spot")
      for b, a in moved:
        print(f"    {b}  ->  {a}")
      names = sorted({b.split('=', 1)[0] for b, _ in moved})
      print(f"    rows moved by name: {names if names else 'NONE'}")
  finally:
    restore()
    print('\nblob-intern-mutate: restored the fixed tree')


if __name__ == "__main__":
  sys.exit(main() or 0)