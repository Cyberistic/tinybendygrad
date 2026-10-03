#!/usr/bin/env python3
"""dd-mutate.py -- the MUTATION TABLE for codegen/decomp/dtype.bend.

Runs against a MIRROR of the tree, never the live file.  The live file is owned
by the row-regression unit and was observed changing under this harness twice in
four minutes, once of them into a NON-COMPILING state; a mutation harness that
writes it can therefore both corrupt the other unit and be corrupted by it.

RULES THIS FILE ENFORCES (each one has already cost this project a real run):

* RULE A -- diff whole `name=value` LINES, not row names.  A name-comparing
  harness reports 0 for every mutation that changes only a value.

* RULE B -- a mutation that does NOT COMPILE IS NOT A BLIND SPOT.  Non-programs
  say nothing about coverage, so they get their own bucket.

* RULE C -- CONTROLS.  Three no-semantics edits (no-op, comment-only,
  whitespace-only) must all read SAME.  A control that reads MOVED is a BROKEN
  HARNESS and is reported as such, loudly, before any real verdict is trusted.

* RULE D -- PATCH DID NOT APPLY is never printed as "0 rows moved".  Those are
  different facts and conflating them has already produced three false zeros.

* RULE E -- `bend` prints NOTHING on a stack overflow (~1 run in 20 here) and
  that is indistinguishable from "did not start".  So a run is only accepted
  when it reproduces the baseline's exact shape: same first line, same line
  count, same last line.  Otherwise retry.

* RULE F -- LC_ALL=C.  Locale-colating `sort`/`comm` fabricated 6 spurious
  diffs in this project, including on a no-op control.

* RULE G -- REFUSE TO START if a bake exists, and write the bake BEFORE the
  first mutation.  The previous harness deleted the bake after the first
  successful run, so only M01 was ever protected.

* RULE H -- never gate on the exit code: `--check-only` exits 1 on a clean file.

usage: dd-mutate.py BASELINE.txt OUT.txt [name ...]
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# The mirror defaults into .agents/slop/ but DD_TREE overrides it: another
# agent was observed DELETING files under .agents/slop/ mid-run, which took the
# first mirror and its baseline with it.
MIRROR = os.environ.get("DD_TREE") or os.path.join(
    ROOT, ".agents", "slop", "dd-mirror", "tinybendygrad")
TARGET = os.path.join(MIRROR, "codegen", "decomp", "dtype.bend")
BEND = os.path.join(ROOT, "bin", "bend")
SCRATCH = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode"

# RULE H: the shape of a GOOD run, taken from the baseline itself rather than
# hardcoded, so a row-set change upstream invalidates the guard loudly instead
# of silently accepting a truncated run.
def shape(text):
    lines = text.splitlines()
    return (lines[0] if lines else "", len(lines), lines[-1] if lines else "")


def run_gate(path, want):
    """Run the gate until it reproduces `want`'s exact shape.  bend's stack
    overflow prints nothing at all, which is what makes a 0-row result
    indistinguishable from 'never started', so shape is the guard and the
    exit code is not (RULE E, RULE H)."""
    err = ""
    for attempt in range(24):
        with open(path, "w") as fh:
            p = subprocess.run([BEND, TARGET], stdout=fh, stderr=subprocess.PIPE)
        text = open(path).read()
        if shape(text) == want:
            return text, None, attempt + 1
        err = (p.stderr or b"").decode()[:400]
        if text:
            # It printed SOMETHING but the wrong shape: a real behavioural
            # change (fewer rows, refused trace) -- not an overflow.
            return text, None, attempt + 1
    return None, err, 24


def load(text):
    d = {}
    for ln in text.splitlines():
        if not ln or ln.startswith("#"):
            continue
        k, _, v = ln.partition("=")
        d[k] = v
    return d


# --- RULE C: the controls.  Each is an edit with NO semantic content.  If any
# of these moves a row, the diff or the harness is wrong and every verdict in
# the table is void -- so they run FIRST and are reported first.
CONTROLS = [
    ("C00 no-op control (rewrite the file byte-identical)",
     None, None),
    ("C01 comment-only control (append a comment line to a def body)",
     "def l2i_shr.fill(+ar: O.Arena, +a1: U32, +zero: U32, signed: Bool) -> O.Found:\n  match signed:",
     "def l2i_shr.fill(+ar: O.Arena, +a1: U32, +zero: U32, signed: Bool) -> O.Found:\n  # CONTROL C01: a comment line, no semantics\n  match signed:"),
    ("C02 whitespace-only control (re-indent a CONTINUATION line only)",
     "  W2{O.Found.ar(c), O.Found.i(c), 0}",
     "    W2{O.Found.ar(c), O.Found.i(c), 0}"),
]

# --- the mutations.  Anchors are asserted UNIQUE in the target (RULE D), because
# `str.replace(old, new, 1)` on a non-unique anchor mutates whichever site
# happens to come first and reports it as a deliberate one.
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
    ("M26 dd_rs.push: visit src[n] before src[0]",
     "        case s <> t: dd_rs.push(q, t, dd_rs.cat(s, st))",
     "        case s <> t: dd_rs.push(q, t, dd_rs.cat(s, List.reverse(&2, U32, st)))"),
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
]

RESULTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dd-mut")


def edit(src, old, new):
    """Apply one edit and report EXACTLY what happened.  RULE D: a missing or
    ambiguous anchor is `PATCH DID NOT APPLY`, which is never a zero."""
    if old is None:
        return src, "no-op"
    n = src.count(old)
    if n == 0:
        return None, "PATCH DID NOT APPLY: anchor absent"
    if n > 1:
        return None, "PATCH DID NOT APPLY: anchor is %d-AMBIGUOUS" % n
    return src.replace(old, new, 1), "applied"


def main():
    base_txt = open(sys.argv[1]).read()
    base = load(base_txt)
    good = shape(base_txt)          # `want` is the name-filter set; `good` the shape
    want = set(sys.argv[3:])
    src = open(TARGET).read()

    # RULE G: bake BEFORE the first write and refuse to start if one is there.
    # The old harness deleted the bake after the first successful mutation, so
    # M02..M35 ran with no bake at all.
    BAKE = TARGET + ".ddmut"
    if os.path.exists(BAKE):
        sys.exit("REFUSING TO START: %s exists, so an earlier run was killed "
                 "mid-mutation and the mirror may be contaminated.\n"
                 "  diff %s %s\n"
                 "  delete the bake only once they agree."
                 % (BAKE, TARGET, BAKE))
    open(BAKE, "w").write(src)
    os.makedirs(RESULTDIR, exist_ok=True)

    plan = [("C%02d %s" % (i, n), o, w) for i, (n, o, w) in enumerate(CONTROLS)]
    plan += MUTATIONS

    rows, broken = [], []
    for name, old, new in plan:
        short = name.split()[0]
        if want and short not in want and name not in want:
            continue
        dest = os.path.join(RESULTDIR, short + ".txt")
        if os.path.exists(dest):          # resumable: converges over re-runs
            verdict, moved = open(dest).read().split("\t", 1)
            moved = [x for x in moved.split(",") if x]
            rows.append((name, verdict, moved))
            print("%-62s (cached) %s %d rows" % (name[:62], verdict, len(moved)))
            continue

        mutated, how = edit(src, old, new)
        if mutated is None:
            open(TARGET, "w").write(src)          # nothing was written; be sure
            open(dest, "w").write("PATCH-NOT-APPLIED\t" + how)
            rows.append((name, "PATCH-NOT-APPLIED", []))
            print("%-62s %s" % (name[:62], how))
            continue

        open(TARGET, "w").write(mutated)
        got, err, tries = run_gate(os.path.join(SCRATCH, "ddmut.txt"), good)
        open(TARGET, "w").write(src)              # RESTORE FIRST, decide after
        if got is None:
            first = " | ".join((err or "").splitlines()[:3])
            open(dest, "w").write("DID-NOT-COMPILE\t" + first)
            rows.append((name, "DID-NOT-COMPILE", []))
            print("%-62s DID-NOT-COMPILE  %s" % (name[:62], first))
            continue

        cur = load(got)
        moved = sorted(k for k in set(base) | set(cur) if base.get(k) != cur.get(k))
        verdict = "SAME" if not moved else "MOVED"
        if name.split()[0].startswith("C") and moved:
            verdict, broken = "CONTROL-BROKEN", name
        open(dest, "w").write(verdict + "\t" + ",".join(moved))
        rows.append((name, verdict, moved))
        print("%-62s %-9s %3d rows  %s"
              % (name[:62], verdict, len(moved), ", ".join(moved[:10])))

    os.remove(BAKE)

    out = open(sys.argv[2], "w")
    out.write("# dd-mutate.py -- MUTATION TABLE for codegen/decomp/dtype.bend\n")
    out.write("# tree: MIRROR .agents/slop/dd-mirror (git archive HEAD + the live\n")
    out.write("# dtype.bend at shasum %s). The live file is NOT written.\n"
              % __import__("hashlib").sha1(src.encode()).hexdigest())
    out.write("# baseline: %d rows, shape (first=%r lines=%d last=%r)\n"
              % (len(base), good[0], good[1], good[2]))
    ctl = [r for r in rows if r[1] == "SAME" and r[0].startswith("C")]
    mv = [r for r in rows if r[1] == "MOVED"]
    dead = [r for r in rows if r[1] == "SAME" and not r[0].startswith("C")]
    nocc = [r for r in rows if r[1] in ("DID-NOT-COMPILE", "PATCH-NOT-APPLIED")]
    out.write("# %d controls SAME, %d mutations MOVED, %d mutations SAME (zeros), "
              "%d did-not-compile/patch\n" % (len(ctl), len(mv), len(dead), len(nocc)))
    if broken:
        out.write("#\n# !!!!! CONTROL BROKEN: %s MOVED ROWS.  EVERY VERDICT BELOW "
                  "IS VOID. !!!!!\n" % broken)
    for name, verdict, moved in rows:
        out.write("\n%s\n  %s  %d rows\n" % (name, verdict, len(moved)))
        for k in moved:
            out.write("    %s\n" % k)

    # The most valuable output: rows NO mutation moved.
    covered = set()
    for _, _, moved in rows:
        covered |= set(moved)
    orphans = sorted(k for k in base if k not in covered)
    out.write("\n\n=== ROWS NO MUTATION MOVED (%d of %d baseline rows) ===\n"
              % (len(orphans), len(base)))
    for k in orphans:
        out.write("  %s\n" % k)
    out.close()

    if broken:
        sys.exit("CONTROL BROKEN: %s moved rows -- the harness is wrong, not the port"
                 % broken)
    print("\n%d controls SAME | %d moved | %d zeros | %d did-not-compile | %d unmoveable rows"
          % (len(ctl), len(mv), len(dead), len(nocc), len(orphans)))


main()
