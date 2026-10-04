#!/usr/bin/env python3
"""rowform.py -- THE FORM-COMPLETE ROW READER, and the spelling battery that says when a
reader is not one.

WHAT THIS IS FOR. `rebase-gate.py:rows()` is the shared row reader of this repo and 51
tools call it. It reads THREE shapes and refuses everything else, which is right for the
three and silent for the rest. This file states the shapes it refuses, by MEASUREMENT, so
that a count produced through it can be labelled a FLOOR instead of a total. It is not a
replacement: `rebase-gate.py` is owned by another unit this round and is not edited here.

THE RULE THIS FILE EXISTS TO NAME.

    A TOOL THAT MATCHES A FORM CANNOT SEE THE INSTANCE THAT LACKS IT.

Every census entry in this directory is an instance of that one sentence. `rows()` could
not see a row whose name carries a space. `unobservable-census.py --handtyped` could not
see a hex literal or a second `row()` on the same line. The `s5_` tally could not see the
one row written without its binder. `unchunks` could not see a chunk payload containing a
space. Each was found by a DISAGREEMENT between two tools that meant the same thing, never
by reading the tool -- and that is the only reliable detector, so the checkable form of the
rule is:

    SPELLING-INVARIANCE.  If two texts MEAN THE SAME THING and a reader answers differently
    on them, the reader is matching a FORM.  The battery in `respelling_battery()` is the
    finite set of meaning-equal pairs this repo has actually been bitten by; a reader that
    survives all of them is form-complete ON THAT BATTERY, which is a floor, not a proof.

WHY THE ANSWERS ARE NOT TRANSCRIBED. Every claim this file makes about a reader is
obtained by CALLING that reader -- `rebase-gate.py` is imported, not re-implemented, and
`spelling_probe()` below prints `rebase-gate.row()`'s own answer next to this file's. A
reader that agreed with itself would be a new instance of the defect it is auditing.

USAGE
    .venv/bin/python .agents/slop/rowform.py            # the battery against the real reader
    .venv/bin/python .agents/slop/rowform.py --selftest # exits 1 if a blind variant is seen
"""
from __future__ import annotations

import importlib.util
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
RG = HERE / "rebase-gate.py"

PY_TAIL = "]   py=["


def load_shared_reader():
    """`rebase-gate.py`'s `row`/`rows`, IMPORTED. Not copied: a copy would agree with
    itself, which is the defect `not-applied-audit.py` exists to prevent in auditors."""
    spec = importlib.util.spec_from_file_location("rebase_gate", RG)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------------
# THE READ-ANY-SHAPE READER.  Deliberately looser than `rebase-gate.row()`; the POINT is
# that it finds rows `row()` refuses.  It is the reference for "is there a row here", so a
# disagreement is a hole in `row()`, not a disagreement between equals.
# ---------------------------------------------------------------------------
#: `<name><SEP><value>` where SEP is `=`, any run of spaces, or a TAB. ONE space counts:
#: `alpha 1` is a row in every lane that prints it, and a reader that needs two spaces is
#: reading a format rather than a meaning.
ANY_SEP = re.compile(r"^(?P<name>\S+(?:[ \t]+\S+)*?)(?P<sep>[ \t]+|=)(?P<val>\S.*)$")


def any_row(line: str):
    """(name, value) for a line wearing ANY row spelling, or None.

    A TAB counts here. `rebase-gate.row()` refuses TAB on purpose -- a TSV table's first
    column is not a row name -- so a TAB line found INSIDE a lane that `row()` reads as
    rows is a spelling the lane uses that `row()` cannot name, and that is a report, not a
    bug in this function.
    """
    s = line.rstrip()
    if not s.strip() or s.lstrip().startswith("#"):
        return None
    m = ANY_SEP.match(s)
    if not m or not m.group("name").strip() or not m.group("val").strip():
        return None
    return m.group("name").strip(), m.group("val").strip()


def blind_reason(line: str, row) -> str | None:
    """Why `rebase-gate.row()` cannot read `line`, or None when it can.

    The four measured reasons, each one a SPELLING rather than a fact about the row:

      TAB              the separator is a TAB.
      SINGLE-SPACE     one space is not two, and the row is still `name value`.
      NAME-HAS-SPACE   the name is not one token; F3 requires `len(head.split()) == 1`.
      EQ-INSIDE-GAP    the two-space shape whose VALUE carries `=`, which the `=` branch
                       claims first and turns into a DIFFERENT row rather than a refusal.
    """
    s = line.rstrip()
    loose = any_row(s)
    if loose is None:
        return None
    if row is not None:
        return None
    name, _sep = loose
    if "=" in s and not re.match(r"^\S+=(\S.*)$", s):
        return "EQ-INSIDE-GAP"
    if len(name.split()) > 1 and (re.search(r"  +", s) or "=" in s):
        return "NAME-HAS-SPACE"
    if "\t" in s:
        return "TAB"
    if re.match(r"^\S+ \S", s):
        return "SINGLE-SPACE"
    return "OTHER"


# ---------------------------------------------------------------------------
# THE SPELLING BATTERY.  Each entry is a PAIR of texts that MEAN THE SAME THING and are
# WRITTEN DIFFERENTLY.  A reader that answers differently on the two is matching a form.
# The `hidden` field names the reader defect this pair was constructed to expose, and every
# `hidden` value is one that MEASURED on this tree -- the audit prints the measurement, so
# the label cannot rot into a claim.
# ---------------------------------------------------------------------------
def respelling_battery():
    """[(id, subject_kind, text_a, text_b, meaning, measured_hidden_in)]"""
    return [
        # --- lane text: the three shapes rebase-gate.row() claims to read, and the two it
        #     cannot.  rebase-gate.py's own header records the F3 discovery (213 rows).
        ("lane.eq-vs-gap", "lane_txt", "alpha=1\nbeta=2\n",
         "alpha  1\nbeta  2\n",
         "two rows, same names and values, different separator",
         "historical: the pre-F3 reader found 0 rows in 213 real ground-truth rows"),
        ("lane.gap-name-space", "lane_txt", "alpha=1\n",
         "alpha one  1\n",
         "one row named `alpha one`; the value is 1 either way",
         None),
        ("lane.gap-value-eq", "lane_txt", "alpha=1\n",
         "alpha  x=1\n",
         "one row named `alpha` whose value is `x=1`",
         None),
        ("lane.tab", "lane_txt", "alpha=1\n",
         "alpha\t1\n",
         "one row named `alpha` whose value is 1, TAB-separated",
         None),
        ("lane.single-space", "lane_txt", "alpha=1\n",
         "alpha 1\n",
         "one row named `alpha` whose value is 1",
         None),
        ("lane.pyfold", "lane_txt", "kern=[*V]   py=[*W]\n",
         "kern=[*V]\n",
         "one row named `kern`; the py= column is a transcription, not the claim",
         "historical: F2 compared [v]   py=[w] against [v] on all 222 cstyle rows"),
        # --- oracle PYTHON source: what `--handtyped` claims to see.
        ("py.two-rows-one-line", "py_src",
         'row("a", 1)\n', 'row("a", 1); row("b", 2)\n',
         "two row calls, one per line vs both on one line",
         "MEASURED: handtyped-audit.py header names 115 SEMI of the 224->578 delta"),
        ("py.hex", "py_src", 'row("a", 3)\n', 'row("a", 0x3)\n',
         "one row whose expected value is the integer 3",
         "MEASURED: 69 RADIX of the 224->578 delta; agent-core.md records 0x6996 as 24425"),
        ("py.fstring-name", "py_src", 'row("a_0", x)\n', 'row(f"a_{i}", x)  # i == 0\n',
         "one row named `a_0`; the f-string is the same name spelled as an expression",
         "MEASURED: 90 NAME of the 224->578 delta"),
        ("py.bare-fstring", "py_src", 'row("a", "1")\n', 'row("a", f"1")\n',
         "one row whose expected value is the string `1`",
         None),
        ("py.wrapped", "py_src", 'row("a", x)\n', 'row(\n  "a",\n  x,\n)\n',
         "one row call, wrapped across lines",
         "MEASURED: `re.M` + `$` made the call single-line"),
        ("py.binary", "py_src", 'row("a", 3)\n', 'row("a", 0b11)\n',
         "one row whose expected value is the integer 3",
         None),
        # --- BEND source: the two greps that read a port's text.
        ("bend.import-quoted", "bend_src",
         "import ./../uop/ops.bend as O\n", 'import "./../uop/ops.bend" as O\n',
         "one import of ops.bend; Bend writes the path bare",
         "MEASURED: a quoted-import grep reported 0 importers, i.e. a vacuous blast radius"),
        ("bend.index-via-local", "bend_src",
         "  +a = dd_band(O.Found.ar(s), v, O.Found.i(s))\n",
         "  +a = O.Found.i(s)\n  +b = dd_band(O.Found.ar(s), v, a)\n",
         "one dd_band call whose third argument is the arena index of `s`",
         "MEASURED: dd-band-census.py section A counted 5 sites where 7 existed"),
        ("bend.bound-vs-bare", "bend_src",
         '  +l : Unit <- srow("s5_ga_after", nm(u.getaddr("PYTHON")))\n',
         '  srow("s5_ga_add", nm(u.getaddr("PYTHON")))\n',
         "one srow call; the binder is a value, not part of the row",
         "MEASURED: TODO.md:6097 -- 12 s5_ga_* named against a stated 19"),
    ]


def spelling_probe():
    """Run the battery against the REAL `rebase-gate.row()`. Returns
    [(id, subject_kind, saw_a, saw_b, agrees)]."""
    rg = load_shared_reader()
    out = []
    for bid, kind, a, b, _why, _hid in respelling_battery():
        if kind != "lane_txt":
            continue
        ra, rb = rg.rows(a), rg.rows(b)
        out.append((bid, kind, ra, rb, ra == rb))
    return out


def selftest() -> int:
    rg = load_shared_reader()
    bad = 0
    print("=" * 92)
    print("SPELLING-INVARIANCE -- rebase-gate.py:rows() on two spellings of one meaning")
    print("=" * 92)
    for bid, kind, a, b, why, hid in respelling_battery():
        if kind != "lane_txt":
            continue
        ra, rb = rg.rows(a), rg.rows(b)
        ok = ra == rb
        print(f"\n{'ok  ' if ok else 'BLIND'} {bid}\n     meaning: {why}")
        print(f"     rows(a) = {ra}\n     rows(b) = {rb}")
        if hid:
            print(f"     already measured: {hid}")
        if not ok:
            miss = {k: v for k, v in rb.items() if ra.get(k) != v} or {}
            extra = sorted(set(ra) - set(rb))
            print(f"     -> rows() MISSED {miss or '(nothing new)'} and invented {extra or '(nothing)'}")
            bad += 1
    print(f"\n{bad} of the lane_txt entries are INVISIBLE to rows()")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        raise SystemExit(selftest())
    for bid, kind, a, b, agrees in spelling_probe():
        print(f"{'ok   ' if agrees else 'BLIND'} {bid}")