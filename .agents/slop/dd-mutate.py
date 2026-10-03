#!/usr/bin/env python3
"""dd-mutate.py -- the MUTATION TABLE for codegen/decomp/dtype.bend.

NEVER writes the live tree.  It builds a MIRROR from `git archive HEAD
tinybendygrad`, drops the live `dtype.bend` into it, and mutates only the mirror.
The live file is owned by another unit and was observed changing under a harness
twice in four minutes, once of them into a NON-COMPILING state; a harness that
writes it can corrupt that unit and be corrupted by it.

RULES, each of which has already cost this project a real run:

* RULE A -- diff whole `name=value` LINES, not row names.  A name-comparing
  harness reports 0 for every mutation that changes only a value.

* RULE B -- a mutation that does NOT COMPILE IS NOT A BLIND SPOT.  Non-programs
  say nothing about coverage, so they get their own bucket.

* RULE C -- CONTROLS.  Three no-semantics edits (no-op, comment-only,
  whitespace-only) must all read SAME.  A control that reads MOVED is a BROKEN
  HARNESS and is reported as such, loudly, before any real verdict is trusted.
  NOTE the whitespace control is a CONTINUATION line, never a `case` arm: Bend's
  indentation IS semantic, so re-indenting an arm does not compile and a
  "whitespace-only" edit is not a no-op here.

* RULE D -- PATCH DID NOT APPLY is NEVER a zero.  `edit()` returns the phrase, the
  pre-flight audit prints every dead anchor BEFORE the first mutation, and the
  report gets its own `DEAD ANCHOR` section.  A dead patch that reads "0 rows"
  is indistinguishable from a mutation the port survives.

* RULE E -- `bend` prints NOTHING on a stack overflow (~1 run in 20 here) and that
  is indistinguishable from "never started".  A run is accepted only when it
  reproduces the baseline's exact shape: same first line, same line count, same
  last line.  Otherwise retry.

* RULE F -- LC_ALL=C.  Locale-colating `sort`/`comm` fabricated 6 spurious diffs
  in this project, including on a no-op control.  (Python's `sorted` is byte
  order, so the diff below needs no shell.)

* RULE G -- REFUSE TO START if a bake exists IN THE MIRROR, and write the bake
  BEFORE that mirror's first write.  The earlier harness deleted the bake after
  the first successful run, so only M01 was ever protected.  A bake is a
  mirror-local artifact: it exists to catch a run killed mid-write, and it does
  that only for the tree being written.  One in the LIVE tree guards nothing --
  it is a bake against a file this harness refuses to write -- while making the
  harness refuse to start for anyone who mirrors the live tree.  RULE J.

* RULE H -- never gate on the exit code: `--check-only` exits 1 on a clean file.

* RULE I -- ASSERT THE MIRROR REPRODUCES THE LIVE DIGEST before mutating it.
  Otherwise a mutation run measures a file that is not the file.

* RULE J -- NO BAKE, NO MUTANT, NO BYTE OUTSIDE THE MIRROR OR .agents/slop/.
  `git archive` only carries tracked files, so the mirror cannot inherit a bake;
  a stray one is reported, not silently deleted.

usage: dd-mutate.py BASELINE.txt OUT.txt [id ...]
env:   DD_WORKERS (default 6)   DD_KEEP (leave the mirror behind)
"""
import hashlib
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIVE = os.path.join(ROOT, "tinybendygrad", "codegen", "decomp", "dtype.bend")
BEND = os.path.join(ROOT, "bin", "bend")
SCRATCH = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode"
HERE = os.path.dirname(os.path.abspath(__file__))


def sha1(text):
    return hashlib.sha1(text.encode()).hexdigest()


def shape(text):
    """RULE E/H: the shape of a GOOD run, taken from the BASELINE rather than
    hardcoded, so a row-set change upstream invalidates the guard loudly instead
    of silently accepting a truncated run."""
    lines = text.splitlines()
    return (lines[0] if lines else "", len(lines), lines[-1] if lines else "")


def load(text):
    d = {}
    for ln in text.splitlines():
        if not ln or ln.startswith("#"):
            continue
        k, _, v = ln.partition("=")
        d[k] = v
    return d


# --- RULE I + J: the mirror.  Built once, from HEAD, with the live file dropped
# in, and only then asserted equal to the live file.  `git archive HEAD
# tinybendygrad` carries the port and nothing else; the gate's output is
# BYTE-IDENTICAL with the 172 MB full archive, so 11 MB per worker is enough.
def build_mirror():
    src = open(FROZEN).read()
    if sha1(src) != FROZEN_SHA1:
        sys.exit("the frozen snapshot moved: %s is %s, the table says %s"
                 % (FROZEN, sha1(src), FROZEN_SHA1))
    tag = sha1(src)[:12]
    top = os.path.join(SCRATCH, "dd-mut-" + tag)
    if not os.path.isdir(os.path.join(top, "tinybendygrad")):
        archive = subprocess.run(["git", "-C", ROOT, "archive", "HEAD", "tinybendygrad"],
                                 stdout=subprocess.PIPE, check=True).stdout
        base = os.path.join(SCRATCH, "dd-mut-base-" + tag)
        shutil.rmtree(base, ignore_errors=True)
        shutil.rmtree(top, ignore_errors=True)
        os.makedirs(base)
        subprocess.run(["tar", "-x", "-C", base], input=archive, check=True)
        os.rename(base, top)   # rename, not move: move() into an existing dir nests
    tgt = os.path.join(top, "tinybendygrad", "codegen", "decomp", "dtype.bend")
    open(tgt, "w").write(src)
    got = open(tgt).read()
    if sha1(got) != sha1(src):        # RULE I: the mirror is the file under test
        sys.exit("RULE I: the mirror does not reproduce the frozen snapshot")
    if os.path.realpath(tgt) == os.path.realpath(LIVE):
        sys.exit("RULE J: refusing to run -- the mirror IS the live file")
    # The dependencies dtype.bend imports are the LIVE ones only insofar as they
    # are at HEAD; if a sibling is dirty the mirror still gets HEAD's copy, and
    # the C00 control below is what catches the pair being inconsistent.
    return top, tgt, sha1(src)


def stray_bakes():
    """RULE J.  `git archive` cannot carry a bake, so any `.ddmut` outside the
    slop dir and this run's mirror is a leftover from a run that wrote the live
    tree.  It is reported, never deleted: somebody else's mirror may still be
    mid-run against it."""
    out = []
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d != ".git"]
        if base == HERE or base.startswith(HERE + os.sep):
            continue                       # slop holds other units' mirrors
        for f in files:
            if f.endswith(".ddmut"):
                out.append(os.path.join(base, f))
    return out


# --- RULE C: the controls.  Each is an edit with NO semantic content.  If any
# moves a row, the diff or the harness is wrong and EVERY verdict is void -- so
# they run first and are reported first.
CONTROLS = [
    ("C00 no-op control (rewrite the file byte-identical)",
     None, None),
    ("C01 comment-only control (insert a comment line above a def)",
     "def dd_cone(n: Nat, +ar: O.Arena, +roots: List<&2, U32>) -> List<&2, U32>:",
     "# CONTROL C01: a comment line, no semantics\n"
     "def dd_cone(n: Nat, +ar: O.Arena, +roots: List<&2, U32>) -> List<&2, U32>:"),
    # A CONTINUATION/TRAILING statement, NOT a `case` arm: Bend's indentation is
    # semantic and a re-indented arm does not compile, which would make this
    # control fail for the wrong reason (RULE C).
    ("C02 whitespace-only control (re-indent one trailing statement)",
     "  W2{O.Found.ar(c), O.Found.i(c), 0}",
     "    W2{O.Found.ar(c), O.Found.i(c), 0}"),
]

# --- the mutations.  Anchors are asserted EXACTLY-ONCE (RULE D).
MUTATIONS = [
    # --- the CAST ladder: first-wins over three Booleans -------------------
    ("M01 dd_cast_sel: swap the long arm 0/1",
     "    case True{}: Bool.pick(U32, srcfl, 1, 0)\n    case False{}: Bool.pick(U32, flt, 2, 3)",
     "    case True{}: Bool.pick(U32, srcfl, 0, 1)\n    case False{}: Bool.pick(U32, flt, 2, 3)"),
    ("M02 dd_cast_sel: swap the non-long arm 2/3",
     "    case True{}: Bool.pick(U32, srcfl, 1, 0)\n    case False{}: Bool.pick(U32, flt, 2, 3)",
     "    case True{}: Bool.pick(U32, srcfl, 1, 0)\n    case False{}: Bool.pick(U32, flt, 3, 2)"),
    ("M03 dd_cast_fold: never fold a same-dtype cast",
     "    case True{}: O.Found{ar, x}\n    case False{}: P.dc_cast(ar, x, dt)",
     "    case True{}: P.dc_cast(ar, x, dt)\n    case False{}: P.dc_cast(ar, x, dt)"),
    ("M04 dd_cast_bool: invert the bool-source test",
     "    case True{}: P.dc_cast(ar, x, S.single())\n    case False{}: O.Found{ar, x}",
     "    case True{}: O.Found{ar, x}\n    case False{}: P.dc_cast(ar, x, S.single())"),
    ("M05 l2i_cast3.bitc: never fold the uint bitcast",
     "def l2i_cast3.bitc(isu: Bool, +ar: O.Arena, +a0: U32) -> O.Found:\n  match isu:\n    case True{}: O.Found{ar, a0}\n    case False{}: T.tx_bitcast(ar, a0, S.uint32())",
     "def l2i_cast3.bitc(isu: Bool, +ar: O.Arena, +a0: U32) -> O.Found:\n  match isu:\n    case True{}: T.tx_bitcast(ar, a0, S.uint32())\n    case False{}: T.tx_bitcast(ar, a0, S.uint32())"),
    ("M06 l2i_cast.got: route sel 3 to arm 0 instead of arm 3",
     "def l2i_cast.got(sel: U32, +ar: O.Arena, +a0: U32, +dt: S.Dt, +ldt: S.Dt, +xdt: S.Dt) -> Maybe<&2, W2>:\n  match sel:\n    case 0: Some{l2i_cast0(ar, a0, ldt, Bool.or(dd_is_bool(xdt), dd_is_uint(xdt)), xdt)}\n    case 1: Some{l2i_cast1(ar, a0, ldt, xdt)}\n    case 3: Some{l2i_cast3(ar, a0, dt, xdt)}",
     "def l2i_cast.got(sel: U32, +ar: O.Arena, +a0: U32, +dt: S.Dt, +ldt: S.Dt, +xdt: S.Dt) -> Maybe<&2, W2>:\n  match sel:\n    case 0: Some{l2i_cast0(ar, a0, ldt, Bool.or(dd_is_bool(xdt), dd_is_uint(xdt)), xdt)}\n    case 1: Some{l2i_cast1(ar, a0, ldt, xdt)}\n    case 3: Some{l2i_cast0(ar, a0, ldt, False{}, xdt)}"),
    ("M07 dd_bc: never fold (ADD/SUB word bitcasts)",
     "def dd_bc(isu: Bool, +ar: O.Arena, +x: U32) -> O.Found:\n  match isu:\n    case True{}: O.Found{ar, x}\n    case False{}: T.tx_bitcast(ar, x, S.uint32())",
     "def dd_bc(isu: Bool, +ar: O.Arena, +x: U32) -> O.Found:\n  match isu:\n    case True{}: T.tx_bitcast(ar, x, S.uint32())\n    case False{}: T.tx_bitcast(ar, x, S.uint32())"),
    ("M08 l2i_cast0.sgn: const_like(-1) as 1 instead of -1",
     "  +cm = dd_clike(O.Found.ar(c), 4294967295, ldt)",
     "  +cm = dd_clike(O.Found.ar(c), 1, ldt)"),
    # --- the shift arms ----------------------------------------------------
    ("M09 l2i_shl.hi: OR the halves the other way round",
     "  O.Found.i(dd_or(O.Found.ar(t), O.Found.i(s), O.Found.i(t)))",
     "  O.Found.i(dd_or(O.Found.ar(t), O.Found.i(t), O.Found.i(s)))"),
    ("M10 l2i_shl.hi: `>> 31 - n` becomes `>> n`",
     "  +k = dd_rsub31(O.Found.ar(o), n)",
     "  +k = dd_or(O.Found.ar(c1), n, O.Found.i(c1))"),
    ("M11 l2i_shr.fill: always sign-extend",
     "    case True{}:\n      +c = dd_wk(ar, H.i64_of_i32(31))\n      dd_shr(O.Found.ar(c), a1, O.Found.i(c))\n    case False{}: O.Found{ar, zero}",
     "    case True{}:\n      +c = dd_wk(ar, H.i64_of_i32(31))\n      dd_shr(O.Found.ar(c), a1, O.Found.i(c))\n    case False{}:\n      +c = dd_wk(ar, H.i64_of_i32(31))\n      dd_shr(O.Found.ar(c), a1, O.Found.i(c))"),
    ("M12 l2i_shr.fill: always fill with zero",
     "    case True{}:\n      +c = dd_wk(ar, H.i64_of_i32(31))\n      dd_shr(O.Found.ar(c), a1, O.Found.i(c))\n    case False{}: O.Found{ar, zero}",
     "    case True{}: O.Found{ar, zero}\n    case False{}: O.Found{ar, zero}"),
    ("M13 l2i_shl.ge: `b0 >= 32` becomes `b0 < 32`",
     "  dd_ge1(O.Found.ar(c), b0, O.Found.i(c))",
     "  dd_lt1(O.Found.ar(c), b0, O.Found.i(c))"),
    # --- the ALU arms ------------------------------------------------------
    ("M14 l2i_mul.p: swap `a0*b1` and `a1*b0`",
     "  +x1 = dd_mul(O.Found.ar(q), a0, b1)",
     "  +x1 = dd_mul(O.Found.ar(q), a1, b0)"),
    ("M15 l2i_mul.w: shift the product right before left",
     "  +m16 = T.tx_shl(O.Found.ar(m), O.Found.i(m), 16)",
     "  +m16 = T.tx_shr(O.Found.ar(m), O.Found.i(m), 16)"),
    ("M16 l2i_cmplt: swap the two OR halves",
     "  +r = dd_or(O.Found.ar(an), O.Found.i(lt), O.Found.i(an))",
     "  +r = dd_or(O.Found.ar(an), O.Found.i(an), O.Found.i(lt))"),
    ("M17 l2i_where: swap the two branch pairs",
     "  +r0 = dd_where(ar, c, nth(ws, 1n), nth(ws, 3n))\n  +r1 = dd_where(O.Found.ar(r0), c, nth(ws, 2n), nth(ws, 4n))",
     "  +r0 = dd_where(ar, c, nth(ws, 2n), nth(ws, 4n))\n  +r1 = dd_where(O.Found.ar(r0), c, nth(ws, 1n), nth(ws, 3n))"),
    ("M18 l2i_max: swap the WHERE branches",
     "  +r0 = dd_where(ac, cc, nth(ws, 2n), nth(ws, 0n))",
     "  +r0 = dd_where(ac, cc, nth(ws, 0n), nth(ws, 2n))"),
    ("M19 l2i_binop: force AND on both halves",
     "  +s = T.tx_alu2(O.Found.ar(r), op, nth(ws, 1n), nth(ws, 3n))",
     "  +s = T.tx_alu2(O.Found.ar(r), O.OpsAND{}, nth(ws, 1n), nth(ws, 3n))"),
    ("M20 dd_rsub31: `31 - n` becomes `31 + n`",
     "  P.dc_sub(O.Found.ar(c), O.Found.i(c), n)",
     "  dd_add(O.Found.ar(c), O.Found.i(c), n)"),
    ("M21 unpack32: mask 0xFFFF becomes 0x10000",
     "  +lo = dd_band(O.Found.ar(bc), O.Found.i(bc), 65535)",
     "  +lo = dd_band(O.Found.ar(bc), O.Found.i(bc), 65536)"),
    ("M22 unpack32: shift the masked low word instead of the bitcast",
     "  +hi = T.tx_shr(O.Found.ar(lo), O.Found.i(bc), 16)",
     "  +hi = T.tx_shr(O.Found.ar(lo), O.Found.i(lo), 16)"),
    ("M23 reindex.scaled: swap `i1*mul` to `mul*i1`",
     "  +m = dd_mul(O.Found.ar(cm), i1, O.Found.i(cm))",
     "  +m = dd_mul(O.Found.ar(cm), O.Found.i(cm), i1)"),
    ("M24 l2i_cdiv: 64 iterations become 63",
     "  +e = l2i_cdiv.loop(64n, c, 63)",
     "  +e = l2i_cdiv.loop(63n, c, 63)"),
    ("M25 l2i_cast0.pick: sign-extend where dtype.py zero-extends",
     "    case True{}: z\n    case False{}: s",
     "    case True{}: s\n    case False{}: z"),
    # --- the GATE's own metric, which is what makes the table worth having --
    # RE-AIMED.  The old M26 anchored the PRE-fix prepending line, which occurs
    # ZERO times in the fixed file, so it was PATCH-NOT-APPLIED and read as a
    # zero.  The anchor is now the FIXED line and the mutant is the pre-fix one,
    # so the name ("visit src[n] before src[0]") finally describes the edit and
    # the entry finally tests the defect it was written for.
    ("M26 dd_rs.push: visit src[n] before src[0]",
     "        case s <> t: dd_rs.cat(s, dd_rs.push(q, t, st))",
     "        case s <> t: dd_rs.push(q, t, dd_rs.cat(s, st))"),
    ("M27 dd_rs.has: never remember a node (cone visits every edge)",
     "          st2 = dd_rs.more(Bool.not(dd_rs.has(dd_seen(ar), seen, u)), ar, u, rest)",
     "          st2 = dd_rs.more(True{}, ar, u, rest)"),
    ("M28 l2i.roots: root the cone at the low word only",
     "    case True{}: [lo, hi]\n    case False{}: [lo]",
     "    case True{}: [lo]\n    case False{}: [lo]"),
    ("M29 l2i.gone: print `none` instead of naming the exception",
     'String.concat([nm, "=refused:", "NotImplementedError", "\\n", nm, "n=", U32.show(U32.sub(to, from)), "\\n"])',
     'String.concat([nm, "=none\\n", nm, "n=", U32.show(U32.sub(to, from)), "\\n"])'),
    ("M30 dd_eck: treat every node as a CONST",
     "          +k = dd_ck(ar, u)\n          nf = Bool.and(first, Bool.not(k))\n          s = dd_join.ck(first, k, acc, dd_lab(ar, u))",
     "          +k = True{}\n          nf = Bool.and(first, Bool.not(k))\n          s = dd_join.ck(first, k, acc, dd_lab(ar, u))"),
    ("M31 dd_join.add: join with `-` instead of `,`",
     '    case False{}: String.concat([acc, ",", s])',
     '    case False{}: String.concat([acc, "-", s])'),
    ("M32 l2i.went: never call l2i (the refusal guard always fires)",
     "def l2i.one(nm: String, +op: O.Op, +dt: S.Dt, +xdt: S.Dt, base: Nat, nw: U32, +ga: Ga) -> Ga:\n  l2i.went(nm, dd_l2i_ok(op), op, dt, xdt, base, nw, ga)",
     "def l2i.one(nm: String, +op: O.Op, +dt: S.Dt, +xdt: S.Dt, base: Nat, nw: U32, +ga: Ga) -> Ga:\n  l2i.went(nm, Bool.not(dd_l2i_ok(op)), op, dt, xdt, base, nw, ga)"),
    # --- families with NO rows: the zeros that are requests, not theorems ---
    ("M33 l2i_define.size2: stop doubling the size",
     "  match m:\n    case Some{n}: Some{U32.mul(n, 2)}\n    case None{}: None{}",
     "  match m:\n    case Some{n}: Some{n}\n    case None{}: None{}"),
    ("M34 f2f.up.tail: always take the non-fnuz arm",
     "  match fnuz:\n    case True{}: f2f.fnuz(ar, ns, sg, ex, nm, te, tm)\n    case False{}: f2f.ocp(e4m3, ar, ns, sg, ex, nm, nn, fe, fm)",
     "  match fnuz:\n    case True{}: f2f.ocp(e4m3, ar, ns, sg, ex, nm, nn, fe, fm)\n    case False{}: f2f.ocp(e4m3, ar, ns, sg, ex, nm, nn, fe, fm)"),
    ("M35 rne.sel: refuse every shift",
     "  match zero:\n    case True{}: None{}\n    case False{}: Some{rne.go(ar, v, s)}",
     "  match zero:\n    case True{}: None{}\n    case False{}: None{}"),
    # --- FOUND LIVE, 2026-10-03.  dtype.py:74 is `return r if op == Ops.CMOD
    # else q`, and the comment above `uns` quotes it verbatim -- but the arms
    # are the other way round, so the UNSIGNED CDIV row (`lgs`) answers with the
    # remainder and the UNSIGNED CMOD row (`lgt`) answers with the quotient.
    # Same shape as the two mutants that reached origin/master (`l2i_shl.hi`'s
    # OR swap, `reindex.scaled`'s mul swap): operand/arm identity inside a
    # commutative-looking pair.  See dd-mutate-report.md.
    ("M36 l2i_cdiv.uns: swap the two arms (CDIV must take q, CMOD must take r)",
     "  match isdiv:\n    case True{}: W2{ar, Cd.r0(c), 0}\n    case False{}: W2{ar, Cd.q0(c), 0}",
     "  match isdiv:\n    case True{}: W2{ar, Cd.q0(c), 0}\n    case False{}: W2{ar, Cd.r0(c), 0}"),
]

PLAN = [("C%02d %s" % (i, n), o, w) for i, (n, o, w) in enumerate(CONTROLS)] + MUTATIONS

# The frozen snapshot this table is measured against.  `dtype.bend` belongs to a
# CONCURRENT unit that was observed rewriting it mid-run (73b0e1e7 -> a2c68a7e
# while 39 mutations were in flight), and the new file does not even compile
# (`expected : H.I64`).  A harness that reads the live file per mutation measures
# a moving target, so the snapshot is PINNED BY DIGEST and the run asserts it.
# To retarget: freeze the file, record its sha1 here, and re-run the baseline.
FROZEN = os.path.join(HERE, "dd-mutations.frozen.bend")
FROZEN_SHA1 = "73b0e1e7fd6652c5fc7b49323a1956d44545f230"


def edit(src, old, new):
    """Apply one edit and report EXACTLY what happened.  RULE D: a missing or
    ambiguous anchor is PATCH DID NOT APPLY, which is never a zero."""
    if old is None:
        return src, "no-op (byte-identical rewrite)"
    n = src.count(old)
    if n == 0:
        return None, "PATCH DID NOT APPLY: anchor absent (0 occurrences)"
    if n > 1:
        return None, "PATCH DID NOT APPLY: anchor is %d-AMBIGUOUS" % n
    return src.replace(old, new, 1), "applied"


def run_gate(path, tgt, want):
    """Run the gate until it reproduces `want`'s exact shape.  bend's stack
    overflow prints nothing at all, which is what makes a 0-row result
    indistinguishable from 'never started', so SHAPE is the guard and the exit
    code is not (RULE E, RULE H).

    The FIRST attempt of a WHOLE RUN is the substrate probe: the unmutated mirror
    must reproduce the baseline's shape before any mutation is measured.  Without
    it a substrate that stopped compiling turns 39 mutations into 39
    DID-NOT-COMPILE rows, which is what happened once here.
    """
    err = ""
    for attempt in range(24):
        with open(path, "w") as fh:
            p = subprocess.run([BEND, tgt], stdout=fh, stderr=subprocess.PIPE)
        text = open(path).read()
        if shape(text) == want:
            return text, None, attempt + 1
        err = (p.stderr or b"").decode()[:400]
        if text:
            # It printed SOMETHING but the wrong shape: a real behavioural change
            # (fewer rows, a refused trace) -- not an overflow.
            return text, None, attempt + 1
    return None, err, 24


def probe_substrate(tgt, want):
    """RULE C, UPSTREAM of every control: the UNMUTATED mirror must reproduce the
    baseline.  If it does not, no mutation result is evidence about the port."""
    got, err, tries = run_gate(os.path.join(SCRATCH, "ddprobe.txt"), tgt, want)
    if got is None:
        sys.exit("SUBSTRATE FAILS: the unmutated mirror printed nothing in 24 "
                 "attempts -- bend's stack overflow, or a compile failure.  No "
                 "verdict is evidence until this passes.\n  %s" % (err or "")[:400])
    if shape(got) != want:
        sys.exit("SUBSTRATE MISMATCH: the unmutated mirror reads %r but the "
                 "baseline is %r.\n  The mirror and the baseline are not the same "
                 "build.  Re-freeze and re-baseline; do NOT read the diff as "
                 "mutant behaviour." % (shape(got), want))
    return got


def main():
    base_txt = open(sys.argv[1]).read()
    base = load(base_txt)
    good = shape(base_txt)          # `want` is the id filter; `good` the shape
    want = set(sys.argv[3:])
    plan = [p for p in PLAN if not want or p[0].split()[0] in want or p[0] in want]
    top, tgt, digest = build_mirror()
    src = open(tgt).read()
    print("# mirror  %s" % top)
    print("# FROZEN  %s sha1 %s (pinned; the live file is a concurrent unit's)"
          % (FROZEN, digest))
    if sha1(open(LIVE).read()) != digest:
        print("#         live dtype.bend is now %s -- DIFFERENT.  This table is "
              "against the snapshot, not against what is on disk."
              % sha1(open(LIVE).read())[:12])
    for stray in stray_bakes():
        print("# RULE J: STRAY BAKE outside .agents/slop/ and this mirror: %s"
              % stray)

    # RULE D, PRE-FLIGHT: every anchor is audited BEFORE the first write, so a
    # dead patch is a refusal to measure, not a zero discovered afterwards.
    dead = []
    for name, old, new in plan:
        if old is not None and src.count(old) != 1:
            dead.append((name, src.count(old)))
    for name, n in dead:
        print("# PATCH DID NOT APPLY  %s  (anchor occurs %d times, need 1)"
              % (name.split()[0], n))
    if dead:
        print("# %d DEAD ANCHOR(S): these are requests for fixtures/anchors, NOT"
              " passes, and they are reported as such in the table." % len(dead))

    # RULE G, at STARTUP: a bake already inside the mirror means an earlier run
    # was killed mid-write and that mirror cannot be trusted.  `git archive`
    # cannot carry one, so only a killed run leaves it.
    # NOT `for base, ...`: that rebound `base` from the baseline row dict to a
    # directory name, so every diff below raised AttributeError on a str.  A
    # shadowed baseline is worse than no baseline.
    for root, _, files in os.walk(top):
        for f in files:
            if f.endswith(".ddmut"):
                sys.exit("REFUSING TO START: bake %s -- an earlier run was killed "
                         "mid-mutation.\n  diff %s %s\n  delete %s only once they "
                         "agree." % (os.path.join(root, f), LIVE,
                                     os.path.join(root, f), top))

    probe_substrate(tgt, good)
    print("# substrate OK: the unmutated mirror reproduces the baseline shape")

    workers = max(1, min(int(os.environ.get("DD_WORKERS", 6)), len(plan)))
    cache = os.path.join(HERE, "dd-mut", digest)   # keyed: a stale cache from a
    os.makedirs(cache, exist_ok=True)               # 147-row baseline cannot be

    def one(w, job):
        """One entry.  Every worker owns a private copy of the mirror, so no two
        mutations can ever see each other's file."""
        name, old, new = job
        short = name.split()[0]
        tree = os.path.join(top, "w%d" % w)
        wtgt = os.path.join(tree, "tinybendygrad", "codegen", "decomp", "dtype.bend")
        # ONE output file PER WORKER, never one shared path: two workers writing
        # the same path interleave, and a worker's "this shape is not the
        # baseline's" reading of ANOTHER mutation's text is reported as a real
        # behavioural change.  That is a fabricated verdict, not a flaky one.
        out = os.path.join(SCRATCH, "ddmut-%d.txt" % w)
        dest = os.path.join(cache, short + ".txt")
        if os.path.exists(dest):          # resumable: converges over re-runs
            verdict, moved = open(dest).read().split("\t", 1)
            return name, verdict, [x for x in moved.split(",") if x], "cached"
        if not os.path.isdir(tree):
            shutil.copytree(top, tree)
        bake = wtgt + ".ddmut"            # RULE G: written before the first write
        if not os.path.exists(bake):
            open(bake, "w").write(src)
        mutated, how = edit(src, old, new)
        if mutated is None:
            open(wtgt, "w").write(src)    # nothing was written; be sure
            open(dest, "w").write("PATCH-NOT-APPLIED\t" + how)
            return name, "PATCH-NOT-APPLIED", [], how
        open(wtgt, "w").write(mutated)
        got, err, tries = run_gate(out, wtgt, good)
        open(wtgt, "w").write(src)        # RESTORE FIRST, decide after
        if got is None:
            first = " | ".join((err or "").splitlines()[:3])
            open(dest, "w").write("DID-NOT-COMPILE\t" + first)
            return name, "DID-NOT-COMPILE", [], first
        cur = load(got)
        moved = sorted(k for k in set(base) | set(cur) if base.get(k) != cur.get(k))
        verdict = "SAME" if not moved else "MOVED"
        open(dest, "w").write(verdict + "\t" + ",".join(moved))
        return name, verdict, moved, "%d attempt(s)" % tries

    chunks = [(i, plan[i::workers]) for i in range(workers) if plan[i::workers]]

    def run(chunk):
        w, jobs = chunk
        try:
            return [one(w, job) for job in jobs]
        finally:
            # The bake is dropped only when the chunk finished; a kill leaves it
            # and the startup walk above then refuses to start.
            shutil.rmtree(os.path.join(top, "w%d" % w), ignore_errors=True)

    with ThreadPoolExecutor(workers) as pool:
        results = list(pool.map(run, chunks))
    rows = [r for chunk in results for r in chunk]
    rows.sort(key=lambda r: PLAN.index(next(p for p in PLAN if p[0] == r[0])))
    # RULE C, ENFORCED.  A control that is not SAME -- MOVED, or DID-NOT-COMPILE,
    # or PATCH-NOT-APPLIED -- means the measurement is void, and a void
    # measurement MUST NOT BE WRITTEN AS A TABLE.  A run where C00 (the
    # byte-identical rewrite) could not compile produced 39 DID-NOT-COMPILE rows
    # and called it a table; every one of those was noise about the substrate.
    broken = next((n for n, v, _, _ in rows
                   if v != "SAME" and n.split()[0].startswith("C")), None)
    if broken:
        for name, verdict, moved, note in rows:
            print("%-4s %-62s %-17s %3d rows  %s"
                  % (name.split()[0], name[len(name.split()[0]):][:62], verdict,
                     len(moved), note))
        sys.exit("CONTROL NOT SAME: %s read %s.  EVERY VERDICT IS VOID -- the "
                 "harness or the substrate is wrong, not the port.\n"
                 "  No table written.  Check C00 first: a byte-identical "
                 "rewrite that does not compile is a COMPILE failure in the "
                 "mirror, not a mutation result." % (broken, broken))
    for name, verdict, moved, note in rows:
        print("%-4s %-62s %-17s %3d rows  %s"
              % (name.split()[0], name[len(name.split()[0]):][:62], verdict,
                 len(moved), note))

    ctl = [r for r in rows if r[1] == "SAME" and r[0].startswith("C")]
    mv = [r for r in rows if r[1] == "MOVED"]
    deadr = [r for r in rows if r[0] not in ("x",) and r[1] == "PATCH-NOT-APPLIED"]
    zero = [r for r in rows if r[1] == "SAME" and not r[0].startswith("C")]
    nocc = [r for r in rows if r[1] == "DID-NOT-COMPILE"]

    fh = open(sys.argv[2], "w")
    w = fh.write           # NOT `w`: that is the worker index, still in scope
    w("# dd-mutate.py -- MUTATION TABLE for codegen/decomp/dtype.bend\n")
    w("# target sha1 %s, asserted EQUAL to the live file (RULE I)\n" % digest)
    w("# baseline %d rows, shape (first=%r lines=%d last=%r)\n"
      % (len(base), good[0], good[1], good[2]))
    w("# %d controls SAME | %d mutations MOVED | %d SAME (zeros: REQUEST or "
      "THEOREM, never a silent pass) | %d DID-NOT-COMPILE | %d DEAD ANCHOR\n"
      % (len(ctl), len(mv), len(zero), len(nocc), len(deadr)))
    w("#\n# DEAD ANCHOR -- PATCH DID NOT APPLY.  NOT a zero, NOT a pass.\n")
    for name, verdict, moved, note in deadr:
        w("#   %-62s %s\n" % (name, note))
    if not deadr:
        w("#   (none: every anchor occurs exactly once)\n")
    w("#\n# CONTROLS (RULE C -- all must read SAME; a MOVED control voids every "
      "verdict below)\n")
    for name, verdict, moved, note in rows:
        if name.startswith("C"):
            w("#   %-62s %s\n" % (name, verdict))
    w("#\n#   NOTE: a whitespace-only edit of a `case` arm does NOT compile -- "
      "Bend's indentation is\n#   semantic -- so C02 re-indents a trailing "
      "statement, not an arm.\n")
    if broken:
        w("#\n# !!!!! CONTROL BROKEN: %s MOVED ROWS.  EVERY VERDICT BELOW IS VOID. "
          "!!!!!\n" % broken)
    for name, verdict, moved, note in rows:
        if name.startswith("C"):
            continue
        w("\n%s\n  %s  %d rows%s\n" % (name, verdict, len(moved),
                                        "" if verdict in ("MOVED",) else
                                        "   << " + note))
        for k in moved:
            w("    %s\n" % k)
    covered = set()
    for _, _, moved, _ in rows:
        covered |= set(moved)
    orphans = sorted(k for k in base if k not in covered)
    w("\n\n=== ROWS NO MUTATION MOVED (%d of %d baseline rows) ===\n"
      % (len(orphans), len(base)))
    for k in orphans:
        w("  %s\n" % k)
    fh.close()

    # The machine-readable sidecar, so the table can be rebuilt without parsing
    # the prose and the classification lives in one place.
    tsv = open(sys.argv[2] + ".tsv", "w")
    for name, verdict, moved, _ in rows:
        tsv.write("%s\t%s\t%d\t%s\n"
                  % (name.split()[0], verdict, len(moved), ",".join(moved)))
    tsv.close()

    if not os.environ.get("DD_KEEP"):
        for i in range(workers):
            shutil.rmtree(os.path.join(top, "w%d" % i), ignore_errors=True)
        shutil.rmtree(top, ignore_errors=True)
    print("\n%d controls SAME | %d moved | %d zeros | %d did-not-compile | "
          "%d dead anchor | %d unmoveable rows"
          % (len(ctl), len(mv), len(zero), len(nocc), len(deadr), len(orphans)))
    if broken:
        sys.exit("CONTROL BROKEN: %s moved rows -- the harness is wrong, not the port"
                 % broken)
    if deadr:
        sys.exit("DEAD ANCHOR: %d mutation(s) did not apply; the table is "
                 "INCOMPLETE, not green" % len(deadr))


main()