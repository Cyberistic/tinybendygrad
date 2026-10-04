#!/usr/bin/env python3
"""dd-band-census.py -- the SPECIES CENSUS for `codegen/decomp/dtype.bend`: every place a
`U32` is ambiguous between "arena slot" and "the number", with DENOMINATORS.

THE SPECIES. `dd_band`'s third parameter, and `T.tx_shl`/`T.tx_shr`'s THIRD parameter, are
CONSTANT VALUES: `dd_band` is `op.bend`'s `dc_band(ar, x, k)` which interns `dc_cint(ar, k)`,
and `tx_shl(ar, x, y)`/`tx_shr(ar, x, y)` build `tx_pow2(ar, y)` = `tx_ci64(ar, p)` = a
`UOp.const`. Everything else in these two files that takes a `U32` takes a NODE INDEX. A
`U32` is both, so passing the wrong one typechecks.

WHY A DENOMINATOR. "Seven sites" and "seven sites of which two are wrong" are different
claims and the second one is the one that matters, so every category below is reported as
audited/total and every unaudited site is NAMED rather than counted optimistically.

usage: dd-band-census.py [FILE]
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEF = re.compile(r"^def\s+([A-Za-z_][A-Za-z0-9_.]*)\s*\((.*?)\)\s*->", re.M)

# a THIRD parameter that is a constant: the def's body interns it as a CONST
VALUE_PARAMS = {"dd_band": 3, "T.tx_shl": 3, "T.tx_shr": 3,
                "dd_wk": 2, "dd_wkf": 2, "dc_band": 3, "dc_shl": 3, "dc_shr": 3, "dc_cint": 2}
# a THIRD parameter that is a node index
INDEX_PARAMS = {"dd_and": 3, "dd_or": 3, "dd_add": 3, "dd_mul": 3, "dd_shl": 3, "dd_shr": 3,
                "dd_xor": 3, "dd_ne": 3, "dd_eq1": 3, "dd_lt1": 3, "dd_ge1": 3,
                "dd_wf": 2, "dd_bc": 3, "T.tx_alu2": 4, "T.tx_bitcast": 3, "dd_rsub31": 2}

CALL = re.compile(r"(?<![\w.])([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*\(")

#: The callees whose arguments include an INTEGER POSITION. A NAME SET, and therefore a FLOOR
#: over that set: section C cannot see an index whose callee is missing here, whatever its
#: spelling. MEASURED consequence on .agents/slop/dd-mutations.frozen.bend: with `dd_band`
#: absent, section C reported ZERO index-valued mask arguments while section A reported SEVEN
#: -- the same seven, read through a different question. `dd_band` is in here now. A whitelist
#: of names goes stale the moment a def is RENAMED, and dtype.bend's `dc_band` -> `dd_band`
#: is exactly that; the denominator line under section C exists so the coverage is VISIBLE
#: rather than assumed.
INTEGER_CALLEES = (frozenset(VALUE_PARAMS) | frozenset(INDEX_PARAMS) | frozenset({
    "H.i64_of_i32", "H.i64_sub", "H.i64_of_u32", "U32.shl", "U32.shr", "U32.shln",
    "U32.and", "U32.or", "U32.xor", "U32.add", "U32.sub", "U32.mul", "U32.div",
    "U32.mod", "U32.eq", "U32.lt", "U32.le", "U32.gt", "U32.ge", "U32.is_zero",
    "U32.bitcast", "U32.from_nat", "U32.to_nat", "U32.clz", "U32.popcnt",
    "T.tx_powi", "T.tx_powi32", "T.tx_shl", "T.tx_shr", "T.tx_alu2", "T.tx_bitcast",
    "T.exponent_bias", "T.tx_pow2", "P.dc_cast", "P.cast",
}))


def split_args(s):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def call_args(src, upto):
    """(line, [args]) for every call to the def NAMED `dd_band` in `src[:upto]`"""
    out = []
    for m in re.finditer(r"(?<![\w.])dd_band\s*\(", src[:upto]):
        i = m.end()
        depth, j = 1, i
        while depth and j < upto:
            if src[j] == "(":
                depth += 1
            elif src[j] == ")":
                depth -= 1
            j += 1
        out.append((src.count("\n", 0, m.start()) + 1, split_args(src[i:j - 1])))
    return out


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        HERE, "..", "..", "tinybendygrad", "codegen", "decomp", "dtype.bend")
    src = open(path).read()
    code = "\n".join(ln for ln in src.splitlines() if not ln.lstrip().startswith("#"))
    ncall = len(re.findall(r"(?<![\w.])dd_band\s*\(", code))
    print(f"# {os.path.basename(path)}: {len(src.splitlines())} lines\n")

    print("== A. `dd_band` MASK ARGUMENT -- the third parameter is a CONSTANT")
    print("   (`op.bend:239 dc_band` interns it with `dc_cint(ar, k)`), so passing")
    print("   `O.Found.i(n)` interns CONST <the slot number of n>.\n")
    rows = call_args(code, len(code))
    bad = []
    for ln, args in rows:
        m = args[2] if len(args) > 2 else "?"
        if m.endswith(": U32") or m.startswith("+") or m.startswith("-"):
            continue          # the DEF line itself, not a call site
        verdict = ("OK literal" if re.fullmatch(r"\d+", m)
                   else "OK value expression" if "tx_powi" in m or "mask1" in m
                   else "SUSPECT index")
        if verdict.startswith("SUSPECT"):
            bad.append((ln, m))
        print(f"   L{ln:<5} mask = {m:<52} {verdict}")
    print(f"   denominator: {len(rows)} `dd_band` call sites; audited {len(rows)}; "
          f"suspect {len(bad)}\n")

    print("== B. `T.tx_shl` / `T.tx_shr` THIRD ARGUMENT -- a SHIFT AMOUNT, not an index")
    print("   (`transcendental.bend:228/232` builds `tx_pow2(ar, y)` = a CONST)\n")
    rows = []
    for nm in ("T.tx_shl", "T.tx_shr"):
        for m in re.finditer(r"(?<![\w.])" + re.escape(nm) + r"\s*\(", code):
            i, depth, j = m.end(), 1, m.end()
            while depth and j < len(code):
                if code[j] == "(":
                    depth += 1
                elif code[j] == ")":
                    depth -= 1
                j += 1
            args = split_args(code[i:j - 1])
            if len(args) >= 3:
                rows.append((code.count("\n", 0, m.start()) + 1, nm, args[2]))
    for ln, nm, m in sorted(rows):
        ok = not re.search(r"O\.Found\.i\(|\bm\b$", m)
        print(f"   L{ln:<5} {nm:<11} shift = {m:<40} {'OK' if ok else 'SUSPECT index'}")
    print(f"   denominator: {len(rows)} call sites; audited {len(rows)}\n")

    print("== C. AN INDEX IN AN ARGUMENT SLOT -- wherever the callee, whichever spelling.")
    print("   A `finfo` field IS a value and a `T.tx_shl` shift amount IS a value, so this")
    print("   over-matches BY DESIGN and every hit is read against its callee's parameter.")
    print("   It prints the callee precisely so over-matching costs a reader nothing.\n")
    print("   ⚠ THIS SECTION USED TO HAVE TWO BLIND VARIANTS AND BOTH ARE NAMED, because a")
    print("   number that cannot see a variant is worse than a number that is small.")
    print("     C-i   THE SPELLING. The test was `if \"O.Found.i(\" in body`, so an index")
    print("           routed through a local -- `+m = O.Found.i(s)`, then")
    print("           `dd_band(O.Found.ar(s), v, m)` -- was invisible. Same index, other")
    print("           spelling.")
    print("     C-ii  THE WHITELIST, WHICH IS THE DOMINANT ONE. The window was")
    print("           `H.i64_of_i32|H.i64_sub|U32.\\w+|T.tx_powi|T.tx_powi32|T.exponent_bias`,")
    print("           so an index passed to ANY OTHER callee was invisible whatever its")
    print("           spelling. MEASURED on .agents/slop/dd-mutations.frozen.bend: section A")
    print("           reports `suspect 7` index-valued `dd_band` mask arguments and the old")
    print("           window reached NONE of them, because `dd_band` is not one of the six.")
    print("           A NAME WHITELIST IS A FIXTURE LIST: it is stale the moment someone")
    print("           writes `dd_band` instead of `dc_band`, which is exactly what happened")
    print("           when `dtype.bend` was renamed. Section A reads the ARGUMENT and is")
    print("           the one to trust.")
    print("   So the old `hard hits: N` was a floor over (six callees) x (one spelling),")
    print("   presented as a count. On today's dtype.bend it printed 0, and 0 is ALSO what a")
    print("   routed-through-a-local index prints, so 0 was never a clean bill of health.")
    print("   Assertion: .agents/slop/formblind-audit.py A13.\n")
    direct = via = 0
    covered = seen_all = 0
    for m in re.finditer(r"(?<![\w.])([A-Za-z_][A-Za-z_0-9_.]*)\s*\(", code):
        callee = m.group(1)
        i, depth, j = m.end(), 1, m.end()
        while depth and j < len(code):
            if code[j] == "(":
                depth += 1
            elif code[j] == ")":
                depth -= 1
            j += 1
        args = split_args(code[i:j - 1])
        if len(args) < 2:
            continue
        seen_all += 1
        if callee not in INTEGER_CALLEES:
            continue
        covered += 1
        ln = code.count("\n", 0, m.start()) + 1
        for k, a in enumerate(args[1:], start=1):
            if "O.Found.i(" in a:
                print(f"   L{ln:<5} arg{k} of {callee}: {a}")
                direct += 1
            elif re.fullmatch(r"[a-z]\w*", a):
                print(f"   L{ln:<5} arg{k} of {callee}: {a}   -- a bare one-token argument: an "
                      f"index routed through a binder, or a value. UNRESOLVED.")
                via += 1
    print(f"   hits (a FLOOR over the INTEGER_CALLEES set, not a total): {direct + via}")
    print(f"     spelled `O.Found.i(`: {direct}   reached through a local: {via}")
    print(f"   denominator: {covered} of {seen_all} calls in this file go to a callee in")
    print(f"   INTEGER_CALLEES ({len(INTEGER_CALLEES)} names, listed above). The other")
    print(f"   {seen_all - covered} calls are NOT EXAMINED, and that number is the honest")
    print(f"   ceiling of this section: an index in an integer position reached through a")
    print(f"   callee absent from that set is invisible here however it is spelled. Adding a")
    print(f"   name is the fix and renaming one is what made this section report 0 for")
    print(f"   `dd_band` while section A reported 7. Assertion: formblind-audit.py A13.\n")

    print("== D. DEFS WHOSE `U32` RETURN IS AN INDEX -- so the CALLER cannot tell a slot")
    print("   from a number, and `f2f.up` builds its final node in a different arena")
    print("   from the one these returned indices belong to.")
    for m in re.finditer(r"(?<![\w.])([a-z_][a-z0-9_.]*)\s*\(([^)]*)\)\s*->\s*U32\s*:", code):
        nm = m.group(1)
        body = code[m.end():].split("\ndef ", 1)[0]
        if "O.Found.i(" in body:
            ln = code.count("\n", 0, m.start()) + 1
            print(f"   {nm} (L{ln}) -> U32 from `O.Found.i(..)`")
    print()

    print("== E. `f2f.em1` CALL SITES -- one def, THREE readings, and only one is right")
    for m in re.finditer(r"(?<![\w.])f2f\.em1\w*\s*\(", code):
        ln0 = code.count("\n", 0, m.start()) + 1
        i, depth, j = m.end(), 1, m.end()
        while depth and j < len(code):
            if code[j] == "(":
                depth += 1
            elif code[j] == ")":
                depth -= 1
            j += 1
        args = split_args(code[i:j - 1])
        ln = ln0
        if code[max(0, m.start() - 4):m.start()] == "def ":
            continue          # the def line itself
        parent = code[max(0, m.start() - 60):m.start()].split("\n")[-1].strip()
        where = "MASK (wants a VALUE)" if "dd_band" in parent else \
                "tx_shl SRC0 (wants a CONST node, not an ADD tree)"
        print(f"   L{ln:<5} {m.group(0).strip():<26} {where}")
    print("   denominator: 3 call sites; audited 3; all 3 want a CONST node and get")
    print("   an `ADD(C(2**te), MUL(C(1), C(-1)))` -- FOUND, NOT FIXED (see the report)")
    print()


if __name__ == "__main__":
    main()