#!/usr/bin/env python3
"""Re-apply the print_uops RANGE-COLUMN unit to a settled tree. Idempotent.

    .venv/bin/python .agents/slop/ops-pu-range-rows.py [--check]

The unit is VERIFIED -- `ops-pu-gate` reported "14 rows, 3 lanes byte-identical" -- and
it is not on master, because both files it touches are contended by a concurrent agent
whose in-flight edit to `render.bend`'s `main` dropped the `pu_rows` call, and whose churn
reverted the `helpers.bend` half. So the work lives here, in one script, rather than in a
file that a rename or a rewrite takes with it.

IT IS IDEMPOTENT AND IT SAYS SO. Every edit is guarded by an assertion that its target is
present and its result is absent, so running it on a tree that already has the unit is a
no-op that prints "already applied" rather than a second copy. An unguarded script that
duplicates a 40-line arena is how a fixture ends up with two `pu_rr` defs and a gate that
fails for a reason nobody can read.

THE FOUR EDITS, and what each one is:

  1. `helpers.bend` `esc` -- THE COLOUR CODE IS TEXT, NOT A CHARACTER. It was
     `Char.from_u32(u)`, which is a no-op for every code the tree uses: a colour code is
     30-37 or 90-97, TWO digits, so `Char.from_u32(31)` is the control character U+001F
     and not the string "31". MEASURED at the byte level on `print_uops`'s range column:
     the port emitted `033 [ 037 m 0 033 [ 0 m` where CPython emits
     `033 [ 3 1 m 0 033 [ 0 m`. `esc` has exactly one caller (`colored`), so every colour
     in the tree was writing a control character, not just a range's.

  2. `render.bend` `multirange_str.pad` -- CPython pads with `" " * (pad-ansilen(ret))`
     and `ansilen` is ANSI-aware, so escape codes do not count toward the width.
     `String.length` counts them, so a coloured range was padded as if it were eight
     characters longer than it looks. The insertion is BALANCED (`String.length(s)` ->
     `String.length(H.ansistrip(s))`) and never a retyped line: three attempts at
     hand-counting five nested calls produced three paren errors.

  3. `render.bend` `pu_rr` -- a SECOND ARENA, because `pu_ar`'s ADD is `(BUFFER, CONST)`
     and two of the nine gated rows are ABOUT that src being a CONST. And the RANGE was in
     `pu_ar` already, node 2, UNUSED: nothing consumed it, so nothing was ever asked for
     its range. The fixture was not missing a node, it was missing an EDGE -- the same
     shape as the two fixture walls before it, which is three in a row and a pattern.

  4. `render.bend` `main` -- calls `pu_rr_rows(pu_rr())` after `pu_rows(pu_ar())`. The
     rows are inert without this, and a concurrent edit to `main` is what lost them, so it
     is asserted rather than assumed.
"""
import argparse
import pathlib
import sys

RB = pathlib.Path('tinybendygrad/uop/render.bend')
HB = pathlib.Path('tinybendygrad/helpers.bend')

ESC_OLD = ('  String.from_list([Char.from_u32(27), Char.from_u32(91), Char.from_u32(u), Char.from_u32(109)])')
ESC_NEW = ('  String.concat([String.from_list([Char.from_u32(27), Char.from_u32(91)]), U32.show(u), "m"])')

# `String.length(s)` -> `String.length(H.ansistrip(s))` is a matched pair, so the
# surrounding parens cannot be disturbed.
PAD_OLD = 'multirange_str.n(U32.to_nat(sd), String.length(s))'
PAD_NEW = 'multirange_str.n(U32.to_nat(sd), String.length(H.ansistrip(s)))'
for frag in (PAD_OLD, PAD_NEW):
  assert frag.count('(') == frag.count(')'), frag

ARENA = '''
def pu_rr() -> O.Arena:
  O.Arena{[
    O.Arena.bottom(),
    O.Node{O.OpsCONST{}, Nil{}, O.APy{O.CInt{H.i64_of_i32(4)}}, O.TNone{}},
    O.Node{O.OpsRANGE{}, [1], O.ARange{[0], O.AXIS_LOOP{}}, O.TNone{}},
    O.Node{O.OpsBUFFER{}, [1], O.AParam{pu_pa(1)}, O.TNone{}},
    O.Node{O.OpsADD{}, [3, 2], O.ANone{}, O.TNone{}}], [0]}

# `pu_rrange` the RANGE itself: it is its own range, so the column is the coloured index.
#             This is the row that needs the fold to answer a RANGE.
# `pu_radd`   an ADD over it: a range REACHES a consumer, so the column carries the same
#             colour at a node that is not itself a RANGE. Without this row a sweep that
#             answered only RANGE nodes would pass. Its list deliberately mixes a BUFFER
#             and a CONST, which have NO ranges, in with the two that do -- CPython's own
#             answers, measured: BUF has `ranges == []` even with a CONST src, RANGE is its
#             own range, and the ADD inherits it.
def pu_rr_rows(+ar: O.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- pu_row("pu_rrange", ar, [2])
    pu_row("pu_radd", ar, [3, 4, 1, 2])
'''


def edit(text, old, new, what, changes, check):
  n = text.count(old)
  if n == 0 and text.count(new):
    print(f'  already applied: {what}')
    return text
  if n != 1:
    # A MISS IS REPORTED, NOT GUESSED AT. And in `--check` it does not stop the run: the
    # point of a check is the whole picture, and one miss used to hide the other three.
    print(f'  MISS: {what} (target count {n})')
    misses.append(what)
    return text
  changes.append(what)
  if not check:
    print(f'  applied: {what}')
  return text.replace(old, new, 1)


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument('--check', action='store_true', help='report what would change, write nothing')
  args = ap.parse_args()
  changes = []
  global misses
  misses = []

  h = HB.read_text()
  h = edit(h, ESC_OLD, ESC_NEW, 'helpers.bend: esc renders the colour code as decimal text', changes, args.check)
  # THE MISS CHECK RUNS BEFORE ANY WRITE. It used to run after, and so printed "1 target
  # missing, wrote nothing" on a run that had in fact already written both files -- which
  # is worse than no check, because it says the tree is untouched when it is not.
  if misses and not args.check:
    sys.exit(f'ops-pu-range-rows: {len(misses)} target(s) missing, wrote nothing')
  if not args.check:
    HB.write_text(h)

  r = RB.read_text()
  r = edit(r, PAD_OLD, PAD_NEW, 'render.bend: multirange_str pads the VISIBLE length', changes, args.check)
  # THE "ALREADY APPLIED" TEST IS THE DEF NAME AND NOT THE BLOCK. It compared the whole
  # arena-plus-anchor string, and a comment that differs by a line is enough to make that
  # test fail -- so the script inserted a SECOND `pu_rr` into a file that already had one,
  # and the file stopped compiling with "duplicate declaration: pu_rr". A payload
  # comparison cannot tell "already here" from "here but worded differently"; the name can.
  if r.count('def pu_rr() -> O.Arena:') == 1 and r.count('def pu_rr_rows(') == 1:
    print('  already applied: render.bend: pu_rr arena + pu_rr_rows')
  elif r.count('def pu_rr() -> O.Arena:') or r.count('def pu_rr_rows('):
    print(f'  MISS: render.bend: pu_rr is HALF-PRESENT '
          f'(pu_rr {r.count("def pu_rr() -> O.Arena:")}, pu_rr_rows {r.count("def pu_rr_rows(")}) -- '
          f'removing the surplus copies is a manual call')
    misses.append('render.bend: pu_rr')
  else:
    changes.append('render.bend: pu_rr arena + pu_rr_rows')
    if not args.check:
      print('  applied: render.bend: pu_rr arena + pu_rr_rows')
    r = r.replace('\ndef pu_rows(+ar: O.Arena) -> IO(Unit):', ARENA + '\ndef pu_rows(+ar: O.Arena) -> IO(Unit):', 1)
  # `main` IS THE CONTENDED PART. A concurrent agent rewrote it for pyrender work and the
  # rewrite DROPPED the `pu_rows(pu_ar())` call, so anchoring on that line made this edit
  # unappliable exactly when it was needed. The anchor is `main`'s own `do IO<Unit>:`,
  # which every row group in the file hangs off and which no rewrite removes.
  #
  # And because the old call may still be present ELSEWHERE in `main`, an existing
  # `pu_rows(pu_ar())` is removed first: a second one would print the nine rows twice and
  # the gate's ROW-COUNT assertion would fail, which is the right failure but a confusing
  # one to debug. Detecting the second copy by COUNT rather than by trusting the anchor is
  # what keeps this idempotent.
  MAIN = 'def main() -> IO(Unit):\n  do IO<Unit>:\n'
  if r.count(MAIN) == 1 and r.count('    pu_rows(pu_ar())') + r.count('    pu_rr_rows(pu_rr())') == 0:
    changes.append('render.bend: main calls pu_rows and pu_rr_rows')
    if not args.check:
      print('  applied: render.bend: main calls pu_rows and pu_rr_rows')
    r = r.replace(MAIN, MAIN + '    pu_rows(pu_ar())\n    pu_rr_rows(pu_rr())\n', 1)
  elif r.count('    pu_rows(pu_ar())') == 1 and r.count('    pu_rr_rows(pu_rr())') == 0:
    # This is the state `master` is in: the original five rows are called and the two range
    # rows are not, so the gate sees 9 rows against an oracle of 14 and the shortfall reads
    # as a sweep failure rather than as a missing call.
    changes.append('render.bend: main calls pu_rr_rows')
    if not args.check:
      print('  applied: render.bend: main calls pu_rr_rows')
    r = r.replace('    pu_rows(pu_ar())', '    pu_rows(pu_ar())\n    pu_rr_rows(pu_rr())', 1)
  elif r.count('    pu_rr_rows(pu_rr())') == 1 and r.count('    pu_rows(pu_ar())') == 0:
    # THE STATE A CONCURRENT REWRITE LEAVES: the new call is there and the old one is
    # gone. Reporting "already applied" here is what made the gate print 5 of its 14 rows
    # and look like a sweep failure, so the two calls are counted SEPARATELY and the one
    # that is missing is the one that is added.
    changes.append('render.bend: main re-adds pu_rows(pu_ar())')
    if not args.check:
      print('  applied: render.bend: main re-adds pu_rows(pu_ar())')
    r = r.replace('    pu_rr_rows(pu_rr())', '    pu_rows(pu_ar())\n    pu_rr_rows(pu_rr())', 1)
  elif r.count('    pu_rr_rows(pu_rr())') == 1:
    print('  already applied: render.bend: main calls both row groups')
  else:
    print(f'  MISS: render.bend: main (do-block anchors {r.count(MAIN)}, '
          f'pu_rows {r.count("    pu_rows(pu_ar())")}, pu_rr_rows {r.count("    pu_rr_rows(pu_rr())")})')
    misses.append('render.bend: main')
  if not args.check:
    RB.write_text(r)

  print(f'ops-pu-range-rows: {len(changes)} edit(s)' + (' would apply' if args.check else ' applied'))
  return 0


if __name__ == '__main__':
  sys.exit(main())
