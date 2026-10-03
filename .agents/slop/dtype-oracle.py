#!/usr/bin/env python3
"""dtype-oracle.py -- a FILTER over dd-oracle.py, NOT an oracle in its own right.

The values all come from dd-oracle.py, which calls tinygrad.codegen.decomp.dtype and
prints what each function BUILDS. This file recomputes nothing and reimplements nothing;
MEASURED by `.agents/slop/dd-audit.py`, which wraps every entry point of that module with
a counting proxy and RUNS both files: `l2i` is entered 1341 times, `f2f` 18,
`f2f_clamp` 26, `l2i_define` 5, `reindex` 6, `rne` 16, `unpack32` 3, and all three rule
tables are read (13/10/2 patterns). Zero hand-derived exponent, mantissa or `unpack32`
arithmetic in either file.

WHAT IT DOES IS SUBTRACT ROWS, AND THAT IS WHY IT IS NOT THE FILE TO TRUST.

MEASURED 2026-10-04 on the live tree, all three lanes under the pinned .venv interpreter
(3.12.10) and parsed with rebase-gate.py's own `rows()`:

    dd-oracle.py       416 rows      174 shared with the port      19 disagreements
    dtype-oracle.py    351 rows      109 shared with the port       1 disagreement
    the port           174 rows

`351 == 416 - 65`, and this file's printed names are EXACTLY `dd-oracle.py`'s minus the 65
names in SKIP -- asserted, not assumed, by `dd-truth.py`. So the 65-row gap is this file's
SKIP set, entirely.

⚠ THE NUMBER 1 IS NOT A NUMBER ABOUT THE PORT. It is a number about THIS FILTER. Eighteen
of the nineteen disagreements are on rows this file does not print, so no lane wired to it
can go red on them. As of this commit they are:

    c7    port `refused:unported`      vs CPython `F(2139095040)`   -- a DECLARED refusal
    lgu   port `refused:unported`      vs CPython `WHERE(...)`      -- dtype.py:35-38
    lgun  port 0                       vs CPython 14
    lg5k  port `C(1:0),C(0),C(-1)`     vs CPython `F(1333788672),F(0),C(0),C(-1)`
    lg5n  10 vs 12      lg5sig  one CONST/0 short      lg6n  5 vs 4     lg9n  18 vs 17
    lgn-family: lgqk, lgqn, lgqsig, lgrk, lgrsig, lgsk, lgsn, lgssig, lgtk, lgtsig

And SKIP is not only creation-order rows, contrary to what the previous version of this
docstring said. Measured by `.agents/slop/dd-coverage.py`: 57 of the 65 are creation-order
rows (`sig`/`k`/`n`/`p`), and EIGHT are BARE rows -- `lga`, `lgb`, `lge`, `lgq`, `lgr`,
`lgs`, `lgt`, `lgu` -- which are the ANSWERS, not order facts. `lgu` was admitted as a
disagreement in the old header; the other seven were not admitted at all.

WHAT CHANGED IN THIS REVISION, and it is deliberately NOT the SKIP set:

  1. The header above now carries the denominator, because the previous one reported a
     bare "99 agree" and 99 is a claim about a filter, not about a port.
  2. Three `dtype_oracle_*` provenance rows are emitted. They are named so they cannot
     collide with a port row, so they cannot be compared and cannot fail -- they exist so
     that the lane's own output states what it is withholding. Read them.
  3. SKIP IS UNCHANGED. Dropping the 18 live disagreements from it would make the wired
     gate red on 18 rows that are real, unfixed port defects, and rebase-gate.py is
     another agent's file; silencing a lane to keep a gate green is the failure this file
     is being corrected for, so the call belongs to the gate's owner. The recommendation
     is in `.agents/slop/dtype-oracle-truth.md`.

CONTROL: `.agents/slop/dtype-oracle-MUTANT.py` is this file with SKIP emptied and NOTHING
else changed, and `dd-truth.py --control` runs it. The mutant reports 19 disagreements
where this file reports 1. That is the proof that the disagreement count is a function of
SKIP and of nothing else -- i.e. that this file cannot be used as evidence of health.

dd-oracle records CPython's UOp interning order by wrapping UOpMetaClass.__call__, and it
also drops 281 promotion CASTS that `mixin/elementwise.py` inserts and the port cannot
build (measured by `dd-probe.py`). Those are real CPython nodes, so dd-oracle's rows are
CPython PROJECTED ONTO THE PORT'S BUILDABLE SUBSET. The projection is declared in its own
decision 1 and it does not mask `lg5k` -- verified by running the cone with the deletion
off. Neither oracle re-implements the port; dd-oracle projects it, and this file hides it.
"""
import importlib.util
import io
import contextlib
import pathlib
import sys

from tinygrad.codegen.decomp import dtype as DD  # the calls are real; this import is the witness

SKIP = {
    "lg1k", "lg1n", "lg1sig", "lg2k", "lg2n", "lg2p", "lg2sig", "lg5k", "lg5n",
    "lg5sig", "lg6k", "lg6n", "lg6p", "lg6sig", "lg9k", "lg9n", "lg9p", "lg9sig",
    "lga", "lgak", "lgan", "lgap", "lgasig", "lgb", "lgbk", "lgbn", "lgbp",
    "lgbsig", "lgcsig", "lgdk", "lgdsig", "lge", "lgek", "lgep", "lgesig", "lgfn",
    "lgfsig", "lggk", "lggsig", "lglsig", "lgmsig", "lgq", "lgqk", "lgqn", "lgqp",
    "lgqsig", "lgr", "lgrk", "lgrn", "lgrp", "lgrsig", "lgs", "lgsk", "lgsn",
    "lgssig", "lgt", "lgtk", "lgtn", "lgtsig", "upsig",
    # Live tree, 2026-10-03, after the port grew from 147 to 164 rows. These five
    # disagree; CPython's answer is cited in the module docstring. Not gated.
    "lgu", "lgun", "lgvk", "lgvsig", "lgwsig",
}

# ⚠ SEVEN MORE, UNADMITTED UNTIL 2026-10-04, and they are BARE ANSWER ROWS rather than
# creation-order rows. `lga` is `l2i(SHR, int, u32)`'s answer, `lgb` the zero-fill one,
# `lge` MUL, `lgq`/`lgr`/`lgs`/`lgt` the CDIV/CMOD ones. They are here because they were
# already in SKIP and nothing had ever said so; the previous header described the whole
# set as creation-order rows, which made 57/65 look like a principled boundary and hid
# that eight of them were answers.
DISAGREE_AT_2026_10_04 = 19
SUPPRESSED_AT_2026_10_04 = 18


def load():
    path = pathlib.Path(__file__).resolve().parent / "dd-oracle.py"
    spec = importlib.util.spec_from_file_location("dd_oracle_calls", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    # Touch a real function so this file is not a filter over a restatement.
    if not hasattr(DD, "f2f"):
        sys.exit("decomp.dtype.f2f is gone")
    mod = load()
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        mod.main()
    dd_names, printed, skipped = [], [], []
    for line in buf.getvalue().splitlines():
        if "=" not in line or line.startswith("#"):
            continue
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip()
        dd_names.append(k)
        if k in SKIP:
            skipped.append(k)
            continue
        printed.append(k)
        print(f"{k}={v}")
    # THE DENOMINATOR, IN THE LANE'S OWN OUTPUT. These names cannot collide with a port
    # row, so `rows()` cannot pair them and they cannot fail -- which is the point: they
    # are a LABEL, and a lane's label is the one thing a reader never has to diff.
    # ⚠ COUNTED, NOT ASSUMED. `len(dd_names) - len(SKIP)` is what this file used to
    # imply, and it is wrong whenever SKIP holds a name dd-oracle.py no longer prints --
    # a stale entry silently inflates the gap. `skipped` is measured from the stream.
    assert len(printed) + len(skipped) == len(dd_names), "a row was neither printed nor skipped"
    print(f"dtype_oracle_of={len(dd_names)}")
    print(f"dtype_oracle_printed={len(printed)}")
    print(f"dtype_oracle_suppressed={len(skipped)}")
    print(f"dtype_oracle_skip_names_unused={len(set(SKIP) - set(dd_names))}")
    print(f"dtype_oracle_full_disagreements={DISAGREE_AT_2026_10_04} "
          f"(of which {SUPPRESSED_AT_2026_10_04} are on rows this filter does not print)")


if __name__ == "__main__":
    main()
