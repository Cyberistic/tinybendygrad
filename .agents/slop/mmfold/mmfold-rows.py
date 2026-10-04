#!/usr/bin/env python3
"""mmfold-rows.py -- A READER FOR THE ONE-SPACE F3 SHAPE, and nothing else.

WHY IT EXISTS, and it is a CONTRACT COLLISION rather than a defect in either side.
`uop/fold.bend:4071` and its sibling at `:4077` print with EXACTLY ONE space:

    def mm_row(nm: String, got: String) -> IO(Unit):
      IO.print(String.concat(["mm_", nm, " ", got]))

and `rebase-gate.py:412` reads F3 with `GAP = "  "` -- TWO spaces -- for a reason that is not
optional either: a TAB is a table cell, so `dtype_tables.py`'s 14,774 TSV lines must keep reading
as ZERO rows or a lane wired on purpose to be dead would report 14,774 fabricated claims. One
deliberate space in the producer, two deliberate spaces in the reader. Measured on this tree:

    line                          rebase-gate.py's rows()    rows_f3one()
    mm_add_zero 0:0               0 rows                    1 row
    mm_add_zero  0:0              1 row                     0 rows
    mm_add_zero=0:0               1 row                     0 rows

So the two readers are COMPLEMENTARY and each refuses exactly what the other owns, which is what
makes them safe to union. `rows_f3one` reads NOTHING `rows()` reads, and the lane harness ASSERTS
that disjointness rather than assuming it: two readers that both claimed a row would be two
answers to "what does this line mean", which is the thing this project's 157 readers exist to
prevent.

WHAT SUBSTITUTING IT BREAKS, which is the sentence `reader-contracts.tsv` requires:
`rows_f3one` reads none of F1, none of F2 and none of the two-space F3, so putting it where
`rows()` is used turns cstyle.bend's 225 F2 rows into 225 BROKEN rows and `dtype_tables.py`'s
14,774 TSV lines into ... 0 rows, which is CORRECT there. It is a SUPPLEMENT, not a substitute.

WHAT IT REFUSES, and every refusal is a rule rather than a fallback:

  * a name with a SPACE in it -- `rows()`'s own F3 rule, so a prose line cannot manufacture a
    row name out of its first clause, and a shared name is the one thing the lane's keying uses
    as evidence;
  * a line with TWO spaces in it -- that is `rows()`'s F3, and reading it here would make the
    two readers disagree about a line both claim;
  * a line with NO space, a line whose tail is empty, a TAB, and an `#`-prefixed name.

It is registered in `reader-contracts.tsv` with a census signature, so `reader-guard.py` R2 fails
this file if its ANSWERS move and not merely if its source is reformatted.
"""
import re

# `rows()`'s F3 NAME RULE, restated rather than imported: this module must be loadable by the
# census's `sandbox()` with no project on sys.path, and a name is one token.
NAME = re.compile(r"^[A-Za-z0-9_.+/:#-]+$")


def rows_f3one(text):
  """{name: the producer's own answer} for the ONE-SPACE F3 rows in `text`, and no others.

  Returns a plain mapping so the lane can union it with `rows()`; duplicates are NOT hidden by
  the return value, because `len()` on it is compared against the number of lines read by
  `mmfold-lane.py`, which is what turns an overwrite into a reported count.
  """
  out = {}
  for line in text.splitlines():
    line = line.rstrip()
    if not line or "  " in line or "\t" in line or "=" in line:
      continue                      # `=` is F1, two-space and TAB belong to the other shapes
    head, sep, tail = line.partition(" ")
    if not sep or not tail.strip() or " " in head:
      continue
    if head.startswith("#") or not NAME.match(head):
      continue
    out[head] = tail.strip()
  return out
