#!/usr/bin/env python3
"""patch_not_apply.py -- ONE reporter for a mutation whose anchor did not apply.

Twenty-eight harnesses in this directory decide independently what to print when
`if old not in src:` fires, and they disagreed about it in the one way that
costs money.  `ops-python-mutate.py` printed a bare `0`.  A bare `0` in a count
column is not a refusal, it is a MEASUREMENT, and a reader -- or a sum over the
column -- cannot tell it from one.  The row sat in the committed record as
`ops-python-mutations.txt:7` until this was caught.  The same row also had FOUR
cells where every other row had three, so any parser reading column 3 as the
count read `(pattern not found)` there instead: the cell count shifted the
figure out from under the reader, and nothing failed.

So the marker has to satisfy three properties at once, and each of them is a
property of the STRING, not of a promise in a comment:

  1. NON-NUMERIC.  `int(cell)` must raise.  A count column that sums silently
     is how a dead patch becomes a coverage claim.
  2. SAME CELL COUNT as the normal row it replaces.  Enforced structurally by
     `pipe()`, which refuses to build a row of the wrong width, so a reader
     that indexes column N still finds the figure in column N.
  3. ONE SPELLING.  `MARKER` is zero-classify.py's `V_PATCH`, and it is
     QUERIED from that file rather than transcribed -- zero-classify.py has a
     `--verdicts` flag precisely so a consumer does not regex its source, and a
     marker that drifts into a sixth spelling is the bug this file exists to
     end.  The check runs at import, so a rename in one place fails loudly in
     the other instead of producing a table whose zeros nobody can classify.

LOUDNESS IS NOT UP FOR UNIFORMITY.  Two harnesses (`codegen3-mut.py`,
`ptx-s3-mutate.py`) refuse to write a table at all when an anchor is stale.
That is better than a marker, not a different spelling of one, so `fail()`
keeps them refusing while sharing the vocabulary.  A quiet marker must never be
traded for a loud guard: the guard is the thing that stops a stale anchor from
reaching a record at all.

usage:
  import patch_not_apply as PNA
  if old not in src: print(PNA.pipe([mid, what, PNA.not_applied()], 3))
  if old not in src: print(PNA.not_applied("stale: %s moved on" % mid))
  if old not in src: PNA.fail("M%s: %r" % (tag, old))
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# THE MARKER.  zero-classify.py's V_PATCH, verbatim and queried.
MARKER = "PATCH-NOT-APPLY"


def _check_vocabulary():
    """Refuse to exist in a vocabulary zero-classify.py does not know.

    A sixth spelling would parse as an unrecognised measurement, and
    zero-classify.py EXITS on those rather than inventing a verdict.  So a drift
    here does not degrade the table, it breaks the classifier loudly -- which is
    the correct direction for it to break in.
    """
    verdicts = subprocess.run(
        [sys.executable, os.path.join(HERE, "zero-classify.py"), "--verdicts"],
        capture_output=True, text=True).stdout.split()
    if MARKER not in verdicts:
        raise SystemExit(
            "patch_not_apply: %r is not one of zero-classify.py's verdicts (%s). "
            "Rename it in BOTH files or not at all -- a refusal the classifier "
            "cannot read is not a refusal." % (MARKER, " ".join(verdicts)))
    return MARKER


_check_vocabulary()


def not_applied(note=""):
    """The marker for a patch that never landed.

    Property 1 is structural: this string cannot be parsed as an integer,
    because it starts with `PATCH`.  That is the whole point and it is why the
    marker may not be shortened to a numeral or a status letter.
    """
    assert not MARKER.isdigit(), "a digit marker is the defect, not the fix"
    return MARKER if not note else "%s: %s" % (MARKER, note)


def pipe(cells, width):
    """A `|`-delimited row, refused if it is not `width` cells.

    Property 2.  The width is passed by the caller because only the caller knows
    what the NORMAL row looks like; this cannot infer it, and inferring it is
    how a row silently acquires a column.  Passing it at every call site also
    puts the normal row's shape one keystroke from the refusal, which is where
    the drift was visible in the first place.
    """
    if len(cells) != width:
        raise AssertionError(
            "patch_not_apply.pipe: %d cells, the table's rows have %d.  A row of "
            "a different width moves the count into another column -- that is "
            "how `ops-python-mutations.txt:7` read `(pattern not found)` as a "
            "count.  cells=%r" % (len(cells), width, cells))
    return "| " + " | ".join(str(c) for c in cells) + " |"


def fail(note=""):
    """REFUSE, loudly, with the shared vocabulary in the message.

    For the harnesses whose current behaviour is already safe: an anchor that
    does not apply must abort the run rather than reach a record.  This is an
    explicit raise and not an `assert` statement, so it survives `python -O`,
    which strips `assert` -- and a stale anchor is precisely the thing that must
    not be optimisable away.
    """
    raise AssertionError(not_applied(note))