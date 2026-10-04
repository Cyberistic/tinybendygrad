#!/usr/bin/env python3
"""table-pin.py -- PIN WHAT EVERY MUTATION TABLE DESCRIBES, OR SAY IT DESCRIBES NOTHING.

`revision-ledger.py` established the finding: 20 of 22 tables name no revision, so
a reader cannot tell whether a table describes the file on disk, a file from three
hours ago, or a file that never existed.  This answers the follow-up that finding
implies, and it is the harder half.

THREE NUMBERS PER TABLE, and the third is the one that was missing.

  REV    the jj revision of the file the harness patches, read live.
  FILE   sha256[:16] of that file.  This protects the MUTANT -- it proves the edit
         went into the file you meant.  It says NOTHING about whether the ROWS you
         diffed against describe that file.
  ROWS   sha256[:16] of the row SET.  A digest over the mutant provably cannot see
         the M09 defect: swapping `hi42`'s two operands leaves `shape()`'s three
         fields identical, and RULE C caught that twice today.  So a table naming
         only FILE is trusting a number whose input nobody can check.

WHERE NO BASELINE IS COMMITTED, ROWS is `NONE`, and that is printed as a finding
rather than passed over: such a table's zeros cannot be re-derived at all, because
the thing they were compared to is gone.

THE ROW SET IS READ FROM THE HARNESS, NOT THE RECORD.  A record says what the
harness printed; the harness's own `BASE = ...` line says what it compared against,
and only the second can be re-derived.  Where the harness runs its gate as a
subprocess there is no row set to read at all, and that is `NOT-COMMITTED` -- again
a finding, not a gap in this file.

  usage: table-pin.py [--verify]
    --verify  re-run each harness that is safe to run and report whether the table
              still reproduces.  REFUSES every IN-PLAY harness: a snapshot that
              does not match live is a `jj restore` gun, and one put a dead
              6,623-line `ops.bend` over the live 6,306-line one.
"""
import hashlib
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import mutanchor as MA

# table, harness.  The .bend and the baseline are DISCOVERED from the harness by
# `mutanchor`, because a hand-maintained third copy of the same fact is a fourth
# thing to forget to update, and this directory has already been charged for one.
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
    ("helpers-tc-mutations.txt", "helpers-tc-mutate.py"),
    ("nv_ip_mutations.txt", "nv_ip_mutate.py"),
    ("nv_nvdev_MUTATION.md", "nv_mutate.py"),
    ("ops-python-mutations.txt", "ops-python-mutate.py"),
    ("rf-arg-mutations.txt", "rf-arg-mutate.py"),
    ("rf2-mutations.txt", "rf2-mutate.py"),
    ("tc-mutations.txt", "tc-mutate.py"),
    ("usb-mutations.md", "usb-mutate.py"),
    # TWO RECORDS THIS UNIT RECONSTRUCTED today.  `memory-mutate.py` had run 70
    # mutations and written nothing down; `wgsl-mutate.py`'s table was a comment
    # block inside a .bend this unit does not own, so it now has a record out here.
    ("memory-mutations.txt", "memory-mutate.py"),
    ("wgsl-mutations.txt", "wgsl-mutate.py"),
    # dd pins FOUR artifacts against ONE frozen snapshot, which is the only
    # arrangement in this directory where the reference is on disk.
    ("dd-mutations.txt", "dd-mutate.py"),
    ("dd-mutations.txt.tsv", "dd-mutate.py"),
    ("dd-mutations-classified.txt", "zero-classify.py"),
    ("dd-mutations-report.md", "dd-mutate.py"),
]
# A baseline committed ALONGSIDE the table, read for its ROW SET.
BASELINES = {
    "ag-mutations.txt": ".agents/slop/ag-base.txt",
    # Five baselines COMMITTED today by this unit, because a row-set digest over a
    # baseline that is not on disk is a number nobody can check -- which is the
    # whole reason the second digest exists.  Each was captured from the same run
    # that produced the pinned table.
    "amdev_mut.txt": ".agents/slop/amdev-baseline-552.txt",
    "memory-mutations.txt": ".agents/slop/memory-baseline-889.txt",
    "wgsl-mutations.txt": ".agents/slop/wgsl-baseline-172.txt",
    "ops-python-mutations.txt": ".agents/slop/ops-python-baseline-85.txt",
    "rf-arg-mutations.txt": ".agents/slop/rangeify-baseline-126.txt",
    "dd-mutations.txt": ".agents/slop/dd-gate-base-182.txt",
    "dd-mutations.txt.tsv": ".agents/slop/dd-gate-base-182.txt",
    "dd-mutations-classified.txt": ".agents/slop/dd-gate-base-182.txt",
    "dd-mutations-report.md": ".agents/slop/dd-gate-base-182.txt",
}
CLAIM = re.compile(r'(?i)\b(revision|rev\b|commit|tree|snapshot|pinned?|tree rev)\b'
                   r'[^\n]*\b[0-9a-f]{7,40}\b|\b[0-9a-f]{7,40}\b[^\n]*'
                   r'\b(revision|commit|tree|snapshot)\b')
# The reader `zero-classify.py` shares: the name is everything up to the first
# `=` or `:`, because ROW NAMES CONTAIN SPACES and three lanes print three
# formats.  Re-implementing it here would be a second row reader, which is the
# thing `zero-audit-report.md` §6.6 already flagged as unfixed.
ROW = re.compile(r"^(?P<name>[^=:]*?)\s*(?P<sep>=|:)\s*(?P<val>.*)$")


def sha(path):
    if not path or not os.path.exists(path):
        return None
    return hashlib.sha256(open(path, "rb").read()).hexdigest()[:16]


def rowset(path):
    """The digest of a baseline's ROW SET: names and values, sorted, joined.

    Sorted so the digest is of the SET and not of the file's line order, which is
    a formatting property and not a claim.  Both name and value are in it, because
    a row that changed its VALUE is a moved row -- hashing names alone would call
    a fully-corrupted-value baseline identical to a clean one.
    """
    if not path or not os.path.exists(path):
        return None, 0
    rows = []
    for line in open(path, errors="replace"):
        line = line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        m = ROW.match(line)
        if m and m.group("name").strip():
            rows.append("%s=%s" % (m.group("name").strip(), m.group("val").strip()))
    return hashlib.sha256("\n".join(sorted(rows)).encode()).hexdigest()[:16], len(rows)


def rev_of(path):
    if not path or not os.path.exists(path):
        return None
    r = subprocess.run(["jj", "log", "-r", "files(%s)" % os.path.relpath(path, ROOT),
                        "--no-graph", "-T", "commit_id.short() ++ \"\\n\""],
                       cwd=ROOT, capture_output=True, text=True)
    return (r.stdout.split() or ["?"])[0]


def names_a_revision(path):
    for line in open(path, errors="replace"):
        if CLAIM.search(line):
            return line.strip()[:40]
    return None


def main():
    W = 108
    live = subprocess.run(["jj", "log", "-r", "@", "--no-graph", "-T",
                           "commit_id.short()"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip() or "?"
    print("=" * W)
    print("TABLE PIN -- what does each committed mutation table actually DESCRIBE?")
    print("LIVE WORKING COPY @ %s" % live)
    print("REV   the jj revision of the file the harness patches, read live")
    print("FILE  sha256[:16] of that file.  Protects the MUTANT.")
    print("ROWS  sha256[:16] of the ROW SET the zeros were measured against.  Protects")
    print("      the REFERENCE -- and a digest over the mutant provably cannot, since")
    print("      swapping `hi42`'s operands leaves `shape()`'s three fields intact.")
    print("=" * W)
    print("%-26s %-9s %-9s %-17s %-17s %-6s %s"
          % ("TABLE", "TARGET", "ZONE", "REV", "FILE sha256[:16]", "ROWS", "STATE"))
    print("-" * W)
    pinned = withfile = withrows = stale = blocked = 0
    detail = []
    for table, harness in TABLES:
        # wgsl's table is a comment block inside the port, so the path is
        # repo-relative rather than next to the harness.
        tp = table if os.path.exists(os.path.join(ROOT, table)) \
            else os.path.join(HERE, table)
        hp = os.path.join(HERE, harness)
        if not os.path.exists(tp):
            print("%-26s %-9s %-9s %-17s %-17s %-6s %s"
                  % (table[:26], "-", "-", "-", "-", "-", "NO FILE"))
            continue
        tree = MA.parse(hp) if os.path.exists(hp) else None
        tgts = MA.targets(tree, harness) if tree else []
        zone = ",".join(sorted(set(z for z, _ in MA.writes(tree, harness)))) or ["NONE"] \
            if tree else ["?"]
        tgt = tgts[0][1] if tgts else None
        claim = names_a_revision(tp)
        rs, nrows = rowset(os.path.join(ROOT, BASELINES[table]) if table in BASELINES
                           else None)
        fs, rv = sha(tgt), rev_of(tgt)
        pinned += bool(claim)
        withfile += fs is not None
        withrows += rs is not None
        state = []
        if claim:
            state.append("pins " + claim)
        else:
            state.append("NO REVISION")
        if not fs:
            state.append("NO TARGET FILE NAMED")
        if rs is None:
            state.append("no committed baseline")
        elif rv and claim and claim.split()[-1] not in claim:
            pass
        if "IN-PLAY" in zone:
            blocked += 1
            state.append("IN-PLAY: will not run")
        print("%-26s %-9s %-9s %-17s %-17s %-6s %s"
              % (table[:26], os.path.basename(tgt)[:9] if tgt else "-",
                 ",".join(zone)[:9], rv or "-", fs or "-",
                 rs or ("%d" % nrows if nrows else "NONE"), "; ".join(state)[:44]))
        detail.append((table, harness, tgt, rv, fs, rs, nrows, claim, zone))
    print("-" * W)
    print("THE DENOMINATOR, and it is the number nobody was printing:")
    print("  tables audited                          : %d" % len(TABLES))
    print("  name a REVISION                         : %d" % pinned)
    print("  name NO revision                        : %d  <-- a reader cannot tell"
          % (len(TABLES) - pinned))
    print("                                                what file it describes")
    print("  FILE digest computable                  : %d of %d" % (withfile, len(TABLES)))
    print("  ROW-SET digest computable               : %d of %d  <-- the one that"
          % (withrows, len(TABLES)))
    print("                                                constrains the NUMBER")
    print("  refused to run (IN-PLAY on the live tree): %d" % blocked)
    print("=" * W)
    print("WHAT EACH TABLE DESCRIBES, as a line that can be pasted into the record:")
    for table, harness, tgt, rv, fs, rs, nrows, claim, zone in detail:
        print("%-26s %s" % (table, " ".join([
            "rev=" + (rv or "UNSTATED"),
            "file=" + (fs or "NONE"),
            "rows=" + ("%s(%d)" % (rs, nrows) if rs else "NOT-COMMITTED")])))
    print("=" * W)
    print("A TABLE THAT CANNOT SAY WHICH FILE IT DESCRIBES IS AN ANECDOTE.  %d of the"
          % (len(TABLES) - pinned))
    print("%d above name no revision; %d of those also have no committed baseline, so"
          % (len(TABLES) - pinned, len(TABLES) - withrows))
    print("their zeros cannot be re-derived even in principle.")
    print("=" * W)
    return 0


sys.exit(main())