#!/usr/bin/env python3
# tx-mut.py -- the MUTATION TABLE for tinybendygrad/codegen/transcendental.bend.
#
# One hand edit at a time, `./bin/bend --check-only`, then the interpreted lane
# diffed against `.agents/slop/tx-arena.txt`. A mutation that fails to check
# still counts: the rows it would have moved are recorded as "check fails" rather
# than silently dropped.
#
# `--one <name>` runs a single mutation; with no argument it runs them all and
# prints a table.
import os, subprocess, sys, tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
F = os.path.join(ROOT, "tinybendygrad/codegen/transcendental.bend")
ORACLE = os.path.join(ROOT, ".agents/slop/tx-arena.txt")
BEND = os.path.join(ROOT, "bin/bend")

# (name, old, new). Every `old` must occur EXACTLY ONCE in the file.
MUTS = [
    ("poly.coeffs.EXP232.second",
     "[0.0001535920892, 0.001339262701,", "[0.0001535920892, 0.0013392629,"),
    ("finfo.mantissa_bits f32 -> +1",
     "        case 14: 23", "        case 14: 24"),
    ("poly.seed 0.0 -> 1.0",
     "def tx_poly(+ar: O.Arena, +x: U32, cs: List<&2, F32>) -> O.Found:\n  +z = tx_cf(ar, 0.0)",
     "def tx_poly(+ar: O.Arena, +x: U32, cs: List<&2, F32>) -> O.Found:\n  +z = tx_cf(ar, 1.0)"),
    ("_ifand.ne int -> float literal",
     "def _ifand.ne(+b: O.Found, +bi: U32) -> O.Found:\n  +z = tx_ci(O.Found.ar(b), 0)",
     "def _ifand.ne(+b: O.Found, +bi: U32) -> O.Found:\n  +z = tx_cf(O.Found.ar(b), 0.0)"),
    ("xsin: cody_waite built before payne_hanek",
     "  +ph = payne_hanek_reduction(ar, xa, dt, tx_same(dt), dt)\n  +cw = cody_waite_reduction(Red.ar(ph), xa, dt)",
     "  +cw = cody_waite_reduction(ar, xa, dt)\n  +ph = payne_hanek_reduction(Red.ar(cw), xa, dt, tx_same(dt), dt)"),
    ("xpow: neg_base drops the -inf test",
     "  +w1 = tx_alu3(O.Found.ar(nn), O.OpsWHERE{}, O.Found.i(ne), O.Found.i(nn), ret)",
     "  +w1 = tx_alu3(O.Found.ar(nn), O.OpsWHERE{}, O.Found.i(ne), O.Found.i(nn), O.Found.i(nn))"),
    ("table: SQRT rule ignores force",
     "  tx_tab.sqrt.go(tx_tab.keep(has, force), base)",
     "  tx_tab.sqrt.go(Bool.not(has), base)"),
    ("table: the `x` half loses its name",
     "def tx_tab.nm(x: Bool) -> String:\n  match x:\n    case True{}: \"x\"",
     "def tx_tab.nm(x: Bool) -> String:\n  match x:\n    case True{}: \"-\""),
    ("rintk: -0.5 -> +0.5",
     "  +nm = tx_cf(O.Found.ar(c), F32.neg(0.5))",
     "  +nm = tx_cf(O.Found.ar(c), 0.5)"),
    ("ldexp2k: shr by 2 instead of 1",
     "  +h = tx_shr(ar, e, 1)", "  +h = tx_shr(ar, e, 2)"),
    ("payne_hanek: 2**62 -> 2**63",
     "  +c = tx_ci64(ar, tx_powi(62))", "  +c = tx_ci64(ar, tx_powi(63))"),
    ("xpow: `x ** 0` uses the base instead of 1",
     "  +one = tx_cf(O.Found.ar(z), 1.0)", "  +one = tx_cf(O.Found.ar(z), 2.0)"),
    ("switch_over is hard-coded at 30.0",
     "def w_xsin7() -> O.Arena:\n  O.Found.ar(xsin(t_fixtures(), t_d(), S.single(), False{}, False{}, 7.0))",
     "def w_xsin7() -> O.Arena:\n  O.Found.ar(xsin(t_fixtures(), t_d(), S.single(), False{}, False{}, 30.0))"),
]


def keyed(lines):
    """key -> value, where an `a_<tag>=<idx>,...` row is keyed on `<tag>#<idx>`.

    A positional diff reports every row after an insertion as moved, which is
    noise; and keying on `<tag>` alone would collapse all 205 `a_xsin` rows into
    one. The index is the part that makes each node its own claim.
    """
    out = {}
    for l in lines:
        if "=" in l:
            k, v = l.split("=", 1)
            if k.startswith("a_"):
                k = k + "#" + v.split(",")[0]
            out.setdefault(k, v)
    return out


def rows_moved(path):
    want = keyed(open(ORACLE).read().split("\n"))
    got = keyed(subprocess.run([BEND, path], capture_output=True, text=True).stdout.split("\n"))
    return {k for k in set(want) | set(got) if want.get(k) != got.get(k)}


def main():
    base = open(F).read()
    only = None
    if len(sys.argv) > 2 and sys.argv[1] == "--one":
        only = sys.argv[2]
    print("| mutation | rows moved | what it catches |")
    print("| --- | --- | --- |")
    for name, old, new in MUTS:
        if only is not None and only not in name:
            continue
        assert base.count(old) == 1, f"{name}: {base.count(old)} occurrences of the old text"
        chk = subprocess.run([BEND, F, "--check-only"], capture_output=True, text=True)
        tmp = os.path.join(os.path.dirname(F), "_txmut.bend")
        open(tmp, "w").write(base.replace(old, new, 1))
        try:
            r = subprocess.run([BEND, tmp], capture_output=True, text=True)
            moved = rows_moved(tmp) if r.returncode == 0 else {"<gate did not run>"}
        finally:
            os.unlink(tmp)
        ok = "checks" if chk.returncode == 0 and "ALL PROOFS CHECK" in chk.stdout else "CHECK FAILS"
        m = sorted(moved)
        show = ", ".join(m[:6]) + (f", ... (+{len(m) - 6})" if len(m) > 6 else "")
        print(f"| `{name}` | {ok}: {show or 'NOTHING'} | |")


if __name__ == "__main__":
    main()