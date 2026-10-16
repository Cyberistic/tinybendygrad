#!/usr/bin/env python3
"""zero-classify.py -- A ZERO CLASSIFIES ITSELF.  Five verdicts, never a bare `0 rows`.

WHY THIS EXISTS.  A mutation table's whole worth is that a mutation which moves
nothing is suspicious.  Every harness in `.agents/slop` prints that suspicion as
the same two characters -- `0 rows` -- and the four things it can mean are
enormously different:

  1. UNREACHABLE+proof   the site genuinely cannot be called.  A THEOREM, with a
                         MEASUREMENT behind it (the rename compiled and the gate
                         output stayed byte-identical).
  2. PORT-DEFECT         the site IS called and a row asserts a WRONG value.  A
                         defect wearing a coverage fact's clothes.  `l2i_shl.hi`
                         read `SAME -- 0 rows` and was classified REQUEST; the
                         real cause was an arena-aliasing defect in the PINNED
                         SNAPSHOT that overwrote the index pointing at the site, so
                         `lg9p` printed `BITCAST(WHERE)` where CPython has
                         `BITCAST(OR)`.  **A 0 measured against a snapshot with a
                         known defect in it is a statement about the snapshot.**
  3. PATCH-NOT-APPLY     the edit never landed.  RULE D: never a "0 rows".
  4. INVISIBLE-to-reader the reader cannot see the node.  `M05` re-aimed at
                         `l2i_cast3.bitc` gave 0 because `lg7` is `dtype.py:39`'s
                         only fixture and `bitcast(uint)` FOLDS on it, so the node
                         the arm exists to build was in no row at all.
  5. NO-MUTATION-WRITTEN no mutation was aimed at the site.  11 of the dd table's
                         23 unmoved rows were in this bucket and were reported as
                         though they were coverage.  **This is the denominator.**

THE MECHANICAL TEST SEPARATING 2 FROM 4.  Both are zeros; both are reachable;
neither is a missing patch.  They are told apart by TWO questions, both string
questions over data already on disk, asked in this order:

    Q1 WRONG?    does any baseline row in the site's FAMILY DISAGREE with the
                 CPython oracle for the same row name?  A disagreement is a row
                 asserting something untrue, so the port is broken exactly where
                 the reader can see it.                                       -> 2
    Q2 VISIBLE?  does CPython's answer AT THE SITE -- a measured substring,
                 declared per site in --site-answer and never typed here --
                 appear in the value of ANY baseline row?
                 If Q1 is silent and Q2 is no, the site is simply not in any
                 row: the reader cannot see it.                             -> 4

So: WRONG before VISIBLE.  A row that lies is a defect even when it is also the
only witness; a row that is silent is only a coverage gap.  Asking "is it zero?"
never decides it, and comparing against zero never decides it -- a wrong value is
not a zero, and CPython is the only thing that can say so.

CONTAINMENT, which is what makes the denominator real.  A site is a DEF.
`l2i_shl.hi` is inside the family `l2i`.  A family is "aimed" when some aimed
site equals it or is dotted under it, and "visible" when some row belongs to it.
So the universe of sites is NOT the mutation list -- it is every `def` in the
file, read from the file, which is what lets an unaimed site be named.

CONTROLS ARE NOT ZEROS.  A RULE C control is SUPPOSED to read SAME; `0 rows` is
its required outcome and is the guard that makes every other verdict mean
something.  They are counted and printed separately and are excluded from the
tally, because a table whose tally includes its own smoke detector is not
reporting coverage.

usage:
  zero-classify.py --table T.tsv --base BASE.txt --defs FILE.bend
                   [--oracle ORACLE.txt] [--oracle-extra A.txt,B.txt]
                   [--aim A.tsv] [--family F.tsv] [--proof P.tsv]
                   [--site-answer S.tsv] [--label NAME] [--rev REV] [--out O.tsv]
  T.tsv       ID <TAB> VERDICT <TAB> NROWS <TAB> moved,row,...   (dd-mutate.py's TSV)
  A.tsv       ID <TAB> DEF                   which site each mutation is aimed at
  F.tsv       ROWREGEX <TAB> FAMILY          which family each baseline row is in
  P.tsv       ID <TAB> unreachable|intercepted <TAB> EVIDENCE
  S.tsv       SITE <TAB> SUBSTRING           CPython's answer AT the site, MEASURED

VERDICTS, and there are five and no sixth:
  UNREACHABLE+proof | PORT-DEFECT | PATCH-NOT-APPLY | INVISIBLE-to-reader |
  NO-MUTATION-WRITTEN
A zero that cannot be placed in one of the five is an ERROR, never a pass.
"""
import os
import re
import sys

V_UNREACH, V_DEFECT, V_PATCH, V_INVIS, V_UNAIMED = (
    "UNREACHABLE+proof", "PORT-DEFECT", "PATCH-NOT-APPLY",
    "INVISIBLE-to-reader", "NO-MUTATION-WRITTEN")
FIVE = (V_UNREACH, V_DEFECT, V_PATCH, V_INVIS, V_UNAIMED)
# What a HARNESS is allowed to report as its raw measurement.  An id outside this
# set is refused rather than classified: a typo in a table's verdict column must
# not become a confident coverage claim, and "unrecognised" must not be a sixth
# bucket that reads like a pass.
MEASURED = ("MOVED", "SAME", "UNCHANGED", "NO-ROWS",
            "PATCH-NOT-APPLIED", "PATCH-NOT-APPLY",
            "DID-NOT-COMPILE", "DID-NOT-COMPILED")

# RULE F: LC_ALL=C -- locale-colating sort fabricated 6 spurious diffs here.
# ROW NAMES CONTAIN SPACES and lanes print THREE formats (`name=value`,
# `name = [v]  py=[w]`, `name  value`), so the name is everything up to the first
# `=` or `:` and never a whitespace split.  Same reader as unobservable-census.py.
ROW = re.compile(r"^(?P<name>[^=:]*?)\s*(?P<sep>=|:)\s*(?P<val>.*)$")
DEF = re.compile(r"^def ([A-Za-z_][A-Za-z0-9_.]*)\(")


def rows_of(path):
    out = {}
    if not path:
        return out
    for line in open(path, errors="replace").read().splitlines():
        line = line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        m = ROW.match(line)
        if m and m.group("name").strip():
            out[m.group("name").strip()] = m.group("val").strip()
    return out


def tsv(path, cols):
    out = []
    if not path:
        return out
    for line in open(path).read().splitlines():
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        out.append((line.split("\t") + [""] * cols)[:cols])
    return out


def inside(site, fam):
    """Is `site` inside the family `fam`?

    BEND NAMESPACES WITH AN UNDERSCORE, NOT A DOT.  `def l2i_shl.hi(` defines a
    sub-def of `l2i_shl`, which is itself a sub-def of `l2i` -- there is no
    `l2i.` in any name.  So containment is a prefix test on the UNDERSCORE
    segments, and the naive `site.startswith(fam + ".")` that reads correctly for
    every other language in this repo silently fails here: it classifies every
    `l2i_*` site as belonging to NO family, which is what made the first run
    report M09 as UNDECLARED rather than PORT-DEFECT.  A classifier that cannot
    see a family is worse than one that has no opinion.
    """
    return site == fam or site.startswith(fam + "_") or site.startswith(fam + ".")


def main():
    if "--verdicts" in sys.argv:
        # The five are QUERYABLE rather than re-read out of this file's source:
        # a self-test that regexes its own tool's constants tests the regex.
        for v in FIVE:
            print(v)
        return
    arg = sys.argv[1:]
    opt = {}
    for i, a in enumerate(arg):
        if a.startswith("--"):
            opt[a[2:]] = arg[i + 1] if i + 1 < len(arg) and not arg[i + 1].startswith("--") else "1"

    base = rows_of(opt.get("base"))
    oracle = rows_of(opt.get("oracle"))
    # `--oracle-extra` ADDS lanes rather than replacing one, so a table whose rows
    # came from several probes can be compared in FULL.  It exists because
    # "the oracle covers 174 of 182" is a coverage statement, and the classifier
    # must not quietly compare only the 174.
    for extra in (opt.get("oracle-extra") or "").split(","):
        if extra:
            oracle.update(rows_of(extra))

    aim = dict((i, d) for i, d in tsv(opt.get("aim"), 2))
    proof = dict((i, (k, ev)) for i, k, ev in tsv(opt.get("proof"), 3))
    site_ans = dict(tsv(opt.get("site-answer"), 2))
    family = [(re.compile(rx), d) for rx, d in tsv(opt.get("family"), 2)]
    fams_all = sorted(set(d for _, d in family))

    def fam_of(row):
        for rx, d in family:
            if rx.search(row):
                return d
        return None

    # THE SITE UNIVERSE, read from the file rather than from the mutation list.
    # This is the denominator: a def nobody aimed at is a gap in the TABLE, and
    # it cannot be discovered from the table because the table does not mention it.
    defs = set()
    for path in (opt.get("defs") or "").split(","):
        if path and os.path.exists(path):
            defs |= set(DEF.match(l).group(1) for l in
                        open(path, errors="replace").read().splitlines()
                        if DEF.match(l))
    aimed = set(aim.values())

    # Q1's evidence: rows that DISAGREE with CPython.  A set, so a row that
    # disagrees is counted once however many sites are asked about it.
    wrong = set(n for n in base if n in oracle and base[n] != oracle[n])
    wrong_by_fam = {}
    for n in wrong:
        f = fam_of(n)
        if f:
            wrong_by_fam.setdefault(f, []).append(n)

    entries, rows, ctl = [], [], []
    unknown = []
    for eid, verdict, n, moved in tsv(opt.get("table"), 4):
        moved = [m for m in moved.split(",") if m]
        n = int(n) if n.strip().isdigit() else len(moved)
        if verdict not in MEASURED:
            unknown.append((eid, verdict))
        rec = (eid, verdict, n, moved)
        (ctl if eid[:1] == "C" else entries).append(rec)
    if unknown:
        sys.exit("REFUSING: unrecognised MEASURED verdict(s) %s.  The five "
                 "verdicts are decided from a known measurement; an unknown "
                 "measurement is a typo or a new harness, and classifying it "
                 "would invent a coverage claim."
                 % ", ".join("%s=%s" % u for u in unknown))

    for eid, verdict, n, moved in entries:
        site = aim.get(eid)
        if verdict in ("PATCH-NOT-APPLIED", "PATCH-NOT-APPLY"):
            v, why = V_PATCH, "the edit never landed (RULE D: never a bare `0 rows`)"
        elif verdict in ("DID-NOT-COMPILE", "DID-NOT-COMPILED"):
            # RULE B: a mutation that is not a PROGRAM says nothing about
            # coverage -- not even zero.  It is a bucket of its own and it is
            # counted separately, because reporting it as a coverage fact is the
            # same error as reporting a zero as a pass.
            v, why = "NOT-A-PROGRAM", "the mutant does not compile (RULE B): not a zero"
        elif verdict == "MOVED":
            v, why = None, "the gate output changed -- not a zero"
        elif site is None:
            v, why = V_UNAIMED, "%s names no def in --aim, so no site was aimed at" % eid
        elif eid in proof and proof[eid][0] in ("unreachable", "intercepted"):
            v = V_UNREACH
            why = "%s: %s" % proof[eid]
        else:
            ans = site_ans.get(site)
            fams = [f for f in fams_all if inside(site, f)]
            # Q1 is a PER-SITE JOIN, not a family vote.  An earlier version asked
            # only "does any row in this site's family disagree", and because the
            # `l2i` family is deliberately coarse that made all 51 disagreeing
            # `l2i` rows an alibi for EVERY `l2i_*` site -- it would have called
            # M06 a defect when M06 is a proven THEOREM.  The join key is the
            # site's own declared CPython answer: a row can only witness a
            # defect AT this site if CPython's answer for this site is in it.
            hit = sorted(n for n in wrong
                         if ans and ans in oracle.get(n, "")) if ans else []
            seen = sorted(n for n, v in base.items()
                          if ans and ans in v and n not in wrong)
            if hit:
                v = V_DEFECT
                why = ("Q1 WRONG + JOINED: %d disagreeing row(s) carry CPython's "
                       "answer at this site (%r) -- %s.  The port is broken where "
                       "the reader can see it, so this 0 is a fact about the "
                       "SNAPSHOT, not about coverage." % (len(hit), ans, " ".join(hit)))
            elif ans is None:
                v = V_INVIS
                why = ("reachable (no proof); %s has NO --site-answer, so the "
                       "visibility question is UNDECLARED rather than measured.  "
                       "Declare it and re-run -- an unmeasured zero is not a "
                       "verdict." % site)
            elif not seen:
                v = V_INVIS
                why = ("Q1 silent, Q2 VISIBLE=no: CPython's answer at this site "
                       "(%r) is in NO baseline row -- not even a wrong one.  The "
                       "reader cannot see the node; it wants a FIXTURE." % ans)
            else:
                v = V_INVIS
                why = ("Q1 silent, Q2 VISIBLE=yes in %d row(s) (%s), all AGREEING "
                       "with CPython.  The port is right here, so this zero is "
                       "invisibility AT this site's answer -- a coarser row shape "
                       "cannot separate this mutation."
                       % (len(seen), " ".join(seen[:8])))
        rows.append((eid, verdict, n, site, v, why))

    tally = {}
    nonprog = 0
    for r in rows:
        if r[4] == "NOT-A-PROGRAM":
            nonprog += 1
        elif r[4]:
            tally[r[4]] = tally.get(r[4], 0) + 1

    # ---- the denominator, in the units that make it a statement ----
    fam_of_row = dict((n, fam_of(n)) for n in base)
    unattributed = sorted(n for n, f in fam_of_row.items() if f is None)
    moved_all = set(m for _, verdict, _, m in entries if verdict == "MOVED" for m in m)
    unmoved = sorted(n for n in base if n not in moved_all)
    # A row is COVERED when some MOVED mutation touched it.  Rows left over are
    # split by WHY, which is the whole point: a row whose family has no aimed
    # mutation was never a candidate, and a row whose family DOES have one is a
    # real gap at a site somebody looked at.
    gap_aimed = [n for n in unmoved
                 if fam_of_row[n] and any(inside(s, fam_of_row[n]) for s in aimed)]
    gap_unaimed = [n for n in unmoved if n not in gap_aimed]

    label = opt.get("label", opt.get("table", "?"))
    W = 78
    print("=" * W)
    print("ZERO CLASSIFICATION -- %s" % label)
    print("VALID FOR REVISION: %s" % opt.get("rev", "UNSTATED"))
    print("baseline %d rows | oracle %d rows | %d DISAGREE with CPython | "
          "%d baseline rows have NO CPython answer"
          % (len(base), len(oracle), len(wrong), sum(1 for n in base if n not in oracle)))
    if wrong:
        print("  DISAGREEING: %s" % " ".join(sorted(wrong)))
    if opt.get("oracle") and any(n not in oracle for n in base):
        print("  ORACLE GAP:  %s" % " ".join(sorted(n for n in base if n not in oracle)))
    print("-" * W)
    print("%-5s %-9s %4s %-18s %s" % ("ID", "MEASURED", "ROWS", "SITE", "VERDICT"))
    for eid, verdict, n, site, v, why in rows:
        print("%-5s %-9s %4d %-18s %s" % (eid, verdict, n, site or "-", v or "(not a zero)"))
        if v:
            print("      %s" % why)
    print("-" * W)
    print("CONTROLS (RULE C -- NOT counted as zeros; `0 rows` is their REQUIRED "
          "outcome and they are the guard on every verdict above)")
    for eid, verdict, n, moved in ctl:
        print("  %-5s %-9s %4d rows" % (eid, verdict, n))
    print("-" * W)
    print("TALLY of the %d mutations: %s"
          % (len(rows), " | ".join("%s %d" % (v, tally.get(v, 0)) for v in FIVE)))
    print("MOVED (not a zero): %d" % sum(1 for r in rows if r[4] is None))
    print("NOT-A-PROGRAM (RULE B, also not a zero): %d" % nonprog)
    print("")
    print("THE DENOMINATOR -- what was AIMED is not what MOVED")
    print("  defs in the file (the site universe) : %d" % len(defs))
    print("  distinct sites a mutation aimed at    : %d" % len(aimed))
    print("  aimed sites NOT a def in this file    : %d  %s"
          % (len(aimed - defs), " ".join(sorted(aimed - defs))))
    print("  families with NO aimed mutation       : %d  %s"
          % (len([f for f in set(fam_of_row.values()) if f
                  and not any(inside(s, f) for s in aimed)]),
             " ".join(sorted(f for f in set(fam_of_row.values())
                             if f and not any(inside(s, f) for s in aimed)))))
    print("  baseline rows UNATTRIBUTED            : %d  %s"
          % (len(unattributed), " ".join(unattributed)))
    print("  baseline rows COVERED (a mutation moved them) : %d of %d"
          % (len(base) - len(unmoved), len(base)))
    print("  unmoved rows at a site that WAS aimed  : %d  %s"
          % (len(gap_aimed), " ".join(gap_aimed)))
    print("  unmoved rows whose family has NO aimed mutation : %d  %s"
          % (len(gap_unaimed), " ".join(gap_unaimed)))
    if opt.get("out"):
        with open(opt["out"], "w") as fh:
            fh.write("# zero-classify.py -- %s\n# VALID FOR REVISION: %s\n"
                     % (label, opt.get("rev", "UNSTATED")))
            fh.write("# %d baseline rows, %d disagree with CPython, %d have no "
                     "CPython answer\n" % (len(base), len(wrong),
                                           sum(1 for n in base if n not in oracle)))
            fh.write("# ID\tMEASURED\tROWS\tSITE\tVERDICT\tWHY\n")
            for eid, verdict, n, site, v, why in rows:
                fh.write("%s\t%s\t%d\t%s\t%s\t%s\n"
                         % (eid, verdict, n, site or "", v or "MOVED", why))
            for eid, verdict, n, moved in ctl:
                fh.write("%s\t%s\t%d\t\tCONTROL\tRULE C guard; 0 rows is required\n"
                         % (eid, verdict, n))
    for v in FIVE:
        if not tally.get(v):
            print("  NOTE: %s unused by this table -- the table does not exercise it"
                  % v)
    bad = [r for r in rows if r[4] is not None and r[4] not in FIVE
           and r[4] != "NOT-A-PROGRAM"]
    if bad:
        sys.exit("REFUSING: %d verdict(s) outside the five -- a zero must classify "
                 "itself and 'unclassified' is not one of them" % len(bad))


main()