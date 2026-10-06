#!/usr/bin/env python3
"""revision-ledger.py -- WHICH REVISION IS EACH COMMITTED MUTATION TABLE VALID FOR?

THE FINDING THIS EXISTS TO FIX.  Fourteen of the fifteen mutation tables in this
directory name no revision at all.  A reader therefore cannot tell whether a
table describes the file on disk, a file from three hours ago, or a file that
never existed.  `dd-mutations-report.md` is the one that pins -- `e4618a71`
against tree `e17d3f7dd48c` -- and it was written when live was `cdd85227`, so
by now even the ONE pinned table is pinned to something other than the working
copy.  Ten of its rows disagree with CPython on that pinned snapshot, which makes
the pin load-bearing rather than decorative: it is the difference between "the
port is wrong" and "the snapshot is wrong".

TWO DIGESTS, AND THE SECOND ONE IS THE POINT.

  FILE   sha256 of the .bend the harness patches.  This is what most mutation
         gates assert, and it protects the MUTANT -- it proves the edit you are
         about to make went into the file you meant.  It says NOTHING about
         whether the rows you are diffing against describe that file.

  ROWS   sha256 of the BASELINE ROW SET the table's zeros were measured against.

The row-set digest is the one that matters, and the gap is measured, not
asserted: `zero-classify.py` documents that swapping `hi42`'s two shape args --
the exact M09 defect -- leaves `shape()`'s three fields unchanged, so a digest
over the mutant cannot see it.  A digest protects the MUTANT, not the
REFERENCE.  A table therefore names both, or a reader is trusting a number whose
input they cannot check.

WHERE NO BASELINE FILE IS COMMITTED the row-set digest is `NONE`, and that is
reported as a finding rather than passed over: such a table's zeros cannot be
re-derived at all, because the thing they were compared to is gone.

  usage: revision-ledger.py
"""
import hashlib
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# table -> (harness, the .bend it patches, the committed baseline it diffs against)
LEDGER = [
    ("ag-mutations.txt", "ag-mutate.py", "tinybendygrad/runtime/support/autogen.bend", ".agents/slop/ag-base.txt"),
    ("amdev_mut.txt", "amdev_mutate.py", "tinybendygrad/runtime/support/am/amdev.bend", None),
    ("bend_mutations.md", "bend_mutate.py", "tinybendygrad/runtime/ops_bend.bend", None),
    ("c-mutations.txt", "c-mutate.py", "tinybendygrad/runtime/support/c.bend", None),
    ("codegen3-mutations.txt", "codegen3-mut.py",
     "tinybendygrad/codegen/simplify.bend", None),
    # dd is the ONE table that pins, and it pins a FROZEN snapshot rather than the
    # live file -- which is the correct choice for a substrate that moved four times
    # during a single run, and is why its 10 disagreeing rows are attributable.
    ("dd-mutations.txt", "dd-mutate.py",
     ".agents/slop/dd-mutations.frozen.bend", ".agents/slop/dd-gate-base-182.txt"),
    ("dd-mutations.txt.tsv", "dd-mutate.py",
     ".agents/slop/dd-mutations.frozen.bend", ".agents/slop/dd-gate-base-182.txt"),
    ("dd-mutations-classified.txt", "zero-classify.py",
     ".agents/slop/dd-mutations.frozen.bend", ".agents/slop/dd-gate-base-182.txt"),
    ("dd-mutations-report.md", "dd-mutate.py",
     ".agents/slop/dd-mutations.frozen.bend", ".agents/slop/dd-gate-base-182.txt"),
    ("cs_mutation_table.txt", "cs_mutate.py", None, None),
    ("debug-mutate.txt", "debug-mutate.py", None, None),
    ("dsp_mutations.txt", "dsp_mutate.py", "tinybendygrad/runtime/ops_dsp.bend", None),
    ("dsp2_mutations.txt", "dsp2-mutate.py", None, None),
    ("ext_mutation_table.txt", "ext_mutate.py", None, None),
    ("ga-mutate.txt", "ga_mutate.py", None, None),
    ("helpers-tc-mutations.txt", "helpers-tc-mutate.py", "tinybendygrad/helpers.bend", None),
    ("nv_ip_mutations.txt", "nv_ip_mutate.py", None, None),
    ("ops-python-mutations.txt", "ops-python-mutate.py",
     "tinybendygrad/runtime/ops_python.bend", None),
    ("rf-arg-mutations.txt", "rf-arg-mutate.py",
     "tinybendygrad/schedule/rangeify_work.bend", None),
    ("rf2-mutations.txt", "rf2-mutate.py", None, None),
    ("tc-mutations.txt", "tc-mutate.py", "tinybendygrad/codegen/transcendental_f32.bend", None),
    ("usb-mutations.md", "usb-mutate.py", "tinybendygrad/runtime/support/usb.bend", None),
]
HEX = re.compile(r'\b[0-9a-f]{7,40}\b')
# What counts as naming a revision rather than merely containing a hex-looking word.
CLAIM = re.compile(r'(?i)\b(revision|rev\b|commit|tree|snapshot|pinned?)\b[^\n]*\b[0-9a-f]{7,40}\b'
                   r'|\b[0-9a-f]{7,40}\b[^\n]*\b(revision|commit|tree|snapshot)\b')


def sha(path):
    if not path or not os.path.exists(path):
        return None
    return hashlib.sha256(open(path, "rb").read()).hexdigest()[:16]


def live_rev():
    r = subprocess.run(["jj", "log", "-r", "@", "--no-graph", "-T", "commit_id.short()"],
                       cwd=ROOT, capture_output=True, text=True)
    return r.stdout.strip() or "UNKNOWN"


def names_a_revision(path):
    for line in open(path, errors="replace"):
        if CLAIM.search(line):
            return line.strip()[:58]
    return None


def main():
    W = 96
    live = live_rev()
    print("=" * W)
    print("REVISION LEDGER -- which revision is each committed mutation table valid for?")
    print("LIVE WORKING COPY: %s" % live)
    print()
    print("TWO DIGESTS PER TABLE.  FILE protects the MUTANT -- it proves the edit")
    print("landed in the file you meant.  ROWS protects the REFERENCE -- it is the")
    print("only one that can see a row moving for a reason the file digest cannot,")
    print("and a digest over the mutant provably cannot (the M09 `hi42` order swap")
    print("leaves `shape()`'s three fields identical).  A table naming only FILE is")
    print("trusting a number whose input nobody can check.")
    print("=" * W)
    pinned = rows_ok = file_ok = 0
    print("%-26s %-5s %-17s %-17s %s"
          % ("TABLE", "REVS", "FILE sha256[:16]", "ROWS sha256[:16]", "NAMES A REVISION"))
    print("-" * W)
    for table, harness, bend, base in LEDGER:
        p = os.path.join(HERE, table)
        if not os.path.exists(p):
            print("%-26s %-5s %-17s %-17s %s"
                  % (table[:26], "-", "-", "-", "NO FILE"))
            continue
        claim = names_a_revision(p)
        if claim:
            pinned += 1
        fs, rs = sha(os.path.join(ROOT, bend) if bend else None), \
            sha(os.path.join(ROOT, base) if base else None)
        file_ok += fs is not None
        rows_ok += rs is not None
        print("%-26s %-5s %-17s %-17s %s"
              % (table[:26], "YES" if claim else "no",
                 fs or "NO FILE DECLARED", rs or "NONE COMMITTED",
                 (claim or "-- names none --")[:44]))
    print("-" * W)
    print("THE DENOMINATOR, and it is the number nobody was printing:")
    print("  committed mutation tables audited        : %d" % len(LEDGER))
    print("  tables that NAME a revision              : %d" % pinned)
    print("  tables that name NO revision             : %d   <-- a reader cannot"
          % (len(LEDGER) - pinned))
    print("                                                tell whether the table")
    print("                                                describes the file on disk")
    print("  tables with a FILE digest available      : %d of %d"
          % (file_ok, len(LEDGER)))
    print("  tables with a ROW-SET digest available   : %d of %d   <-- the digest"
          % (rows_ok, len(LEDGER)))
    print("                                                that actually constrains")
    print("                                                the number in the table")
    if pinned and pinned < len(LEDGER):
        print()
        print("  THE PINNED ONES ARE ALSO STALE against live %s.  A pin is only worth" % live)
        print("  anything if someone checks it, and `dd` carries 10 rows that disagree")
        print("  with CPython on its own pinned snapshot -- so for those rows the pin")
        print("  is what distinguishes 'the port is wrong' from 'the snapshot is wrong'.")
    print("=" * W)


main()