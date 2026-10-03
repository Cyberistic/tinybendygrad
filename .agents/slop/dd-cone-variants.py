#!/usr/bin/env python3
"""dd-cone-variants.py -- build MIRROR trees of tinybendygrad for the cone-fix
isolation and revert runs.  Never writes the live tree.

usage:
  dd-cone-variants.py list
  dd-cone-variants.py build NAME      # writes .agents/slop/dd-cone-wt/NAME/tinybendygrad

VARIANTS are named sets of edits applied to `.agents/slop/dd-cone-wt/dtype.bend.prefix`
(the pre-fix live file, sha1 215eca996a99a616d0217255b45827b2c199a14a).  The
edits are the two cone bugs and their reverts, so a run of the mirror is a run of
a specific combination -- never a hand-edited file, and never the live tree.
"""
import hashlib
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WT = os.path.join(ROOT, ".agents", "slop", "dd-cone-wt")
PREFIX = os.path.join(WT, "dtype.bend.prefix")

# ---- the two bugs, quoted from the PRE-FIX file, and their fixes -------------
PUSH_OLD = """# Prepends each src in order, so the head popped is the LAST src, not src[0].
# TODO: the oracle cone is src[0] first. Reversing this push is the fix; it moves sig rows.
def dd_rs.push(f: Nat, srcs: List<&2, U32>, st: List<&2, U32>) -> List<&2, U32>:
  match f:
    case 0n: st
    case 1n+q:
      match srcs:
        case Nil{}: st
        case s <> t: dd_rs.push(q, t, dd_rs.cat(s, st))"""

PUSH_NEW = """# APPENDS each src in order, so the head popped is src[0], which is what
# dd-oracle.py's `cone` walks: `for s in v.src: go(s)` is src[0] first.
# Prepending here would pop src[n] first and reverse every multi-src node's
# children in `sig`, which is what this did until the TODO at the `add` below
# was closed.
def dd_rs.push(f: Nat, srcs: List<&2, U32>, st: List<&2, U32>) -> List<&2, U32>:
  match f:
    case 0n: st
    case 1n+q:
      match srcs:
        case Nil{}: st
        case s <> t: dd_rs.cat(s, dd_rs.push(q, t, st))"""

ADD_OLD = """# PREPENDED, so the push is O(1) and only the one `List.reverse` at the end is
# O(n). Appending instead makes the walk O(n^2) in list cells on top of `has`.

def dd_rs.add(u: U32, +xs: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [u], xs)"""

ADD_NEW = """# PREPENDED, so the push is O(1) and only the one `List.reverse` at the end is
# O(n). Appending instead makes the walk O(n^2) in list cells on top of `has`.
# It is also the MEMBERSHIP TEST, not an append: a node reachable from two
# parents is reachable ONCE, so it is listed once. Unconditional, it listed a
# shared node once per parent -- `lgwsig` read `CAST/1,CONST/0,CAST/1` where
# CPython's `cone` dedups by `id` and reads `CAST/1,CONST/0`.
#
# The `has` here and the one in `dd_rs.more` are the same walk over the same
# list, so the fix costs a second pass rather than a second traversal class:
# `go` already spends one per pop on `more`, and the code above already pays
# O(n^2) here. Threading ONE test through both consumers needs a pair, and Bend
# has no pair; re-testing is the smaller change and keeps `more`'s call site --
# which the M27 anchor quotes verbatim -- untouched.
#
# `nat` is a PARAMETER, not a bound value, because Bend's `match` will not
# scrutinise a local binder ("give it its own def"). `dd_rs.more` is the same
# shape for the same reason.
def dd_rs.add(nat: Bool, u: U32, xs: List<&2, U32>) -> List<&2, U32>:
  match nat:
    case True{}: xs
    case False{}: List.append(&2, U32, [u], xs)"""

CALL_OLD = """          # TODO: add is unconditional, so a node with two parents is listed twice.
          # A freshness Bool cannot be read twice ("consumed more than once").
          st2 = dd_rs.more(Bool.not(dd_rs.has(dd_seen(ar), seen, u)), ar, u, rest)
          sn = dd_rs.add(u, seen)
          dd_rs.go(q, ar, st2, sn)"""

CALL_NEW = """          st2 = dd_rs.more(Bool.not(dd_rs.has(dd_seen(ar), seen, u)), ar, u, rest)
          sn = dd_rs.add(Bool.not(dd_rs.has(dd_seen(ar), seen, u)), u, seen)
          dd_rs.go(q, ar, st2, sn)"""

# ---- candidate shapes for the dedup ---------------------------------------
# (4) keep `more`'s anchor line byte-for-byte by computing `sn` BEFORE `st2`, so
#     `ar` is read twice before `more` consumes it rather than three times after.
CALL_REORDER = """          # TODO: add is unconditional, so a node with two parents is listed twice.
          # A freshness Bool cannot be read twice ("consumed more than once").
          sn = dd_rs.add(Bool.not(dd_rs.has(dd_seen(ar), seen, u)), u, seen)
          st2 = dd_rs.more(Bool.not(dd_rs.has(dd_seen(ar), seen, u)), ar, u, rest)
          dd_rs.go(q, ar, st2, sn)"""

# (1) ONE decision, TWO effects: `more` returns the `(st, seen)` pair, which is
#     the `A & B` return type `helpers.bend:1903` already uses.
MORE_OLD = """def dd_rs.more(nat: Bool, +ar: O.Arena, +u: U32, st: List<&2, U32>) -> List<&2, U32>:
  match nat:
    case True{}: dd_rs.push(U32.to_nat(O.Arena.nsrc(ar, u)), O.Arena.srcs(ar, u), st)
    case False{}: st"""

MORE_PAIR = """def dd_rs.more(nat: Bool, +ar: O.Arena, +u: U32, st: List<&2, U32>, +seen: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match nat:
    case True{}: (dd_rs.push(U32.to_nat(O.Arena.nsrc(ar, u)), O.Arena.srcs(ar, u), st), dd_rs.add(u, seen))
    case False{}: (st, seen)"""

ADD_PAIR = """def dd_rs.add(u: U32, +xs: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [u], xs)"""

CALL_PAIR = """          # TODO: add is unconditional, so a node with two parents is listed twice.
          # A freshness Bool cannot be read twice ("consumed more than once").
          st2, sn = dd_rs.more(Bool.not(dd_rs.has(dd_seen(ar), seen, u)), ar, u, rest, seen)
          dd_rs.go(q, ar, st2, sn)"""

EDITS = {"push": (PUSH_OLD, PUSH_NEW), "add": (ADD_OLD, ADD_NEW), "call": (CALL_OLD, CALL_NEW),
         "add4": (ADD_OLD, ADD_NEW), "call4": (CALL_OLD, CALL_REORDER),
         "add1": (ADD_OLD, ADD_PAIR), "more1": (MORE_OLD, MORE_PAIR),
         "call1": (CALL_OLD, CALL_PAIR)}

# name -> which of the three edits to apply.  `fix-add`/`fix-push` isolate the two
# bugs; `revert-*` are the mutation harness's A/B arms; `ctl-comment` is RULE C.
VARIANTS = {
    "prefix": [],
    "fix-add": ["add", "call"],
    "fix-push": ["push"],
    "fix-both": ["push", "add", "call"],
    "shape4": ["push", "add4", "call4"],
    "shape1": ["push", "add1", "more1", "call1"],
    "revert-add": ["push"],
    "revert-push": ["add", "call"],
    "revert-both": [],
    "ctl-comment": ["push", "add", "call", "comment"],
}

COMMENT_OLD = "def dd_cone(n: Nat, +ar: O.Arena, +roots: List<&2, U32>) -> List<&2, U32>:"
COMMENT_NEW = ("# CONTROL: a comment line, no semantics.\n"
               "def dd_cone(n: Nat, +ar: O.Arena, +roots: List<&2, U32>) -> List<&2, U32>:")


def apply(name, text):
    for e in name:
        old, new = (COMMENT_OLD, COMMENT_NEW) if e == "comment" else EDITS[e]
        n = text.count(old)
        if n != 1:
            sys.exit("PATCH DID NOT APPLY (%s): anchor is %d-occurrences" % (e, n))
        text = text.replace(old, new, 1)
    return text


def main():
    if sys.argv[1:] == ["list"]:
        for k, v in VARIANTS.items():
            print("%-12s %s" % (k, ",".join(v) or "(pre-fix)"))
        return
    name = sys.argv[2]
    src = os.path.join(ROOT, "tinybendygrad")
    dest = os.path.join(WT, name)
    body = apply(VARIANTS[name], open(PREFIX).read())
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    shutil.copytree(src, dest)
    tgt = os.path.join(dest, "codegen", "decomp", "dtype.bend")
    open(tgt, "w").write(body)
    print("%s  dtype.bend sha1 %s  (%d edits)"
          % (dest, hashlib.sha1(body.encode()).hexdigest(), len(VARIANTS[name])))
    r = subprocess.run([os.path.join(ROOT, "bin", "bend"), tgt, "--check-only"],
                       capture_output=True)
    print("  --check-only first line: %s" % (r.stdout.decode().splitlines() or ["<none>"])[0])


main()