#!/usr/bin/env python3
"""blob-intern-mutate.py -- the mutation table for `eq_arg.ABlob`, on a STAGED MIRROR.

    .venv/bin/python .agents/slop/blob-intern-mutate.py
    .venv/bin/python .agents/slop/blob-intern-mutate.py --report FILE
    .venv/bin/python .agents/slop/blob-intern-mutate.py --diagnose

CONVERTED 2026-10-04 FROM AN IN-PLACE HARNESS, and the old one is the reason this
file needed converting.  Its own docstring recorded the incident:

    IT MUTATES `tinybendygrad/uop/ops.bend` IN PLACE and restores it from
    `.agents/slop/ops-blob-fixed.pristine.bend` after every step, including on
    failure. ... the restore put the dead 6623-line file back over the live
    6306-line one.

That is a `finally` restore over a file somebody else was editing, and it did the
damage.  `--snapshot` and `--restore` are GONE, and `--restore` is gone because it
is a live-tree writer by construction: it copies a file from 2026-10-04 04:58 onto
`ops.bend`, and no flag should exist whose whole job is to do that.  There is now
no code path in this file that opens a `.bend` for writing, and `live-write-guard.py`
fails the build if one appears.

THE STALE-SNAPSHOT GUARD IS ALSO GONE, and the reason is the interesting half.
It compared live against `PRISTINE` and refused when they differed.  On this tree
right now they DO differ -- live is 369,504 bytes and `PRISTINE` is 287,092 -- so the
old guard refuses to run, while the anchor it was protecting is present EXACTLY ONCE
in the live file.  A guard that refuses for a `file-changed` reason while printing
the words of an `anchor-stale` verdict is worse than no guard, because the operator
cannot tell which one happened.  `--diagnose` prints the three separately.

The substrate is now `staged_mut.Staged`, which:
  * asserts `sha256(jj @) == sha256(live)` at stage time, with
    `jj --ignore-working-copy` so the assertion is a measurement rather than the
    identity that a snapshotting `jj file show` would make it;
  * writes ONLY the staged copy, beside the live file and with no `.bend`
    extension, so it is invisible to `find tinybendygrad -name '*.bend'`;
  * unlinks the staged copy in `finally`, so a kill cannot leave source behind;
  * reports -- rather than papers over -- a live digest that moved during the run.

THE ROW READER IS `rebase-gate.py`'s `rows()`, imported through `staged_mut` and
never transcribed, keyed on NAME over whole `name=value` lines.  This harness
reports the moved rows over the WHOLE row set and marks which of them are
`blob_*`, because a subset reader cannot see a defect that moves a row outside it.

WHAT EACH MUTATION IS.  M1 is the bug: `eq_arg.ABlob`'s ORIGINAL body -- a comparison
of the LENGTH -- restated in the new representation, so it is the pre-fix comparator
rather than a different bug wearing the pre-fix comparator's clothes.  M2 is a key
that separates almost everything.  M3 and M4 are the two ways a content comparison
can be wrong in the OTHER direction: a key that separates everything, and a key
that separates nothing.
"""
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import staged_mut as S                                        # noqa: E402
import patch_not_apply as PNA                                  # noqa: E402

ROOT = S.ROOT
REAL = ROOT / "tinybendygrad" / "uop" / "ops.bend"
PRISTINE = HERE / "ops-blob-fixed.pristine.bend"   # the DEAD SNAPSHOT, read-only now

# The verdict vocabulary is owned by `zero-classify.py` and `patch_not_apply.py` and is
# spelled through them, LOOKED UP BY NAME.  `zero-classify.py` prints
# `UNREACHABLE+proof` and `INVISIBLE-to-reader`, so its query returns five strings that
# are not the five names a table uses; slicing it by position reads the wrong one.
VERDICTS = S.zero_verdict_map()
NOT_A_PROGRAM = PNA.NOT_A_PROGRAM
NO_MUTATION = VERDICTS["NO-MUTATION-WRITTEN"]
PATCH_NOT_APPLY = PNA.MARKER

FIXED = """# CONTENT, NOT A SUMMARY. This arm used to compare `U32.is_eq(n, y1)` on an
# `ABlob{n: U32}` -- the LENGTH -- and two different same-length blobs were then the
# same ucache key: ONE node where `ops.py:201`'s key, which holds the `bytes` object
# and lets dict equality compare bytes content-wise, has two. Measured on the pristine
# tree before the fix: two BINARY nodes with 4-byte args interned to arena index `1,1`
# and `Arena.next - 1 == 1`; CPython answers `False` and `2`. `eq_u32` is the file's
# structural list equality -- the SAME def `eq_arg.ATuple` and `eq_tag.TTuple` compare
# with, so a blob is compared exactly as an axis tuple or a tag tuple is: elementwise,
# order-sensitive, and length-sensitive because the empty/non-empty cases are arms.
def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: eq_u32(bs, y1)
    case _: False{}"""

LEN = """def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: U32.is_eq(U32.from_nat(List.length(&2, U32, bs)), U32.from_nat(List.length(&2, U32, y1)))
    case _: False{}"""

HEAD1 = """def eq_head(bs: List<&2, U32>, y1: List<&2, U32>) -> Bool:
  match bs y1:
    case Nil{} Nil{}: True{}
    case b <> _ w <> _: U32.is_eq(b, w)
    case _ _: False{}

def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: eq_head(bs, y1)
    case _: False{}"""

NEVER = """def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: False{}
    case _: False{}"""

ALWAYS = """def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: True{}
    case _: False{}"""

# (id, description, the exact text that replaces FIXED)
MUTATIONS = [
    ("M1", "eq_arg.ABlob: content -> LENGTH (THE ORIGINAL BUG, restated)", LEN),
    ("M2", "eq_arg.ABlob: content -> FIRST BYTE ONLY", HEAD1),
    ("M3", "eq_arg.ABlob: content -> NEVER EQUAL (a key that separates everything)", NEVER),
    ("M4", "eq_arg.ABlob: content -> ALWAYS EQUAL (a key that separates nothing)", ALWAYS),
]

# A zero may be classified as INVISIBLE only with a REASON, and a reason that names a
# def is not a reason: the refutation of "unreachable" is a counterexample, and only a
# counterexample is one.  These are the arguments this table is prepared to accept, and
# each is a claim about reachability that a reader can CHECK by looking at the row.
ZERO_REASONS = {
    # M3 keeps the arena at one node per blob, so every count row that counts DISTINCT
    # interned nodes must rise.  If a fixture had none, `blob_count_same = 1` and
    # `rra_arena = 1` are both witnesses that the lane counts interning.
    "M3": "no fixture interns two blobs the comparator would separate",
    "M4": "no fixture interns two blobs the comparator would merge",
    "M2": "no fixture interns two blobs differing past byte 0",
    "M1": "no fixture interns two blobs of EQUAL LENGTH and different content",
}


def diagnose():
    """The three conditions the old guard conflated, named separately.

    `anchor-stale`  the anchor is absent from a substrate whose digest was ASSERTED
                    equal to live, so the anchor really is gone.
    `mirror-stale`  `sha256(jj @) != sha256(live)`, so the copy being searched is not
                    the file anybody is looking at.  REACHED BY REFUSAL, not reported.
    `file-changed`  live is not the snapshot the harness was written against.  This is
                    the state RIGHT NOW and it is the one the old guard printed under
                    the words `REFUSING`.
    """
    print("DIAGNOSIS -- three conditions, never one string")
    occ = REAL.read_text().count(FIXED)
    print("  live      %s  %d bytes  sha256 %s"
          % (REAL.relative_to(ROOT), REAL.stat().st_size, S.digest(REAL.read_bytes())[:16]))
    if PRISTINE.exists():
        p = PRISTINE.read_bytes()
        same = p == REAL.read_bytes()
        print("  PRISTINE  %s  %d bytes  sha256 %s   %s"
              % (PRISTINE.name, len(p), S.digest(p)[:16],
                 "file-changed: live != snapshot (the old guard's REFUSING)"
                 if not same else "file-changed: none, live IS the snapshot"))
    else:
        print("  PRISTINE  absent -- the dead snapshot, which no longer gates anything")
    print("  anchor `FIXED` occurrences in LIVE: %d  -> %s"
          % (occ, "anchor-stale: the anchor really is gone" if occ == 0 else
             "ANCHOR PRESENT x%d, so the anchor is NOT stale" % occ))
    r = subprocess.run(["jj", "--ignore-working-copy", "file", "show", "-r", "@", "--",
                        str(REAL.relative_to(ROOT))], cwd=str(ROOT), capture_output=True)
    m = r.stdout
    print("  mirror    sha256(jj --ignore-working-copy @)  %s  -> %s"
          % (S.digest(m)[:16],
             "mirror-stale: REFUSED, nothing measured" if S.digest(m) != S.digest(REAL.read_bytes())
             else "mirror-stale: no, mirror == live"))
    return occ


def classify(mid, moved, compiled):
    """One of the six classes, from the measurement and never from expectation.

    The zero class and the not-a-program class are SEPARATE, and the separation is the
    whole point: a harness that counts lines counts bend's `1007>|` parse-error ROWS on
    stderr, and three mutations that never compiled were once published as "49 rows
    moved" each.  A `DID-NOT-COMPILE` here never carries a row count.
    """
    if moved:
        return "MOVED", ""
    if not compiled:
        return NOT_A_PROGRAM, "the mutant is not a program"
    return VERDICTS["UNREACHABLE"], ZERO_REASONS[mid]


def main():
    if "--diagnose" in sys.argv:
        diagnose()
        return 0

    print("blob-intern-mutate: substrate diagnosis BEFORE staging")
    diagnose()
    print()

    table, tally = [], {}
    with S.Staged(REAL, "blob") as g:
        # THE CONTROL IS THE SAME MIRROR WITH NO EDIT, RUN TWICE.  A baseline can BE
        # the mutant, and the digest is over the ROW SET rather than the file: a
        # count is equal when one row is lost and another gained, and frozen file
        # digests cover the file MUTATED, never the one SAME is measured against.
        g.write(g.origin())
        c1 = g.rows()
        g.write(g.origin())
        c2 = g.rows()
        S.control(c1, c2, "ops.bend unedited staged mirror, two runs")
        base = c1
        print("CONTROL SAME: %d rows, row-set digest %s, both runs\n"
              % (len(base), S.row_digest(base)[:16]))

        for mid, label, body in MUTATIONS:
            occ = g.occurrences(FIXED)
            if occ != 1:
                # RULE: a patch that does not apply prints PATCH-NOT-APPLY.  It never
                # prints a row count, because a row count here would be a count of
                # rows the mutation never had a chance to touch.
                note = "FIXED occurs %dx in the asserted-equal substrate" % occ
                print("%s %s  %s  -- %s" % (mid, PATCH_NOT_APPLY, label, note))
                table.append((mid, label, NO_MUTATION, 0, 0, note))
                tally[NO_MUTATION] = tally.get(NO_MUTATION, 0) + 1
                continue
            g.write(g.origin().replace(FIXED, body, 1))
            if g.text() == g.origin():
                note = "the replacement is byte-identical to the anchor"
                print("%s %s  %s  -- %s" % (mid, NO_MUTATION, label, note))
                table.append((mid, label, NO_MUTATION, 0, 0, note))
                tally[NO_MUTATION] = tally.get(NO_MUTATION, 0) + 1
                continue
            got = g.try_rows()
            g.write(g.origin())                     # restore from pristine, not from disk
            moved = [] if got is None else \
                sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
            blobm = [k for k in moved if k.startswith("blob_")]
            verdict, why = classify(mid, moved, got is not None)
            tally[verdict] = tally.get(verdict, 0) + 1
            table.append((mid, label, verdict, len(moved), len(blobm), why))
            print("%s %-18s rows_moved=%-4d blob_rows_moved=%-3d  %s" %
                  (mid, verdict, len(moved), len(blobm), label))
            for k in moved:
                print("      %-26s %s -> %s" % (k, base.get(k), got.get(k)))
            if why:
                print("      reason offered: %s" % why)
        print()
        print("SUBSTRATE  live=%s staged=%s  (%d rows, %d blob_*)"
              % (g.live_sha[:16], g.mirror_sha[:16], len(base),
                 sum(1 for k in base if k.startswith("blob_"))))
        live_after = g.live_digest()
        print("LIVE AFTER %s  ->  %s" % (g.live_sha[:16], live_after[:16]))

    out = None
    if "--report" in sys.argv:
        out = pathlib.Path(sys.argv[sys.argv.index("--report") + 1])
        lines = ["blob-intern-mutate -- STAGED, live tree never written",
                 "substrate tinybendygrad/uop/ops.bend, sha256(mirror)==sha256(live) asserted",
                 "reader rebase-gate.rows(), keyed on NAME over whole name=value lines",
                 "control SAME on %d rows, row-set digest %s" % (len(base), S.row_digest(base)[:16]),
                 "load: measured on this tree, see the report",
                 "",
                 "ID  VERDICT  ROWS  BLOB  DESCRIPTION"]
        for mid, label, verdict, n, nb, why in table:
            lines.append("%-4s %-18s %-5d %-5d %s%s"
                         % (mid, verdict, n, nb, label, ("  [" + why + "]") if why else ""))
        out.write_text("\n".join(lines) + "\n")
        print("wrote %s" % out)

    print()
    print("%d mutations: %s" % (len(MUTATIONS),
                                ", ".join("%s=%d" % kv for kv in sorted(tally.items()))))
    for v in (VERDICTS["UNREACHABLE"], VERDICTS["PORT-DEFECT"], VERDICTS["INVISIBLE"],
              NOT_A_PROGRAM, NO_MUTATION):
        for mid, label, verdict, _, _, why in table:
            if verdict == v:
                print("  %-20s %s  %s%s" % (v, mid, label, ("  -- " + why) if why else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())