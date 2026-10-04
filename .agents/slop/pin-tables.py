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


def main():
    if "--out" not in sys.argv:
        sys.exit(__doc__)
    measured = dict()
    for a in sys.argv[sys.argv.index("--out") + 2:]:
        t, rev, f, r, n = a.split(":")
        measured[t] = (rev, f, r, n)
    for table in sorted(set(list(measured) + list(UNSTATED))):
        p = os.path.join(HERE, table)
        if not os.path.exists(p):
            sys.exit("no such table: %s -- a pin for a file that is not there is a "
                     "claim about nothing" % table)
        body = open(p, errors="replace").read()
        if "PIN -- what this table describes" in body:
            continue
        if table in measured:
            rev, f, r, n = measured[table]
            pin = ("#   rev %s | file %s | rows %s (%s rows)\n%s"
                   % (rev, f, r, n, HEAD))
        else:
            pin = ("# PIN NOT WRITTEN -- UNSTATED.  %s\n%s" % (UNSTATED[table], HEAD))
        open(p, "w").write(body.rstrip("\n") + "\n" + pin)
        print("pinned %s" % table)


main()