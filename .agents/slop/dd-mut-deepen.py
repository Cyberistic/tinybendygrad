#!/usr/bin/env python3
"""dd-mut-deepen.py -- ANSWER "is this mutation invisible because the gate does
not PRINT it, or because the code is not RUN?".

A REQUEST-classified zero has two possible causes and they need opposite fixes:

  the code does not run        -> the fixture never reaches it (add a fixture)
  the code runs but is UNPRINTED -> the row is too shallow (deepen the row)

Telling them apart needs TWO gate runs on TWO trees, because the question is
about the MUTANT: does the mutation change a DEEPER gate?  So this deepens the
gate's own tree printer by `levels`, then applies the mutation, and diffs.
A swap that moves nothing on the shallow gate and moves on the deep one is
PROVEN to be a printer-depth blind spot and not a coverage hole.

usage:
  dd-mut-deepen.py BASELINE.txt FILE.bend LEVEL ANCHOR=OLD@@NEW [LEVEL ...]
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, "bin", "bend")
SCRATCH = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode"
TREE_REV = "e17d3f7dd48cf84c7a101b3d6aee11c0284a165e"

# dd_tree recurses while the node has srcs: `leaf` is `nsrc == 0`.  Passing a
# level counter and stopping at it is the ONLY change needed to deepen it, and it
# is a parameter rather than a literal so one build serves every depth.
DEEPEN = """def dd_tree.go(+ar: O.Arena, +u: U32, leaf: Bool) -> String:
  match leaf:
    case True{}: dd_lab(ar, u)
    case False{}: String.concat([dd_lab(ar, u), "(", dd_sfx2.put(ar, u,
                                  U32.sub(U32.min(O.Arena.nsrc(ar, u), 3), 1)), ")"])"""



def gate(tgt):
    out = os.path.join(SCRATCH, "dddeep-%d.txt" % os.getpid())
    for _ in range(24):
        with open(out, "w") as fh:
            p = subprocess.run([BEND, tgt], stdout=fh, stderr=subprocess.PIPE)
        text = open(out).read()
        if text:
            return text
        if "Error" in (p.stderr or b"").decode():
            return "REFUSED"
    return ""


def lines(t):
    return dict(ln.split("=", 1) for ln in t.splitlines()
                if ln and not ln.startswith("#") and "=" in ln)


# The deep printer, in the shape Bend actually accepts.  Three refusals had to be
# worked through, and each names neither the rule nor the fix, so they are recorded
# here rather than rediscovered:
#
#   1. A `match` may not scrutinise a computed value -- not even a nullary def's
#      RESULT.  The arity must arrive as a PARAMETER (`k`), computed by the caller.
#   2. That `k` then cannot be re-matched after `case 1n+q:` has consumed the
#      countdown: "a match on a parameter or field (this name is a def or a
#      consumed binder)".  So the arity dispatch gets its OWN defs -- one per arity,
#      each with the countdown as its only match -- and only `dd_tree.at` matches on
#      `k`.  Two nested matches, one scrutinee each, is the most Bend accepts here.
#
#   3. Bend has NO MUTUAL RECURSION and NO FORWARD REFERENCES, so the depth is
#      UNROLLED into three defs that must be written in the order they are used:
#      `d1` before `d2` before `d3`.  Written the other way round the error is
#      "an unfilled law is a dead claim: live code cannot use it", which names
#      neither the cause nor the fix.  Six refusals in a row reached this shape,
#      and every one of them named something else.
DEEPENED = """def dd_tree.arity(+ar: O.Arena, +u: U32) -> U32:
  U32.min(O.Arena.nsrc(ar, u), 3)

def dd_tree.d1(+ar: O.Arena, +u: U32, k: U32) -> String:
  dd_sfx2.put(ar, u, U32.sub(k, 1))

def dd_tree.d2(+ar: O.Arena, +u: U32, k: U32) -> String:
  match k:
    case 0: dd_lab(ar, u)
    case 1: String.concat([dd_lab(ar, u), "(", dd_tree.d1(ar,
      O.Arena.src0(ar, u), dd_tree.arity(ar, O.Arena.src0(ar, u))), ")"])
    case 2: String.concat([dd_lab(ar, u), "(", dd_tree.d1(ar,
      O.Arena.src0(ar, u), dd_tree.arity(ar, O.Arena.src0(ar, u))), ",",
      dd_tree.d1(ar, O.Arena.src(ar, u, 1), dd_tree.arity(ar,
      O.Arena.src(ar, u, 1))), ")"])
    case _: String.concat([dd_lab(ar, u), "(", dd_tree.d1(ar,
      O.Arena.src0(ar, u), dd_tree.arity(ar, O.Arena.src0(ar, u))), ",",
      dd_tree.d1(ar, O.Arena.src(ar, u, 1), dd_tree.arity(ar,
      O.Arena.src(ar, u, 1))), ",", dd_tree.d1(ar, O.Arena.src(ar, u, 2),
      dd_tree.arity(ar, O.Arena.src(ar, u, 2))), ")"])

def dd_tree.d3(+ar: O.Arena, +u: U32, k: U32) -> String:
  match k:
    case 0: dd_lab(ar, u)
    case 1: String.concat([dd_lab(ar, u), "(", dd_tree.d2(ar,
      O.Arena.src0(ar, u), dd_tree.arity(ar, O.Arena.src0(ar, u))), ")"])
    case 2: String.concat([dd_lab(ar, u), "(", dd_tree.d2(ar,
      O.Arena.src0(ar, u), dd_tree.arity(ar, O.Arena.src0(ar, u))), ",",
      dd_tree.d2(ar, O.Arena.src(ar, u, 1), dd_tree.arity(ar,
      O.Arena.src(ar, u, 1))), ")"])
    case _: String.concat([dd_lab(ar, u), "(", dd_tree.d2(ar,
      O.Arena.src0(ar, u), dd_tree.arity(ar, O.Arena.src0(ar, u))), ",",
      dd_tree.d2(ar, O.Arena.src(ar, u, 1), dd_tree.arity(ar,
      O.Arena.src(ar, u, 1))), ",", dd_tree.d2(ar, O.Arena.src(ar, u, 2),
      dd_tree.arity(ar, O.Arena.src(ar, u, 2))), ")"])

def dd_tree.go(+ar: O.Arena, +u: U32, leaf: Bool) -> String:
  dd_tree.d3(ar, u, dd_tree.arity(ar, u))"""


def main():
    src = open(sys.argv[2]).read()
    if src.count(DEEPEN) != 1:
        sys.exit("the DEEPEN anchor occurs %d times" % src.count(DEEPEN))
    tree = os.path.join(SCRATCH, "dddeep-%d" % os.getpid())
    shutil.rmtree(tree, ignore_errors=True)
    os.makedirs(tree)
    archive = subprocess.run(["git", "-C", ROOT, "archive", TREE_REV, "tinybendygrad"],
                             stdout=subprocess.PIPE, check=True).stdout
    subprocess.run(["tar", "-x", "-C", tree], input=archive, check=True)
    tgt = os.path.join(tree, "tinybendygrad", "codegen", "decomp", "dtype.bend")
    open(tgt, "w").write(src)
    shallow = gate(tgt)
    base = lines(shallow)
    print("shallow gate: %d rows\n" % len(base))

    for spec in sys.argv[4:]:
        name, _, body = spec.partition("=")
        old, _, new = body.partition("@@")
        old, new = old.replace("\\n", "\n"), new.replace("\\n", "\n")
        if src.count(old) != 1:
            print("%-28s SKIP: anchor occurs %d times" % (name, src.count(old)))
            continue
        mut = src.replace(old, new, 1)

        open(tgt, "w").write(src)
        s = lines(gate(tgt))
        d0 = sorted(k for k in set(base) | set(s) if base.get(k) != s.get(k))

        deep_src = src.replace(DEEPEN, DEEPENED, 1)
        open(tgt, "w").write(deep_src)
        dr = gate(tgt)
        if dr == "REFUSED":
            print("%-28s the DEEPENED gate does not compile" % name)
            continue
        dl = lines(dr)
        open(tgt, "w").write(deep_src.replace(old, new, 1))
        dm = lines(gate(tgt))
        d1 = sorted(k for k in set(dl) | set(dm) if dl.get(k) != dm.get(k))

        print("%-28s shallow %2d rows | DEEP %2d rows | %s"
              % (name, len(d0), len(d1),
                 "PRINTER-DEPTH BLIND SPOT -- the deep gate sees it" if d1 and not d0
                 else "seen at both depths" if d0 and d1
                 else "seen shallow, not deep (unexpected)" if d0
                 else "NEITHER -- a real coverage hole, not a printer one"))
        print("%-28s   deep moves: %s" % ("", ", ".join(d1[:12]) or "-"))

    open(tgt, "w").write(src)
    shutil.rmtree(tree, ignore_errors=True)


main()