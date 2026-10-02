"""Diff the Bend gate against the CPython oracle.

    python3 .agents/slop/nv-diff.py

Prints three sections: gate rows the oracle cannot answer, oracle rows the gate
does not print, and the DISAGREEMENTS -- which is the only section that matters,
and it must be EMPTY.

It was not always empty and the two disagreements it printed are both instructive.
One was a real bug (`nv_query_litter_n`, where gate and oracle agreed on the wrong
answer because both were hand-written), and one was a transcription of a bug
another agent had already fixed (`nv_REPORTED_args_device_*`, a copy of
device.bend's old `iter_sig`). **A permanent disagreement trains every later reader
to skip the section that matters, so a row that is expected to differ belongs in
the file as a comment and not in the differ's output.**

The differ keys on the ROW NAME, so a claim the two sides spell differently is
reported as UNMATCHED on both sides rather than as a disagreement -- which is how
seventy-three rows sat uncompared for a stage. Any new row needs the same name
in both files, and `grep` for it in both before believing it is checked.
"""
import subprocess, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, "tinybendygrad/runtime/ops_nv.bend")


def rows_of(text):
    out = {}
    for l in text.split("\n"):
        if "=" in l:
            k, v = l.rsplit("=", 1)
            out[k] = v
    return out


def main():
    r = subprocess.run(["./bin/bend", BEND], capture_output=True, text=True, cwd=ROOT)
    if r.returncode != 0:
        print(r.stdout[-3000:], r.stderr[-2000:])
        return 1
    bend = rows_of(r.stdout)
    c = subprocess.run([sys.executable, ".agents/slop/nv-oracle.py"],
                       capture_output=True, text=True, cwd=ROOT)
    if c.returncode != 0:
        print(c.stderr[-3000:])
        return 1
    cp = rows_of(c.stdout)
    gk, ck = set(bend), set(cp)
    only_bend = sorted(k for k in gk - ck if not k.startswith("nv-done"))
    only_cp = sorted(ck - gk)
    dis = [(k, bend[k], cp[k]) for k in sorted(gk & ck) if bend[k] != cp[k]]
    print("BEND rows %d   CPYTHON rows %d" % (len(bend), len(cp)))
    if only_bend:
        print("\n-- gate rows with NO oracle counterpart (%d) --" % len(only_bend))
        for k in only_bend:
            print("   %-40s = %s" % (k, bend[k]))
    if only_cp:
        print("\n-- oracle rows the gate does not print yet (%d) --" % len(only_cp))
        for k in only_cp:
            print("   %-40s = %s" % (k, cp[k]))
    print("\n-- DISAGREEMENTS (%d) --" % len(dis))
    for k, b, p in dis:
        print("   %-40s bend=%-34s cpython=%s" % (k, b, p))
    print("\n%s" % ("AGREE" if not dis else "MISMATCH"))
    return 0 if not dis else 1


if __name__ == "__main__":
    sys.exit(main())