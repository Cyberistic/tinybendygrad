#!/usr/bin/env python3
"""dd-mut-tether.py -- a mutation's zero explained by an INTERCEPTION, not by
unreachability.

dd-mut-proof.py answers "is this def reachable?".  It cannot answer "is this ARM
reachable?", because an arm is not a def and renaming one changes nothing.  The
other honest route to a THEOREM is to delete the interception and show the gate
output is BYTE-IDENTICAL: that proves the arm is dead, and it also proves what
would happen if the interception were ever removed.

THE MOVE is always minimal and always reversible: delete one line (an arm head,
or the `case` that intercepts) and re-run.  Two outcomes, both informative:

  THEOREM       the edit compiled and the output is BYTE-IDENTICAL -> the arm
                was dead.  PROOF, and the reason is now a measured fact.
  STILL REACHED the output changed -> the arm is live and the zero needs a
                FIXTURE, whatever the file's comment says.

usage: dd-mut-tether.py BASELINE.txt FILE.bend NAME=OLD_LINES@@NEW_LINES ...
  where OLD_LINES and NEW_LINES are `\n`-separated and @@ separates them
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, "bin", "bend")
SCRATCH = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode"
TREE_REV = "e17d3f7dd48cf84c7a101b3d6aee11c0284a165e"   # the same pin dd-mutate uses


def gate(tgt):
    out = os.path.join(SCRATCH, "ddtether-%d.txt" % os.getpid())
    for _ in range(24):
        with open(out, "w") as fh:
            p = subprocess.run([BEND, tgt], stdout=fh, stderr=subprocess.PIPE)
        text = open(out).read()
        if text:
            return text
        err = (p.stderr or b"").decode()
        if "Error" in err:
            return err
    return ""


def main():
    src = open(sys.argv[2]).read()
    tree = os.path.join(SCRATCH, "ddtether-%d" % os.getpid())
    shutil.rmtree(tree, ignore_errors=True)
    os.makedirs(tree)
    archive = subprocess.run(["git", "-C", ROOT, "archive", TREE_REV, "tinybendygrad"],
                             stdout=subprocess.PIPE, check=True).stdout
    subprocess.run(["tar", "-x", "-C", tree], input=archive, check=True)
    tgt = os.path.join(tree, "tinybendygrad", "codegen", "decomp", "dtype.bend")
    open(tgt, "w").write(src)
    base = gate(tgt)
    print("baseline: %d lines, first %r\n" % (len(base.splitlines()),
                                              base.splitlines()[0] if base else ""))
    for spec in sys.argv[3:]:
        name, _, body = spec.partition("=")
        old, _, new = body.partition("@@")
        old, new = old.replace("\\n", "\n"), new.replace("\\n", "\n")
        if src.count(old) != 1:
            print("%-28s SKIP: anchor occurs %d times" % (name, src.count(old)))
            continue
        open(tgt, "w").write(src.replace(old, new, 1))
        got = gate(tgt)
        if got == base:
            v = "THEOREM -- compiled, output BYTE-IDENTICAL"
        elif "Error" in got or "expected" in got:
            v = "REFUSED -- %s" % " / ".join(got.splitlines()[1:5])
        elif got:
            diff = sum(1 for a, b in zip(got.splitlines(), base.splitlines()) if a != b)
            v = "STILL REACHED -- %d lines differ from the baseline" % diff
        else:
            v = "NO OUTPUT in 24 attempts (bend's stack overflow) -- NOT A VERDICT"
        print("%-28s %s" % (name, v))
        open(tgt, "w").write(src)
    shutil.rmtree(tree, ignore_errors=True)


main()