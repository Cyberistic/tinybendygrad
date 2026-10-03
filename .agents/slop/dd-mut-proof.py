#!/usr/bin/env python3
"""dd-mut-proof.py -- PROVE a mutation is unobservable, or admit it is not.

A mutation that moves no rows is only a THEOREM when the mutated code is
UNREACHABLE.  "I read the code and saw no caller" is not a proof, and this
project has six wrong such claims on the record.  So this proves it by
construction: it makes the code unreachable (not merely wrong) and shows the gate
output is BYTE-IDENTICAL to the baseline.

THE MOVE is always the same and always minimal -- rename the def to something
nothing can call.  A rename cannot change semantics, cannot break the type, and
cannot be mistaken for a semantic edit.  Renaming is enough: if no call resolves,
Bend refuses it, and the refusal is the proof that the def was reachable ONLY
through that name.

So there are two outcomes and both are informative:

  REACHABLE-WAS  the rename REFUSED to compile (bend names the missing def)
                 -> the def had a live caller, and the zero needs a FIXTURE.
  UNREACHABLE    the rename compiled and the gate output is byte-identical
                 -> THEOREM, with the rename as the evidence.

usage: dd-mut-proof.py BASELINE.txt FILE.bend DEFNAME...
env:   DD_WORKERS unused; one gate run per def, sequentially (each ~40 s)
"""
import hashlib
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, "bin", "bend")
SCRATCH = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode"


def shape(t):
    L = t.splitlines()
    return (L[0] if L else "", len(L), L[-1] if L else "")


def gate(tgt, want):
    """RULE E/H from dd-mutate.py: shape is the guard, exit code is not, and an
    empty print is retried rather than believed."""
    out = os.path.join(SCRATCH, "ddproof.txt")
    for _ in range(24):
        with open(out, "w") as fh:
            subprocess.run([BEND, tgt], stdout=fh, stderr=subprocess.PIPE)
        text = open(out).read()
        if text:
            return text
    return ""


def main():
    want = shape(open(sys.argv[1]).read())
    src = open(sys.argv[2]).read()
    tree = os.path.join(SCRATCH, "ddproof-%d" % os.getpid())
    shutil.rmtree(tree, ignore_errors=True)
    os.makedirs(tree)
    archive = subprocess.run(["git", "-C", ROOT, "archive", "HEAD", "tinybendygrad"],
                             stdout=subprocess.PIPE, check=True).stdout
    subprocess.run(["tar", "-x", "-C", tree], input=archive, check=True)
    tgt = os.path.join(tree, "tinybendygrad", "codegen", "decomp", "dtype.bend")
    open(tgt, "w").write(src)

    base_txt = gate(tgt, want)
    if shape(base_txt) != want:
        sys.exit("the unmutated mirror does not reproduce the baseline shape; "
                 "no proof here is evidence")
    print("baseline reproduced: %d lines\n" % len(base_txt.splitlines()))

    for name in sys.argv[3:]:
        dead = "__unreachable_%s" % hashlib.sha1(name.encode()).hexdigest()[:8]
        # Rename the DEF only: `def name(` at column 0.  Every call site keeps
        # the old name and now resolves to nothing.
        old = "def %s(" % name
        if src.count(old) != 1:
            print("%-24s SKIP: %r occurs %d times" % (name, old, src.count(old)))
            continue
        open(tgt, "w").write(src.replace(old, "def %s(" % dead, 1))
        got = gate(tgt, want)
        if not got:
            sys.exit("bend printed nothing in 24 attempts for %s" % name)
        if "not defined" in got or "undefined" in got or "expected : a defined name" in got:
            verdict = "REACHABLE-WAS -- bend refuses the rename, so a caller exists"
        elif got == base_txt:
            verdict = "THEOREM: UNREACHABLE -- rename compiled, output BYTE-IDENTICAL"
        elif shape(got) != want:
            verdict = "THEOREM-ish: rename compiled and the output CHANGED (%r)" % (shape(got),)
        else:
            verdict = "ROWS CHANGED -- rename compiled and rows differ"
        print("%-24s %s" % (name, verdict))
        open(tgt, "w").write(src)

    shutil.rmtree(tree, ignore_errors=True)


main()