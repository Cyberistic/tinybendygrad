#!/usr/bin/env python3
"""false-zero-sweep.py -- which committed mutation records can no longer tell a
MEASUREMENT from a DEAD PATCH?

THE QUESTION, and it is deliberately not "is this zero real".  A row reading `0`
is only a problem when the record cannot say WHICH of two things produced it:

  * the patch applied and moved nothing  -> a coverage fact, and a REQUEST FOR A
    FIXTURE (agent-core.md: a `0` is a request for a fixture, never a claim); or
  * the patch never landed                -> no measurement was taken at all, and
    the `0` is a fabrication.

Those are opposite findings about the port and the record prints the same two
characters for both.  `ops-python-mutations.txt:7` was the second kind and read
as the first.

SO THIS DOES NOT RE-RUN ANYTHING, and it says so rather than implying a
measurement.  It is a RE-PARSE of two things already on disk:

  1. THE RECORD.  Every `*mutat*` table's rows, and for each row whether the cell
     that would hold a count holds a bare `0`.
  2. THE PRODUCER.  Each harness's own not-applied marker, read from its SOURCE.
     A report cannot say which branch produced its own figure -- that is the
     whole lesson -- so the only place the answer lives is the branch body, and
     the only honest move is to instrument the producer and re-read it.

A row is flagged AMBIGUOUS when its count cell's first token is a digit AND the
producing harness could have written a count there at all, i.e. nothing in the
record distinguishes the two branches.  It is flagged REPRODUCIBLE-NOT when the
harness's anchor for that mutation id is absent from the file the harness names
today, so re-running cannot re-derive the figure -- which is a statement about
reproducibility, NOT a claim that the recorded number was wrong.

  usage: false-zero-sweep.py [--verbose]
  exits 1 if any row is AMBIGUOUS.
"""
import ast
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import patch_not_apply as PNA
# The predicates are IMPORTED, not re-implemented: "what is a stale-anchor branch"
# answered twice is two answers, and they will disagree -- which is this defect.
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location("naa", os.path.join(HERE, "not-applied-audit.py"))
NAA = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(NAA)

# Every committed mutation record in this directory, with the harness that
# produced it.  A table whose producer cannot be named is REPORTED, never skipped
# silently -- an unparsed table read as a clean one is a failure this project has
# already paid for six times.
TABLES = [
    ("ag-mutations.txt", "ag-mutate.py"),
    ("amdev_mut.txt", "amdev_mutate.py"),
    ("bend_mutations.md", "bend_mutate.py"),
    ("c-mutations.txt", "c-mutate.py"),
    ("codegen3-mutations.txt", "codegen3-mut.py"),
    ("cs_mutation_table.txt", "cs_mutate.py"),
    ("debug-mutate.txt", "debug-mutate.py"),
    ("dsp_mutations.txt", "dsp_mutate.py"),
    ("dsp2_mutations.txt", "dsp2-mutate.py"),
    ("ext_mutation_table.txt", "ext_mutate.py"),
    ("ga-mutate.txt", "ga_mutate.py"),
    ("helpers-i64-mutations.txt", "helpers-tc-mutate.py"),
    ("helpers-tc-mutations.txt", "helpers-tc-mutate.py"),
    ("lift-mut-table.txt", "nv_ip_mutate.py"),
    ("nv_ip_mutations.txt", "nv_ip_mutate.py"),
    ("nv_nvdev_MUTATION.md", "nv_mutate.py"),
    ("ops-python-mutations.txt", "ops-python-mutate.py"),
    ("rf-arg-mutations.txt", "rf-arg-mutate.py"),
    ("rf2-mutations.txt", "rf2-mutate.py"),
    ("tc-mutations.txt", "tc-mutate.py"),
    ("usb-mutations.md", "usb-mutate.py"),
]
ID = re.compile(r'\b([A-Z]{1,3}\d+[a-z]?)\b')


def rows_with_zero_count(path):
    """(lineno, id, the count cell) for every row whose count cell reads `0`.

    A row's count cell is the cell whose FIRST TOKEN is a digit; a marker cell
    starts with a word.  That is the same first-token rule the RULE D audit uses,
    and for the same reason: `int(cell)` is the lenient test and it is the wrong
    one.
    """
    out = []
    for n, line in enumerate(open(path, errors="replace").read().splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        # `|`-delimited rows split on `|`; the space-aligned tables (amdev, rf,
        # nv_ip) split on runs of whitespace.  NESTING the second case inside the
        # first test skipped every space-aligned row in this directory, which is
        # how a sweep reports "clean" over half the records it was pointed at.
        if line.lstrip().startswith("|"):
            cells = line.split("|")[1:-1]
        else:
            cells = [c for c in re.split(r"\s{2,}|\t", line) if c.strip()]
        for c in cells:
            tok = c.strip().split()
            if tok and re.fullmatch(r'0', tok[0]):
                m = ID.search(line)
                out.append((n, m.group(1) if m else "?", c.strip()))
                break
    return out


def harness_marker(path):
    """Does this harness route its stale-anchor branch through the shared reporter?

    Asked of the SOURCE with the RULE D audit's own predicates, because a report
    cannot say which branch produced its own figure.  Read, never executed: many
    of these harnesses run their whole mutation loop at import, and three mutate
    the LIVE tree in place.
    """
    try:
        tree = ast.parse(open(path, errors="replace").read())
    except (OSError, SyntaxError):
        return None
    alias, bound = NAA.count_aliases(tree), NAA.reporter_aliases(tree)
    found = False
    for n in ast.walk(tree):
        if not (isinstance(n, ast.If) and NAA.is_stale_anchor(n.test, alias)):
            continue
        found = True
        if NAA.calls_reporter(n.body, bound):
            return PNA.MARKER
    return None if found else False


def anchors(harness):
    """`{id: anchor}` read statically from the harness's literal mutation list.

    `ast.literal_eval` and NOT an import, because importing a harness runs its
    main loop.  A list that is not a pure literal yields None and is reported as
    undeclared rather than guessed at.
    """
    try:
        tree = ast.parse(open(harness, errors="replace").read())
    except (OSError, SyntaxError):
        return None
    for n in tree.body:
        if isinstance(n, ast.Assign) and len(n.targets) == 1 \
           and isinstance(n.targets[0], ast.Name):
            try:
                v = ast.literal_eval(n.value)
            except (ValueError, SyntaxError, TypeError):
                continue
            if isinstance(v, list) and v and isinstance(v[0], (tuple, list)):
                out = {}
                for e in v:
                    if len(e) > 1 and isinstance(e[0], str):
                        anchor = e[1] if isinstance(e[1], str) else None
                        if anchor is None and len(e) > 3 and isinstance(e[3], str):
                            anchor = e[3]
                        out[e[0]] = anchor
                return out
    return None


def target_text(harness):
    """The file this harness patches, read from the harness's own path constants."""
    try:
        tree = ast.parse(open(harness, errors="replace").read())
    except (OSError, SyntaxError):
        return None
    for n in tree.body:
        if isinstance(n, ast.Assign) and len(n.targets) == 1 \
           and isinstance(n.targets[0], ast.Name) \
           and n.targets[0].id in ("SRC", "TARGET", "BEND", "F", "PORT"):
            v = n.value
            if isinstance(v, ast.Constant) and isinstance(v.value, str) \
               and v.value.endswith((".bend", ".py")):
                p = v.value if os.path.isabs(v.value) else os.path.join(ROOT, v.value)
                return p if os.path.exists(p) else None
    return None


def main():
    verbose = "--verbose" in sys.argv
    W = 78
    print("=" * W)
    print("FALSE-ZERO SWEEP -- committed mutation records, re-parsed.  NOT re-run.")
    print("A row is AMBIGUOUS when its count cell reads 0 and NOTHING in the record")
    print("distinguishes 'moved nothing' from 'the patch never landed'.")
    print("=" * W)
    print("%-26s %5s %6s %8s  %s" % ("RECORD", "ROWS", "ZERO", "FINDING", "STATE"))
    print("-" * W)
    grand = amb = 0
    notes = []
    for table, harness in TABLES:
        p = os.path.join(HERE, table)
        if not os.path.exists(p):
            print("%-26s %5s %6s %8s  %s" % (table[:26], "-", "-", "-", "NO FILE"))
            notes.append((table, "no file"))
            continue
        zs = rows_with_zero_count(p)
        grand += len(zs)
        hp = os.path.join(HERE, harness)
        marker = harness_marker(hp) if os.path.exists(hp) else None
        anc, tgt = (anchors(hp), target_text(hp)) if os.path.exists(hp) else (None, None)
        text = open(tgt, errors="replace").read() if tgt else None
        flagged = []
        for ln, mid, cell in zs:
            # AMBIGUOUS: the harness, AS IT STANDS, could not have written a word
            # here, so the row is a measurement -- but if it was written BEFORE the
            # marker existed, the same shape meant a dead patch.  Either way the
            # record alone cannot settle it.
            now_marker = marker is not None
            stale_anchor = (mid in (anc or {}) and anc[mid] and text is not None
                            and anc[mid] not in text)
            if stale_anchor:
                flagged.append((ln, mid, "ANCHOR-GONE", "anchor absent from %s NOW; the "
                                "recorded 0 cannot be re-derived"
                                % os.path.basename(tgt)))
            elif marker is False:
                flagged.append((ln, mid, "NO-GUARD", "the producer has no stale-anchor "
                                "branch at all, so nothing in it can say how this 0 "
                                "was produced"))
            elif not now_marker:
                flagged.append((ln, mid, "UNMARKED", "producer writes its own marker, so "
                                "this 0 is indistinguishable from a dead patch"))
            else:
                flagged.append((ln, mid, "MEASURED?", "the producer can only write a "
                                "count here, so the patch applied and moved nothing "
                                "-- still a REQUEST, not a claim"))
        un = sum(1 for f in flagged if f[2] in ("UNMARKED", "NO-GUARD"))
        amb += un
        state = ("%d flagged, %d unmarked" % (len(flagged), un)) if flagged \
            else "no bare-0 count"
        print("%-26s %5d %6d %8d  %s" % (table[:26], len(zs), len(zs), un, state))
        for ln, mid, kind, why in flagged:
            print("      %-26s %s  %-12s %s" % ("%s:%d" % (table, ln), mid, kind, why))
            if verbose:
                print("          count cell %r" % mid)
    print("-" * W)
    print("THE DENOMINATOR: %d committed rows carry a bare-0 count across %d records."
          % (grand, len(TABLES)))
    print("  of those, %d are UNMARKED -- the producer writes no marker there, so"
          % amb)
    print("  the record cannot say which branch produced its own figure.")
    print("  ANCHOR-GONE is a REPRODUCIBILITY finding, not a claim the number was")
    print("  wrong: the anchor is absent from the file the harness names TODAY, so")
    print("  re-running cannot re-derive the figure.  Fix the record honestly --")
    print("  %s, never a re-run nobody performed." % PNA.MARKER)
    print("=" * W)
    if notes:
        print("REPORTED, NEVER SKIPPED SILENTLY:")
        for t, why in notes:
            print("  %-28s %s" % (t, why))
        print("=" * W)
    if amb:
        sys.exit(1)


main()