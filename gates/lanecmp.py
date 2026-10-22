#!/usr/bin/env python3
"""lanecmp.py -- the SHAPE-AGNOSTIC row comparator the LANE gates share.

    from lanecmp import read_rows, compare

WHY A SHAPE-AGNOSTIC READER, AND WHY IT IS NOT A `diff`.

THE TWO SHAPES, AND WHY ONE READER HAS TO TAKE BOTH.  A lane's row is one of

    F1   name=value                       -- `gates/mixin-op-oracle.py`'s shape
    F2   name = [value]   py=[value]      -- the RENDER lanes' shape

and the port's rows are NOT all one shape: `tinybendygrad/runtime/support/objc.bend`
prints **twelve** F1 rows and **one hundred and eleven** F2 rows, in the same file,
because six of its printers were written before the derived-row shape was adopted.
The recovered `gates/objc-oracle.py` is F1 for all of its rows, and
`gates/ga-oracle.py` and `gates/nir-oracle.py` are F2.  So a reader that knew ONE
shape would read a third of the objc lane and call it a whole lane.

**THE COMPARISON IS BY NAME AND BY VALUE, NOT BY THE WHOLE ROW'S BYTES.**  An F2 row
carries TWO halves -- the port's answer and the `py=` half -- and the `py=` half is
the port's OWN value re-read (`renderer/tc.bend`'s `rd`), so it cannot disagree with
the row it sits in and it is not an independent witness.  The witness is the ORACLE's
row, and the question is "does CPython's answer for this row equal the port's
answer for this row".  Diffing whole bytes would also compare the SHAPE, and nine of
`tinybendygrad/renderer/__init__.bend`'s rows print `py=False` beside a bracketed
`[False]` -- so a byte diff there reports a difference in the SPELLING and learns
nothing about the ANSWER.

THE COMPARISON IS DRIVEN BY THE PORT'S ROWS.  The oracle may print more rows than the
port (the recovered objc oracle answers 247 distinct names and the port prints 123),
and it may print a trailer (`gates/ga-oracle.py`'s `ORACLE ROW COUNT = 778`, the
recovered objc oracle's `ROWS=266`).  So the port's rows drive the comparison and a
line the port does not have a name for is simply not compared -- and the oracle's own
row count is asserted separately, because an oracle that lost rows must fail rather
than shrink the comparison.

THE AMBIGUITY, AND WHY IT IS REPORTED RATHER THAN RESOLVED.  The recovered objc
oracle prints **nineteen** of its row names TWICE, and for two of them the two
occurrences carry DIFFERENT values -- `mangle_leading_and_trailing_stripped` is the
mangled NAME in one section and a BOOLEAN in another, and `own_release_c_call_names`
is one message's call names in one section and another's in the next.  A name-keyed
comparison therefore cannot decide those rows by equality alone.  So: when the
oracle has several rows for a name, the port's row AGREES when its value is AMONG
them, and the AMBIGUITY IS COUNTED AND NAMED, because "the oracle answered this
question twice and one of its answers is the port's" is a fact about the ORACLE that
a reader has to be told.  It is not silently resolved, and it is not a pass.

THE DIVERGENCES, AND WHY THEY ARE PAIRS.  A DIVERGENCE is a row where the two sides
are KNOWN to differ, and it is pinned on BOTH sides: pinning one side can only ever
describe half of it.  And a declared divergence is CHECKED AGAINST THE LANES, NOT
TRUSTED: a declaration says "the port's row and CPython's row DIFFER here", and if
the two sides become the SAME row the declaration is STALE, so the comparator REFUSES
rather than excluding a row it no longer measures.  A divergence that cannot go stale
is a label.
"""
from __future__ import annotations

from collections import namedtuple

Row = namedtuple("Row", "name value raw shape")

F1 = "F1"
F2 = "F2"


def _bracket(rest: str) -> tuple[str, str]:
    """the value and the tail of an F2 row, at the `]` that CLOSES the `[`.

    The brackets BALANCE, so the end is the `]` that closes the one the row opened.
    Taking the FIRST `]` would cut a value that contains brackets -- and
    `tinybendygrad/renderer/amd/generate.bend`'s rows carry whole JSON documents
    inside their values.
    """
    depth = 1
    for i, ch in enumerate(rest):
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return rest[:i], rest[i + 1:]
    raise ValueError(f"an F2 row has no closing `]`: {rest[:80]!r}")


def read_rows(text: str) -> list[Row]:
    """every row of a lane, in either shape, in the order the lane printed them.

    A line that is neither shape is NOT a row and is not silently dropped: it is
    returned with the value `None`, so the caller can name it.  A lane's trailer and
    a lane's stray text are two different things and only one of them is a row.
    """
    rows = []
    for line in text.splitlines():
        if not line.strip():
            continue
        if " = [" in line:
            name, _, rest = line.partition(" = [")
            try:
                value, _tail = _bracket(rest)
            except ValueError:
                # A line that LOOKS like an F2 row and is not one: a linker script
                # carries ` = [` inside it, and a reader that CRASHES on one takes the
                # whole lane down with it.  It is a NON-ROW, and it is reported as
                # one -- not dropped, and not compared.
                rows.append(Row(name, None, line, "NONE"))
                continue
            rows.append(Row(name, value, line, F2))
            continue
        name, sep, value = line.partition("=")
        if sep:
            rows.append(Row(name, value, line, F1))
            continue
        rows.append(Row(line, None, line, "NONE"))
    return rows


def by_name(rows: list[Row]) -> dict[str, list[Row]]:
    """`{name: [every row with that name, in order]}` -- the DUPLICATES KEPT."""
    out: dict[str, list[Row]] = {}
    for r in rows:
        out.setdefault(r.name, []).append(r)
    return out


def compare(port: list[Row], oracle: list[Row]) -> dict:
    """the comparison, by name and by value.  Nothing is decided here.

    `agree`       the port's value is the oracle's value -- one oracle row, equal.
    `agree_many`  the port's value is AMONG the oracle's values for that name, and
                  the oracle printed that name more than once.  The AMBIGUITY is
                  reported, not resolved.
    `differ`      the port's value is not among the oracle's values for that name.
    `unanswered`  the oracle has no row with that name at all.
    `port_only`   names the port printed and the oracle did not.
    `oracle_only` names the oracle printed and the port did not.
    """
    # THE NON-ROWS ARE COUNTED AND NOT COMPARED.  A line that is neither shape is
    # not a row, and a row the reader cannot name is not a row this comparison can
    # decide -- so it is left out of the diff and the caller is told how many there
    # were, because a reader that silently dropped a line would report agreement on
    # a comparison it never made.
    port = [r for r in port if r.shape != "NONE"]
    oracle = [r for r in oracle if r.shape != "NONE"]
    p_idx, o_idx = by_name(port), by_name(oracle)
    out = {"agree": [], "agree_many": [], "differ": [], "unanswered": [],
           "port_only": [], "oracle_only": []}
    for name, prows in p_idx.items():
        orows = o_idx.get(name)
        if not orows:
            out["unanswered"].append((name, prows[0]))
            continue
        vals = [o.value for o in orows]
        if prows[0].value in vals:
            (out["agree_many"] if len(orows) > 1 else out["agree"]).append((name, prows[0], orows))
        else:
            out["differ"].append((name, prows[0], orows))
    out["port_only"] = [n for n in p_idx if n not in o_idx]
    out["oracle_only"] = [n for n in o_idx if n not in p_idx]
    return out
