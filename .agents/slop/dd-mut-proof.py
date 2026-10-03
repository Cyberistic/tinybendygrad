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
# The SAME pinned tree dd-mutate.py uses.  Built from HEAD this tool failed its
# own substrate probe, because HEAD moved to a revision whose tree prints zero
# lines with this dtype.bend -- a proof tool with a moving substrate proves
# nothing about anything.
TREE_REV = "e17d3f7dd48cf84c7a101b3d6aee11c0284a165e"


def shape(t):
    L = t.splitlines()
    return (L[0] if L else "", len(L), L[-1] if L else "")


def gate(tgt, want):
    """RULE E/H from dd-mutate.py: shape is the guard, exit code is not, and an
    empty print is retried rather than believed.

    A COMPILE REFUSAL IS ALSO AN EMPTY PRINT here: bend prints its error on
    stderr and nothing on stdout.  So an empty stdout is ambiguous between "stack
    overflow" and "bend refused this edit", and the first 24 attempts here burned
    on the second kind.  It is not ambiguous once stderr is read: a refusal names
    `Error:` and the overflow does not.
    """
    out = os.path.join(SCRATCH, "ddproof-%d.txt" % os.getpid())
    for _ in range(24):
        with open(out, "w") as fh:
            p = subprocess.run([BEND, tgt], stdout=fh, stderr=subprocess.PIPE)
        text = open(out).read()
        if text:
            return text
        err = (p.stderr or b"").decode()
        if "Error" in err or "expected" in err:
            # bend refused the edit.  Return it as stdout so the classifier below
            # sees it, and mark it so a refusal is never read as THEOREM.
            return err
    return ""


def main():
    want = shape(open(sys.argv[1]).read())
    src = open(sys.argv[2]).read()
    tree = os.path.join(SCRATCH, "ddproof-%d" % os.getpid())
    shutil.rmtree(tree, ignore_errors=True)
    os.makedirs(tree)
    archive = subprocess.run(["git", "-C", ROOT, "archive", TREE_REV, "tinybendygrad"],
                             stdout=subprocess.PIPE, check=True).stdout
    subprocess.run(["tar", "-x", "-C", tree], input=archive, check=True)
    tgt = os.path.join(tree, "tinybendygrad", "codegen", "decomp", "dtype.bend")
    open(tgt, "w").write(src)

    base_txt = gate(tgt, want)
    if shape(base_txt) != want:
        sys.exit("the unmutated mirror does not reproduce the baseline shape; "
                 "no proof here is evidence")
    print("baseline reproduced: %d lines\n" % len(base_txt.splitlines()))
    print("A `REACHABLE-WAS` line means the zero needs a FIXTURE, not a defence.\n"
          "A `THEOREM` line is the rename compiling AND the output matching.\n")

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
            sys.exit("bend printed nothing on stdout AND nothing on stderr in 24 "
                     "attempts for %s -- that is the stack overflow, and it is "
                     "NOT a proof either way." % name)
        if "SOME PROOFS FAIL" in got and not base_txt.startswith("SOME PROOFS"):
            # dtype.bend has 14 permanently-red laws, so the first line is expected.
            # A refusal is anything past that.
            verdict = "REACHABLE-WAS  -- bend REFUSED the rename:\n%s" % got[:300]
        elif "expected : a defined name" in got or "not defined" in got:
            verdict = "REACHABLE-WAS  -- bend names a missing def:\n%s" % got[:300]
        elif got == base_txt:
            verdict = "THEOREM        -- rename compiled, output BYTE-IDENTICAL"
        elif shape(got) != want:
            verdict = "NOT A THEOREM  -- rename compiled and the output changed shape"
        else:
            verdict = "NOT A THEOREM  -- rename compiled and rows differ"
        print("%-24s %s" % (name, verdict))
        open(tgt, "w").write(src)

    shutil.rmtree(tree, ignore_errors=True)


main()