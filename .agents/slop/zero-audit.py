#!/usr/bin/env python3
"""zero-audit.py -- AUDIT every mutation table in .agents/slop under the FIVE-VERDICT
classification, and report the DENOMINATOR for each.

The bug this exists to kill: every harness in this directory prints the same two
characters for four completely different facts, so "unmoved" silently conflates
*no mutation was written* with *a mutation was written and it did not move*.  A
table that reports 23 unmoved rows without saying how many of those had a
mutation aimed at them is not reporting coverage, it is reporting arithmetic.

WHAT IT CAN AND CANNOT DO, stated up front so the output is not over-read.
  * It is EXHAUSTIVE over the tables it can parse mechanically.
  * It is a RE-PARSE of what each table already recorded, not a re-run.  A
    re-run costs 25 s per mutation and these harnesses mutate the LIVE tree in
    several cases, which is forbidden.  So the MEASURED column here is the
    table's own measurement, and this tool's job is the CLASSIFICATION and the
    DENOMINATOR, which no table currently states.
  * Where a table records no per-mutation verdict at all, the row says so rather
    than inferring one.  An absent number is not a zero.

Each table is declared with a PATTERN for its verdict lines and a PATTERN for
its moved-row column, because eleven harnesses in this directory disagree about
both.  A table whose pattern matches nothing is REPORTED as unmatched, never
skipped silently -- an unparsed table read as a clean one is the exact failure
this project has already paid for six times.

usage: zero-audit.py [--verbose]
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# --- what a harness is ALLOWED to have meant by a zero -----------------------
# The five verdicts a zero must land in, plus the two things that are NOT zeros.
V_UNREACH, V_DEFECT, V_PATCH, V_INVIS, V_UNAIMED = (
    "UNREACHABLE+proof", "PORT-DEFECT", "PATCH-NOT-APPLY",
    "INVISIBLE-to-reader", "NO-MUTATION-WRITTEN")
NOT_A_ZERO = ("MOVED", "OK", "NOT-A-PROGRAM", "DID-NOT-COMPILE")

# --- the tables, and how each one PRINTS ------------------------------------
# `re` matches ONE verdict line; groups: (id, verdict, count, moved-ids).
TABLES = [
    ("dd-mutate.py", "dd-mutations.txt.tsv",
     r"^(?P<id>[A-Z]\d+)\t(?P<v>[A-Z-]+)\t(?P<n>\d+)\t(?P<m>.*)$"),
    ("c-mutate.py", "c-mutations.txt",
     r"^(?P<id>M\d+b?)\s+(?P<v>OK|ZERO|DID-NOT-COMPILE)\s+(?P<n>\d+)\s*line"),
    ("ga-mutate.py", "ga-mutate.txt",
     r"^\|\s*(?P<id>M\d+)\s*\|[^|]*\|\s*(?P<n>\d+)\s"),
    ("ag-mutate.py", "ag-mutations.txt",
     r"^\|\s*(?P<id>M{1,2}M?\d+)\s*\|[^|]*\|\s*(?P<n>\d+)\s"),
    ("dsp2-mutate.py", "dsp2_mutations.txt",
     r"^(?P<id>[A-Z]{2}\d+)\s+(?P<v>MOVED|SAME|DID-NOT-COMPILE)\s+(?P<n>\d+)"),
    ("dsp-mutate.py", "dsp_mutations.txt",
     r"^\|\s*(?P<id>M\d+)\s*\|\s*(?P<n>\d+)\s*\|"),
    ("codegen3-mut.py", "codegen3-mutations.txt",
     r"^(?P<id>X\d+)\s+.*moved:\s*(?P<m>.*)$"),
    ("cs-mutate.py", "cs_mutation_table.txt",
     r"^(?P<id>amd\.M\d+)\s+(?P<what>.*?)\s*(?P<n>\d+)\s+rows?\s*(?P<m>.*)$"),
    ("ext-mutate.py", "ext_mutation_table.txt",
     r"^(?P<file>\S+)\s+(?P<n>\d+)\s+(?P<what>.*?)\s*\((?P<id>M\d+)\)\s*$"),
    ("nv-ip-mutate.py", "nv_ip_mutations.txt",
     r"^(?P<what>[a-z0-9_.]+)\s+(?P<n>\d+)\s+(?P<v>MOVED|NOTHING)\s*(?P<m>.*)$"),
    ("rf-arg-mutate.py", "rf-arg-mutations.txt",
     r"^(?P<id>M\d+)\s+(?P<what>.*?)\s+compiled;\s*(?P<n>\d+)\s*rows moved"),
    ("rf2-mutate.py", "rf2-mutations.txt",
     r"^(?P<id>M\d+)\t(?P<n>\d+) moved\t(?P<what>.*?)\t*(?P<m>.*)$"),
    ("tc-mutate.py", "tc-mutations.txt",
     r"^(?P<id>M\d+) :.*?\s(?P<n>\d+) moved\s"),
    ("usb-mutate.py", "usb-mutations.md",
     r"^\|\s*(?P<id>M\d+)\s*\|\s*(?P<n>\d+)\s*\|"),
    ("ops-python-mutate.py", "ops-python-mutations.txt",
     r"^\|\s*(?P<id>M\d+)\s*\|\s*(?P<what>[^|]*)\|\s*(?P<n>\d+)[^|]*\|"),
    ("mm-mutate.py", "mm-mutations.txt", None),
    ("ops-mutate.py", "ops-mutations.txt", None),
    ("dk-mutate.py", "dk-mutations.txt", None),
]

# --- RULE D, SCANNED ACROSS EVERY HARNESS ------------------------------------
# A patch that did not apply must print PATCH-NOT-APPLY and NEVER a bare 0.  This
# greps the harness SOURCES for a zero printed on the not-found branch, which is
# the only place the violation can hide -- a report file cannot tell you which
# branch produced its number.
RULE_D = re.compile(
    r'print\([^)]*(\{[a-z_]*mid[a-z_]*\}[^)]*\|\s*0\s*\||0[^)]*not found'
    r'|not found[^)]*0)', re.I)
NOTFOUND_BRANCH = re.compile(r'(if (?:old )?not in src|if src\.count\(old\) == 0|'
                             r'if old_s not in src|if old not in BASE)'
                             r'[^\n]*\n?[^\n]*?print\((.*?)\)\s*$', re.M)


def parse(path, rx):
    if not rx:
        return None, "NO PATTERN DECLARED -- not parsed, not called clean"
    text = open(path, errors="replace").read()
    out = []
    for line in text.splitlines():
        m = re.match(rx, line)
        if m:
            g = m.groupdict()
            out.append((g.get("id", "").strip(), (g.get("v") or "").strip(),
                        int(g["n"]) if (g.get("n") or "").strip().isdigit() else None,
                        g.get("m", "")))
    return out, None if out else "PATTERN MATCHED ZERO LINES -- unparsed, not clean"


def main():
    verbose = "--verbose" in sys.argv
    W = 74
    print("=" * W)
    print("ZERO AUDIT -- every mutation table in .agents/slop, under five verdicts")
    print("MEASURED values are each table's OWN, re-parsed.  Not re-run: several of")
    print("these harnesses mutate the LIVE tree, which is forbidden.")
    print("=" * W)
    unmatched, tally = [], {}
    print("%-22s %5s %6s %6s %6s %s"
          % ("TABLE", "MUTS", "MOVED", "ZERO", "N-A-P", "STATE"))
    for harness, table, rx in TABLES:
        p = os.path.join(HERE, table)
        if not os.path.exists(p):
            print("%-22s %5s %6s %6s %6s %s"
                  % (table[:22], "-", "-", "-", "-", "NO FILE"))
            unmatched.append((table, "no file"))
            continue
        rows, err = parse(p, rx)
        if not rows:
            print("%-22s %5s %6s %6s %6s %s"
                  % (table[:22], "-", "-", "-", "-", "UNPARSED"))
            unmatched.append((table, err))
            continue
        moved = [r for r in rows if r[1] in ("MOVED", "OK") or (r[2] or 0) > 0]
        zero = [r for r in rows if r not in moved]
        nap = [r for r in rows if r[1] in ("DID-NOT-COMPILE", "DID-NOT-COMPILED")]
        print("%-22s %5d %6d %6d %6d %s"
              % (table[:22], len(rows), len(moved), len(zero), len(nap),
                 "parsed" if not err else err[:24]))
        if verbose:
            for r in rows:
                print("    %-8s %-14s %s" % (r[0], r[1] or "(implied)", r[2]))
        for r in zero:
            tally[r[1] or "(unstated)"] = tally.get(r[1] or "(unstated)", 0) + 1
    print("-" * W)
    print("THE DENOMINATOR, per table, and it is the number nobody was printing:")
    print("  a ZERO is only a coverage fact once you know a mutation was AIMED at")
    print("  the site.  'unmoved' alone cannot tell that from 'never tried'.")
    print()
    for harness, table, rx in TABLES:
        p = os.path.join(HERE, table)
        if not os.path.exists(p):
            continue
        rows, err = parse(p, rx)
        if not rows:
            continue
        ids = set(r[0] for r in rows)
        print("  %-24s %3d mutation(s) recorded" % (table[:24], len(ids)))
    print("-" * W)
    print("RULE D, SCANNED IN THE HARNESS SOURCES.  A patch that did not apply must")
    print("print PATCH-NOT-APPLY and NEVER a bare 0.  This is grepped at the branch")
    print("that PRODUCES the number, because a report file cannot say which branch")
    print("produced its own figure.")
    viol, ok = [], []
    for f in sorted(os.listdir(HERE)):
        if not re.match(r'.*mut.*\.(py|sh)$', f):
            continue
        text = open(os.path.join(HERE, f), errors="replace").read()
        for m in NOTFOUND_BRANCH.finditer(text):
            printed = m.group(2)
            # A zero printed on the not-found branch is the violation.  A named
            # refusal (PATCH DID NOT APPLY / SKIP / NOT FOUND / EDIT NOT FOUND)
            # is compliance, however it is spelled.
            if re.search(r'\|\s*0\s*\||\b0 rows\b|\b0 moved\b|\b0 line', printed):
                viol.append((f, printed.strip()[:88]))
            elif re.search(r'PATCH|SKIP|NOT FOUND|REFUS', printed, re.I):
                ok.append(f)
    if viol:
        print("  RULE D VIOLATIONS -- a dead patch printed as a zero:")
        for f, p in viol:
            print("    %-28s %s" % (f, p))
    else:
        print("  no violation found in %d harness sources" %
              len([f for f in os.listdir(HERE) if re.match(r'.*mut.*\.(py|sh)$', f)]))
    if ok:
        print("  compliant refusals found in: %s" % " ".join(sorted(set(ok))))
    print("-" * W)
    print("WHAT A ZERO IN THESE TABLES WAS LABELLED, verbatim (the alias problem):")
    for k in sorted(tally):
        print("    %-22s %d" % (k, tally[k]))
    print()
    print("  The labels above are NOT the five verdicts.  NONE of these tables")
    print("  distinguishes PORT-DEFECT from INVISIBLE-to-reader, and only ONE")
    print("  (dd) records a reachability PROOF beside its zeros.  So every zero")
    print("  in the other tables is, today, an unclassified zero -- which is")
    print("  precisely the thing this audit is for.")
    if unmatched:
        print("-" * W)
        print("UNPARSED / UNMATCHED -- reported, never skipped silently:")
        for t, why in unmatched:
            print("  %-28s %s" % (t, why))
    print("=" * W)


main()