#!/usr/bin/env python3
"""dd-cone-variants.py -- build MIRROR trees of tinybendygrad from ONE frozen
snapshot of the live dtype.bend, each with exactly ONE cone fix reverted.

It never writes the live tree.  `snap` freezes the live file once; every `build`
derives from that same freeze, so the A/B arms of a revert cannot drift apart
because a concurrent agent moved the live file between them.

usage:
  dd-cone-variants.py snap            # freeze the live dtype.bend
  dd-cone-variants.py list
  dd-cone-variants.py build NAME      # -> .agents/slop/dd-cone-wt/NAME
"""
import hashlib
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WT = os.path.join(ROOT, ".agents", "slop", "dd-cone-wt")
BASE = os.path.join(WT, "dtype.bend.base")
LIVE = os.path.join(ROOT, "tinybendygrad", "codegen", "decomp", "dtype.bend")

# ---- the FIXED text, quoted from the live file, and its revert --------------
PUSH_FIXED = "        case s <> t: dd_rs.cat(s, dd_rs.push(q, t, st))"
PUSH_BUGGY = "        case s <> t: dd_rs.push(q, t, dd_rs.cat(s, st))"

ADD_FIXED = """def dd_rs.add(nat: Bool, u: U32, xs: List<&2, U32>) -> List<&2, U32>:
  match nat:
    case True{}: dd_rs.cat(u, xs)
    case False{}: xs"""

# The pre-fix `add` AND the pre-fix `go` call site are ONE revert: the old `add`
# took no Bool, so restoring it without restoring the call would not compile.
ADD_BUGGY = """def dd_rs.add(u: U32, +xs: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [u], xs)"""

CALL_FIXED = "          sn = dd_rs.add(Bool.not(dd_rs.has(dd_seen(ar), seen, u)), u, seen)"
CALL_BUGGY = "          sn = dd_rs.add(u, seen)"

# ---- the CONTROL: a comment line, no semantics (dd-mutate.py RULE C01) -------
CTL_FIXED = "def dd_cone(n: Nat, +ar: O.Arena, +roots: List<&2, U32>) -> List<&2, U32>:"
CTL_CTL = ("# CONTROL C01: a comment line, no semantics\n"
           "def dd_cone(n: Nat, +ar: O.Arena, +roots: List<&2, U32>) -> List<&2, U32>:")

EDITS = {"push": (PUSH_FIXED, PUSH_BUGGY),
         "add": (ADD_FIXED, ADD_BUGGY),
         "call": (CALL_FIXED, CALL_BUGGY),
         "ctl": (CTL_FIXED, CTL_CTL)}

# name -> the edits to REVERT.  "" is the frozen snapshot itself (both fixes on).
VARIANTS = {
    "fix-both": [],
    "revert-push": ["push"],
    "revert-add": ["add", "call"],
    "revert-both": ["push", "add", "call"],
    "ctl-comment": ["ctl"],
    # M26, re-aimed at the fix: revert `push`.  The `dd-mutate.py` table's M26
    # quotes the PRE-fix line as its anchor, so on this file it is
    # PATCH-NOT-APPLIED; see the report.
    "M26": ["push"],
    # M27 unchanged: its anchor line is byte-identical in the fixed file.
    "M27": ["ctl"],
}


def apply(names, text):
    for e in names:
        old, new = EDITS[e]
        n = text.count(old)
        if n != 1:
            sys.exit("PATCH DID NOT APPLY (%s): anchor is %d-occurrences" % (e, n))
        text = text.replace(old, new, 1)
    return text


def main():
    cmd = sys.argv[1]
    if cmd == "snap":
        shutil.copy(LIVE, BASE)
        t = open(BASE).read()
        print("froze %s  sha1 %s  %d bytes" % (BASE, hashlib.sha1(t.encode()).hexdigest(), len(t)))
        return
    if cmd == "list":
        for k, v in VARIANTS.items():
            print("%-12s revert: %s" % (k, ",".join(v) or "(nothing -- both fixes on)"))
        return
    name = sys.argv[2]
    body = apply(VARIANTS[name], open(BASE).read())
    dest = os.path.join(WT, name)
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    shutil.copytree(os.path.join(ROOT, "tinybendygrad"), dest)
    tgt = os.path.join(dest, "codegen", "decomp", "dtype.bend")
    open(tgt, "w").write(body)
    r = subprocess.run([os.path.join(ROOT, "bin", "bend"), tgt, "--check-only"], capture_output=True)
    first = (r.stdout.decode().splitlines() or ["<none>"])[0]
    print("%-12s sha1 %s  reverts %d  --check-only: %s"
          % (name, hashlib.sha1(body.encode()).hexdigest(), len(VARIANTS[name]), first))


main()