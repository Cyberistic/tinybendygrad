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

# RULE B, SPELLED OUT.  A mutant that is not a PROGRAM says nothing about
# coverage -- not even zero -- so it needs its own cell value, and it must be one
# `zero-classify.py` already knows: that classifier REFUSES an unrecognised
# measurement rather than inventing a verdict for it, so appending a diagnostic
# here (`DID-NOT-COMPILE rc=1`) would break the classifier loudly.  The value is
# therefore spelled exactly as `zero-classify.py`'s MEASURED tuple spells it, and a
# caller that wants the rc puts it in the DESCRIPTION cell.
#
# This is a different claim from MARKER and the difference is the whole point:
# MARKER says the edit never landed; this says it landed and the result is not a
# program.  A table that uses MARKER for both is reporting an edit as dead when
# the port under test was the thing that failed to build.
NOT_A_PROGRAM = "DID-NOT-COMPILE"


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


class PatchNotApplied(Exception):
    """A patch did not apply, and this harness refuses to go on as if it had.

    NOT an AssertionError.  Both `pipe` and `fail` REFUSE -- they decline to
    build a row or write a record -- which is a control-flow decision, not a
    claim that turned out false.  Sharing AssertionError with real assertions
    means one `except AssertionError` anywhere upstream silently converts a
    refusal into a failed test, and the table still gets written.  The two must
    stay distinguishable to whoever catches them.
    """


def not_applied(note=""):
    """The marker for a patch that never landed.

    Property 1 is structural: this string cannot be parsed as an integer,
    because it starts with `PATCH`.  That is the whole point and it is why the
    marker may not be shortened to a numeral or a status letter.
    """
    if MARKER.isdigit():
        raise PatchNotApplied("a digit marker is the defect, not the fix")
    return MARKER if not note else "%s: %s" % (MARKER, note)


def not_a_program():
    """RULE B's cell value, and it is deliberately NOT `not_applied()`.

    `not_applied` says the edit never landed.  This says the edit landed and the
    result is not a program, which is a different claim about a different thing:
    `ops-python-mutate.py`'s M17 and M22 each LOST ALL 85 ROWS to a run that
    produced none and printed `85` for both, which is 170 moved rows that do not
    exist.  Calling that a dead patch indicts the edit instead of the build.

    Spelled through `zero-classify.py`'s vocabulary rather than invented, and
    spelled EXACTLY: that classifier compares the whole cell and REFUSES anything
    it does not recognise, so a diagnostic suffix here would break it loudly.  The
    rc belongs in the description cell.
    """
    if NOT_A_PROGRAM.isdigit():
        raise PatchNotApplied("a digit marker is the defect, not the fix")
    return NOT_A_PROGRAM


def pipe(cells, width):
    """A `|`-delimited row, refused if it is not `width` cells.

    Property 2.  The width is passed by the caller because only the caller knows
    what the NORMAL row looks like; this cannot infer it, and inferring it is
    how a row silently acquires a column.  Passing it at every call site also
    puts the normal row's shape one keystroke from the refusal, which is where
    the drift was visible in the first place.
    """
    if len(cells) != width:
        raise PatchNotApplied(
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
    raise PatchNotApplied(not_applied(note))