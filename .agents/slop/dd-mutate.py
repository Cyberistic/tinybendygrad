#!/usr/bin/env python3
# dd-mutate.py -- the MUTATION TABLE for codegen/decomp/dtype.bend.
#
# RULE: diff whole `name=value` LINES, not row names.  A harness that compares
# names reports 0 for every mutation that changes only a value.
#
# RULE: a mutation that does NOT COMPILE IS NOT A BLIND SPOT.  A non-program says
# nothing about coverage, so it is reported in its own bucket and never counted as
# "moved 0 rows".  That distinction is the whole reason this file separates
# `NO-COMPILE` from `MOVED NOTHING`.
#
# usage: dd-mutate.py BASELINE.txt OUT.txt [name ...]
import os
import subprocess
import sys

ROOT = os.getcwd()
BEND = "./bin/bend"
TARGET = "tinybendygrad/codegen/decomp/dtype.bend"


def run_gate(path):
    """`bend` overflows its machine stack on ~1 run in 20 and sometimes prints
    ZERO rows, which is indistinguishable from 'did not start'.  So loop until a
    run prints the head rows, and never gate on the exit code."""
    for _ in range(8):
        with open(path, "w") as fh:
            p = subprocess.run([BEND, TARGET], stdout=fh, stderr=subprocess.PIPE)
        head = open(path).read()
        if head.startswith("l2idt0=") and head.count("\nlg") > 100:
            return head, None
    return None, (p.stderr.decode()[:200] or p.stdout.decode()[:200])


def load(text):
    d = {}
    for ln in text.splitlines():
        if not ln or ln.startswith("#"):
            continue
        k, _, v = ln.partition("=")
        d[k] = v
    return d


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
    ("M06 l2i_cast.got: route sel 3 to arm 0 instead of the else",
     "    case 3: Some{l2i_cast3(ar, a0, dt, xdt)}",
     "    case 3: Some{l2i_cast0(ar, a0, ldt, False{}, xdt)}"),
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
    ("M19 l2i_binop: XOR both halves into the same op",
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
    ("M23 reindex.scaled: `i1*mul + off` becomes `i1 + off*mul`",
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
     "          k = dd_ck(ar, u)",
     "          k = Bool.not(Bool.not(True{}))"),
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


# RESUMABLE, and that is not an optimisation: this suite takes ~20 minutes and
# the server restarts underneath it.  Each mutation writes its verdict to its own
# file the moment it is known, the target is restored IMMEDIATELY after every run
# (a `finally` at the end of the loop is not enough -- the process was killed once
# and left `l2i_where` mutated on disk), and a verdict that is already on disk is
# skipped.  Re-run it as many times as it takes; it converges.

RESULTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dd-mut")


def main():
    base_txt = open(sys.argv[1]).read()
    out = open(sys.argv[2], "w")
    want = set(sys.argv[3:])
    base = load(base_txt)
    src = open(TARGET).read()
    os.makedirs(RESULTDIR, exist_ok=True)
    rows = []
    for name, old, new in MUTATIONS:
        short = name.split()[0]
        if want and short not in want and name not in want:
            continue
        dest = os.path.join(RESULTDIR, short + ".txt")
        if os.path.exists(dest):
            verdict, moved = open(dest).read().split("\t", 1)
            rows.append((name, verdict, [x for x in moved.split(",") if x]))
            print("%-64s (cached) %s %d rows" % (name, verdict, len(rows[-1][2])))
            continue
        if old not in src:
            open(dest, "w").write("PATCH-NOT-FOUND\t")
            rows.append((name, "PATCH-NOT-FOUND", []))
            print("%-64s PATCH-NOT-FOUND" % name)
            continue
        open(TARGET, "w").write(src.replace(old, new, 1))
        got, err = run_gate("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/ddmut.txt")
        open(TARGET, "w").write(src)          # RESTORE FIRST, decide after
        if got is None:
            first = (err or "").splitlines()[:2]
            open(dest, "w").write("NO-COMPILE\t" + " | ".join(first))
            rows.append((name, "NO-COMPILE", []))
            print("%-64s NO-COMPILE  %s" % (name, " | ".join(first)))
            continue
        cur = load(got)
        moved = sorted(k for k in set(base) | set(cur) if base.get(k) != cur.get(k))
        open(dest, "w").write("OK\t" + ",".join(moved))
        rows.append((name, "OK", moved))
        shown = ", ".join(moved[:14]) + (" ..." if len(moved) > 14 else "")
        print("%-64s moved %3d  %s" % (name, len(moved), shown))
    movedn = [r for r in rows if r[1] == "OK" and r[2]]
    deadn = [r for r in rows if r[1] == "OK" and not r[2]]
    nocc = [r for r in rows if r[1] != "OK"]
    out.write("# dd-mutate.py -- %d mutations, whole `name=value` line diffs\n" % len(rows))
    out.write("# %d moved rows, %d moved nothing, %d did not compile/patch\n"
              % (len(movedn), len(deadn), len(nocc)))
    for name, verdict, moved in rows:
        out.write("\n%s\n  %s  %d rows\n" % (name, verdict, len(moved)))
        for k in moved:
            out.write("    %s\n" % k)
    out.close()


main()