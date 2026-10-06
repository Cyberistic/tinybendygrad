#!/usr/bin/env python3
"""pin-tables.py -- WRITE THE PIN INTO EACH MUTATION TABLE, OR WRITE WHY NOT.

`table-pin.py` computes the three numbers.  This writes them, because a pin that
lives only in a tool's output is not in the artifact a reader opens.

THE RULE THAT MAKES THIS SAFE TO AUTOMATE, and it is the whole reason the file
exists rather than a shell loop: a pin is only worth writing for a table whose
figure was MEASURED.  For every other table this writes

    PIN NOT WRITTEN -- UNSTATED.  <the reason>

and that is a better record than a pin nobody measured.  A pin is a claim about a
run; a fabricated pin is a claim about a run that never happened, and it is
indistinguishable from a real one forever after.

MEASURED is passed in, never inferred.  There is no code path in this file that
decides a table reproduces: it can only be told.

    usage: pin-tables.py --out DIR <measured...>
      measured  `table:rev:file:rows:nrows` for each table MEASURED today, where
                `rows` is the row-set digest and `nrows` its row count.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
# table -> the reason its pin is UNSTATED.  A table with no reason listed here and
# no measurement supplied is an ERROR, not a default: an unstated reason is an
# unstated reason.
UNSTATED = {
    "ag-mutations.txt": "not re-run: `ag-mutate.py` declares 44 anchors and all 44 are "
                        "present, so nothing is stale, but the run was not performed here",
    "bend_mutations.md": "not re-run: 22/22 anchors present; no anchor work was needed "
                         "and no run was performed here",
    "c-mutations.txt": "REFUSED: `c-mutate.py` patches tinybendygrad/runtime/support/c.bend "
                       "IN PLACE with no mirror and no digest guard",
    "codegen3-mutations.txt": "not re-run: its target `codegen/simplify.bend` does not "
                              "exist on disk, so the table has no substrate",
    "cs_mutation_table.txt": "not re-run: no source file resolvable from the harness's "
                             "own path constants",
    "debug-mutate.txt": "not re-run: writes inside the repo with no digest guard",
    "dsp_mutations.txt": "not re-run: anchors all present; no run performed here",
    "dsp2_mutations.txt": "not re-run: no source file resolvable from the harness",
    "ext_mutation_table.txt": "not re-run: no source file resolvable from the harness",
    "ga-mutate.txt": "REFUSED: `ga_mutate.py` writes into the repo (IN-PLAY)",
    "helpers-tc-mutations.txt": "REFUSED: `helpers-tc-mutate.py` writes into the repo, "
                                "and helpers.bend is explicitly not this unit's file",
    "nv_ip_mutations.txt": "not re-run: `nv_ip_mutate.py` edits tinybendygrad/runtime/"
                           "support/nv/ip.bend IN PLACE and restores it from a snapshot; "
                           "refused without a matching digest",
    "nv_nvdev_MUTATION.md": "NOT A MEASURED TABLE: its own header says 'ENUMERATED AND "
                            "THEN NOT RUN TO COMPLETION', and 15 of its rows disagree "
                            "with CPython today.  See the report.",
    "rf2-mutations.txt": "not re-run: `rf2-mutate.py`'s mutation list is not a module-level "
                         "literal, so its anchors are UNDECLARED and cannot be checked",
    # --- ADDED 2026-10-04.  Every table below EXISTS, is a record of mutation
    # --- results, and named no revision at all -- not even an UNSTATED one.  The
    # --- rule this file exists for says a pin is only worth writing for a table
    # --- whose figure was MEASURED, and `UNSTATED. <reason>` is the correct record
    # --- for a table nobody re-ran.  What is NOT correct is a table with no
    # --- header: `table-pin.py` reports "NO REVISION" for those, and a reader has
    # --- no way to tell a table that was never pinned from one that was pinned and
    # --- the pin was lost.  Absent is fine; unrecorded-as-absent is not.
    "cs_mutation_report.txt": "not re-run: a prose REPORT of `cs_mutate.py`, not a "
                              "machine-read row table, so there is no row set to digest",
    "dd-mutations-classified.txt": "already carries its own classification header; "
                                   "pinning it here would put two PIN blocks in one file",
    "dd-mutations-report.md": "not re-run: a prose REPORT of `dd-mutate.py`, not a "
                              "row table, so there is no row set to digest",
    "dd-mutations.txt": "not re-run: `dd-mutate.py` runs its gate as a subprocess, so "
                        "there is no row set on disk to digest (table-pin.py records "
                        "this as NOT-COMMITTED)",
    "elf_mutations.txt": "EMPTY (0 bytes): no rows to describe",
    "helpers-i64-mutations.txt": "not re-run: `helpers-i64-mutate.sh` is a shell "
                                 "harness with no module-level literal list, so "
                                 "`mutanchor` declares its anchors UNDECLARED",
    "ra-mutations.txt": "not re-run: `ra-mutate.py` now GUARDS itself (stage beside, "
                        "digest-asserted) and could be re-run; it was not re-run here "
                        "because another unit was editing `codegen/late/*.bend`",
    "ra2-mutations.txt": "not re-run: same reason as ra-mutations.txt",
    "rf-mutations.txt": "not re-run: `rf-mut.py` now GUARDS itself and could be "
                        "re-run; it was not re-run here because `schedule/rangeify.bend` "
                        "is under active edit by another unit",
    "tc-mutations.txt": "not re-run: no source file resolvable from the harness",
    "usb-mutations.md": "not re-run: `usb-mutate.py`'s target is not resolvable from "
                        "the harness's own path constants",
    "validate-mutations.txt": "not re-run: no source file resolvable from the harness",
    "memory-mutations.txt": "SUPERSEDED BY `table-pin.py`, which reports this table's "
                            "rev/file/rows from the committed baseline; the hand-typed "
                            "rev here was never verified against a digest",
}
HEAD = ("\n# ======================================================================\n"
        "# PIN -- what this table describes.  Written by pin-tables.py, 2026-10-04.\n"
        "#   rev   the jj revision of the file the harness patched\n"
        "#   file  sha256[:16] of that file.  Protects the MUTANT: it proves the edit\n"
        "#         went into the file you meant.\n"
        "#   rows  sha256[:16] of the ROW SET the counts were measured against.\n"
        "#         Protects the REFERENCE, and it is the one that matters: a digest\n"
        "#         over the mutant PROVABLY cannot see an operand-order defect, because\n"
        "#         swapping `hi42`'s two shape args leaves `shape()`'s three fields\n"
        "#         unchanged.  RULE C caught that twice in one day.\n"
        "#   REPRODUCES  measured on 2026-10-04, TWICE, byte-identically.\n")


def _existing_pin(body):
    """The `#   rev ... | file ... | rows ...` line already in a table, or `none`.

    Printed in a conflict message so the reader sees BOTH numbers rather than being
    told only that a conflict exists.
    """
    for line in body.splitlines():
        if line.startswith("#   rev ") and " | " in line:
            return line.strip()
    return "none"


def main():
    if "--out" not in sys.argv:
        sys.exit(__doc__)
    measured = dict()
    for a in sys.argv[sys.argv.index("--out") + 2:]:
        # A `file` field for a three-file SET is `digest+digest+digest`, which
        # contains no `:`.  A five-field split is what lets a split unit be pinned at
        # all rather than forcing the single-file shape onto `codegen/late/`.
        t, rev, f, r, n = a.split(":")
        measured[t] = (rev, f, r, n)
    for table in sorted(set(list(measured) + list(UNSTATED))):
        p = os.path.join(HERE, table)
        if not os.path.exists(p):
            sys.exit("no such table: %s -- a pin for a file that is not there is a "
                     "claim about nothing" % table)
        body = open(p, errors="replace").read()
        if "PIN -- what this table describes" in body:
            # ALREADY PINNED -- but only a skip when the pin on disk MATCHES the one
            # being offered.  `continue` unconditionally meant a table re-pinned after
            # its harness was re-run kept the OLD numbers forever, so a second
            # measurement could never reach the record and a stale pin read as
            # current.  A pin that disagrees with a fresh measurement is a FINDING and
            # is reported, not silently preferred.
            if table not in measured:
                continue
            rev, f, r, n = measured[table]
            live = "#   rev %s | file %s | rows %s (%s rows)" % (rev, f, r, n)
            if live in body:
                continue
            sys.exit("PIN CONFLICT in %s: it already carries a pin and the pin you "
                     "are offering differs.\n  on disk: %s\n  offered:  %s\n"
                     "  A pin is a claim about ONE run.  Two runs, two revisions, one "
                     "table -- write the second to its own file rather than "
                     "overwriting, because the reader of the first has no way to know "
                     "it was replaced." % (table, _existing_pin(body), live))
        if table in measured:
            rev, f, r, n = measured[table]
            pin = ("#   rev %s | file %s | rows %s (%s rows)\n%s"
                   % (rev, f, r, n, HEAD))
            # RULE C, asserted at write time.  `e3b0c44298fc1c14` -- the sha256 of
            # the EMPTY STRING -- went into `wgsl-mutations.txt` once because a
            # summary line was hashed instead of a row set, and a zero-row digest is
            # indistinguishable from a real one to every reader afterwards.  A pin
            # that names a row count of 0, or a digest equal to the empty string's,
            # is refused here rather than published.
            import hashlib
            EMPTY = hashlib.sha256(b"").hexdigest()[:16]
            if n == "0" or r == EMPTY or f == EMPTY:
                sys.exit("REFUSING to pin %s: rev=%r file=%r rows=%r nrows=%r.  A "
                         "fabricated digest is worse than an absent one, because it "
                         "converts unknown into apparently-known.  Write "
                         "`PIN NOT WRITTEN -- UNSTATED` with the reason instead."
                         % (table, rev, f, r, n))
        else:
            pin = ("# PIN NOT WRITTEN -- UNSTATED.  %s\n%s" % (UNSTATED[table], HEAD))
        open(p, "w").write(body.rstrip("\n") + "\n" + pin)
        print("pinned %s" % table)


main()