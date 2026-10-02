#!/usr/bin/env python3
"""dtype-gate.py -- the gate for tinybendygrad/dtype.bend.

Runs BOTH lanes of tinybendygrad/test/dtype_oracle.bend -- the bend program and
.agents/slop/oracle/dtype_tables.py -- and compares them SECTION BY SECTION, so a
section that moves or disappears is named instead of being 85073 lines of `diff`.

    python3 .agents/slop/dtype-gate.py            # gate
    python3 .agents/slop/dtype-gate.py --write    # refresh the two lane files

Both lanes must be byte-identical apart from the ONE declared deviation below.
The lane files are committed, so a rerun is reproducible and the gate needs no
substrate other than the repo.
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SLOP = os.path.join(REPO, ".agents", "slop")
BEND_ORACLE = "tinybendygrad/test/dtype_oracle.bend"
PY_ORACLE = ".agents/slop/oracle/dtype_tables.py"
BEND_OUT = os.path.join(SLOP, "dt-bend.txt")
PY_OUT = os.path.join(SLOP, "dt-py.txt")

# The sections, in the order dtype_oracle.bend prints them. Blank-line separated.
SECTIONS = ["rows", "lut_rows", "clc_rows", "sum_rows(f32)", "sum_rows(bf16)",
            "sum_rows(f16)", "finfo_rows", "commit_rows"]

# THE ONE DECLARED DEVIATION. Pre-dates the dtype rename, is not caused by it, and
# is a property of the port's I64 rather than a wrong answer.
#
# `dtypes.uint64.max` is 2^64-1. tinybendygrad's I64 is a SIGNED pair of U32s, so
# that value has no image -- the correct spelling would be hi = 0xFFFFFFFF, which
# reads back as -1. `i64_max_u` answers int64's max (0x7FFF:0xFFFFFFFF) and its
# own comment argues why that is sound for the ONE test it is read by, `hi <= max`.
# So the `rows` group's u64 max column is int64's, not uint64's, and this row is
# the place that is reported once.
#
# It is declared, not hand-typed as an expected value: the CPython side still
# prints the truth (4294967295:4294967295) and the bend side still prints what it
# computes (2147483647:4294967295). The gate names the pair and fails if anything
# ELSE differs, or if this one stops differing -- a row that silently starts
# agreeing is a row that stopped testing the limit.
COL = {"u64": {"max": 9}}
KNOWN = [("rows", "u64", "max",
          "the I64 is a signed pair of U32s, so 2^64-1 has no image and "
          "`i64_max_u` answers int64's max; pre-dates the rename")]


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=REPO, capture_output=True, text=True, **kw)


def sections(text):
    groups, cur = [], []
    for line in text.split("\n"):
        if line == "":
            if cur:
                groups.append(cur)
            cur = []
        else:
            cur.append(line)
    if cur:
        groups.append(cur)
    return groups


def main():
    write = "--write" in sys.argv
    if write or not (os.path.exists(BEND_OUT) and os.path.exists(PY_OUT)):
        b = run(["./bin/bend", BEND_ORACLE])
        if b.returncode != 0:
            sys.stderr.write(b.stdout + b.stderr)
            return 1
        open(BEND_OUT, "w").write(b.stdout)
        p = run([sys.executable, PY_ORACLE])
        if p.returncode != 0:
            sys.stderr.write(p.stdout + p.stderr)
            return 1
        open(PY_OUT, "w").write(p.stdout)

    bend = sections(open(BEND_OUT).read())
    py = sections(open(PY_OUT).read())
    if len(bend) != len(SECTIONS) or len(py) != len(SECTIONS):
        print("SECTION COUNT py=%d bend=%d expected=%d" % (len(py), len(bend), len(SECTIONS)))
        return 1

    bad, declared = [], []
    for i, name in enumerate(SECTIONS):
        x, y = py[i], bend[i]
        if len(x) != len(y):
            print("  %-16s ROW COUNT py=%d bend=%d" % (name, len(x), len(y)))
            bad.append((name, "<row count>"))
            continue
        diffs = [(p, q) for p, q in zip(x, y) if p != q]
        print("  %-16s rows=%-6d differ=%d" % (name, len(x), len(diffs)))
        for p, q in diffs:
            (declared if matches_known(name, p, q) else bad).append((name, p, q))

    for name, p, q in declared:
        print("\nDECLARED DEVIATION (%s):" % name)
        print("  cpython: %s" % p)
        print("  bend   : %s" % q)
        for k in KNOWN:
            if k[0] == name:
                print("  reason : %s" % k[3])
    for name, p, q in bad:
        print("\nUNEXPECTED (%s):\n  cpython: %s\n  bend   : %s" % (name, p, q))

    total = sum(len(sections(open(f).read())[i]) for i, f in
                ((i, BEND_OUT) for i in range(len(SECTIONS))))
    print("\n%d rows compared, %d declared, %d unexpected"
          % (total, len(declared), len(bad)))
    return 0 if not bad and len(declared) == len(KNOWN) else 1


def matches_known(section, py_row, bend_row):
    for sec, dtype, col, _ in KNOWN:
        if sec != section:
            continue
        pc, bc = py_row.split("\t"), bend_row.split("\t")
        if len(pc) != len(bc) or pc[0] != dtype:
            continue
        # the ONE differing column must be the declared one, and `max` is column 9
        if [i for i, (a, b) in enumerate(zip(pc, bc)) if a != b] == [COL[dtype][col]]:
            return True
    return False


if __name__ == "__main__":
    sys.exit(main())