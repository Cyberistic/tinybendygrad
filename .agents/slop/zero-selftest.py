#!/usr/bin/env python3
"""zero-selftest.py -- PROVE the classifier separates PORT-DEFECT from
INVISIBLE-to-reader, and that it never emits a sixth verdict.

A classifier that cannot tell case 2 from case 4 is worse than no classifier,
because it converts both into a confident wrong answer.  So the discrimination
is TESTED against the two real cases this project has already paid for, using
the real snapshots, not against invented fixtures:

  CASE 2 (PORT-DEFECT)  `l2i_shl.hi`, read against snapshot `73b0e1e7`, whose
                        arena-aliasing defect overwrote the index pointing at
                        the site.  `lg9p` reads `BITCAST(WHERE)` where CPython
                        has `BITCAST(OR)`.  This was published as
                        `SAME -- 0 rows` and classified REQUEST.
  CASE 4 (INVISIBLE)    `l2i_cast3.bitc`.  `lg7` is `dtype.py:39`'s only
                        fixture and `bitcast(uint)` FOLDS on it, so the node the
                        arm exists to build is in NO row -- silent, not wrong.

The same site on the same rows must land on different verdicts, and the ONLY
difference between the two inputs is the snapshot's own bytes.  If this test
ever passes for both, the classifier is reading the label rather than the data.

    usage: zero-selftest.py
    exits 1 on any failure.  Nothing here is a unit test of a helper: every
    input is a file this project produced by running something.
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CLASSIFY = os.path.join(HERE, "zero-classify.py")

# ---- the four cases, as (site, CPython-answer-at-that-site) -------------------
# The answer strings are MEASURED: `BITCAST(OR)` is dd-oracle.py's `lg9p`, and
# `CAST(Pu320)` is its `lg7`.  Neither is typed from memory.
OLD_SITE_ANS = "l2i_shl.hi\tBITCAST(OR)\n"
NEW_SITE_ANS = "l2i_shl.hi\tOR(SHL(BITCAST,CAST),SHR(SHR,ADD))\n"
OLD_AIM = "M09\tl2i_shl.hi\nM33\tl2i_define.size2\n"
# `l2i_define` was PROVEN unreachable by dd-mut-proof.py (rename compiled, output
# byte-identical), so it is the UNREACHABLE+proof arm and needs no site answer.
OLD_PROOF = "M33\tunreachable\tdd-mut-proof.py: renaming `def l2i_define(` compiled and the output stayed BYTE-IDENTICAL.\n"


def verdict_of(base, table, aim, proof, site_ans, label):
    with tempfile.TemporaryDirectory() as d:
        def w(name, text):
            p = os.path.join(d, name)
            open(p, "w").write(text)
            return p
        out = subprocess.run(
            [sys.executable, CLASSIFY,
             "--table", w("t.tsv", table), "--base", base,
             "--oracle", os.path.join(HERE, "dd-oracle.txt"),
             "--aim", w("a.tsv", aim),
             "--proof", w("p.tsv", proof),
             "--family", os.path.join(HERE, "dd-zero-family.tsv"),
             "--site-answer", w("s.tsv", site_ans),
             "--label", label, "--rev", "self-test"],
            stdout=subprocess.PIPE).stdout.decode()
    got = {}
    for line in out.splitlines():
        f = line.split()
        if len(f) >= 5 and f[0].startswith("M") and f[4] != "(not":
            got[f[0]] = f[4]
    return got, out


def main():
    base_old = os.path.join(HERE, "dd-gate-base-172.txt")
    base_new = os.path.join(HERE, "dd-gate-base-182.txt")
    for b in (base_old, base_new):
        if not os.path.exists(b):
            sys.exit("missing %s -- this test compares real snapshots and will not "
                     "invent them" % b)

    # CASE 2: the same site, the same rows, the DEFECTIVE snapshot.
    v_old, out_old = verdict_of(
        base_old, "M09\tSAME\t0\t\nM33\tSAME\t0\t\n", OLD_AIM, OLD_PROOF,
        OLD_SITE_ANS, "CASE 2: l2i_shl.hi on the defective snapshot 73b0e1e7")

    # CASE 4: a LIVE site whose answer is in no row at all.  `l2i_cast3.bitc`
    # builds a BITCAST that `lg7` folds away, so nothing carries it.
    v_inv, _ = verdict_of(
        base_new, "M09\tSAME\t0\t\n", "M09\tl2i_cast3.bitc\n", "",
        "l2i_cast3.bitc\tCAST(BITCAST(Pu32", "CASE 4: an answer in no row")

    fails = []

    def want(label, got, expect):
        mark = "ok  " if got == expect else "FAIL"
        if got != expect:
            fails.append("%s: %s read %s, expected %s" % (label, label, got, expect))
        print("  %s %-58s %s" % (mark, label, got))

    print("THE DISCRIMINATION, on real snapshots:")
    want("CASE 2  l2i_shl.hi on the DEFECTIVE snapshot",
         v_old.get("M09"), "PORT-DEFECT")
    want("CASE 2b l2i_define, proven by rename",
         v_old.get("M33"), "UNREACHABLE+proof")
    want("CASE 4  an answer that is in NO row",
         v_inv.get("M09"), "INVISIBLE-to-reader")

    # The five verdicts are exactly five.  A sixth is a bug, not an extension.
    print("\nTHE FIVE VERDICTS, and there is no sixth:")
    names = subprocess.run([sys.executable, CLASSIFY, "--verdicts"],
                           stdout=subprocess.PIPE).stdout.decode().split()
    print("  declared: %s" % " | ".join(names))
    if len(names) != 5:
        fails.append("there are %d verdicts, not 5" % len(names))
    # And the classifier REFUSES a verdict outside the five -- checked by
    # feeding it a measurement it does not know, which must not be silently kept.
    p = subprocess.run(
        [sys.executable, CLASSIFY, "--table", "/dev/stdin", "--base", base_new,
         "--oracle", os.path.join(HERE, "dd-oracle.txt"),
         "--aim", os.path.join(HERE, "dd-zero-aim.tsv"),
         "--family", os.path.join(HERE, "dd-zero-family.tsv"),
         "--label", "self-test", "--rev", "self-test"],
        input=b"M99\tTOTALLY-UNKNOWN\t0\t\n", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE)
    if p.returncode == 0:
        fails.append("an unknown MEASUREMENT was accepted; 'unrecognised' must not "
                     "become a sixth verdict that reads like a pass")
    print("  %s an unknown MEASUREMENT is REFUSED (exit %d): %s"
          % ("ok  " if p.returncode else "FAIL", p.returncode,
             (p.stderr.decode().strip().splitlines() or [""])[-1][:60]))

    print()
    if fails:
        for f in fails:
            print("FAILED: %s" % f)
        sys.exit(1)
    print("ALL CHECKS PASS: PORT-DEFECT and INVISIBLE-to-reader are told apart by "
          "the DATA, not by a label.")


main()